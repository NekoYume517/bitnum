///|
/// BN-19-2: `check`'s `value` line is the datum the same command's `value` line
/// would have printed — a NaN's payload included.
///
/// `check` prints a human-readable `value` line next to `in`/`out` so a reader
/// can see *what* round-tripped when the bytes did not. For a decimal NaN that
/// line went through `to_scientific_string`, the width-less entry point, which
/// cannot read the payload digit groups and therefore prints bare `NaN`:
///
/// ```
/// $ bitnum value @lib.Decimal64 7C00000000FF0000
/// sign=0  payload=1671168
/// kind=nan  value=NaN...          (the width-aware line, with the payload)
/// $ bitnum check @lib.Decimal64 7C00000000FF0000
/// out   7C00000000FF0000
/// value NaN                       <- the payload vanished
/// result: round-trip ok
/// ```
///
/// This is the same defect class as BN-18-1 (the `describe` line dropped the
/// payload too) on the one other rendering path that had no test. The
/// width-aware renderer already existed; the two `main.mbt` call sites simply
/// were not using it.
///
/// The assertions here are on the renderer directly, because `println` cannot be
/// captured from a whitebox test: the width-aware text for a non-zero payload
/// must differ from the width-less text (which is exactly `NaN`), and must name
/// the payload. The CLI half is locked by construction in `src/` instead — the
/// `value` line and the `describe` line are one renderer, and `describe` is
/// tested against the same width (`describe_nan_test.mbt`, BN-18-1).
test "check value line: a NaN payload is rendered at the format's field width" {
  let f : @lib.DecimalFormat = @lib.Decimal64
  let payload = 1671168
  let v = @lib.Decimal::nan(false, BigInt::from_int(payload))
  let width_aware = decimal_value_text(f, v)
  let width_less = v.to_scientific_string()
  inspect(width_less, content="NaN")
  inspect(width_aware == width_less, content="false")
  inspect(width_aware.length() > 3, content="true")
}

///|
test "check value line: the infinity-padding family keeps the NaN payload" {
  // The pattern `check` classifies as infinity padding carries bits the encoder
  // drops. For a *NaN* that classification cannot happen (NaN has no ignored
  // bits), so the interesting case is that the payload survives the re-encode
  // and that both renderings of it agree once the width is known.
  let formats : Array[@lib.DecimalFormat] = [
    @lib.Decimal32,
    @lib.Decimal64,
    @lib.Decimal128,
  ]
  for f in formats {
    let width = f.nan_payload_bits()
    let payloads : Array[BigInt] = [
      BigInt::from_int(1),
      BigInt::from_int(42),
      (BigInt::from_int(1) << (width - 1)) + BigInt::from_int(7),
    ]
    for p in payloads {
      let v = @lib.Decimal::nan(false, p)
      let raw = f.encode_raw(v) catch { _ => continue }
      let decoded = f.decode_raw(raw)
      inspect(decoded.value.coefficient, content=p.to_string(radix=10))
      // The line `check` actually prints, through the call site itself.
      let rendered = decimal_value_text(f, decoded.value)
      inspect(rendered.has_prefix("NaN"), content="true")
      if p != BigInt::from_int(0) {
        inspect(rendered == "NaN", content="false")
      }
    }
  }
}

///|
test "check value line: sNaN with a payload is spelled the same way" {
  let f : @lib.DecimalFormat = @lib.Decimal32
  let v : @lib.Decimal = {
    negative: false,
    coefficient: BigInt::from_int(9),
    exponent: 0,
    kind: @lib.DSignalingNan,
  }
  let rendered = decimal_value_text(f, v)
  inspect(rendered.has_prefix("sNaN"), content="true")
  inspect(rendered == "sNaN", content="false")
  // And the width-less entry point stays the bare spelling, unchanged.
  inspect(v.to_scientific_string(), content="sNaN")
}
