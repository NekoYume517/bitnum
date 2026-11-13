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
/// A magnitude too wide even for `Int64` is reported as a **saturated** value with
/// the input's own sign, against the container's real bound `[-2147483648,
/// 2147483647]`. The pre-2026-11-12 version reported the scanned prefix against
/// `[0, 2147483647]`, and the locking test only asserted "no minus sign" — an
/// assertion about a proxy that also ruled out the honest negative lower bound
/// (2026-11-12 audit, C1). Saturating is the honest statement of degree: the input
/// is far past the container, and no number is minted by wrapping.
test "parse_decimal: an astronomically wide positive exponent saturates at Int64::max" {
  let msg = try {
    let _ = parse_decimal("1e99999999999999999999999999")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(
    msg.contains(
      "exponent 9223372036854775807 out of range [-2147483648, 2147483647]",
    ),
    content="true",
  )
}

///|
/// The same magnitude with a negative exponent sign saturates to `Int64::min` —
/// the sign of the report follows the sign of the input, which is exactly what the
/// old `contains("-")` check could not express.
test "parse_decimal: an astronomically wide negative exponent saturates at Int64::min" {
  let msg = try {
    let _ = parse_decimal("1e-99999999999999999999999999")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(
    msg.contains(
      "exponent -9223372036854775808 out of range [-2147483648, 2147483647]",
    ),
    content="true",
  )
}

///|
/// D1 (2026-11-13 audit, P2): the guard in `digits_to_int64` fired one digit too
/// late, and the machine underneath it is what made that expensive.
///
/// The guard was `acc > Int64::max / 10` and was tested *before* folding a digit
/// in, so the equality case slipped through: with `acc == 922337203685477580` a
/// last digit of `8` or `9` computes `acc * 10 + d`, which is `2^63` / `2^63 + 1`
/// — past `Int64::max`. Two's-complement wrap takes it to `Int64::min` /
/// `Int64::min + 1`, and from there `acc * 10` is `0` (or `10`) mod `2^64`, so the
/// *remaining* digits fold into a small number and no later guard can fire.
///
/// Consequences, both reproduced below:
///
///   - `1e9223372036854775808` reported `exponent -9223372036854775808`, i.e. the
///     opposite sign from the one the user typed, contradicting the saturation
///     contract (`API.md` §8: report `Int64::MAX` for a positive exponent);
///   - `1e92233720368547758080` **parsed successfully** as `1` at exponent `0`. A
///     nonzero literal two orders of magnitude past the container became a plain
///     `1`, silently — the one outcome `parse_decimal` is not allowed to produce
///     (PLAN.md §1.2: never silently correct a non-canonical input).
///
/// The old tests could not see it because they used all-`9` exponents, where the
/// guard fires on the *first* digit of the overflow and never reaches the edge.
test "parse_decimal: a magnitude past Int64 saturates, it never wraps into a value" {
  // One past Int64::max. The sign of the report follows the input's own sign.
  let pos = try {
    let _ = parse_decimal("1e9223372036854775808")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(
    pos.contains(
      "exponent 9223372036854775807 out of range [-2147483648, 2147483647]",
    ),
    content="true",
  )
  let neg = try {
    let _ = parse_decimal("1e-9223372036854775809")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(
    neg.contains(
      "exponent -9223372036854775808 out of range [-2147483648, 2147483647]",
    ),
    content="true",
  )
  // The silent-acceptance half: 20 digits whose 19-digit prefix is exactly
  // `Int64::max + 1`. Before the fix this returned a Decimal (exponent 0).
  let wrapped = try {
    let v = parse_decimal("1e92233720368547758080")
    "parsed as exponent \{v.exponent}"
  } catch {
    e => e.describe()
  }
  inspect(wrapped.contains("out of range"), content="true")
  let wrapped_neg = try {
    let v = parse_decimal("1e-92233720368547758080")
    "parsed as exponent \{v.exponent}"
  } catch {
    e => e.describe()
  }
  inspect(wrapped_neg.contains("out of range"), content="true")
  // Exactly `Int64::max` still saturates upward rather than being refused as a
  // *lexical* problem: the magnitude fits, the container does not.
  let exact = try {
    let _ = parse_decimal("1e9223372036854775807")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(
    exact.contains("exponent 9223372036854775807 out of range"),
    content="true",
  )
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
