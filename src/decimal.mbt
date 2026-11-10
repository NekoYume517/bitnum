///|
/// The decimal triple of IEEE 754-2008 §3.5.2: `(sign, coefficient, exponent)`,
/// value `(-1)^sign x coefficient x 10^exponent`.
///
/// This type carries an *exact* triple and nothing else. There is no context, no
/// preferred exponent, no implicit rounding (PLAN.md §4.1): converting a number
/// that does not fit is a separate, explicit operation that either reports an
/// error or returns a rounded result flagged `inexact`, and those two outcomes
/// are never mixed.
///
/// `coefficient` is a `BigInt` because decimal128 holds 34 digits and the whole
/// point of the format is that those digits stay exact — narrowing to 64 bits
/// would make the format unimplementable, not merely inconvenient.

///|
/// Kind of decimal datum. Zero is not a separate variant: a finite datum with a
/// zero coefficient is a zero, and its sign and exponent are both observable in
/// the wire format, so folding it out would lose information.
///
/// The variant names carry a `D` prefix (`DInfinity`, `DNan`, ...) so they never
/// collide with binary16's `FloatClass` variants: both enums live in this package,
/// and an unqualified `Infinity` would be ambiguous at every use site.
#derive(Eq, Debug)
pub(all) enum DecimalKind {
  DFinite
  DInfinity
  DNan
  /// A NaN carrying diagnostic information (the trailing significand field).
  DSignalingNan
}

///|
/// Canonical spelling, for the CLI and for tests.
pub fn DecimalKind::label(self : DecimalKind) -> String {
  match self {
    DFinite => "finite"
    DInfinity => "infinity"
    DNan => "nan"
    DSignalingNan => "signaling-nan"
  }
}

///|
/// An exact decimal triple with its datum kind.
#derive(Eq, Debug)
pub(all) struct Decimal {
  negative : Bool
  coefficient : BigInt
  exponent : Int32
  kind : DecimalKind
}

///|
/// Build a finite triple. `coefficient` must be non-negative; the sign lives in
/// `negative`, as the standard requires (there is no negative coefficient).
pub fn Decimal::make(
  negative : Bool,
  coefficient : BigInt,
  exponent : Int32,
) -> Decimal raise BitnumError {
  if coefficient.compare_int(0) < 0 {
    raise InexactConversion(
      "negative coefficient: the sign of a Decimal lives in `negative`",
    )
  }
  Decimal::{ negative, coefficient, exponent, kind: DFinite, }
}

///|
/// A zero with an explicit exponent. The exponent is a parameter because each
/// wire format has its own preferred exponent for zero (`Etiny`, -95 / -383 /
/// -6176) and a bare `Decimal` is format-agnostic.
pub fn Decimal::zero(negative : Bool, exponent : Int32) -> Decimal {
  Decimal::{
    negative,
    coefficient: BigInt::from_int(0),
    exponent,
    kind: DFinite,
  }
}

///|
/// Positive or negative infinity.
pub fn Decimal::infinity(negative : Bool) -> Decimal {
  Decimal::{
    negative,
    coefficient: BigInt::from_int(0),
    exponent: 0,
    kind: DInfinity,
  }
}

///|
/// A quiet NaN with the given diagnostic payload (0 for a bare NaN).
pub fn Decimal::nan(negative : Bool, payload : BigInt) -> Decimal {
  Decimal::{ negative, coefficient: payload, exponent: 0, kind: DNan, }
}

///|
/// Whether this value is zero (finite with a zero coefficient).
pub fn Decimal::is_zero(self : Decimal) -> Bool {
  self.kind == DFinite && self.coefficient.is_zero()
}

///|
/// Whether the value is any kind of NaN.
pub fn Decimal::is_nan(self : Decimal) -> Bool {
  self.kind == DNan || self.kind == DSignalingNan
}

///|
/// Whether the sign bit is set. Distinct from "less than zero": -0 and -NaN both
/// report true.
pub fn Decimal::is_negative(self : Decimal) -> Bool {
  self.negative
}

///|
/// Decimal digit count of the coefficient; zero counts as one digit.
pub fn Decimal::digit_count(self : Decimal) -> Int32 {
  digit_count_big(self.coefficient)
}

///|
/// The *adjusted* exponent of §3.5.2: the exponent the value would have if its
/// coefficient were written with a single leading digit, i.e.
/// `exponent + digits - 1`. For zero (digit count 1) this equals the exponent,
/// which is what the standard specifies.
pub fn Decimal::adjusted_exponent(self : Decimal) -> Int32 {
  self.exponent + self.digit_count() - 1
}

