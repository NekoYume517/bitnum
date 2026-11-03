///|
/// Regression test for the README's library snippet.
///
/// The README shows this code to users; if it stops compiling, the first thing a
/// reader tries fails. Testing it here is the only way to keep the docs honest
/// against the real API — and it earned its keep immediately: `Decimal64` is an
/// enum *variant*, so it has to be bound to a `let` before the method call
/// (`DecimalFormat::encode_bytes(Decimal64, v)` also works), and the encoder can
/// raise (the test itself may raise, so the call reads plainly here).
test "readme: library snippet works as documented" {
  // binary16 bit pattern -> field breakdown -> exact value
  let d = Binary16::decode(0x3C00)
  let v = d.to_f64()
  let diff = v - 1.0
  assert_true(diff.abs() < 0.0000000000001)

  // decimal triple -> decimal64 wire format
  let fmt : DecimalFormat = Decimal64
  let value = Decimal::make(true, BigInt::from_int(750), -2)
  let bytes = fmt.encode_bytes(value)
  inspect(hex_of_test(bytes), content="A2300000000003D0")
  let back = fmt.decode_bytes(bytes).value
  inspect(back.negative, content="true")
  inspect(back.coefficient.to_string(), content="750")
  inspect(back.exponent, content="-2")
  inspect(back.to_scientific_string(), content="-7.50")
}

///|
/// Hex helper for this test file, so the assertion above reads like the README's
/// own output rather than a byte-index chain.
fn hex_of_test(b : Bytes) -> String {
  let sb = StringBuilder()
  for i in 0..<b.length() {
    let v = b[i].to_int()
    sb.write_char(hex_digit_char(v >> 4))
    sb.write_char(hex_digit_char(v & 0xF))
  }
  sb.to_string()
}

///|
fn hex_digit_char(n : Int32) -> Char {
  if n < 10 {
    (48 + n).unsafe_to_char()
  } else {
    (55 + n).unsafe_to_char()
  }
}
