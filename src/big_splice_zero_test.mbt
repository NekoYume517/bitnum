///|
/// Zero shifted by any width is still zero, so the OR is exactly `to`.
test "big_splice: zero from is an identity at a huge width" {
  let to = (BigInt::from_int(1) << 80) + BigInt::from_int(3)
  inspect(
    big_splice(BigInt::from_int(0), to, 2147483647).equal(to),
    content="true",
  )
}

///|
/// The identity does not change the established negative-width normalization.
test "big_splice: negative width still means zero-width OR" {
  let from = BigInt::from_int(1)
  let to = BigInt::from_int(4)
  inspect(big_splice(from, to, -2147483648).to_string(), content="5")
  inspect(
    big_splice(BigInt::from_int(0), to, -2147483648).to_string(),
    content="4",
  )
}
