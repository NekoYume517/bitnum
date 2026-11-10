///|
/// BN-B3 (2026-11-10 audit, P2): the exponent arithmetic in `parse_decimal` and in
/// `encode_raw` wrapped through `Int32`, and the resulting message described a
/// number nobody wrote.
///
/// The fractional-digit count and the explicit exponent are algebraically one
/// number: `0.01e-2147483647` means `1 x 10^(-2 - 2147483647)`. Both halves were
/// `Int32` and the sum had no overflow check, so the true `-2147483649` wrapped to
/// a *plausible* `+2147483647`; the encoder then added the bias and wrapped a
/// second time, reporting
/// `biased exponent -2147483548 out of range [0, 197]`.
///
/// `1e2147483647` never wrapped in the parse — `2147483647` fits `Int32` — but the
/// bias sum did, so it printed the same `-2147483548`. That is why the fix has to
/// cover both sites, and why both are asserted here.
test "parse_decimal: an exponent sum that overflows Int32 is rejected with its true value" {
  // -2 from the fraction and -2147483647 explicit: -2147483649, one past Int32::min.
  let deep = try {
    let _ = parse_decimal("0.01e-2147483647")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(deep.contains("-2147483649"), content="true")
  // The wrapped value must be gone entirely: it used to be the *reported* number.
  inspect(deep.contains("-2147483548"), content="false")
  // The wording is about a true exponent, not a biased one (BN-B5's split).
  inspect(deep.contains("biased"), content="false")
}

///|
/// The same sum past `Int32::max`: `0.1e2147483647` is `(-1) + 2147483647`, which
/// fits, so the boundary has to be checked from both sides — accepted here,
/// rejected one digit further out.
test "parse_decimal: the sum's upper boundary is accepted exactly where it fits" {
  let fits = parse_decimal("0.1e2147483647")
  inspect(fits.exponent, content="2147483646")
  let exact_max = parse_decimal("1e2147483647")
  inspect(exact_max.exponent, content="2147483647")
  let exact_min = parse_decimal("0.1e-2147483647")
  inspect(exact_min.exponent, content="-2147483648")
}

///|
/// The encoder's own sum had the second wrap. `1e2147483647` is a legal triple
/// (the exponent fits), so `parse_decimal` accepts it and `encode_raw` is what
/// rejects — and the number it must name is the true biased value
/// `2147483647 + 101 = 2147483748`, not the wrapped `-2147483548`.
test "encode_raw: the biased sum is reported without wrapping" {
  let f : DecimalFormat = Decimal32
  let v = parse_decimal("1e2147483647")
  inspect(v.exponent, content="2147483647")
  let msg = try {
    let _ = f.encode_raw(v)
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(msg.contains("2147483748"), content="true")
  inspect(msg.contains("-2147483548"), content="false")
  // And the biased wording is right for this branch: it really is a biased value.
  inspect(msg.contains("biased exponent"), content="true")
}

///|
/// A magnitude too wide even for `Int64` is still reported by value rather than
/// wrapping. The scanner's guard is on the accumulator, so the number in the
/// message is a prefix of the input — never a negative number minted by overflow.
test "parse_decimal: an astronomically wide exponent reports a positive magnitude" {
  let msg = try {
    let _ = parse_decimal("1e99999999999999999999999999")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(msg.contains("-"), content="false")
  inspect(msg.contains("exponent"), content="true")
}

///|
/// The check must not reject exponents the container can legitimately hold: every
/// `dectest`-style triple still parses to the same exponent it always did.
test "parse_decimal: in-range exponents still parse unchanged" {
  let a = parse_decimal("0.01e-99")
  inspect(a.exponent, content="-101")
  let b = parse_decimal("1E+90")
  inspect(b.exponent, content="90")
  let c = parse_decimal("-7.50")
  inspect(c.exponent, content="-2")
  let d = parse_decimal("9.999999E+96")
  inspect(d.exponent, content="90")
  let e = parse_decimal("1e2147483646")
  inspect(e.exponent, content="2147483646")
}
