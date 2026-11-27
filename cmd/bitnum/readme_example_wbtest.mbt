// bitnum round 22 — README's own `bitnum` examples were never replayed.
//
// `table_wbtest.mbt` locks the one `$ bitnum table decimal32` block README
// quotes, and `demo_replay_wbtest.mbt` locks `docs/DEMO.md`. The *other* five
// `$ bitnum …` command lines in README — the lexer examples and the two `value`
// breakdowns that carry the "field breakdown, not just the value" claim — had no
// test at all: they are the first thing a reader copies, and nothing stopped
// them drifting from the tool the way DEMO's blocks once did.
//
// All five were replayed by hand during this round and matched. This file turns
// that one-off check into coverage: the expectations are read out of README at
// test time, so a document edit and a code change cannot part ways silently.
//
// Two of them share one fence (the two lexer examples sit next to each other with
// no blank line between), so the reader below takes a block up to the *next*
// command line, not up to the closing fence.

///|
/// The lines that follow `marker` in README, up to the closing fence or the next
/// `$ bitnum …` line, joined with `\n`.
fn readme_block(marker : String) -> String raise {
  let text = @fs.read_file_to_string("README.md")
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
    if l.has_prefix("```") || l.has_prefix("$ bitnum") {
      break
    }
    if not(first) {
      sb.write_char('\n')
    }
    first = false
    sb.write_string(l)
  }
  if not(started) {
    fail("README.md no longer quotes the block starting at '\{marker}'")
  }
  // The fence (or the next command) ends the body, so a block comes back without
  // a trailing newline; the line lists below are compared the same way. A block
  // followed by a blank line inside the same fence carries that blank, which the
  // document does not mean as content.
  let body = sb.to_string()
  if body.has_suffix("\n") {
    body[:body.length() - 1].to_owned()
  } else {
    body
  }
}

///|
/// The block as lines, so an assertion can name one line instead of an
/// embedded-newline string literal.
fn readme_block_lines(marker : String) -> Array[String] raise {
  readme_block(marker).split("\n").map(fn(s) { s.to_owned() }).collect()
}

///|
test "readme: the lexer examples are the tool's own output" {
  // A rejection names the literal and exits 1.
  match binary16_bits("xyz") {
    BitsRejected(msg) => inspect(msg, content="bitnum: not a number: 'xyz'")
    BitsHex(hex, _) => inspect("accepted as \{hex}", content="rejected")
  }
  let rejected = readme_block_lines("$ bitnum bits binary16 xyz")
  inspect(rejected.length(), content="2")
  inspect(rejected[0], content="bitnum: not a number: 'xyz'")
  inspect(rejected[1], content="exit=1")
  // A magnitude binary64 cannot hold overflows to infinity, with a note naming
  // the literal; stdout carries the hex line and stderr the note.
  match binary16_bits("1e999") {
    BitsHex(hex, _) => inspect(hex, content="7C00")
    BitsRejected(r) => inspect("rejected: \{r}", content="accepted")
  }
  let overflow = readme_block_lines("$ bitnum bits binary16 1e999")
  inspect(overflow.length(), content="3")
  inspect(overflow[0], content="7C00")
  inspect(
    overflow[1].contains("'1e999' is too large for binary64"),
    content="true",
  )
  inspect(overflow[2], content="exit=0")
  // A short hex string is refused at the format's own width, never padded.
  let short = readme_block_lines("$ bitnum value decimal64 A2300000000003D")
  inspect(short.length(), content="2")
  inspect(short[0], content="bitnum: decimal64 is 16 hex digits, got 15")
  inspect(short[1], content="exit=1")
}

///|
test "readme: the two `value` breakdowns are the tool's own output" {
  // The subnormal: field breakdown plus the exact-value hint. The binary16
  // subnormal 0x0001 is 2^-24 exactly.
  let subnormal = readme_block_lines("$ bitnum value binary16 0001")
  inspect(subnormal.length(), content="2")
  inspect(subnormal[0], content="sign=0  exponent=0 (subnormal)  significand=1")
  inspect(
    subnormal[1],
    content="kind=finite  value=5.960464477539063e-08   (2^-24)",
  )
  // The decimal triple: raw fields, then the rendered value.
  let triple = readme_block_lines("$ bitnum value decimal64 A2300000000003D0")
  inspect(triple.length(), content="2")
  inspect(triple[0], content="sign=1  exponent=-2  coefficient=750")
  inspect(triple[1], content="kind=finite  value=-7.50")
}