///|
/// Render in the standard's *to-scientific-string* form (§5.12.1).
///
/// The rule set is short, but every clause is load bearing:
///
///   - if `exponent <= 0` and `adjusted >= -6`: plain notation, inserting the
///     decimal point `-exponent` digits from the right (padding with zeros)
///   - otherwise: scientific notation, exactly one digit before the point, and an
///     explicit exponent sign
///
/// That is why `-7.50E-7` renders as `-7.50E-7` (adjusted is -7, below -6) while
/// `-0.00000750` renders as `-0.00000750` (adjusted is exactly -6, on the
/// boundary). Getting the boundary wrong is invisible until a full `dectest`
/// transcript is diffed, so `examples/vectors-decimal.tsv` carries the expected
/// text for all 568 vectors and this renderer is tested against that column.
pub fn Decimal::to_scientific_string(self : Decimal) -> String {
  match self.kind {
    DInfinity => if self.negative { "-Infinity" } else { "Infinity" }
    DNan => if self.negative { "-NaN" } else { "NaN" }
    DSignalingNan => if self.negative { "-sNaN" } else { "sNaN" }
    DFinite => {
      let sign = if self.negative { "-" } else { "" }
      if self.coefficient.is_zero() {
        render_zero(sign, self.exponent)
      } else {
        let digits = self.coefficient.to_string(radix=10)
        let n = digits.length()
        let exp = self.exponent
        let adjusted = exp + n - 1
        if exp <= 0 && adjusted >= -6 {
          if exp == 0 {
            sign + digits
          } else {
            let e = -exp
            if e >= n {
              // Fewer significant digits than the scale: pad with zeros.
              sign + "0." + String::make(e - n, '0') + digits
            } else {
              let cut = n - e
              sign + digits[0:cut].to_owned() + "." + digits[cut:].to_owned()
            }
          }
        } else {
          let mantissa = if n == 1 {
            digits
          } else {
            digits[0:1].to_owned() + "." + digits[1:].to_owned()
          }
          let exp_text = if adjusted >= 0 {
            "E+" + adjusted.to_string()
          } else {
            "E" + adjusted.to_string()
          }
          sign + mantissa + exp_text
        }
      }
    }
  }
}

///|
/// Zero needs its own renderer: the general path would treat its single `0` digit
/// as significant and collapse `0E+3` to `0`. The exponent is part of a zero's
/// identity in the wire format, so it has to survive rendering.
fn render_zero(sign : String, exponent : Int32) -> String {
  if exponent == 0 {
    sign + "0"
  } else if exponent > 0 {
    sign + "0E+" + exponent.to_string()
  } else if exponent >= -6 {
    sign + "0." + String::make(-exponent, '0')
  } else {
    sign + "0E" + exponent.to_string()
  }
}

