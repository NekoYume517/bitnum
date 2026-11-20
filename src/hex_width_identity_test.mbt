///|
/// `to_hex` keeps the container's own width for every `BigInt`, and `from_hex`
/// reverses it exactly on that set.
///
/// `to_hex` clamps (API §6: a wider value is reported as the container's all-ones
/// pattern, a negative one as zero) and pads to `hex_width`. Those two rules together
/// are what makes the hex spelling a *width* and not a magnitude: a caller can count
/// characters and know the format. `decimal_vector_test.mbt` exercises the middle of
/// the range; this test pins the ends and the two out-of-range sides, where the
/// clamping happens, on all three widths.
test "decimal wire: to_hex always prints exactly hex_width characters" {
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  for f in formats {
    let width = f.hex_width()
    let top = (BigInt::from_int(1) << f.bits()) - BigInt::from_int(1)
    let over = BigInt::from_int(1) << f.bits()
    // In range: width characters, and the round trip through `from_hex` is exact.
    for raw in [BigInt::from_int(0), BigInt::from_int(1), top] {
      let text = f.to_hex(raw)
      inspect(text.length(), content="\{width}")
      inspect(f.from_hex(text).compare(raw), content="0")
    }
    // Out of range: the clamp is the container's convention, and the width survives.
    let over_text = f.to_hex(over)
    inspect(over_text.length(), content="\{width}")
    inspect(
      over_text.contains("ff") || over_text.contains("FF"),
      content="true",
    )
    inspect(f.from_hex(over_text).compare(top), content="0")
    let negative = f.to_hex(BigInt::from_int(-1))
    inspect(negative.length(), content="\{width}")
    inspect(f.from_hex(negative).compare_int(0), content="0")
    // `from_hex` takes the width and only the width, on both sides of it.
    // Both sides of the width are the same rejection, and the numbers are hex digits
    // (the sentence still spells them as bytes — a unit slip recorded in the report,
    // not endorsed here: the *point* of this lock is that the count is the digit count).
    for off in [-1, 1] {
      let outcome = try {
        let _ = f.from_hex(text_of_zeros(width + off))
        "accepted"
      } catch {
        TruncatedInput(needed, got) => "digits \{needed} vs \{got}"
        e => "wrong variant: \{e.describe()}"
      }
      inspect(outcome, content="digits \{width} vs \{width + off}")
    }
  }
}

///|
/// `count` zeros, for building a hex string of a chosen width.
fn text_of_zeros(count : Int32) -> String {
  let mut out = ""
  let mut i = 0
  while i < count {
    out = out + "0"
    i += 1
  }
  out
}
