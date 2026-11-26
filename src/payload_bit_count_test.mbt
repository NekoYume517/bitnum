///|
/// Round 21 (2026-11-29): the rename `nan_payload_bits` -> `payload_bit_count`, and the
/// lock that keeps the deprecated alias honest.
///
/// Why the rename: the old name reads like "the width to render a payload with", and
/// confusing it with the renderer's width argument was the P1 defect of this round
/// (`check` printed `NaN891999999` where `value` printed `NaN999999`). The quantity is
/// "how many bits of the pattern are payload" — `(exp_cont - 1) + coef_cont` — which is
/// not any format's render width.
///
/// The old name stays as a forwarding alias so external callers keep compiling. A
/// forwarding *body* can rot two ways, and this file closes both:
///
///   1. someone edits one function and not the other — pinned by asserting the two
///      return the same value for **every** format, not just one;
///   2. someone "improves" the alias into its own implementation — pinned by asserting
///      the alias's body text is a single call to the new name (`src/decimal_wire.mbt`
///      is read as text), because "identical today" is weaker than "cannot diverge".
///
/// The `.mbti` presence of both names is already pinned by `api_signature_test.mbt`;
/// this file is about the values.

///|
test "decimal: payload_bit_count and its deprecated alias return the same number" {
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  for f in formats {
    inspect(
      f.payload_bit_count().to_string(),
      content=f.nan_payload_bits().to_string(),
    )
  }
  // The concrete numbers, so a geometry change is caught here as well.
  let f32 : DecimalFormat = Decimal32
  inspect(f32.payload_bit_count(), content="25")
  let f64 : DecimalFormat = Decimal64
  inspect(f64.payload_bit_count(), content="57")
  let f128 : DecimalFormat = Decimal128
  inspect(f128.payload_bit_count(), content="121")
  // And it is not the render width — the distinction the rename exists to make.
  for f in formats {
    assert_true(f.payload_bit_count() > f.coef_cont_bits())
  }
}

///|
/// The alias must be a forwarder, not a second implementation: exactly one statement,
/// and that statement is the call to `payload_bit_count`.
///
/// Reading the source as text is the point. A behavioural assertion ("they agree
/// today") is satisfied by two copies of the same formula; the failure this guards
/// against is precisely the day one copy changes.
test "decimal: the deprecated alias is a forwarder, not a second implementation" {
  let text = @fs.read_file_to_string("src/decimal_wire.mbt")
  let lines = text.split("\n").to_array()
  // Find the alias's signature, then count its body lines until the closing brace.
  let mut start = -1
  let mut i = 0
  for line in lines {
    if "\{line}".contains(
        "pub fn DecimalFormat::nan_payload_bits(self : DecimalFormat)",
      ) {
      start = i
    }
    i = i + 1
  }
  if start < 0 {
    fail("the deprecated alias vanished from src/decimal_wire.mbt")
  }
  let body : Array[String] = []
  let mut j = start + 1
  while j < lines.length() {
    let line = "\{lines[j]}".trim_start().trim().to_string()
    if line == "}" {
      break
    }
    if line != "" {
      body.push(line)
    }
    j = j + 1
  }
  if body.length() != 1 {
    fail(
      "the alias has \{body.length()} statements, want exactly 1: \{body[0]}",
    )
  }
  if !body[0].contains("self.payload_bit_count()") {
    fail("the alias does not forward to payload_bit_count: \{body[0]}")
  }
}
