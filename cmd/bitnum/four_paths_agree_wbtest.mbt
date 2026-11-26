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
// function: `check` passed `nan_payload_bits()` (25 / 57 / 121) where `describe`
// passed `coef_cont_bits()` (20 / 50 / 110), so a pattern with bits set above the
// coefficient field printed `NaN891999999` from one path and `NaN999999` from the
// other. Then a third: the `table` column still used the width-less
// `to_scientific_string()`, which drops every payload by contract — invisible only
// because the table had no non-zero-payload row to show it.
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

// --------------------------------------------------------------- path 3: the table

///|
/// One parsed table row: the hex, the class, the value cell, and the note.
type TableRow = (String, String, String, String)

///|
/// True when every character of `s` is a hex digit.
fn all_hex(s : String) -> Bool {
  let mut ok = s.length() > 0
  for ch in s.to_array() {
    let digit = ch >= '0' && ch <= '9'
    let upper = ch >= 'A' && ch <= 'F'
    let lower = ch >= 'a' && ch <= 'f'
    if !(digit || upper || lower) {
      ok = false
    }
  }
  ok
}

///|
/// Split a table line into its four cells, **by column offset** rather than by runs of
/// spaces.
///
/// A row is built as `hex + "  " + pad_right(class, cw) + "  " + pad_right(value, vw) +
/// "  (" + note + ")"`, so the columns start at fixed offsets once the hex width is
/// known. Splitting on `"  "` does *not* work: when the class fills its column exactly
/// and the value is long, no run of two spaces separates them, and cells vanish — the
/// first version of this parser passed cell 1 straight through as the value and read
/// `''` for every decimal row.
///
/// The two tables use different column widths (`10`/`26` for decimal, `10`/`14` for the
/// binary ones), so the widths are parameters.
fn parse_table_row(
  line : String,
  class_width : Int32,
  value_width : Int32,
) -> TableRow? {
  let hex_len = hex_prefix_len(line)
  if hex_len < 8 || hex_len % 8 != 0 {
    return None
  }
  let hex = "\{line[0:hex_len]}"
  // After the hex: two spaces, then the padded class.
  let class_start = hex_len + 2
  let class_end = class_start + class_width
  if line.length() < class_end + 2 {
    return None
  }
  let class_name = strip_trailing_blanks(
    line[class_start:class_end].to_string(),
  )
  // Then two spaces, then the padded value.
  let value_start = class_end + 2
  let value_end = value_start + value_width
  if line.length() < value_end {
    return None
  }
  let value_cell = strip_trailing_blanks(
    line[value_start:value_end].to_string(),
  )
  // Then two spaces and the parenthesised note.
  let note_start = value_end + 2
  let note = if line.length() > note_start {
    strip_trailing_blanks(line[note_start:].to_string())
  } else {
    ""
  }
  Some((hex, class_name, value_cell, note))
}

///|
/// Length of the leading run of hex digits, or 0.
fn hex_prefix_len(line : String) -> Int32 {
  let mut i = 0
  let mut stop = false
  for ch in line.to_array() {
    if stop {
      continue
    }
    let digit = ch >= '0' && ch <= '9'
    let upper = ch >= 'A' && ch <= 'F'
    let lower = ch >= 'a' && ch <= 'f'
    if digit || upper || lower {
      i = i + 1
    } else {
      stop = true
    }
  }
  i
}

