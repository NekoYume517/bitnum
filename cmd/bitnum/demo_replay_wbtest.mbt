// bitnum DEMO — the third rendering path, locked the way `table` is.
//
// `docs/DEMO.md` promises, in its own header, that "每一条输出都是**实际跑出来的**"
// and that "要复核任意一条，复制 `$` 开头的命令在仓库根目录执行即可". Two of its
// 53 blocks were locked by a test (`table`, via `table_wbtest.mbt`); the other 48
// quoted `bitnum …` runs were not, and round 19 replayed all 53 against the real
// binary. Exactly one had drifted:
//
//     $ bitnum value decimal32 7F7FFFFF
//     sign=0  payload=25165823
//     kind=signaling-nan  value=sNaN          <- the document
//     kind=signaling-nan  value=sNaN999999    <- the tool
//
// BN-18-1 had fixed the *code* for precisely that payload case and updated the
// `describe` prose around it, but this block was never re-run.
//
// The comparison below reads the block out of the document and calls the same
// `cmd_value` / `cmd_bits` / `cmd_check` entries `dispatch` calls (see the report
// extractors in `demo_capture_wbtest.mbt`), so a row that moves in the code and
// not in the document fails here. `println` cannot be captured from a whitebox
// test, so what is asserted is the *report text* each command produces — the
// `describe_*` rendering for `value`, the `BitsOutcome` for `bits`, and the
// verdict lines for `check` — assembled in the order and on the stream the
// document quotes.
//
// Not covered: `moon check` / `moon test` / `moon fmt` blocks (their task counts
// move with the build cache, and the document says so) and the two
// `python scripts/*.py` runs (they belong to `scripts/`).

///|
/// The command a DEMO block quotes, replayed.
struct DemoCase {
  sub : String
  format : String
  arg : String
  exit : Int32
  stdout : Array[String]
  stderr : Array[String]
}

///|
fn demo_case(sub : String, format : String, arg : String) -> DemoCase {
  let (out, err, code) = match sub {
    "value" => value_report(format, arg)
    "bits" => bits_report(format, arg)
    _ => check_report(format, arg)
  }
  { sub, format, arg, exit: code, stdout: out, stderr: err, }
}

///|
/// The block's lines as the document writes them: stdout, then stderr, then the
/// literal `exit=N` line the document appends to non-zero exits.
fn demo_expected_lines(c : DemoCase) -> Array[String] {
  let lines = c.stdout.copy()
  for l in c.stderr {
    lines.push(l)
  }
  if c.exit != 0 {
    lines.push("exit=\{c.exit}")
  }
  lines
}

///|
/// The marker the document writes above the block: the literal command line.
fn demo_marker(c : DemoCase) -> String {
  match c.sub {
    "value" => "$ bitnum value \{c.format} \{c.arg}"
    "bits" => "$ bitnum bits \{c.format} \{c.arg}"
    _ => "$ bitnum check \{c.format} \{c.arg}"
  }
}

///|
/// Every `$ bitnum …` block of `docs/DEMO.md`, replayed and compared. The count
/// is asserted so a block that disappears from either side cannot make the test
/// pass by comparing nothing.
test "demo: every quoted bitnum run in DEMO.md is the tool's output, line for line" {
  let demo = @fs.read_file_to_string("docs/DEMO.md")
  let cases : Array[DemoCase] = [
    demo_case("value", "binary16", "0001"),
    demo_case("value", "decimal64", "A2300000000003D0"),
    demo_case("value", "binary16", "3C00"),
    demo_case("value", "binary16", "7C00"),
    demo_case("value", "bfloat16", "7FC0"),
    demo_case("value", "decimal32", "7F7FFFFF"),
    demo_case("value", "decimal32", "78000000"),
    demo_case("value", "bfloat16", "8000"),
    demo_case("value", "bfloat16", "FF80"),
    demo_case("value", "binary16", "FE01"),
    demo_case("bits", "binary16", "1.0"),
    demo_case("bits", "binary16", "0.1"),
    demo_case("bits", "bfloat16", "1.0"),
    demo_case("bits", "decimal64", "-7.50"),
    demo_case("bits", "decimal32", "1.23"),
    demo_case("bits", "decimal128", "1E-6176"),
    demo_case("bits", "binary16", "xyz"),
    demo_case("bits", "binary16", "1.2.3"),
    demo_case("bits", "binary16", "1e"),
    demo_case("bits", "binary16", "1e999"),
    demo_case("bits", "binary16", "-1e999"),
    demo_case("bits", "binary16", "1e-999"),
    demo_case("bits", "binary16", "1e-320"),
    demo_case("bits", "bfloat16", "1e999"),
    demo_case("bits", "bfloat16", "1e39"),
    demo_case("bits", "bfloat16", "1e-46"),
    demo_case("check", "binary16", "7E00"),
    demo_case("check", "decimal64", "A2300000000003D0"),
    demo_case("check", "decimal32", "2250016E"),
    demo_case("value", "decimal32", "2250016E"),
    demo_case("check", "decimal32", "79000000"),
    demo_case("value", "binary16", "ZZZZ"),
    demo_case("bits", "decimal64", "nan"),
    demo_case("bits", "decimal64", "1.2.3"),
    demo_case("bits", "decimal64", "+"),
    demo_case("bits", "decimal64", "1e"),
    demo_case("bits", "decimal64", "1e+"),
    demo_case("value", "decimal32", "78ZZ0000"),
    demo_case("value", "nosuch", "0000"),
    demo_case("value", "binary16", "000100"),
    demo_case("bits", "decimal32", "12345678"),
    demo_case("bits", "decimal32", "1" + String::make(198, '1')),
    demo_case("bits", "decimal32", "9999999E+96"),
    demo_case("bits", "decimal32", "1e155"),
    demo_case("bits", "binary16", "xyz"),
    demo_case("value", "decimal64", "A2300000000003D"),
    demo_case("value", "binary16", "3c0"),
    demo_case("bits", "binary16", "1e999"),
  ]
  let mut compared = 0
  for c in cases {
    // The 199-ones block is written `111…1` in the document (prose for 199 ones);
    // the marker it is filed under carries the ellipsis and the trailing comment.
    let marker = if c.arg == "1" + String::make(198, '1') {
      "$ bitnum bits decimal32 111…1        # 199 个 1"
    } else {
      demo_marker(c)
    }
    let want = fenced_block_after(demo, marker)
    if want == "" {
      // A missing block must fail loudly instead of comparing nothing.
      inspect("\{marker} not found in docs/DEMO.md", content="")
      continue
    }
    let got = demo_expected_lines(c).join("\n")
    if got != want {
      // Name the block in the failure, so the diff is attributable.
      println("DEMO block at \{marker} differs from the tool")
    }
    inspect(got, content=want)
    compared = compared + 1
  }
  inspect(compared, content="48")
}
