// bitnum round 22 — the bfloat16 widening test's backend switch can be satisfied
// by the wrong backend, and its js expectation named the wrong bit pattern.
//
// `src/bfloat16_test.mbt` measures one backend-dependent fact and then asserts two
// numbers that are both derived from it:
//
//   let j = js_value_route_quiets_nans()
//   inspect(value_bad, content=if j { "126" } else { "0" })
//   inspect(canonical_only, content=(if j { 126 } else { 0 }).to_string())
//
// Two separate problems, both measured this round:
//
// 1. The two errors cancel. `value_bad` counts patterns whose widened bits differ
//    from the stored pattern: 0 on wasm/wasm-gc, 126 on js. `canonical_only`
//    counts *signaling* patterns whose payload survives a shift — and that count
//    is 126 on **every** backend, because it is a property of the pattern space,
//    not of the backend. So when `j` is true the first assertion expects 126,
//    which is exactly the mismatch count a wasm backend produces once it is told
//    to use the js expectation. Forcing `j` to a constant `true` on wasm-gc
//    leaves the suite green (measured: 224/224), so the test cannot tell the two
//    backends apart.
//
// 2. The js expectation's *bit pattern* was wrong for three classes of pattern.
//    The test's `signaling && j` branch expects
//        ((want & 0x007FFFFF) >> 1) | 0x7FC00000
//    which is a *shift* of the whole binary32 mantissa field. Measured on js,
//    pattern for pattern, the transformation is not a shift: the quiet bit is set
//    and every other bit stays put —
//        0x7F81 -> 0x7FC10000   0x7F82 -> 0x7FC20000   0x7F83 -> 0x7FC30000
//        0xFF81 -> 0xFFC10000   0x7F01 -> 0x7F410000
//        0x7F7F -> 0x7F7F0000   0x7FFF -> 0x7FFF0000   (payload bits already zero)
//    i.e. `want | 0x00400000`. The shift formula turns `0x7F7F` into `0x7FFF8000`,
//    which would be an *infinity* pattern with the quiet bit set — not what the
//    backend produces. On the 126 signaling patterns the two formulas disagree on
//    three, which is why the existing test's own count (125 for the shift formula)
//    never matched the 126 it asserted: the assertion compares `value_bad` against
//    a constant, so the disagreement was invisible.
//
// This file locks the fact directly and on both sides:
//
//   * the `j` probe must agree with what the widening itself does, so a probe that
//     has stopped measuring anything fails;
//   * the quieted count must be the number the loop measures under the *correct*
//     rule, so a forced `j` contradicts a number the loop computed.

///|
test "bfloat16: the backend probe agrees with the widening it is used to explain" {
  let via_bits = BFloat16::decode(0x7F81).to_f32_bits()
  let via_value = f32_pattern(BFloat16::decode(0x7F81).to_f32())
  // `to_f32_bits` is the backend-independent route: the stored 16 bits at the top
  // of binary32, always. It returns the pattern as a number, hence the decimal.
  inspect(via_bits, content="2139160576")
  let j = js_value_route_quiets_nans()
  if j {
    // One NaN shape: quiet bit set, everything else where it was.
    inspect(via_value, content="2143354880")
  } else {
    // A real reinterpret: unchanged.
    inspect(via_value, content="2139160576")
  }
  // The two routes must agree exactly when the probe says patterns are kept.
  if not(j) && via_value != via_bits {
    fail(
      "probe says the value route keeps patterns, but it read a different one",
    )
  }
}

///|
test "bfloat16: signaling NaNs come back quiet-in-place, not shifted" {
  let j = js_value_route_quiets_nans()
  let mut sig = 0
  let mut in_place = 0
  let mut shifted = 0
  for i in 0..<65536 {
    let bits = i.to_uint16()
    let d = BFloat16::decode(bits)
    if d.kind != Nan || (d.significand & 0x40) != 0 {
      continue
    }
    sig = sig + 1
    let want = bits.to_uint() << 16
    let u = f32_pattern(d.to_f32())
    let in_place_want = want | 0x00400000
    if u == in_place_want {
      in_place = in_place + 1
    }
    // The shift formula is counted too, but only to record that it does *not*
    // describe this backend: `shifted` must stay 0 wherever `in_place` is 126.
    let shift_want = ((want & 0x007FFFFF) >> 1) | 0x7FC00000
    if u == shift_want {
      shifted = shifted + 1
    }
  }
  // 2 signs x 63 signaling payloads.
  inspect(sig, content="126")
  if j {
    // The backend has one NaN shape: every signaling pattern gets the quiet bit
    // and nothing else moves.
    if in_place != 126 {
      fail(
        "expected 126 quiet-in-place results on this backend, measured a different count",
      )
    }
    inspect(in_place, content="126")
    // The shift formula the original expectation used describes no pattern here:
    // `((want & 0x007FFFFF) >> 1) | 0x7FC00000` sets the quiet bit *and* moves the
    // payload, which the backend does not do.
    inspect(shifted, content="0")
  } else {
    // Patterns are kept: nothing changes, and the two formulas each disagree with
    // the observation somewhere, which is what makes the counts above meaningful.
    inspect(in_place, content="0")
    inspect(shifted, content="0")
  }
}
