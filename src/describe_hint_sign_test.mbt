///|
/// Every parenthetical hint on the `value` line must agree with the sign the value
/// text prints.
///
/// The set already carried the sign for the two datums where the annotation was doing
/// real work: `(-0)` (before 2026-11-17 it was the only place negative zero survived)
/// and `(-infinity)`. The power-of-two hints did not, so `value binary16 C000` printed
/// `value=-2   (2^1)` — a line whose two halves disagree about the sign of the datum.
/// The fix is not a new vocabulary: it is the rule the other two hints already follow.
test "describe: a negative power-of-two hint carries its sign" {
  // binary16: the three hint shapes, both signs.
  inspect(
    describe_binary16(0xC000).contains("value=-2   (-2^1)"),
    content="true",
  )
  inspect(describe_binary16(0x4000).contains("value=2   (2^1)"), content="true")
  inspect(
    describe_binary16(0x8001).contains(
      "value=-5.960464477539063e-08   (-2^-24)",
    ),
    content="true",
  )
  inspect(
    describe_binary16(0x0001).contains("value=5.960464477539063e-08   (2^-24)"),
    content="true",
  )
  inspect(describe_binary16(0xC000).contains("(2^-1)"), content="false")
  inspect(
    describe_binary16(0x8400).contains("value=-0.00006103515625   (-2^-14)"),
    content="true",
  )
  inspect(
    describe_binary16(0x0400).contains("value=0.00006103515625   (2^-14)"),
    content="true",
  )
  // The datums whose hints already had a sign are unchanged.
  inspect(describe_binary16(0x8000).contains("value=-0   (-0)"), content="true")
  inspect(
    describe_binary16(0x7C00).contains("value=Infinity   (infinity)"),
    content="true",
  )
  inspect(
    describe_binary16(0xFC00).contains("value=-Infinity   (-infinity)"),
    content="true",
  )
  inspect(describe_binary16(0xFE00).contains("value=-NaN"), content="true")
  // A non-anchor datum still carries no hint at all.
  inspect(describe_binary16(0x3C01).contains("(2^"), content="false")
}

///|
/// The same rule on bfloat16, which mirrors the annotation set on purpose: the two
/// binary containers must diagnose one datum the same way.
test "describe: bfloat16's negative power-of-two hint carries its sign" {
  inspect(
    describe_bfloat16(0xBF80).contains("value=-1   (-2^0)"),
    content="true",
  )
  inspect(describe_bfloat16(0x3F80).contains("value=1   (2^0)"), content="true")
  inspect(
    describe_bfloat16(0xC000).contains("value=-2   (-2^1)"),
    content="true",
  )
  inspect(
    describe_bfloat16(0x8001).contains(
      "value=-9.183549615799121e-41   (-2^-133)",
    ),
    content="true",
  )
  inspect(
    describe_bfloat16(0x0001).contains("value=9.183549615799121e-41   (2^-133)"),
    content="true",
  )
  inspect(describe_bfloat16(0x8000).contains("value=-0   (-0)"), content="true")
  inspect(
    describe_bfloat16(0xFF80).contains("value=-Infinity   (-infinity)"),
    content="true",
  )
  inspect(describe_bfloat16(0xFFC0).contains("value=-NaN"), content="true")
  inspect(describe_bfloat16(0x3F81).contains("(2^"), content="false")
}
