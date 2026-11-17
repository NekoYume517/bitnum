///|
/// Rendering consistency across the two binary formats (2026-11-15 audit).
///
/// The `value` command's value line is the one place the same datum must read
/// the same way regardless of which binary container carries it. Two gaps made
/// bfloat16 the odd one out:
///
///   - `value bfloat16 8000` printed `value=0` with no annotation. The value
///     text itself loses the sign (`Double::to_string` renders -0.0 as "0"),
///     so binary16's `(-0)` annotation is what keeps negative zero visible —
///     and bfloat16 had no annotations at all for zero and infinity.
///   - a negative NaN printed `value=NaN` in both binary formats, while the
///     decimal renderer prints `-NaN`: the sign bit survives the wire and the
///     decoder reports `sign=1`, so the value line dropping it is an
///     inconsistency, not a format property.
///
/// The fix unifies both formats onto the fuller scheme: the annotation set
/// binary16 already had (zero, infinity, min subnormal, exact powers of two)
/// plus a sign-preserving value text for negative NaNs, matching decimal's
/// `-NaN`.

///|
test "describe: bfloat16 carries the same annotations as binary16" {
  // Negative zero: the annotation is what keeps the sign visible.
  inspect(describe_bfloat16(0x8000).contains("(-0)"), content="true")
  inspect(describe_binary16(0x8000).contains("(-0)"), content="true")
  // Positive zero's annotation stays explicit that it is plain zero.
  inspect(describe_bfloat16(0x0000).contains("(0)"), content="true")
  // Infinities: both formats annotate, with the sign.
  inspect(describe_bfloat16(0x7F80).contains("(infinity)"), content="true")
  inspect(describe_bfloat16(0xFF80).contains("(-infinity)"), content="true")
  inspect(describe_binary16(0x7C00).contains("(infinity)"), content="true")
  inspect(describe_binary16(0xFC00).contains("(-infinity)"), content="true")
  // Exact powers of two for normals: binary16 already had the general form,
  // bfloat16 only spelled out 2^0.
  inspect(describe_bfloat16(0x3F80).contains("(2^0)"), content="true")
  inspect(describe_bfloat16(0x4000).contains("(2^1)"), content="true")
  inspect(describe_bfloat16(0x0080).contains("(2^-126)"), content="true")
  inspect(describe_binary16(0x3C00).contains("(2^0)"), content="true")
  // Min subnormal anchors stay as they were.
  inspect(describe_bfloat16(0x0001).contains("(2^-133)"), content="true")
  inspect(describe_binary16(0x0001).contains("(2^-24)"), content="true")
}

///|
test "describe: a negative NaN keeps its sign in the value line" {
  // The wire carries the sign bit and the decoder reports sign=1; the value
  // line must not be the one place it disappears. decimal prints "-NaN" for
  // the same datum, so the binary formats now match it.
  inspect(describe_binary16(0xFE01).contains("value=-NaN"), content="true")
  inspect(describe_bfloat16(0xFFC1).contains("value=-NaN"), content="true")
  // Positive NaNs keep the bare spelling (DEMO §2's locked output), and the
  // payload lines are untouched.
  inspect(describe_binary16(0x7C01).contains("value=NaN"), content="true")
  inspect(describe_bfloat16(0x7FC1).contains("value=NaN"), content="true")
  inspect(describe_bfloat16(0xFFC1).contains("sign=1"), content="true")
  inspect(describe_bfloat16(0xFFC1).contains("significand=65"), content="true")
}

///|
/// The `value` token, per format and per datum — one cell per container.
///
/// This is the matrix the 2026-11-17 audit built: the same datum must read the
/// same way in all five containers, because `value` is the line whose whole job
/// is to state the value. Every column already agreed except `-0`: the binary
/// renderers printed `0` and left the sign to a trailing `(-0)` annotation, while
/// the decimal renderer printed `-0`. API.md §7 claims one spelling across the
/// five formats, so the binary side was made to match the claim rather than the
/// claim being narrowed to an exception.
test "describe: the value token is the same in all five containers" {
  // binary16 / bfloat16 cells.
  inspect(value_token(describe_binary16(0x0000)), content="0")
  inspect(value_token(describe_binary16(0x8000)), content="-0")
  inspect(value_token(describe_binary16(0x7C00)), content="Infinity")
  inspect(value_token(describe_binary16(0xFC00)), content="-Infinity")
  inspect(value_token(describe_binary16(0x7E01)), content="NaN")
  inspect(value_token(describe_binary16(0xFE01)), content="-NaN")
  inspect(value_token(describe_bfloat16(0x0000)), content="0")
  inspect(value_token(describe_bfloat16(0x8000)), content="-0")
  inspect(value_token(describe_bfloat16(0x7F80)), content="Infinity")
  inspect(value_token(describe_bfloat16(0xFF80)), content="-Infinity")
  inspect(value_token(describe_bfloat16(0x7FC1)), content="NaN")
  inspect(value_token(describe_bfloat16(0xFFC1)), content="-NaN")
  // The public value-text helpers are the `table` column, so they must agree
  // with the `describe_*` line they are a part of.
  inspect(binary16_value_text(0x0000), content="0")
  inspect(binary16_value_text(0x8000), content="-0")
  inspect(bfloat16_value_text(0x8000), content="-0")
  // decimal32 / 64 / 128 cells, same datums.
  let f32 : DecimalFormat = Decimal32
  let f64 : DecimalFormat = Decimal64
  let f128 : DecimalFormat = Decimal128
  inspect(
    value_token(describe_decimal(f32, f32.from_hex("22500000"))),
    content="0",
  )
  inspect(
    value_token(describe_decimal(f32, f32.from_hex("A2500000"))),
    content="-0",
  )
  inspect(
    value_token(describe_decimal(f32, f32.from_hex("78000000"))),
    content="Infinity",
  )
  inspect(
    value_token(describe_decimal(f32, f32.from_hex("F8000000"))),
    content="-Infinity",
  )
  inspect(
    value_token(describe_decimal(f32, f32.from_hex("7C000000"))),
    content="NaN",
  )
  inspect(
    value_token(describe_decimal(f32, f32.from_hex("FC000000"))),
    content="-NaN",
  )
  inspect(
    value_token(describe_decimal(f64, f64.from_hex("A238000000000000"))),
    content="-0",
  )
  inspect(
    value_token(
      describe_decimal(f128, f128.from_hex("A2080000000000000000000000000000")),
    ),
    content="-0",
  )
}

