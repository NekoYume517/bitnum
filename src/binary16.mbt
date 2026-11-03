///|
/// IEEE 754-2008 `binary16` — the interchange format of §3.6, `s(1) e(5) m(10)`,
/// bias 15.
///
/// The decoder always reports the *stored* fields (PLAN.md §7 requires the field
/// breakdown, not just a value), so `exponent` is the raw 5-bit field and
/// `significand` the raw 10-bit field. Interpretation is a separate step, which
/// is what keeps `kind` honest: a decode never invents a normalised exponent.
///
/// `of_f64` never guesses. If the exact value needs rounding, the caller chose
/// the rounding direction and the result is flagged `inexact`; if the value needs
/// more rounding than 11 significand bits can ever express, that is reported
/// rather than swallowed.

///|
/// Number of bit patterns in binary16 — the exhaustive-test domain.
pub let binary16_patterns : Int32 = 65536

///|
/// Exponent field width.
pub let binary16_exp_bits : Int32 = 5

///|
/// Significand field width.
pub let binary16_sig_bits : Int32 = 10

///|
/// Exponent bias.
pub let binary16_bias : Int32 = 15

///|
/// The decoded view of one binary16 bit pattern.
#derive(Eq, Debug)
pub(all) struct Binary16 {
  /// Raw sign bit.
  sign : Int32
  /// Raw 5-bit exponent field, `0 .. 31`. Not biased-adjusted.
  exponent : Int32
  /// Raw 10-bit significand field.
  significand : Int32
  kind : FloatClass
}

///|
/// Split one 16-bit pattern into its fields. Total on all 65536 inputs: the only
/// distinctions are between the five datum classes.
pub fn Binary16::decode(bits : UInt16) -> Binary16 {
  let u = bits.to_uint()
  let sign = ((u >> 15) & 1).to_int()
  let exponent = ((u >> 10) & 0x1F).to_int()
  let significand = (u & 0x3FF).to_int()
  let kind = if exponent == 0x1F {
    if significand == 0 {
      Infinity
    } else {
      Nan
    }
  } else if exponent == 0 {
    if significand == 0 {
      Zero
    } else {
      Subnormal
    }
  } else {
    Normal
  }
  Binary16::{ sign, exponent, significand, kind, }
}

///|
/// Reassemble the bit pattern from its fields. This is the *only* encoder for
/// binary16, so `decode → encode` holds for all 65536 patterns by construction:
/// the decoder is field-for-field lossless.
pub fn Binary16::encode(self : Binary16) -> UInt16 {
  let u = (self.sign << 15) | (self.exponent << 10) | self.significand
  u.to_uint16()
}

///|
/// Convenience: the bit pattern of a struct round-trips unchanged.
pub fn Binary16::bits(self : Binary16) -> UInt16 {
  self.encode()
}

///|
/// `true` for the two infinities and every NaN: the values with no finite
/// double counterpart in the ordinary sense.
pub fn Binary16::is_special(self : Binary16) -> Bool {
  self.kind == Infinity || self.kind == Nan
}

///|
/// Whether the significand carries the quiet bit (bit 9). Only meaningful for
/// NaN; for every other class the field is an ordinary significand.
pub fn Binary16::is_quiet_nan(self : Binary16) -> Bool {
  self.kind == Nan && ((self.significand >> 9) & 1) == 1
}

///|
/// The 10-bit NaN payload, including the quiet bit as stored.
pub fn Binary16::nan_payload(self : Binary16) -> Int32 {
  self.significand
}

///|
/// The exact value of the pattern as a binary64.
///
/// Exact for every pattern: binary16 has 11 significand bits and a 5-bit
/// exponent, both strictly narrower than binary64's 53 and 11, so no rounding
/// can occur here. Infinity maps to infinity and NaN to NaN, with the payload
/// (minus the quiet bit) placed in the upper payload bits.
pub fn Binary16::to_f64(self : Binary16) -> Double {
  let neg = self.sign == 1
  let mag = match self.kind {
    Zero => 0.0
    Infinity => infinity_double()
    Nan => {
      // Build a quiet NaN carrying the binary16 payload in the high bits.
      let payload = self.significand & 0x1FF
      let quiet = 0x400UL
      let bits = 0x7FF0000000000000UL |
        (quiet << 41) |
        (payload.to_uint64() << 42)
      let base = bits.reinterpret_as_double()
      if neg {
        -base
      } else {
        base
      }
    }
    Subnormal => {
      // value = significand * 2^-24, exactly.
      let m = self.significand.to_double()
      m * pow2_exact(-24)
    }
    Normal => {
      // value = (2^10 + significand) * 2^(exponent - 15 - 10), exactly.
      let m = (self.significand + 0x400).to_double()
      m * pow2_exact(self.exponent - 15 - 10)
    }
  }
  if self.kind == Nan {
    mag
  } else if neg {
    -mag
  } else {
    mag
  }
}

