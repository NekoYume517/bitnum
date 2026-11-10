///|
/// The DPD wire formats: decimal32, decimal64, decimal128 (IEEE 754-2008 §3.5.2).
///
/// Geometry (fitted from the official `dectest` vectors by `scripts/fit_comb.py`,
/// and re-derived independently by `scripts/decimal_ref.py`):
///
/// | format     | bits | exp cont | coef cont | digits | bias |
/// |------------|------|----------|-----------|--------|------|
/// | decimal32  |   32 |        6 |        20 |      7 |  101 |
/// | decimal64  |   64 |        8 |        50 |     16 |  398 |
/// | decimal128 |  128 |       12 |       110 |     34 | 6176 |
///
/// Layout, most significant bit first: sign(1), combination(5), exponent
/// continuation, coefficient continuation.
///
/// Combination field `G0G1G2G3G4`:
///
///   G0G1 = 00|01|10  ->  exponent top 2 bits = G0G1,  leading digit = G2G3G4
///   G0G1 = 11        ->  exponent top 2 bits = G2G3,  leading digit = 8 + G4
///   11110            ->  Infinity
///   11111            ->  NaN
///
/// The two `11` forms exist because digits 8 and 9 must not collide with the
/// Infinity/NaN patterns, so they spend the extra exponent prefix instead.
///
/// **NaN layout** (this is the part that is easy to get backwards). For a NaN the
/// combination field is `11111` and the bits below it are not an exponent: the
/// *first* bit below the combination is the signaling flag, and the rest is the
/// diagnostic payload. `dectest`'s `ddEncode.decTest` pins it down:
///
///   0x7C00000000000000 -> NaN     (signaling bit 0)
///   0x7E00000000000000 -> sNaN    (signaling bit 1)
///
/// That is the opposite of the binary formats, where the quiet bit is the *set*
/// one; a payload that looks right by analogy is wrong here.

///|
/// The three DPD decimal formats, with their geometry as data rather than as three
/// copies of the same code. A wrong constant in this table is silent, so
/// `geometry_is_consistent` recomputes every derived quantity and the tests assert
/// it.
#derive(Eq, Debug)
pub(all) enum DecimalFormat {
  Decimal32
  Decimal64
  Decimal128
}

///|
/// Wire width in bits.
pub fn DecimalFormat::bits(self : DecimalFormat) -> Int32 {
  match self {
    Decimal32 => 32
    Decimal64 => 64
    Decimal128 => 128
  }
}

///|
/// Wire width in bytes.
pub fn DecimalFormat::byte_width(self : DecimalFormat) -> Int32 {
  self.bits() / 8
}

///|
/// Exponent-continuation field width.
pub fn DecimalFormat::exp_cont_bits(self : DecimalFormat) -> Int32 {
  match self {
    Decimal32 => 6
    Decimal64 => 8
    Decimal128 => 12
  }
}

///|
/// Coefficient-continuation field width, in bits.
pub fn DecimalFormat::coef_cont_bits(self : DecimalFormat) -> Int32 {
  self.bits() - 1 - 5 - self.exp_cont_bits()
}

///|
/// Total decimal digits held, including the leading digit from the combination
/// field.
pub fn DecimalFormat::digits(self : DecimalFormat) -> Int32 {
  match self {
    Decimal32 => 7
    Decimal64 => 16
    Decimal128 => 34
  }
}

///|
/// Exponent bias.
pub fn DecimalFormat::bias(self : DecimalFormat) -> Int32 {
  match self {
    Decimal32 => 101
    Decimal64 => 398
    Decimal128 => 6176
  }
}

///|
/// Human-readable name, matching the CLI's `<format>` argument.
pub fn DecimalFormat::name(self : DecimalFormat) -> String {
  match self {
    Decimal32 => "decimal32"
    Decimal64 => "decimal64"
    Decimal128 => "decimal128"
  }
}

///|
/// Largest biased exponent **representable in the field**: `2^(exp_cont + 2) - 1`.
///
/// Note that the field is wider than the range of legal exponents. That is not an
/// oversight in this table: the standard reserves the top of the field, and the
/// legal maximum is `Emax + bias` (197 / 782 / 12320), well below the field
/// capacity. Encoding a biased exponent above `Emax + bias` is therefore a real
/// error — the pattern would be legal bits but not a legal number — and it is
/// rejected by `check_biased` rather than written.
///
/// The `+2` is the two exponent bits carried inside the combination field, so the
/// biased exponent is `exp_cont + 2` bits wide overall.
pub fn DecimalFormat::biased_exponent_field_max(self : DecimalFormat) -> Int32 {
  (1 << (self.exp_cont_bits() + 2)) - 1
}

