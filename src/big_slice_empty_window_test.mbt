///|
/// An empty bit window must not allocate the mask for a non-empty one.
test "big_slice: a zero value returns immediately for a huge empty window" {
  inspect(
    big_slice(BigInt::from_int(0), 0, 2147483647).compare_int(0),
    content="0",
  )
}

///|
/// Starting beyond the value's bits is empty even when the requested width is huge.
test "big_slice: a window past the value returns immediately for a huge width" {
  inspect(
    big_slice(BigInt::from_int(255), 64, 2147483647).compare_int(0),
    content="0",
  )
}

///|
/// Non-empty windows keep their bit-level results.
test "big_slice: ordinary non-empty windows are unchanged" {
  let v = BigInt::from_int(255)
  inspect(big_slice(v, 0, 4).to_string(), content="15")
  inspect(big_slice(v, 4, 4).to_string(), content="15")
  inspect(big_slice(v, 7, 1).to_string(), content="1")
  inspect(big_slice(v, 7, 2147483647).to_string(), content="1")
}

///|
/// Empty and untruncated windows preserve their bit-level answers at huge widths.
test "big_slice: huge empty and untruncated windows" {
  inspect(
    big_slice(BigInt::from_int(0), 0, 2147483647).to_string(),
    content="0",
  )
  inspect(
    big_slice(BigInt::from_int(255), 64, 2147483647).to_string(),
    content="0",
  )
  inspect(
    big_slice(BigInt::from_int(255), 7, 2147483647).to_string(),
    content="1",
  )
}
