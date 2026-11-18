///|
/// Decimal is a public datum: for Infinity the coefficient and exponent are
/// meaningless, so a hand-built non-zero coefficient must not change numeric
/// equality. NaN payloads remain significant and are covered by existing tests.
test "decimal: numerically_equal ignores the coefficient of Infinity" {
  let canonical = Decimal::infinity(false)
  let hand_built = Decimal::{
    negative: false,
    coefficient: BigInt::from_int(1),
    exponent: 999,
    kind: DInfinity,
  }
  inspect(numerically_equal(canonical, hand_built), content="true")
  inspect(
    numerically_equal(canonical, Decimal::infinity(true)),
    content="false",
  )
}