///|
/// Convert a binary64 to binary16 under an explicitly chosen rounding mode.
///
/// Every decision is made on exact integer quantities: the significand and
/// exponent are pulled out of the binary64 pattern and rounded with integer
/// quotient/remainder arithmetic, so a tie is detected by `2 * remainder ==
/// divisor` rather than by a floating-point comparison that may itself round.
pub fn of_f64(
  x : Double,
  mode : RoundingMode,
) -> FloatConversion raise BitnumError {
  let u = x.reinterpret_as_uint64()
  let sign = (u >> 63).to_int()
  let exp_field = ((u >> 52) & 0x7FFUL).to_int()
  let mantissa = u & 0x000FFFFFFFFFFFFFUL

  if exp_field == 0x7FF {
    if mantissa == 0 {
      // Infinity keeps its sign and is exact.
      let bits = (sign << 15) | 0x7C00
      return FloatConversion::{ bits: bits.to_uint16(), inexact: false, }
    }
    // NaN: binary16 cannot carry a binary64's 52-bit payload and PLAN.md §2
    // mandates the canonical quiet NaN `0x7E00` (sign preserved). Every NaN
    // therefore loses payload information — a NaN always has a non-zero
    // mantissa, so there is no NaN that survives unchanged — and `inexact` is
    // reported, unlike bfloat16 where 6 payload bits do survive.
    let bits = (sign << 15) | 0x7E00
    return FloatConversion::{ bits: bits.to_uint16(), inexact: true, }
  }

  if exp_field == 0 && mantissa == 0 {
    // Signed zero is preserved exactly: -0.0 must not collapse to +0.0.
    let bits = sign << 15
    return FloatConversion::{ bits: bits.to_uint16(), inexact: false, }
  }

  // Exact decomposition: value = m * 2^e with m a non-negative integer.
  let (m, e) = if exp_field == 0 {
    (mantissa, -1074)
  } else {
    (mantissa | 0x0010000000000000UL, exp_field - 1023 - 52)
  }
  let bl = bit_length64(m)
  let p = bl - 1 + e // floor(log2(value)), exact

  if p < -14 {
    // Subnormal region: quantum is 2^-24.
    let (n, inexact) = round_to_quantum(m, e, -24, mode, sign == 1)
    if n >= 0x400UL {
      // Rounded up into the smallest normal number.
      let bits = (sign << 15) | 0x0400
      return FloatConversion::{ bits: bits.to_uint16(), inexact, }
    }
    let bits = (sign << 15) | n.to_int()
    return FloatConversion::{ bits: bits.to_uint16(), inexact, }
  }

  // Normal region: 11-bit significand, quantum 2^(p-10).
  let (sig, inexact) = round_to_quantum(m, e, p - 10, mode, sign == 1)
  let mut sig = sig
  let mut exp = p + 15
  if sig >= 0x800UL {
    // Carry out of the 11-bit field bumps the exponent.
    sig = sig >> 1
    exp = exp + 1
  }
  if exp > 30 {
    // Overflow. Nearest modes go to infinity; the directed modes go to the
    // largest finite value of the same sign (PLAN.md §2).
    let bits = if overflow_to_infinity(mode, sign == 1) {
      (sign << 15) | 0x7C00
    } else {
      (sign << 15) | 0x7BFF
    }
    return FloatConversion::{ bits: bits.to_uint16(), inexact: true, }
  }
  let bits = (sign << 15) | (exp << 10) | (sig.to_int() - 0x400)
  FloatConversion::{ bits: bits.to_uint16(), inexact, }
}

///|
/// Round `m * 2^e` to an integer count of `2^q` units.
///
/// Returns `(count, inexact)`. For the directed modes the direction is fixed by
/// the *sign of the result*, not by the sign of the integer significand — a
/// negative value rounded toward +∞ moves toward zero, which is the opposite of
/// what rounding a positive value does. Getting this backwards is the single
/// easiest mistake in this file, so it is decided in one place.
fn round_to_quantum(
  m : UInt64,
  e : Int32,
  q : Int32,
  mode : RoundingMode,
  neg : Bool,
) -> (UInt64, Bool) {
  let shift = q - e
  if shift <= 0 {
    // Exact: the quantum is coarser than the value's own resolution.
    return (m << -shift, false)
  }
  if shift >= 64 {
    // |m * 2^e| < 2^q for every significand a binary64 can hold, so the count is
    // zero and the rounding cannot carry — but the value is not zero, hence
    // inexact. Guarding here is not defensive padding: `of_f64` reaches this
    // with a binary64 *subnormal* input, where `e == -1074` and `shift` is 1050.
    return (0UL, m != 0UL)
  }
  let divisor = 1UL << shift
  let quo = m >> shift
  let rem = m & (divisor - 1UL)
  if rem == 0 {
    return (quo, false)
  }
  let half = 1UL << (shift - 1)
  let bumped = match mode {
    NearestEven => rem > half || (rem == half && (quo & 1UL) == 1UL)
    NearestAway => rem >= half
    TowardZero => false
    TowardPositive => not(neg)
    TowardNegative => neg
  }
  (if bumped { quo + 1UL } else { quo }, true)
}

///|
/// Whether an overflow under this mode produces an infinity (rather than the
/// largest finite value). Nearest modes overflow to infinity; the directed
/// modes only do so if the direction points away from zero.
fn overflow_to_infinity(mode : RoundingMode, neg : Bool) -> Bool {
  match mode {
    NearestEven => true
    NearestAway => true
    TowardZero => false
    TowardPositive => not(neg)
    TowardNegative => neg
  }
}

///|
/// The signed zero of a given sign, as an exact binary64.
pub fn zero_of_sign(neg : Bool) -> Double {
  if neg {
    -0.0
  } else {
    0.0
  }
}

///|
/// Positive infinity, built from its bit pattern so no libm constant is involved.
pub fn infinity_double() -> Double {
  0x7FF0000000000000UL.reinterpret_as_double()
}

///|
/// A quiet NaN with a zero payload, built from its bit pattern.
pub fn quiet_nan_double() -> Double {
  0x7FF8000000000000UL.reinterpret_as_double()
}
