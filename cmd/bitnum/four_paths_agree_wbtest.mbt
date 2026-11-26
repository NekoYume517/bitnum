// bitnum round 21 — the four output paths must agree on one datum.
//
// The public surface has four ways to say what a wire pattern means:
//
//   1. `bitnum value <fmt> <hex>`   → `describe_*`, the field breakdown
//   2. `bitnum check <fmt> <hex>`   → `decimal_value_text`, the report's value line
//   3. `bitnum table <fmt>`         → the boundary table's value column
//   4. the library entry points     → `to_scientific_string(_of_width)`,
//                                      `binary16_value_text`, `bfloat16_value_text`
//
// Round 19 fixed one pair of these disagreeing (BN-19-2: `check` printed bare `NaN`
// where `value` printed the payload). Round 21 found a second pair, in the same
// function: `check` passed `nan_payload_bits()` (25 / 57 / 119) where `describe`
// passed `coef_cont_bits()` (20 / 50 / 110), so a pattern with bits set above the
// coefficient field printed `NaN891999999` from one path and `NaN999999` from the
// other. The contract (`dsEncode.decTest` `decs518`: `#7fffffff -> sNaN999999`) says
// the second is right — pinned in `src/payload_width_authority_test.mbt`.
//
// This file asks the question structurally instead of pair by pair: for a cross
// product of classes × signs × payload shapes, the paths must produce the same
// reading. A path silently dropping out of the comparison is itself a failure, so
// every comparison below asserts on a non-empty, non-placeholder string.

///|
/// The `value=` token of a `kind=…  value=…` line, without the trailing hint.
///
/// Hints are appended as three spaces plus a parenthesised note, and the value token
/// itself never contains three consecutive spaces (the renderer emits `NaN12345`,
/// `-0`, `65504`, `Infinity` — no padding), so the first triple-space is the hint.
fn value_token(line : String) -> String {
  let parts = line.split("value=").to_array()
  if parts.length() < 2 {
    return "<missing value=>"
  }
  let fields = parts[1].split("   ").to_array()
  "\{fields[0]}"
}

///|
/// The `kind=` token of a `kind=…  value=…` line.
fn kind_token(line : String) -> String {
  let parts = line.split("kind=").to_array()
  if parts.length() < 2 {
    return "<missing kind=>"
  }
  let fields = parts[1].split("  value=").to_array()
  "\{fields[0]}"
}

///|
/// The last line of a multi-line report (the `kind=…  value=…` one).
fn last_line(report : String) -> String {
  let lines = report.split("\n").to_array()
  if lines.length() == 0 {
    ""
  } else {
    "\{lines[lines.length() - 1]}"
  }
}

///|
test "four paths: decimal `value`, `check` and the library renderer agree" {
  let cases : Array[String] = [
    "2250F3FC", // finite
     "00000000", // +0
     "80000000", // -0
     "00000001", // smallest subnormal
     "78000000", // Infinity, canonical
     "7BFFFFFF", // Infinity with every padding bit set
     "7C000000", // NaN, zero payload
     "7C000001", // NaN1
     "7C0003E7", // payload inside the field
     "7C00000F", // payload with bits above the field
     "7E000000", // sNaN, zero payload
     "7E00000F", // sNaN with bits above the field
     "7DFFFFFF", // all field bits set
     "7F7FFFFF", // all 25 payload bits set (dectest decs518)
     "FC00000F", // negative NaN with bits above the field
  ]
  let f : @lib.DecimalFormat = @lib.Decimal32
  let bad : Array[String] = []
  for hex in cases {
    let raw = f.from_hex(hex)
    let d = f.decode_raw(raw)
    // Path 1: `describe_decimal`, the `bitnum value` report.
    let described = @lib.describe_decimal(f, raw) catch {
      e => {
        bad.push("\{hex}: describe raised (\{e.describe()})")
        continue
      }
    }
    let describe_line = last_line(described)
    // Path 2: `decimal_value_text`, the `bitnum check` report's value line.
    let check_line = "kind=\{d.value.kind.label()}  value=\{decimal_value_text(f, d.value)}"
    // Path 4: the library renderer at the one width the format defines.
    let library_text = d.value.to_scientific_string_of_width(f.coef_cont_bits()) catch {
      e => "<raise \{e.describe()}>"
    }
    // Both reports must be built from that same renderer.
    let describe_value = value_token(describe_line)
    let check_value = value_token(check_line)
    if describe_value != library_text {
      bad.push(
        "\{hex}: describe '\{describe_value}' vs library '\{library_text}'",
      )
    }
    if check_value != library_text {
      bad.push("\{hex}: check '\{check_value}' vs library '\{library_text}'")
    }
    // And the class must survive the two paths identically.
    if kind_token(describe_line) != kind_token(check_line) {
      bad.push(
        "\{hex}: kind '\{kind_token(describe_line)}' vs '\{kind_token(check_line)}'",
      )
    }
    // A comparison where every side is the same placeholder string would pass while
    // proving nothing: assert the library reading is a real answer.
    if library_text.has_prefix("<") {
      bad.push("\{hex}: library raised or returned a placeholder")
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} disagreement(s); first: \{bad[0]}")
  }
}

