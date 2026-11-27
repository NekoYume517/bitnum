// bitnum round 22 — the backend table's "invisible payload" row names a finite
// number as a signaling NaN.
//
// `README.md` §后端无关 and `API.md` both carry this row:
//
//   | signaling NaN `0x7F7F` / `0x7FFF`（payload 在 bit 16 不可见） | 原样 | 落到规范 quiet NaN |
//
// bfloat16 is `s(1) e(8) m(7)`. `0x7F7F` has exponent `0xFE`, so it is the
// **largest finite** bfloat16 (3.3895313892515355e+38) — the value
// `bitnum table bfloat16` prints as `max finite`, and the value `src/bfloat16.mbt`
// builds when it needs max-finite. It is not a NaN at all. The signaling NaN whose
// payload bit sits where binary32 cannot see it is `0x7FBF`; `0x7FFF` is the quiet
// NaN with the same property.
//
// Measured on `moonc v1.0.0-rc1` this round:
//
//   0x7F7F  normal   0x7F7F0000 on every backend (nothing happens at all)
//   0x7FBF  sNaN     js: 0x7FFF0000 — an *infinity* pattern     wasm/wasm-gc: unchanged
//   0x7FFF  qNaN     js: 0x7FFF0000 (unchanged)                 wasm/wasm-gc: unchanged
//
// so the row's first member is wrong in kind, and its "落到规范 quiet NaN" gloss
// is right for neither of the two patterns it names on js: `0x7FBF` lands on an
// infinity pattern, `0x7FFF` does not move.
//
// This file locks the classification from the geometry, so a document that calls a
// finite value a NaN fails, and a test comment that repeats the mistake fails too.

///|
/// `true` when the 16-bit pattern has the all-ones exponent, i.e. is Inf or NaN.
fn has_all_ones_exponent(bits : UInt32) -> Bool {
  ((bits >> 7) & 0xFF) == 0xFF
}

///|
test "bfloat16: the backend table's 'invisible payload' patterns are NaNs" {
  // Geometry, read off the pattern rather than trusted from the table.
  inspect(has_all_ones_exponent(0x7F7F), content="false")
  inspect(has_all_ones_exponent(0x7FBF), content="true")
  inspect(has_all_ones_exponent(0x7FFF), content="true")
  // And the decoder agrees with the geometry.
  inspect(BFloat16::decode(0x7F7F).kind == Normal, content="true")
  inspect(BFloat16::decode(0x7FBF).kind == Nan, content="true")
  inspect(BFloat16::decode(0x7FFF).kind == Nan, content="true")
  // 0x7F7F is the max finite value — that is what makes calling it a NaN wrong.
  inspect(
    BFloat16::decode(0x7F7F).to_f64() > BFloat16::decode(0x7F7E).to_f64(),
    content="true",
  )
}

///|
test "docs: no document calls the finite pattern 0x7F7F a NaN" {
  // The two files that carried the row. A correct rewrite may still mention both
  // patterns — the point is that the *row* must not label the pair as signaling
  // NaNs, and must not attach the "invisible payload" gloss to a finite number.
  let files : Array[String] = ["README.md", "API.md", "docs/DEMO.md"]
  let mut offenders = 0
  for name in files {
    let text = @fs.read_file_to_string(name)
    for line in text.split("\n") {
      let l = line.to_owned()
      // The offending shape: one line that mentions 0x7F7F *and* calls it a NaN.
      if l.contains("0x7F7F") &&
        (l.contains("NaN") || l.contains("nan")) &&
        not(l.contains("max finite")) &&
        not(l.contains("最大有限值")) {
        // A line that *retracts* the mistake ("0x7F7F is not a NaN") is fine; the
        // offense is presenting it as one.
        if l.contains("不是") && l.contains("NaN") {
          continue
        }
        // `$ bitnum value decimal32 7F7FFFFF` and other decimal32 hex strings are
        // a different number that merely starts the same way.
        if l.contains("7F7FFFFF") || l.contains("7F7F FFFF") {
          continue
        }
        offenders = offenders + 1
        println("\{name}: \{l}")
      }
    }
  }
  inspect(offenders, content="0")
}