///|
/// Largest *legal* biased exponent, `Emax + bias` (197 / 782 / 12320).
pub fn DecimalFormat::biased_exponent_max(self : DecimalFormat) -> Int32 {
  self.emax() + self.bias()
}

///|
/// `Emax`. The standard fixes it from the bias and precision: `Emax = bias - p + 2`
/// with `p = digits`. Verified for all three formats by
/// `geometry_is_consistent`.
pub fn DecimalFormat::emax(self : DecimalFormat) -> Int32 {
  self.bias() - self.digits() + 2
}

///|
/// `Emin`: the smallest exponent for a number with a non-zero leading digit,
/// `1 - Emax`.
pub fn DecimalFormat::emin(self : DecimalFormat) -> Int32 {
  1 - self.emax()
}

///|
/// `Etiny`: exponent of the smallest subnormal, `Emin - (digits - 1)`, which equals
/// `-bias` for all three formats.
pub fn DecimalFormat::etin_y(self : DecimalFormat) -> Int32 {
  self.emin() - (self.digits() - 1)
}

///|
/// Width of the diagnostic payload a NaN can carry, in bits: everything below the
/// signaling flag.
pub fn DecimalFormat::nan_payload_bits(self : DecimalFormat) -> Int32 {
  self.exp_cont_bits() + self.coef_cont_bits() - 1
}

///|
/// Largest exponent a datum may carry.
///
/// Two independent ceilings apply, and the answer is the smaller:
///
///  1. **Adjusted exponent.** The standard requires `adjusted <= Emax`, and
///     `adjusted = exponent + digits - 1`. So `exponent <= Emax - (digits - 1)`.
///     This is what makes `9999999E+90` the largest decimal32 rather than
///     `9999999E+96` — the latter would be `9.999999E+102`, past Emax.
///
///  2. **Combination field.** A biased exponent needs `exp_top <= 2` in the
///     `00/01/10` forms, and `exp_top <= 2` in the `11` form too (`exp_top == 3`
///     there produces `111xx`, and `11110`/`11111` are Infinity/NaN). Both forms
///     therefore top out at `3 * 2^exp_cont - 1` biased, i.e. `Emax_top`
///     (90 / 369 / 6111).
///
/// The two coincide at full precision — `Emax - (p - 1) == Emax_top` — which is
/// exactly why the format is coherent: reaching `Emax` requires p significant
/// digits, and those digits already force the exponent down to what the
/// combination field can hold. Below full precision the branch ceiling wins, which
/// is why `dectest` clamps `0e+10000` to `0E+90 / 0E+369 / 0E+6111` instead of to
/// `Emax`.
pub fn DecimalFormat::max_exponent_for(
  self : DecimalFormat,
  coefficient : BigInt,
) -> Int32 {
  let nd = if coefficient.is_zero() { 1 } else { digit_count_big(coefficient) }
  let by_adjusted = self.emax() - (nd - 1)
  if by_adjusted < self.emax_top() {
    by_adjusted
  } else {
    self.emax_top()
  }
}

///|
/// `Emax_top`: the largest exponent reachable, `3 * 2^exp_cont - 1 - bias`.
pub fn DecimalFormat::emax_top(self : DecimalFormat) -> Int32 {
  3 * (1 << self.exp_cont_bits()) - 1 - self.bias()
}

///|
/// Self-check of the geometry table. Called by the tests, not by the codecs: a
/// failed derivation means the table itself is wrong, and no amount of decoding
/// would reveal it.
pub fn DecimalFormat::geometry_is_consistent(self : DecimalFormat) -> Bool {
  if (self.digits() - 1) % 3 != 0 {
    return false
  }
  let groups = (self.digits() - 1) / 3
  if groups * 10 != self.coef_cont_bits() {
    return false
  }
  match self {
    Decimal32 =>
      self.biased_exponent_field_max() == 255 &&
      self.biased_exponent_max() == 197 &&
      self.emax() == 96 &&
      self.emin() == -95 &&
      self.etin_y() == -101 &&
      // `0e+10000` clamps to `0E+90` in dsBase.decTest.
      self.max_exponent_for(BigInt::from_int(0)) == 90
    Decimal64 =>
      self.biased_exponent_field_max() == 1023 &&
      self.biased_exponent_max() == 782 &&
      self.emax() == 384 &&
      self.emin() == -383 &&
      self.etin_y() == -398 &&
      // `0e+10000` clamps to `0E+369` in ddBase.decTest.
      self.max_exponent_for(BigInt::from_int(0)) == 369
    Decimal128 =>
      self.biased_exponent_field_max() == 16383 &&
      self.biased_exponent_max() == 12320 &&
      self.emax() == 6144 &&
      self.emin() == -6143 &&
      self.etin_y() == -6176 &&
      // `0e+10000` clamps to `0E+6111` in dqBase.decTest.
      self.max_exponent_for(BigInt::from_int(0)) == 6111
  }
}

