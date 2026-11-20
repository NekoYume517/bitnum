///|
/// The five formats' `value` tokens for every special datum, pinned as bytes.
///
/// API §7 claims "五种格式的 `value` 输出口径一致". The claim is about the *token*, so
/// it is locked here as a token: the decimal formats spell `Infinity`, `NaN` and
/// `sNaN` with the sign in front, and the two binary formats must spell the same three
/// the same way, including the negatives. A NaN's diagnostic payload lives on the
/// `payload=` line and must never leak into the value text.
///
/// The decimal side also covers the third NaN spelling that the binary side does not
/// have: `0x7E000000` is a *signaling* NaN and prints `sNaN` (2026-11-20 audit), while
/// every other bit pattern that is a NaN prints `NaN` whether or not the quiet bit is
/// set — which is why `0x7D000000` and `0x7C000000` must agree here.
test "describe: decimal specials spell one set of value tokens" {
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  let cases : Array[(Decimal, String)] = [
    (Decimal::infinity(false), "kind=infinity  value=Infinity"),
    (Decimal::infinity(true), "kind=infinity  value=-Infinity"),
    (Decimal::nan(false, BigInt::from_int(0)), "kind=nan  value=NaN"),
    (Decimal::nan(true, BigInt::from_int(0)), "kind=nan  value=-NaN"),
    (Decimal::nan(false, BigInt::from_int(1)), "kind=nan  value=NaN"),
    (Decimal::nan(true, BigInt::from_int(1)), "kind=nan  value=-NaN"),
    (
      Decimal::{
        negative: false,
        coefficient: BigInt::from_int(0),
        exponent: 0,
        kind: DSignalingNan,
      },
      "kind=signaling-nan  value=sNaN",
    ),
    (
      Decimal::{
        negative: true,
        coefficient: BigInt::from_int(0),
        exponent: 0,
        kind: DSignalingNan,
      },
      "kind=signaling-nan  value=-sNaN",
    ),
    (
      Decimal::{
        negative: false,
        coefficient: BigInt::from_int(7),
        exponent: 0,
        kind: DSignalingNan,
      },
      "kind=signaling-nan  value=sNaN",
    ),
    (Decimal::zero(false, 0), "kind=finite  value=0"),
    (Decimal::zero(true, 0), "kind=finite  value=-0"),
  ]
  for f in formats {
    for pair in cases {
      let raw = f.encode_raw(pair.0)
      inspect(describe_decimal(f, raw).contains(pair.1), content="true")
    }
    // A payload that is not zero must stay on the `payload=` line and out of the
    // value text, on all three widths.
    let payload = f.encode_raw(Decimal::nan(true, BigInt::from_int(1)))
    inspect(describe_decimal(f, payload).contains("-NaN"), content="true")
  }
}

///|
/// The same three tokens on the binary side, where the equality also has to reach the
/// annotation: `(0)` / `(-0)`, `(infinity)` / `(-infinity)`.
test "describe: binary specials spell the same tokens as the decimal side" {
  let b16 : Array[(UInt16, String)] = [
    (0x0000, "kind=finite  value=0   (0)"),
    (0x8000, "kind=finite  value=-0   (-0)"),
    (0x7C00, "kind=infinity  value=Infinity   (infinity)"),
    (0xFC00, "kind=infinity  value=-Infinity   (-infinity)"),
    (0x7E00, "kind=nan  value=NaN"),
    (0xFE00, "kind=nan  value=-NaN"),
    // A NaN with a payload is still spelled `NaN`: the payload is not in this text.
    (0x7E01, "kind=nan  value=NaN"),
    (0xFE01, "kind=nan  value=-NaN"),
  ]
  for pair in b16 {
    inspect(describe_binary16(pair.0).contains(pair.1), content="true")
  }
  let bf : Array[(UInt16, String)] = [
    (0x0000, "kind=finite  value=0   (0)"),
    (0x8000, "kind=finite  value=-0   (-0)"),
    (0x7F80, "kind=infinity  value=Infinity   (infinity)"),
    (0xFF80, "kind=infinity  value=-Infinity   (-infinity)"),
    (0x7FC0, "kind=nan  value=NaN"),
    (0xFFC0, "kind=nan  value=-NaN"),
    (0x7FC1, "kind=nan  value=NaN"),
    (0xFFC1, "kind=nan  value=-NaN"),
  ]
  for pair in bf {
    inspect(describe_bfloat16(pair.0).contains(pair.1), content="true")
  }
}