///|
/// Parse the standard's *to-number* form into an exact triple.
///
/// Accepts an optional sign, digits with an optional single decimal point, and an
/// optional `E`-exponent with an optional sign. Deliberately does **not** accept
/// `NaN` or `Infinity` (those are not numbers; the wire layer builds them from
/// fields), nor hex, nor underscores, nor whitespace. A parser that quietly
/// accepts more than the grammar makes a caller error indistinguishable from a
/// decoder bug.
pub fn parse_decimal(text : StringView) -> Decimal raise BitnumError {
  let s = text.to_owned()
  let n = s.length()
  if n == 0 {
    raise InexactConversion("empty string is not a number")
  }
  let mut i = 0
  let mut negative = false
  let first = s.get_char(0).unwrap()
  if first == '-' {
    negative = true
    i = 1
  } else if first == '+' {
    i = 1
  }
  if i >= n {
    raise InexactConversion("sign with no digits: \{s}")
  }
  let dsb = StringBuilder()
  let mut seen_point = false
  let mut frac_digits = 0
  while i < n {
    let c = s.get_char(i).unwrap()
    if c == '.' {
      if seen_point {
        raise InexactConversion("more than one decimal point: \{s}")
      }
      seen_point = true
    } else if c >= '0' && c <= '9' {
      dsb.write_char(c)
      if seen_point {
        frac_digits = frac_digits + 1
      }
    } else {
      break
    }
    i = i + 1
  }
  let digit_text = dsb.to_string()
  if digit_text.length() == 0 {
    raise InexactConversion("no digits in \{s}")
  }
  // The exponent of the triple is one number, not two: `0.01e-99` means
  // `(-2) + (-99)`. Both halves are accumulated in `Int64` because their sum can
  // legitimately leave `Int32` — `0.01e-2147483647` wants `-2147483649` — and an
  // `Int32` sum would wrap into a *plausible* exponent rather than an obviously
  // broken one (BN-B3). The parse therefore never produces a wrapped exponent;
  // it either fits or it is reported by value.
  let mut exponent64 = Int64::from_int(-frac_digits)
  if i < n {
    let c = s.get_char(i).unwrap()
    if c != 'e' && c != 'E' {
      raise InexactConversion("junk after number: \{s}")
    }
    i = i + 1
    let mut exp_negative = false
    if i < n {
      let sc = s.get_char(i).unwrap()
      if sc == '-' {
        exp_negative = true
        i = i + 1
      } else if sc == '+' {
        i = i + 1
      }
    }
    if i >= n {
      raise InexactConversion("exponent sign with no digits: \{s}")
    }
    let esb = StringBuilder()
    while i < n {
      let dc = s.get_char(i).unwrap()
      if dc >= '0' && dc <= '9' {
        esb.write_char(dc)
        i = i + 1
      } else {
        raise InexactConversion("junk after exponent: \{s}")
      }
    }
    let etext = esb.to_string()
    if etext.length() == 0 {
      raise InexactConversion("exponent with no digits: \{s}")
    }
    let mag = digits_to_int64(etext)
    let signed = if exp_negative { -mag } else { mag }
    // Both operands are within `Int32` (the scanner bound `mag` there), so their
    // `Int64` sum cannot overflow `Int64` either. The check is therefore on the
    // *result*, not on the addition: what "overflow" means here is "past the
    // container `Decimal.exponent` can hold", which is the honest bound.
    let total = exponent64 + signed
    if total > 2147483647L || total < -2147483648L {
      raise UnbiasedExponentOutOfRange(total, -2147483648L, 2147483647L)
    }
    exponent64 = total
  }
  let coefficient = BigInt::from_string(digit_text, radix=10)
  Decimal::{
    negative,
    coefficient,
    exponent: exponent64.to_int(),
    kind: DFinite,
  }
}

///|
/// Whether two values are *numerically* equal, ignoring trailing-zero padding and
/// exponent representation. `1.0` and `1.00` are numerically equal but not
/// bit-identically equal as triples; the standard keeps them distinct, and so
/// does this package — which is why both comparisons exist and neither is called
/// just `equal`.
pub fn numerically_equal(a : Decimal, b : Decimal) -> Bool {
  if a.kind != b.kind {
    return false
  }
  match a.kind {
    DFinite => {
      if a.negative != b.negative && not(a.is_zero() && b.is_zero()) {
        return false
      }
      let av = strip_trailing_zeros(a.coefficient)
      let bv = strip_trailing_zeros(b.coefficient)
      if av.is_zero() && bv.is_zero() {
        return true
      }
      av.equal(bv) && a.adjusted_exponent() == b.adjusted_exponent()
    }
    _ => a.negative == b.negative && a.coefficient.equal(b.coefficient)
  }
}

///|
/// Strip decimal trailing zeros from a coefficient.
fn strip_trailing_zeros(v : BigInt) -> BigInt {
  let mut r = v
  let ten = BigInt::from_int(10)
  while not(r.is_zero()) && BigInt::mod(r, ten).is_zero() {
    r = BigInt::div(r, ten)
  }
  r
}

///|
/// Convert an all-digit string to an `Int64` magnitude.
///
/// Hand-rolled rather than delegating to a library parser: the exponent text is
/// already known to be non-empty and all decimal digits (the scanner above rejects
/// anything else), so the only remaining concern is magnitude, and an explicit
/// bound says what happened instead of surfacing a library-specific error.
///
/// The bound is `Int64::max / 10`, not `Int32::max`, because the magnitude and the
/// signed value have different ranges: `1e-2147483648` has an `Int32`-sized
/// magnitude whose negation is exactly `Int32::min`, and that is a value the triple
/// can hold. Only the *signed sum* is checked against `Int32`, so the scanner stays
/// as permissive as the container and the single, honest rejection comes from the
/// arithmetic the audit found broken (BN-B3).
fn digits_to_int64(text : String) -> Int64 raise BitnumError {
  // Int64::max / 10, so folding one more digit in cannot wrap.
  let limit : Int64 = 922337203685477580L
  let mut acc : Int64 = 0L
  for i in 0..<text.length() {
    let c = text.get_char(i).unwrap()
    let d = Int64::from_int(c.to_int() - '0'.to_int())
    if acc > limit {
      raise UnbiasedExponentOutOfRange(acc, 0L, 2147483647L)
    }
    acc = acc * 10L + d
  }
  acc
}