///|
/// The result of decoding a wire pattern: the exact triple, plus how many
/// coefficient groups were redundant DPD codes.
///
/// Redundant codes are *accepted*, never rejected and never silently rewritten
/// (PLAN.md §1.2, §4.4). The count exists so a caller can audit an input the
/// encoder could never have produced — which is exactly what the 24 `dectest`
/// cases per format are.
#derive(Eq, Debug)
pub(all) struct DecodedDecimal {
  value : Decimal
  redundant_groups : Int32
}

///|
/// Decode wire bits into an exact triple.
///
/// `raw` is right-aligned in the low `bits` of a BigInt; anything above that is
/// rejected rather than truncated. That one convention lets a single function
/// serve all three formats without three copies of the same bit arithmetic.
pub fn DecimalFormat::decode_raw(
  self : DecimalFormat,
  raw : BigInt,
) -> DecodedDecimal raise BitnumError {
  let width = self.bits()
  let limit = BigInt::from_int(1) << width
  if raw.compare(limit) >= 0 {
    raise TruncatedInput(width, raw.bit_length())
  }
  if raw.compare_int(0) < 0 {
    raise TruncatedInput(width, -1)
  }
  let negative = big_slice(raw, width - 1, 1).compare_int(1) == 0
  let comb = big_slice(raw, width - 6, 5).to_int()

  if comb == 0x1E {
    return DecodedDecimal::{
      value: Decimal::infinity(negative),
      redundant_groups: 0,
    }
  }
  if comb == 0x1F {
    // Signaling flag sits immediately below the combination field; 0 = quiet.
    let signaling = big_slice(raw, width - 7, 1).compare_int(1) == 0
    let payload = big_slice(raw, 0, width - 7)
    let kind = if signaling { DSignalingNan } else { DNan }
    return DecodedDecimal::{
      value: Decimal::{ negative, coefficient: payload, exponent: 0, kind, },
      redundant_groups: 0,
    }
  }

  let (msd, exp_top) = if comb >> 3 == 0b11 {
    (8 + (comb & 1), (comb >> 1) & 0b11)
  } else {
    (comb & 0b111, comb >> 3)
  }
  let exp_cont = big_slice(raw, self.coef_cont_bits(), self.exp_cont_bits()).to_int()
  let biased = (exp_top << self.exp_cont_bits()) | exp_cont
  let exponent = biased - self.bias()

  let groups = (self.digits() - 1) / 3
  let coef_sb = StringBuilder()
  coef_sb.write_string(msd.to_string())
  let mut redundant = 0
  for gi in 0..<groups {
    let shift = (groups - 1 - gi) * 10
    let code = big_slice(raw, shift, 10).to_int()
    let (d1, d2, d3, is_redundant) = dpd_decode3_checked(code)
    if is_redundant {
      redundant = redundant + 1
    }
    coef_sb.write_string(d1.to_string())
    coef_sb.write_string(d2.to_string())
    coef_sb.write_string(d3.to_string())
  }
  let coefficient = BigInt::from_string(coef_sb.to_string(), radix=10)
  DecodedDecimal::{
    value: Decimal::{ negative, coefficient, exponent, kind: DFinite, },
    redundant_groups: redundant,
  }
}

