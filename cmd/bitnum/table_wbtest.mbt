// bitnum table — the boundary-value report, locked against the blocks the
// documents quote.
//
// `table` was the only subcommand with no whitebox test at all (even `help`,
// which prints prose, had one), while `docs/DEMO.md` quotes all five reports and
// `README.md` quotes the decimal32 one, character for character. A drifted row
// there is invisible in code review and visible to every reader — the same
// asymmetry `help_wbtest.mbt` describes for `--help`, but with a much bigger
// surface (five formats, 55 rendered lines).
//
// The comparison reads the documents at test time instead of embedding a copy of
// the expected output, so the assertion and the document cannot drift apart: a
// row that moves in the code and not in the document fails here.

///|
/// The body of the fenced block whose first line is `marker`, joined with `\n`.
///
/// The quoted `$ bitnum …` line is the *first* line inside the fence, so the
/// body is everything after it up to the closing fence. Returns `""` when the
/// marker or the fence is missing, so a document edit that removes the block
/// fails the length assertion below instead of silently passing an empty
/// comparison.
fn fenced_block_after(text : String, marker : String) -> String {
  let sb = StringBuilder()
  let mut started = false
  let mut first = true
  for line in text.split("\n") {
    let l = line.to_owned()
    if not(started) {
      if l == marker {
        started = true
      }
      continue
    }
    if l.has_prefix("```") {
      break
    }
    if not(first) {
      sb.write_char('\n')
    }
    first = false
    sb.write_string(l)
  }
  sb.to_string()
}

///|
/// `table` for one format, as the text the command prints.
fn table_of(fmt : FormatName) -> String {
  table_text(fmt) catch {
    e => "table_text raised: \{e.describe()}"
  }
}

///|
/// The README block is the whole report, ceiling lines included, so this one is
/// an equality on the full text.
test "table: README's decimal32 block is the tool's output, byte for byte" {
  let readme = @fs.read_file_to_string("README.md")
  let want = fenced_block_after(readme, "$ bitnum table decimal32")
  // Title + header + 11 rows + a blank line + the two ceiling lines.
  inspect(want.split("\n").collect().length(), content="16")
  inspect(table_of(DecimalFmt(@lib.Decimal32)), content=want)
}

///|
/// All five reports, against the blocks DEMO quotes. The binary ones stop after
/// the rows (13 lines); the decimal ones carry the blank line and the two
/// ceiling lines (16).
test "table: every report is the block DEMO quotes, byte for byte" {
  let demo = @fs.read_file_to_string("docs/DEMO.md")
  let cases : Array[(String, FormatName, Int32)] = [
    ("$ bitnum table binary16", Binary16Fmt, 13),
    ("$ bitnum table bfloat16", Bfloat16Fmt, 13),
    ("$ bitnum table decimal32", DecimalFmt(@lib.Decimal32), 16),
    ("$ bitnum table decimal64", DecimalFmt(@lib.Decimal64), 16),
    ("$ bitnum table decimal128", DecimalFmt(@lib.Decimal128), 16),
  ]
  for entry in cases {
    let (marker, fmt, lines) = entry
    let block = fenced_block_after(demo, marker)
    inspect(block.split("\n").collect().length(), content=lines.to_string())
    inspect(table_of(fmt), content=block)
  }
}

///|
/// An unknown format is a usage error before any table is built, and the report
/// never ends in a stray newline — the printer adds exactly one, which is what
/// keeps the printed bytes identical to the old one-`println`-per-line version.
test "table: shape of the report" {
  inspect(cmd_table("nosuch") catch { _ => -1 }, content="2")
  let text = table_of(DecimalFmt(@lib.Decimal32))
  inspect(text.has_suffix("\n"), content="false")
  inspect(text.has_prefix("decimal32 boundary values"), content="true")
}