///|
/// Index of the first space in `s`, or -1.
fn find_space(s : String) -> Int32 {
  let mut i = 0
  for ch in s.to_array() {
    if ch == ' ' {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Drop trailing blanks. `String` has no `trim_right` here (`cmd` only imports
/// `trim_start`), and the table pads its value cell to 26 columns, so the parser has
/// to strip the padding itself.
fn strip_trailing_blanks(s : String) -> String {
  let chars = s.to_array()
  let mut end = chars.length()
  while end > 0 && chars[end - 1] == ' ' {
    end = end - 1
  }
  if end == 0 {
    ""
  } else {
    s[0:end].to_string()
  }
}

///|
/// Every parsed row of a table for `fmt`.
fn table_rows(
  fmt : FormatName,
  class_width : Int32,
  value_width : Int32,
) -> Array[TableRow] {
  let text = table_text(fmt) catch { _ => "" }
  let rows : Array[TableRow] = []
  for line in text.split("\n").to_array() {
    match parse_table_row("\{line}", class_width, value_width) {
      Some(row) => rows.push(row)
      None =>
        match parse_gap_row("\{line}") {
          Some(row) => rows.push(row)
          None => ()
        }
    }
  }
  rows
}

///|
/// The binary tables are plain `pad_left(hex,4) + "  " + pad_right(class,10) + "  " +
/// value + "   (" + note + ")"`: the hex column is 4 wide and the value column is
/// **not** padded, so the fixed-offset parser above cannot read them. This one splits
/// on runs of two-or-more spaces and requires exactly four cells, the last starting
/// with `(`.
fn parse_gap_row(line : String) -> TableRow? {
  let cells = split_on_gap(line)
  if cells.length() != 4 {
    return None
  }
  let hex = strip_trailing_blanks(cells[0])
  let width_ok = hex.length() == 4 && all_hex(hex)
  if !width_ok {
    return None
  }
  Some(
    (
      hex,
      cells[1],
      strip_trailing_blanks(cells[2]),
      strip_trailing_blanks(cells[3]),
    ),
  )
}

///|
/// Split on runs of two or more spaces. Single spaces stay inside a cell, which is what
/// keeps `5.960464477539063e-08` and `(min subnormal, 2^-24)` intact.
fn split_on_gap(line : String) -> Array[String] {
  let cells : Array[String] = []
  let mut current = ""
  let mut spaces = 0
  for ch in line.to_array() {
    if ch == ' ' {
      spaces = spaces + 1
      current = current + ch.to_string()
    } else {
      if spaces >= 2 && current != "" {
        cells.push(strip_trailing_blanks(current))
        current = ""
      }
      spaces = 0
      current = current + ch.to_string()
    }
  }
  let last = strip_trailing_blanks(current)
  if last != "" {
    cells.push(last)
  }
  cells
}

///|
/// The table's value column must be what the value-and-check renderer produces for the
/// same datum — read back through a decode of the row's own hex, so the comparison
/// covers the round trip the row claims.
///
/// **This replaces a tautology.** The first version of this test compared
/// `binary16_value_text(bits)` with `binary16_value_text(bits)`, which would pass no
/// matter what the column did. It also never looked at a decimal row, which is exactly
/// where the column was wrong: it called the width-less `to_scientific_string()`, so
/// every NaN row dropped its payload — invisible while the only NaN row in the table
/// had a zero payload. The table now carries a `payload 999` row, so the width-less
/// column would print `NaN` and this test would catch it.
test "four paths: the table's value column is the same renderer as value and check" {
  let bad : Array[String] = []
  let f : @lib.DecimalFormat = @lib.Decimal32
  let rows = table_rows(DecimalFmt(@lib.Decimal32), 10, 26)
  // The table must actually have parsed — an empty row list would make every
  // comparison below vacuous, which is the failure mode this file exists to avoid.
  if rows.length() < 10 {
    fail(
      "parsed only \{rows.length()} table rows; the parser or the table changed",
    )
  }
  let mut saw_nan_payload = false
  for row in rows {
    let (hex, class_name, value_cell, note) = row
    let raw = f.from_hex(hex)
    let d = f.decode_raw(raw) catch {
      e => {
        bad.push("\{hex}: decode raised (\{e.describe()})")
        continue
      }
    }
    // The class cell and the decoded kind must agree.
    if class_name != d.value.kind.label() {
      bad.push(
        "\{hex}: table class '\{class_name}' vs decoded '\{d.value.kind.label()}'",
      )
    }
    // The value cell must be the width-aware rendering.
    let expected = decimal_value_text(f, d.value)
    if value_cell != expected {
      bad.push("\{hex}: table '\{value_cell}' vs renderer '\{expected}'")
    }
    // A NaN row with a non-zero payload is the only kind that can tell the two
    // renderers apart, so its presence is part of the contract.
    if d.value.kind.label() == "nan" && !d.value.coefficient.is_zero() {
      saw_nan_payload = true
      if !value_cell.has_prefix("NaN") || value_cell == "NaN" {
        bad.push("\{hex}: the payload row rendered '\{value_cell}'")
      }
    }
    if note == "" {
      bad.push("\{hex}: lost its note cell")
    }
  }
  if !saw_nan_payload {
    fail(
      "the table has no non-zero-payload NaN row, so this comparison proves nothing",
    )
  }
  if bad.length() > 0 {
    fail("\{bad.length()} disagreement(s); first: \{bad[0]}")
  }
}

///|
/// The binary tables' value columns, parsed the same way. `-0` and `-NaN` are the two
/// rows where the sign bit is not in the numeric value, and the two a table column
/// historically dropped.
test "four paths: the binary tables' value columns match the value_text functions" {
  let bad : Array[String] = []
  let rows16 = table_rows(Binary16Fmt, 10, 14)
  if rows16.length() < 5 {
    fail("parsed only \{rows16.length()} binary16 rows")
  }
  for row in rows16 {
    let (hex, class_name, value_cell, _note) = row
    let bits = hex_to_uint16(hex)
    let expected = @lib.binary16_value_text(bits)
    if value_cell != expected {
      bad.push(
        "binary16 \{hex}: table '\{value_cell}' vs value_text '\{expected}'",
      )
    }
    if class_name != @lib.Binary16::decode(bits).kind.label() {
      bad.push("binary16 \{hex}: class '\{class_name}'")
    }
    if hex == "8000" {
      inspect(value_cell, content="-0")
    }
  }
  for row in table_rows(Bfloat16Fmt, 10, 14) {
    let (hex, _class_name, value_cell, _note) = row
    let bits = hex_to_uint16(hex)
    let expected = @lib.bfloat16_value_text(bits)
    if value_cell != expected {
      bad.push(
        "bfloat16 \{hex}: table '\{value_cell}' vs value_text '\{expected}'",
      )
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} disagreement(s); first: \{bad[0]}")
  }
}

///|
/// `"7C00"` -> `0x7C00u16`, for reading a hex cell back into a binary16 pattern.
fn hex_to_uint16(hex : String) -> UInt16 {
  let mut value = 0
  for ch in hex.to_array() {
    let d = if ch >= '0' && ch <= '9' {
      ch.to_int() - '0'.to_int()
    } else if ch >= 'A' && ch <= 'F' {
      ch.to_int() - 'A'.to_int() + 10
    } else if ch >= 'a' && ch <= 'f' {
      ch.to_int() - 'a'.to_int() + 10
    } else {
      0
    }
    value = value * 16 + d
  }
  value.to_uint16()
}
