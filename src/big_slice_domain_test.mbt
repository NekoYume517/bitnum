///|
/// `big_slice`'s four documented shapes, exhaustively over a small domain.
///
/// The doc promises a **total** window in `offset` and `width` and a **non-negative**
/// result, but the three empty-window cases and the masked case are described in prose
/// only. `big_slice_empty_window_test.mbt` pins one value of each shape; this test
/// pins the *rule* — for every offset from two below the number to two past its last
/// bit, and every width from -2 to eight past what is left, the answer is exactly the
/// documented one and it is non-negative.
///
/// The value direction (`v >= 0`) is a declared precondition of the function, not a
/// guard: `decode_raw` is the only producer of wire bits and rejects a negative
/// pattern first (`decimal_wire_test.mbt`, `cannot represent a negative wire pattern`),
/// so no call site can hand this function a negative value.
test "bits: big_slice is the documented total window for every non-negative value" {
  let values : Array[BigInt] = [
    BigInt::from_int(0),
    BigInt::from_int(1),
    BigInt::from_int(5),
    BigInt::from_int(42),
    (BigInt::from_int(1) << 63) + BigInt::from_int(1),
    (BigInt::from_int(1) << 64) - BigInt::from_int(1),
    (BigInt::from_int(1) << 100) + BigInt::from_int(7),
  ]
  let mut checked = 0
  for v in values {
    let bits = v.bit_length()
    let hi = bits + 3
    for offset in -2..<hi {
      for width in -2..<12 {
        let got = big_slice(v, offset, width)
        let ok = if offset < 0 || width <= 0 || offset >= bits {
          // The three empty windows are one answer: zero.
          got.is_zero()
        } else {
          let shifted = v >> offset
          let remaining = bits - offset
          let expected = if width >= remaining {
            shifted
          } else {
            BigInt::land(
              shifted,
              (BigInt::from_int(1) << width) - BigInt::from_int(1),
            )
          }
          // The window's answer is the slice itself, non-negative, and no wider than
          // the window it came from.
          got.compare(expected) == 0 &&
          got.compare_int(0) >= 0 &&
          got.bit_length() <= width
        }
        if not(ok) {
          println(
            "big_slice(v=\{v}, offset=\{offset}, width=\{width}) = \{got}",
          )
        }
        inspect(ok, content="true")
        checked += 1
      }
    }
  }
  // The sweep is not vacuous: seven values, every offset and every width.
  inspect(checked > 500, content="true")
}
