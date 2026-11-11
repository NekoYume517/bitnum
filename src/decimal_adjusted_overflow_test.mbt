///|
/// Regression: the *adjusted* exponent of a legal triple does not fit `Int32`.
///
/// `adjusted = exponent + digits - 1`. The container holds any `Int32` exponent
/// and a coefficient of up to 34 digits, so the adjusted exponent needs 33 bits:
/// `parse_decimal("10e2147483647")` is a legal triple whose adjusted exponent is
/// `2147483648`. Computing that sum in `Int32` wraps it to `-2147483648`, which
/// makes an astronomical value look like an infinitesimal one:
///
/// - `numerically_equal` compares adjusted exponents, so it reported
///   `10e2147483647` and `1e-2147483648` as *numerically equal*;
/// - `to_scientific_string` renders the wrapped value, so the same triple came
///   out as `1.0E-2147483648` — the sign flipped and 33 bits of magnitude lost.
///
/// Neither is caught by any test that stays inside the formats' own exponent
/// ranges, because `Emax` (90 / 369 / 6111) is nowhere near `Int32::MAX`. The
/// triples are reachable from both public entry points: `parse_decimal` accepts
/// them and `Decimal::make` does not bound the exponent.
test "decimal: adjusted exponent does not wrap at the Int32 boundary" {
  let a = parse_decimal("10e2147483647")
  inspect(a.adjusted_exponent(), content="2147483648")
  let b = parse_decimal("1e-2147483648")
  inspect(b.adjusted_exponent(), content="-2147483648")
  // The two values are 10^2147483648 and 10^-2147483648; no reading of
  // "numerically equal" makes them equal.
  inspect(numerically_equal(a, b), content="false")
  // And the renderer must print the adjusted exponent it actually has.
  inspect(a.to_scientific_string(), content="1.0E+2147483648")
  inspect(b.to_scientific_string(), content="1E-2147483648")
}

///|
/// The same sum must still behave at the ordinary end, including the `-6`
/// boundary the standard's plain/scientific switch sits on.
test "decimal: adjusted exponent keeps its ordinary values" {
  inspect(parse_decimal("-0.00000750").adjusted_exponent(), content="-6")
  inspect(parse_decimal("-7.50e-7").adjusted_exponent(), content="-7")
  inspect(parse_decimal("1").adjusted_exponent(), content="0")
  inspect(
    numerically_equal(parse_decimal("1.0"), parse_decimal("1.00")),
    content="true",
  )
  inspect(
    numerically_equal(parse_decimal("1.0"), parse_decimal("1.01")),
    content="false",
  )
}
