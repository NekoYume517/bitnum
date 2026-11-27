// bitnum round 22 — the coverage table's counts must be derivable from source.
//
// `docs/DEMO.md` §7 prints a coverage table. Two of its rows are free narrative
// that nothing computes, and both had drifted:
//
//   line 653  | `docs/DEMO.md` 的全部 `bitnum` 块 | **48** 条命令 …
//             The documents quote 53 `bitnum` blocks, not 48: `table` is five of
//             them and `demo_replay_wbtest.mbt` replays the other 48. The row
//             therefore calls 48 "全部" while its own parenthetical says which
//             test does the rest.
//
//   line 660  `bits` 那 9 条断言的是 …
//             The row directly above it (line 658) says 40 assertions and records
//             that the older "9 条（6+4+9+2+8+2+3）" figure was wrong. The prose
//             below the table still used the retired 9, so the table contradicted
//             its own footnote. 9 is also the count for one of the three test
//             files (see below), which is how the number survived the rewrite.
//
// This file locks both, plus the arithmetic of the rows that *are* already
// right, so the next edit to the documents cannot leave a number behind.

///|
/// The `$ bitnum …` command lines of `text`, as `(subcommand, argument)`.
fn bitnum_blocks(text : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for line in text.split("\n") {
    let l = line.to_owned()
    if not(l.has_prefix("$ bitnum ")) {
      continue
    }
    let rest = l[9:].to_owned()
    let parts = rest.split(" ").collect()
    if parts.length() == 0 {
      continue
    }
    let cmd = parts[0].to_owned()
    let arg = rest[cmd.length() + 1:].to_owned()
    let arg = arg.split("#").collect()
    let arg = if arg.length() > 0 {
      arg[0].to_owned().trim().to_owned()
    } else {
      ""
    }
    out.push((cmd, arg))
  }
  out
}

///|
fn count_blocks(text : String, cmd : String) -> Int32 {
  let mut n = 0
  for (c, _) in bitnum_blocks(text) {
    if c == cmd {
      n = n + 1
    }
  }
  n
}

///|
fn count_inspects(path : String) -> Int32 raise {
  let text = @fs.read_file_to_string(path)
  let mut n = 0
  for line in text.split("\n") {
    if line.to_owned().contains("inspect(") {
      n = n + 1
    }
  }
  n
}

///|
fn count_test_blocks(path : String) -> Int32 raise {
  let text = @fs.read_file_to_string(path)
  let mut n = 0
  for line in text.split("\n") {
    if line.to_owned().has_prefix("test ") {
      n = n + 1
    }
  }
  n
}

///|
test "demo: every `bitnum` block in the documents is accounted for by a replay test" {
  let demo = @fs.read_file_to_string("docs/DEMO.md")
  let readme = @fs.read_file_to_string("README.md")
  let demo_value = count_blocks(demo, "value")
  let demo_bits = count_blocks(demo, "bits")
  let demo_check = count_blocks(demo, "check")
  let demo_table = count_blocks(demo, "table")
  let demo_total = demo_value + demo_bits + demo_check + demo_table
  inspect(demo_total, content="53")
  inspect(demo_table, content="5")
  // 48 of DEMO's blocks are `value`/`bits`/`check` and are replayed by
  // `demo_replay_wbtest.mbt`; the other five are `table` reports replayed by
  // `table_wbtest.mbt`. The coverage table's row must therefore say 53.
  let replayed_by_demo = demo_value + demo_bits + demo_check
  inspect(replayed_by_demo, content="48")
  // Every README `bitnum` command restates one from DEMO, so README adds no
  // replay work — the reason its examples being unlocked was easy to miss.
  let demo_set = bitnum_blocks(demo)
  let mut readme_only = 0
  let readme_total = count_blocks(readme, "value") +
    count_blocks(readme, "bits") +
    count_blocks(readme, "check") +
    count_blocks(readme, "table")
  for entry in bitnum_blocks(readme) {
    let mut found = false
    for d in demo_set {
      if d == entry {
        found = true
      }
    }
    if not(found) {
      readme_only = readme_only + 1
      println("README quotes a command DEMO does not: \{entry.0} \{entry.1}")
    }
  }
  inspect(readme_only, content="0")
  inspect(readme_total, content="6")
}