///|
/// Encode an exact triple to wire bits.
///
/// Rejects, with the numbers that make the rejection actionable, a coefficient
/// with more digits than the format holds and an exponent outside the biased
/// range. It does **not** round, pad, or expand the coefficient — PLAN.md §1.3.
/// The distinction is real: `750` at exponent -2 is `-7.50`; quietly
/// reinterpreting it as `7500` at exponent -3 would print the same yet no longer
/// round-trip.
pub fn DecimalFormat::encode_raw(
  self : DecimalFormat,
  value : Decimal,
) -> BigInt raise BitnumError {
  let width = self.bits()
  let sign_bit = if value.negative {
    BigInt::from_int(1) << (width - 1)
  } else {
    BigInt::from_int(0)
  }
  let comb_shift = width - 6

  match value.kind {
    DInfinity => sign_bit + (BigInt::from_int(0x1E) << comb_shift)
    DNan => {
      let payload = self.check_payload(value.coefficient)
      sign_bit + (BigInt::from_int(0x1F) << comb_shift) + payload
    }
    DSignalingNan => {
      let payload = self.check_payload(value.coefficient)
      let signal_bit = BigInt::from_int(1) << (width - 7)
      sign_bit + (BigInt::from_int(0x1F) << comb_shift) + signal_bit + payload
    }
    DFinite => {
      // `exponent + bias` is computed in `Int64`: a legal `Int32` exponent can
      // still push the biased value past `Int32` (`1e2147483647` wants
      // 2147483748), and wrapping there would report a plausible but unrelated
      // number (BN-B3).
      let biased = value.exponent.to_int64() + self.bias().to_int64()
      self.check_biased(biased)
      // A datum's maximum exponent depends on its digit count, and zero is no
      // exception (it counts as one digit). Without this check `exp_top` can reach
      // 3, which the `00/01/10` combination forms cannot express — see
      // `max_exponent_for`. Rejecting here is what keeps the encoder from writing a
      // pattern that decodes to a completely different number.
      let digits_text = if value.coefficient.is_zero() {
        ""
      } else {
        value.coefficient.to_string(radix=10)
      }
      let nd = if digits_text.length() == 0 { 1 } else { digits_text.length() }
      let exp_limit = self.max_exponent_for(value.coefficient)
      if value.exponent > exp_limit {
        // The value being reported is the *true* exponent and the bounds are true
        // exponents too, so this must not reuse the biased wording (BN-B5).
        raise UnbiasedExponentOutOfRange(
          value.exponent.to_int64(),
          self.etin_y().to_int64(),
          exp_limit.to_int64(),
        )
      }
      let exp_top = (biased >> self.exp_cont_bits()).to_int()
      let exp_low = (biased & ((1L << self.exp_cont_bits()) - 1L)).to_int()
      let exp_field = BigInt::from_int(exp_low) << self.coef_cont_bits()
      if value.coefficient.is_zero() {
        // Zero's leading digit is 0, so the combination is `exp_top << 3` — legal
        // because the check above bounds `exp_top` at 2.
        let comb = exp_top << 3
        sign_bit + (BigInt::from_int(comb) << comb_shift) + exp_field
      } else {
        let cap = self.digits()
        if nd > cap {
          raise CoefficientTooLarge(nd, cap)
        }
        // Left-pad to `cap` digits. The padding is *leading*, which is what the
        // format has room for: trailing zeros belong to the exponent, and adding
        // them would change the triple rather than widen the container.
        let padded = String::make(cap - nd, '0') + digits_text
        // The leading digit is only meaningful because the coefficient has *no*
        // more than `cap` digits, and less is allowed: a short coefficient is
        // simply a value whose leading digits are zero, which is exactly what the
        // zero padding says. Trailing zeros, by contrast, are the exponent's job.
        let msd = digit_at(padded, 0)
        // `exp_top == 3` is unreachable for any legal datum — `max_exponent_for`
        // already rejected it above, for zero and for non-zero coefficients alike —
        // so the `11` branch below only ever runs with `exp_top` in `0..2`. There
        // is therefore no way to collide with `0x1E`/`0x1F` (Infinity/NaN) by
        // accident, and no defensive re-check is needed here.
        let comb = if msd <= 7 {
          (exp_top << 3) | msd
        } else {
          (0b11 << 3) | (exp_top << 1) | (msd - 8)
        }
        let coef_cont = self.encode_dpd_groups(padded)
        sign_bit +
        (BigInt::from_int(comb) << comb_shift) +
        exp_field +
        coef_cont
      }
    }
  }
}

///|
/// Validate a NaN payload and return it as a BigInt.
fn DecimalFormat::check_payload(
  self : DecimalFormat,
  payload : BigInt,
) -> BigInt raise BitnumError {
  let cap = self.nan_payload_bits()
  if payload.compare_int(0) < 0 {
    raise NanPayloadTooLarge(-1, cap)
  }
  if payload.compare(BigInt::from_int(1) << cap) >= 0 {
    raise NanPayloadTooLarge(payload.bit_length(), cap)
  }
  payload
}