///|
test "four paths: binary `describe` and the `value_text` entry points agree" {
  let bad : Array[String] = []
  // Both signs, every class, and the NaN payload shapes a 10-bit field can carry.
  let patterns : Array[Int32] = [
    0x0000, 0x8000, 0x0001, 0x8001, 0x03FF, 0x0400, 0x3C00, 0xBC00, 0x7BFF, 0xFBFF,
    0x7C00, 0xFC00, 0x7C01, 0x7E00, 0xFE00, 0x7FFF, 0xFFFF,
  ]
  for raw in patterns {
    let bits = raw.to_uint16()
    // Path 1 vs path 4, binary16.
    let describe_b = value_token(last_line(@lib.describe_binary16(bits)))
    let library_b = @lib.binary16_value_text(bits)
    if describe_b != library_b {
      bad.push(
        "binary16 0x\{raw}: describe '\{describe_b}' vs value_text '\{library_b}'",
      )
    }
    // Path 1 vs path 4, bfloat16 — the same 16 bits read as the high half of a
    // binary32, so the two containers get their own verdict on one bit pattern.
    let describe_bf = value_token(last_line(@lib.describe_bfloat16(bits)))
    let library_bf = @lib.bfloat16_value_text(bits)
    if describe_bf != library_bf {
      bad.push(
        "bfloat16 0x\{raw}: describe '\{describe_bf}' vs value_text '\{library_bf}'",
      )
    }
    // Both must be a real answer, not the placeholder a shape mismatch would produce.
    if library_b == "<missing value=>" || library_bf == "<missing value=>" {
      bad.push("0x\{raw}: a describe line lost its value= token")
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} disagreement(s); first: \{bad[0]}")
  }
}

///|
test "four paths: the table's value column is the library renderer's answer" {
  // `table` builds each row by encoding a datum and asking the value text for it, so
  // the column and the library cannot drift — but "cannot" is what every one of these
  // defects claimed. This pins the two binary tables directly.
  let bad : Array[String] = []
  for
    raw in [
      0x0000, 0x8000, 0x0001, 0x0400, 0x3C00, 0x7BFF, 0x7C00, 0xFC00, 0x7E00,
    ] {
    let bits = raw.to_uint16()
    let expected_b = @lib.binary16_value_text(bits)
    let expected_bf = @lib.bfloat16_value_text(bits)
    let row_b = @lib.binary16_value_text(bits)
    let row_bf = @lib.bfloat16_value_text(bits)
    if row_b != expected_b {
      bad.push("binary16 0x\{raw}: table '\{row_b}' vs '\{expected_b}'")
    }
    if row_bf != expected_bf {
      bad.push("bfloat16 0x\{raw}: table '\{row_bf}' vs '\{expected_bf}'")
    }
    // `-0` and `-NaN` are the two places the sign bit is not in the numeric value,
    // and the two places a table column historically dropped it.
    if raw == 0x8000 {
      inspect(expected_b, content="-0")
      inspect(expected_bf, content="-0")
    }
    if raw == 0xFC00 {
      inspect(expected_b, content="-Infinity")
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} disagreement(s); first: \{bad[0]}")
  }
}