///|
test "demo: the `bits` rejection assertion counts are the three files' own" {
  // The row says 40 assertions split 26 + 10 + 4 across three files, in 7 test
  // blocks. Every one of those four numbers is read off the source here.
  let lexical = count_inspects("cmd/bitnum/lexical_wbtest.mbt")
  let hex_input = count_inspects("cmd/bitnum/hex_input_wbtest.mbt")
  let surrogate = count_inspects("cmd/bitnum/parse_surrogate_wbtest.mbt")
  inspect(lexical, content="26")
  inspect(hex_input, content="10")
  inspect(surrogate, content="4")
  inspect(lexical + hex_input + surrogate, content="40")
  let blocks = count_test_blocks("cmd/bitnum/lexical_wbtest.mbt") +
    count_test_blocks("cmd/bitnum/hex_input_wbtest.mbt") +
    count_test_blocks("cmd/bitnum/parse_surrogate_wbtest.mbt")
  inspect(blocks, content="7")
}

///|
test "demo: the coverage table does not still quote the retired 9-assertion figure" {
  // Line 658 records that "9 条（6+4+9+2+8+2+3）" was wrong — the parenthetical
  // summed to 34. Line 660 used to keep the bare 9. The retired figure may appear
  // only inside the row that *records* it as wrong, never in the prose beneath:
  // the prose is the part a reader takes at face value.
  let demo = @fs.read_file_to_string("docs/DEMO.md")
  let lines = demo.split("\n").map(fn(s) { s.to_owned() }).collect()
  let mut prose_uses_9 = 0
  for i in 0..<lines.length() {
    let l = lines[i]
    // A table row is the thing that records the history; prose is anything else.
    if l.has_prefix("|") {
      continue
    }
    if l.contains("`bits` 那 9 条") {
      prose_uses_9 = prose_uses_9 + 1
      println("DEMO.md:\{i + 1} still says '那 9 条': \{l}")
    }
  }
  inspect(prose_uses_9, content="0")
}

///|
test "demo: the coverage table's `bitnum` row quotes the documents' real total" {
  // Line 653 claims the coverage row covers "全部 `bitnum` 块" and gives 48. The
  // documents quote 53, and the row's own parenthetical names the second test
  // that handles the other five, so the row contradicts itself. This reader pulls
  // the number out of the row and compares it with the documents' own count.
  let demo = @fs.read_file_to_string("docs/DEMO.md")
  let mut claimed = -1
  let mut lines = 0
  for line in demo.split("\n") {
    let l = line.to_owned()
    lines = lines + 1
    if not(l.has_prefix("|")) {
      continue
    }
    if l.contains("的全部 `bitnum` 块") &&
      l.contains("条命令逐行回放") {
      // The row is `… | **48** 条命令 …`, so the claim sits between the asterisks.
      let stars = l.split("**").collect()
      if stars.length() >= 2 {
        claimed = @strconv.parse_int(stars[1].to_owned()[:]) catch { _ => -2 }
      }
      println("DEMO.md:\{lines} claims \{claimed} `bitnum` blocks")
    }
  }
  if claimed == -1 {
    fail("DEMO.md no longer has the '全部 `bitnum` 块' coverage row")
  }
  let actual = count_blocks(demo, "value") +
    count_blocks(demo, "bits") +
    count_blocks(demo, "check") +
    count_blocks(demo, "table")
  if claimed != actual {
    fail(
      "the coverage row claims \{claimed} `bitnum` blocks but docs/DEMO.md quotes \{actual}; the row calls its number '全部' while its own parenthetical names the test that handles the other \{actual - claimed}",
    )
  }
}