///|
/// The token after `value=` on a `describe_*` value line, up to the next space
/// (the annotation column) or the end.
fn value_token(text : String) -> String {
  let start = match find_from(text, "value=") {
    Some(i) => i + 6
    None => return "<no value= field>"
  }
  let mut end = start
  while end < text.length() {
    if text.get_char(end).unwrap() == ' ' {
      break
    }
    end = end + 1
  }
  text[start:end].to_owned()
}

///|
/// Index of `needle` in `text`, or None.
fn find_from(text : String, needle : String) -> Int32? {
  let n = needle.length()
  if n == 0 || text.length() < n {
    return None
  }
  let mut i = 0
  while i + n <= text.length() {
    if text[i:i + n].to_owned() == needle {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// The two lines that carry the `-0` change verbatim, so the exact spelling is
/// locked and not just the token: the sign the value text now shows is the same
/// one the annotation restates.
test "describe: negative zero spells -0 and keeps its annotation" {
  inspect(
    describe_binary16(0x8000),
    content="sign=1  exponent=0 (zero)  significand=0\n" +
      "kind=finite  value=-0   (-0)",
  )
  inspect(
    describe_bfloat16(0x8000),
    content="sign=1  exponent=0 (zero)  significand=0\n" +
      "kind=finite  value=-0   (-0)",
  )
}

///|
test "describe: binary16 value lines stay byte-for-byte as documented" {
  // The existing locked outputs (README/DEMO) must not move. The -0 line did
  // move on 2026-11-17 — deliberately, see the matrix test above: alue now
  // spells the sign itself, so the expected string is alue=-0   (-0).
  inspect(
    describe_binary16(0x0001),
    content="sign=0  exponent=0 (subnormal)  significand=1\n" +
      "kind=finite  value=5.960464477539063e-08   (2^-24)",
  )
  inspect(
    describe_binary16(0x3C00),
    content="sign=0  exponent=15 (normal)  significand=0\n" +
      "kind=finite  value=1   (2^0)",
  )
  inspect(
    describe_binary16(0x8000),
    content="sign=1  exponent=0 (zero)  significand=0\n" +
      "kind=finite  value=-0   (-0)",
  )
}

///|
/// The public value-text helpers are rendering entry points too, not just the
/// `describe_*` functions used by the CLI. They receive the original wire bits,
/// so they can and must preserve a negative NaN's sign just as `describe_*` does.
test "value text helpers preserve a binary NaN's sign" {
  inspect(binary16_value_text(0xFE01), content="-NaN")
  inspect(bfloat16_value_text(0xFFC1), content="-NaN")
  inspect(binary16_value_text(0x7E01), content="NaN")
  inspect(bfloat16_value_text(0x7FC1), content="NaN")
}

///|
/// Infinity has a sign but no diagnostic payload. Only NaNs carry the latter;
/// printing `payload=0` for Infinity invents a field that the format does not have.
test "describe: decimal Infinity is not given a NaN payload" {
  let f32 : DecimalFormat = Decimal32
  let f64 : DecimalFormat = Decimal64
  let f128 : DecimalFormat = Decimal128
  inspect(
    describe_decimal(f32, f32.from_hex("78000000")),
    content="sign=0\nkind=infinity  value=Infinity",
  )
  inspect(
    describe_decimal(f64, f64.from_hex("F800000000000000")),
    content="sign=1\nkind=infinity  value=-Infinity",
  )
  inspect(
    describe_decimal(f128, f128.from_hex("78000000000000000000000000000000")),
    content="sign=0\nkind=infinity  value=Infinity",
  )
  inspect(
    describe_decimal(f128, f128.from_hex("7C000000000000000000000000000000")),
    content="sign=0  payload=0\nkind=nan  value=NaN",
  )
}
