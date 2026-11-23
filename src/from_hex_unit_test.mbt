///|
/// BN-2026-11-23-3 (2026-11-23 audit, P3): `from_hex`'s width rejection went
/// through `TruncatedInput`, whose sentence was `need N bytes, got M` — but
/// `from_hex` counts **hex digits**, not bytes: its `needed` is `hex_width()`
/// and its `got` is `text.length()`. For decimal64 the sentence said
/// `need 16 bytes, got 15` about a container that is 8 bytes wide; the unit
/// was the CLI's translation, spoken in the library's own voice.
///
/// One variant serves two entry points that count different units
/// (`decode_bytes` really does count bytes), so the shared sentence cannot
/// name either unit without lying to the other caller. The neutral sentence
/// (`needed N, got M`) keeps both numbers; the unit contract lives in the
/// field docs (`error.mbt`) and each entry point's own doc comment, and the
/// CLI keeps translating to hex digits byte for byte —
/// `wire_width_message_test.mbt` builds the byte-count sentence from the
/// fields for `decode_bytes`, which is the caller the unit was true for.
test "from_hex: the width rejection does not claim a unit it does not count" {
  let f64 : DecimalFormat = Decimal64
  let short = try {
    let _ = f64.from_hex("A2300000000003D")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(short, content="needed 16, got 15")
  // The other caller of the same variant counts bytes; it shares the neutral
  // sentence, and the numbers stay exactly what it used to print.
  let bytes = try {
    let _ = f64.decode_bytes(b"\x00\x00\x00\x00\x00\x00\x00\x00\xFF")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(bytes, content="needed 8, got 9")
}
