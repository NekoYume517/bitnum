///|
/// A hex argument is caller text, and `String::length()` counts UTF-16 code
/// units while `get_char(i)` addresses Unicode scalars by that code-unit
/// offset — so an astral-plane character (anything above U+FFFF: an emoji, a
/// mathematical alphanumeric, a CJK extension ideograph) makes `get_char`
/// return `None` for its low-surrogate half. The old `hex_digit` unwrapped
/// that `None`, so `bitnum value binary16 🐛` aborted with a `PanicError`
/// instead of reporting the non-hex character (2026-11-17 audit, BN-n):
///
/// ```
/// $ bitnum value binary16 🐛
/// PanicError
///     at moonbit_panic
///     at ??? (…)
/// exit=-1073740791          # not 1, not 2: the process died
/// ```
///
/// The panic fired exactly where an index landed on a low-surrogate half, which
/// the eager `hex_digit` calls reach even when the neighbouring index already
/// failed. Making `hex_digit` total — `None` instead of `unwrap()` — turns the
/// same input into the ordinary rejection, and the even-length pre-check cannot
/// protect the loop: `"🐛".length() == 2` passes it.
///
/// The decimal entry (`from_hex`) is safe for the same input: its loop raises
/// at the first non-hex *scalar*, which always precedes any low-surrogate half
/// it would have reached, so the library side never meets this `unwrap`.
/// The CLI's byte-wise hex reader is the one path that walks every code unit,
/// which is why this file lives in `cmd/`.
test "hex input: an astral-plane character is rejected, not a panic" {
  // Each of these used to abort the process (exit -1073740791). The even-length
  // check passes for `🐛` (length 2), and `00𝔸𝔸𝔸` is eight code units — the
  // same shape as a valid 4-byte hex string — so both reached the unwrap.
  let bad : Array[String] = [
    "🐛", "🐛🐛", "𝔸", "00𝔸𝔸𝔸", "A🐛B", "7E🐛",
  ]
  for text in bad {
    inspect(parse_hex_bytes(text) is None, content="true")
    inspect(expect_two_bytes(text, "binary16") is None, content="true")
  }
  // The command layer turns the rejection into the ordinary data error.
  inspect(cmd_value("binary16", "🐛") catch { _ => -1 }, content="1")
  inspect(cmd_check("bfloat16", "🐛") catch { _ => -1 }, content="1")
  // ASCII hex still parses; the fix must not have broadened the rejection.
  let ok = parse_hex_bytes("7E00")
  match ok {
    Some(b) => inspect(bytes_to_u16(b).to_int(), content="32256")
    None => inspect("rejected", content="parsed")
  }
}

///|
/// Full Unicode uppercase mappings must not expand caller text into ASCII hex.
/// `ﬀ` has a full mapping to `FF`; four copies still occupy exactly four UTF-16
/// code units and must be rejected rather than interpreted as binary16 `FFFF`.
test "hex input: BMP uppercase expansions are not ASCII hex" {
  for text in ["ﬀﬀﬀﬀ", "ßßßß"] {
    match parse_hex_bytes(text) {
      Some(_) => inspect("accepted", content="rejected")
      None => inspect("rejected", content="rejected")
    }
  }
  match parse_hex_bytes("aAbB") {
    Some(b) => inspect(bytes_to_u16(b).to_int(), content="43707")
    None => inspect("rejected", content="parsed")
  }
}