///|
/// Encode the `digits - 1` trailing digits into the coefficient continuation.
fn DecimalFormat::encode_dpd_groups(
  self : DecimalFormat,
  digits_text : String,
) -> BigInt {
  let groups = (self.digits() - 1) / 3
  let mut acc = BigInt::from_int(0)
  for gi in 0..<groups {
    let start = 1 + gi * 3
    let code = dpd_encode3(
      digit_at(digits_text, start),
      digit_at(digits_text, start + 1),
      digit_at(digits_text, start + 2),
    )
    acc = (acc << 10) + BigInt::from_int(code)
  }
  acc
}

///|
/// The decimal value of the ASCII digit at `i`. Callers guarantee the character is
/// a digit.
fn digit_at(text : String, i : Int32) -> Int32 {
  text.get_char(i).unwrap().to_int() - '0'.to_int()
}

///|
/// Reject a biased exponent outside the representable range, naming the value and
/// both bounds (PLAN.md §5).
///
/// `biased` arrives as `Int64` because the caller's sum can leave `Int32`; the
/// bounds are tight and positive, so `Int64` costs nothing here and buys the
/// difference between reporting `2147483748` and reporting a wrapped
/// `-2147483548` (BN-B3).
fn DecimalFormat::check_biased(
  self : DecimalFormat,
  biased : Int64,
) -> Unit raise BitnumError {
  let max = self.biased_exponent_max().to_int64()
  if biased < 0L || biased > max {
    raise ExponentOutOfRange(biased, 0L, max)
  }
}

///|
/// Encode to the format's natural byte string, big-endian: the wire order that the
/// standard's hex dumps and `dectest` use.
pub fn DecimalFormat::encode_bytes(
  self : DecimalFormat,
  value : Decimal,
) -> Bytes raise BitnumError {
  let raw = self.encode_raw(value)
  let nbytes = self.byte_width()
  // `BigInt::to_octets` emits most-significant byte first, which is already the
  // wire order (checked against dectest: `A2300000000003D0` starts with 0xA2).
  raw.to_octets(length=nbytes)
}

///|
/// Decode from the format's natural byte string, big-endian.
pub fn DecimalFormat::decode_bytes(
  self : DecimalFormat,
  bytes : Bytes,
) -> DecodedDecimal raise BitnumError {
  let needed = self.byte_width()
  let got = bytes.length()
  if got < needed {
    raise TruncatedInput(needed, got)
  }
  let mut acc = BigInt::from_int(0)
  for i in 0..<needed {
    acc = (acc << 8) + BigInt::from_int(bytes[i].to_int())
  }
  self.decode_raw(acc)
}

///|
/// Number of hex digits a wire pattern occupies.
pub fn DecimalFormat::hex_width(self : DecimalFormat) -> Int32 {
  self.byte_width() * 2
}

///|
/// Format a wire pattern as upper-case hex, zero-padded to the format width.
pub fn DecimalFormat::to_hex(self : DecimalFormat, raw : BigInt) -> String {
  let text = raw.to_string(radix=16).to_lower()
  let width = self.hex_width()
  if text.length() >= width {
    text.to_upper()
  } else {
    (String::make(width - text.length(), '0') + text).to_upper()
  }
}

///|
/// Parse a hex string into wire bits. Rejects any length other than the format's
/// own, and any non-hex character, rather than skipping, masking, or padding it.
///
/// The length must be **exact**, not merely bounded above. A wire pattern is a
/// byte string: `A2300000000003D` is `A2300000000003D0` with a digit missing, and
/// right-aligning it into `0A2300000000003D` decodes a different number that
/// happens to look plausible. `decode_bytes` already refuses a short buffer with
/// `TruncatedInput`; this is the same rejection for the hex spelling of the same
/// input, so the two entry points cannot disagree (PLAN.md §1.2).
///
/// The check is `!=` rather than `<`: a string wider than the format is the same
/// class of error — it does not fit the container — and reporting both through
/// `TruncatedInput(width, got)` keeps one wording for "the size is wrong".
pub fn DecimalFormat::from_hex(
  self : DecimalFormat,
  text : String,
) -> BigInt raise BitnumError {
  let width = self.hex_width()
  if text.length() != width {
    raise TruncatedInput(width, text.length())
  }
  let upper = text.to_upper()
  let mut acc = BigInt::from_int(0)
  for i in 0..<upper.length() {
    let c = upper.get_char(i).unwrap()
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      raise UnparsableInput(text, "non-hex character")
    }
    acc = (acc << 4) + BigInt::from_int(d)
  }
  acc
}
