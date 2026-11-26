// The test count in the documents must equal the number of `test` blocks the source
// tree actually contains.
//
// Round 19 established the rule ("the number in the docs is the number `moon test`
// prints"), and round 20 broke it again: two tests were added and `README.md` /
// `docs/DEMO.md` still said 195. `demo_replay_wbtest.mbt` cannot catch this — it
// replays the `$ bitnum …` blocks, and a `$ moon test` block cannot replay itself.
//
// What is locked here instead is the *derivation*: one `test "…" {` block per test
// in `moon test`'s total, so counting them in the tree is the same number. That is
// observable without running the suite, so the document claim can be checked from
// inside the suite — no build cache, no task counts, no external process.
//
// Both documents must agree with the tree, and with each other: a stale count in one
// of them is the failure this file exists to catch.

///|
/// The test-block count of the tracked source tree, from the package's own view of
/// its files. `@fs` is available here (this is the `cmd` package), and the two source
/// directories are the only ones that can hold tests in this repository.
fn test_block_count() -> Int32 raise {
  let mut total = 0
  for dir in ["src", "cmd/bitnum"] {
    for name in @fs.read_dir(dir) {
      if name.has_suffix(".mbt") {
        let text = @fs.read_file_to_string("\{dir}/\{name}")
        for line in text.split("\n") {
          // `test "…" {` at column 0; `wbtest`/`inspect` lines never start with it.
          if line.has_prefix("test \"") {
            total = total + 1
          }
        }
      }
    }
  }
  total
}

///|
/// The number a document's `$ moon test` block quotes, or -1 when the block is
/// missing (a missing block is a bigger problem than a stale one, and must not read
/// as "zero tests").
fn quoted_total(doc : String) -> Int32 raise {
  let text = @fs.read_file_to_string(doc)
  for line in text.split("\n") {
    let trimmed = line.trim_start()
    if trimmed.has_prefix("Total tests:") {
      // `Total tests: 201, passed: 201, failed: 0.`
      let rest = trimmed[13:].trim_start()
      let mut digits = ""
      for ch in rest.to_array() {
        if ch >= '0' && ch <= '9' {
          digits = digits + ch.to_string()
        } else {
          break
        }
      }
      if digits != "" {
        return @strconv.parse_int(digits[:]) catch { _ => -1 }
      }
    }
  }
  -1
}

///|
test "docs: the quoted test count equals the number of test blocks in the tree" {
  let actual = test_block_count() catch { _ => -1 }
  // Sanity: the tree really has tests, so a broken reader cannot pass as `0 == 0`.
  assert_true(actual > 150)
  let readme = quoted_total("README.md") catch { _ => -1 }
  let demo = quoted_total("docs/DEMO.md") catch { _ => -1 }
  if readme != actual {
    fail("README.md quotes \{readme} tests, the tree has \{actual}")
  }
  if demo != actual {
    fail("docs/DEMO.md quotes \{demo} tests, the tree has \{actual}")
  }
}
