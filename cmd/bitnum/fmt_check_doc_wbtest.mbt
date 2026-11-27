// bitnum round 22 — the documented `moon fmt --check` landmine no longer exists.
//
// `docs/DEMO.md` §0 used to carry this warning, between two fences that claim to be
// measured output:
//
//   **`moon fmt --check` 必须先跑一次 `moon fmt`**，顺序不能反。… 如果那个目录还不
//   存在（全新 clone、或刚删过 `_build`），它就直接失败：
//
//   $ moon fmt --check        # 在干净的 _build 上
//   error: open("...\_build\wasm-gc\release\format\src\decimal_wire.mbt"): No such
//   file or directory
//   Error: failed when formatting project
//
//   … CI 里如果只写 `moon fmt --check`，在 fresh runner 上会假红。
//
// Measured on `moonc v1.0.0-rc1` this round: a fresh `git clone` with **no**
// `_build` at all runs `moon fmt --check` and exits 0. The repo's own CI has been
// running bare `moon fmt --check` on `ubuntu-latest` (a fresh runner every time)
// and has been green, which is the same fact from the other direction. So the
// warning, the quoted "error:" block, and the CI advice all describe an older
// toolchain, not this one.
//
// A document that tells the reader a working command will fail, and tells the
// maintainer to work around it in CI, is worse than one that says nothing: it
// invites a `moon fmt` step that rewrites files before the check, which is the
// only way that advice can hide a formatting regression.

///|
test "demo: the fmt --check landmine warning matches the toolchain it names" {
  let demo = @fs.read_file_to_string("docs/DEMO.md")
  // Three things the retracted section asserted; each must stay out. The section
  // itself stays — it records that the old claim was wrong — which is why these
  // are the quoted error line, the "must run fmt first" rule, and the CI advice,
  // rather than the topic.
  let quoted_error = demo.contains("_build\\wasm-gc\\release\\format") ||
    demo.contains("No such file or directory")
  let must_run_first = demo.contains("必须先跑一次")
  let ci_false_red = demo.contains("在 fresh runner 上会假红")
  if quoted_error || must_run_first || ci_false_red {
    fail(
      "docs/DEMO.md still asserts that `moon fmt --check` fails on a fresh tree; measured on moonc v1.0.0-rc1 it exits 0, and this repo's CI runs it bare on a fresh runner",
    )
  }
}
