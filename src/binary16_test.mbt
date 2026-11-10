///|
/// Exhaustive binary16 coverage: PLAN.md §8 requires all 65536 bit patterns.
///
/// The first test is the round-trip. It is deliberately the *cheapest* possible
/// statement — the decoder must be field-for-field lossless — because a
/// round-trip over the whole domain catches any lookup-table or branch that
/// quietly substitutes a nearby legal value.

///|
test "binary16: all 65536 patterns decode->encode byte-identical" {
  let mut failures = 0
  let mut first_bad = -1
  for i in 0..<65536 {
    let bits = i.to_uint16()
    let d = Binary16::decode(bits)
    let back = d.encode()
    if back != bits {
      failures = failures + 1
      if first_bad < 0 {
        first_bad = i
      }
    }
  }
  inspect(failures, content="0")
  inspect(first_bad, content="-1")
}

///|
test "binary16: class partition covers all 65536 patterns disjointly" {
  let mut zero = 0
  let mut sub = 0
  let mut normal = 0
  let mut inf = 0
  let mut nan = 0
  for i in 0..<65536 {
    match Binary16::decode(i.to_uint16()).kind {
      Zero => zero = zero + 1
      Subnormal => sub = sub + 1
      Normal => normal = normal + 1
      Infinity => inf = inf + 1
      Nan => nan = nan + 1
    }
  }
  // The counts are forced by the field geometry: 2 zeros, 2*1023 subnormals,
  // 2*30*1024 normals, 2 infinities, 2*1023 NaNs.
  inspect(zero, content="2")
  inspect(sub, content="2046")
  inspect(normal, content="61440")
  inspect(inf, content="2")
  inspect(nan, content="2046")
  inspect(zero + sub + normal + inf + nan, content="65536")
}

///|
test "binary16: PLAN.md §2 anchors" {
  let one = Binary16::decode(0x3C00)
  let v = one.to_f64()
  inspect(one.kind.label(), content="normal")
  inspect(v, content="1")
  let d = v - 1.0
  assert_true(d.abs() < 0.0000000000001)

  let third = Binary16::decode(0x3555)
  let t = third.to_f64()
  let td = t - 0.333251953125
  assert_true(td.abs() < 0.0000000000001)

  let tiny = Binary16::decode(0x0001)
  inspect(tiny.kind.label(), content="subnormal")
  let tv = tiny.to_f64()
  let tvd = tv - pow2_exact(-24)
  assert_true(tvd.abs() < 0.0000000000000000000000000000001)

  let big = Binary16::decode(0x7BFF)
  let bv = big.to_f64()
  let bvd = bv - 65504.0
  assert_true(bvd.abs() < 0.000000001)

  let mn = Binary16::decode(0x0400)
  inspect(mn.kind.label(), content="normal")
  let mnv = mn.to_f64()
  let mnvd = mnv - pow2_exact(-14)
  assert_true(mnvd.abs() < 0.0000000000001)

  inspect(Binary16::decode(0x7C00).kind.label(), content="infinity")
  inspect(Binary16::decode(0xFC00).kind.label(), content="infinity")
  inspect(Binary16::decode(0xFC00).sign, content="1")
}

///|
test "binary16: both zeros keep their sign through to_f64" {
  let pos = Binary16::decode(0x0000).to_f64()
  let neg = Binary16::decode(0x8000).to_f64()
  // 1/x distinguishes the two zeros without needing bit-pattern helpers that
  // would themselves be under test.
  assert_true(pos == 0.0)
  assert_true(neg == 0.0)
  let pid = 1.0 / pos
  let nid = 1.0 / neg
  inspect(pid, content="Infinity")
  inspect(nid, content="-Infinity")
}

///|
test "binary16: of_f64 preserves signed zero" {
  let z = of_f64(0.0, NearestEven)
  inspect(z.bits, content="0")
  inspect(z.inexact, content="false")
  let nz = of_f64(-0.0, NearestEven)
  inspect(nz.bits, content="32768")
  inspect(nz.inexact, content="false")
}

///|
test "binary16: finite patterns survive f64 round-trip, exactly" {
  // Every finite pattern must come back bit-identical *and* be reported exact:
  // binary16 is a subset of binary64, so no rounding is legitimate here.
  //
  // NaNs are excluded on purpose, not for convenience: `to_f64` cannot carry a
  // 10-bit payload into a binary64 NaN and back, so the round-trip through a
  // double is lossy for payloads by construction. The byte-level round-trip for
  // NaNs goes through `Binary16::encode` instead, tested separately.
  let mut failures = 0
  let mut inexact_failures = 0
  for i in 0..<65536 {
    let bits = i.to_uint16()
    let d = Binary16::decode(bits)
    if d.is_special() {
      continue
    }
    let v = d.to_f64()
    let conv = of_f64(v, NearestEven)
    if conv.bits != bits {
      failures = failures + 1
    } else if conv.inexact {
      inexact_failures = inexact_failures + 1
    }
  }
  inspect(failures, content="0")
  inspect(inexact_failures, content="0")
}

///|
test "binary16: NaN through f64 collapses to the canonical quiet NaN" {
  // The honest statement of the asymmetry: a payload survives decode->encode,
  // but not decode->to_f64->of_f64. Only the canonical quiet NaN is a fixed
  // point, and it is the only one reported exact.
  let mut fixed_points = 0
  let mut others_inexact = 0
  let mut wrong_bits = 0
  for i in 0..<65536 {
    let bits = i.to_uint16()
    let d = Binary16::decode(bits)
    if d.kind != Nan {
      continue
    }
    let conv = of_f64(d.to_f64(), NearestEven)
    let canonical = if d.sign == 1 { 0xFE00 } else { 0x7E00 }
    let got = conv.bits.to_int()
    if got == bits.to_int() {
      fixed_points = fixed_points + 1
    } else if conv.inexact && got == canonical {
      others_inexact = others_inexact + 1
    } else {
      wrong_bits = wrong_bits + 1
    }
  }
  // 0x7E00 and 0xFE00 are the canonical quiet NaNs and are fixed points.
  inspect(fixed_points, content="2")
  inspect(others_inexact, content="2044")
  inspect(wrong_bits, content="0")
}

///|
test "binary16: f64 subnormal input underflows, it does not shift wrongly" {
  // A binary64 subnormal has e = -1074, so the rounding shift is 1050 bits —
  // far beyond a 64-bit word. Before the guard in `round_to_quantum` this
  // produced a nonsense count instead of zero. Every mode reports inexact; where
  // the count lands is decided by the mode (BN-B1: the nearest modes and
  // `TowardZero` go to the signed zero, the outward directed modes go to the
  // smallest subnormal of that sign).
  let tiny = 5.0 * pow2_exact(-1074)
  let inward : Array[RoundingMode] = [NearestEven, NearestAway, TowardZero]
  for mode in inward {
    let c = of_f64(tiny, mode)
    inspect(c.bits, content="0")
    inspect(c.inexact, content="true")
  }
  // TowardPositive on a positive value is outward: one ulp, never zero.
  inspect(of_f64(tiny, TowardPositive).bits, content="1")
  inspect(of_f64(tiny, TowardPositive).inexact, content="true")
  // TowardNegative on a positive value is inward.
  inspect(of_f64(tiny, TowardNegative).bits, content="0")
  // And a negative one, where the directed modes must flip toward -0.
  let neg_tiny = -5.0 * pow2_exact(-1074)
  let cp = of_f64(neg_tiny, TowardNegative)
  inspect(cp.bits, content="32769")
  inspect(cp.inexact, content="true")
  let cz = of_f64(neg_tiny, TowardZero)
  inspect(cz.bits, content="32768")
  inspect(of_f64(neg_tiny, TowardPositive).bits, content="32768")
}

///|
/// BN-B1: the deep-underflow region — everything with |x| < 2^-35, which includes
/// every binary64 subnormal — has a rounding shift of 64 bits or more, and the
/// guard for that region used to return zero units regardless of the mode. IEEE
/// 754-2008 §4.3.3 is unambiguous: a nonzero value rounded *outward* is the
/// smallest subnormal of that sign, so `TowardPositive` on a positive value (and
/// `TowardNegative` on a negative one) must produce `0x0001` / `0x8001`, not a
/// signed zero.
///
/// The boundary is sharp because it is `shift == 64`: `2^-35` still fits the
/// 64-bit path and was always right, `2^-36` does not. Both sides are asserted so
/// a future change to the guard cannot move the seam unnoticed.
test "binary16: deep underflow rounds away from zero under the directed modes" {
  // 2^-35 is the last input the 64-bit-shift path handles: it is exact-zero
  // everything but directed-outward, and it was already correct.
  inspect(of_f64(pow2_exact(-35), TowardPositive).bits, content="1")
  inspect(of_f64(-pow2_exact(-35), TowardNegative).bits, content="32769")
  // 2^-36 crosses into shift >= 64 and is the audit's reproduction.
  inspect(of_f64(pow2_exact(-36), TowardPositive).bits, content="1")
  inspect(of_f64(-pow2_exact(-36), TowardNegative).bits, content="32769")
  // The inward side of the same inputs stays at the signed zero.
  inspect(of_f64(pow2_exact(-36), TowardNegative).bits, content="0")
  inspect(of_f64(-pow2_exact(-36), TowardPositive).bits, content="32768")
  inspect(of_f64(pow2_exact(-36), NearestEven).bits, content="0")
  inspect(of_f64(pow2_exact(-36), NearestAway).bits, content="0")
  inspect(of_f64(pow2_exact(-36), TowardZero).bits, content="0")
  // And the smallest binary64 subnormal, the deepest input that exists at all.
  let deep = 5.0 * pow2_exact(-1074)
  inspect(of_f64(deep, TowardPositive).bits, content="1")
  inspect(of_f64(-deep, TowardNegative).bits, content="32769")
  // The outward result is flagged inexact in every direction: the value really
  // was not representable, and the flag says so rather than describing the
  // chosen direction.
  inspect(of_f64(pow2_exact(-36), TowardPositive).inexact, content="true")
}

///|
test "binary16: f64 subnormal exactly zero stays exact zero" {
  let c = of_f64(0.0 * pow2_exact(-1074), NearestEven)
  inspect(c.bits, content="0")
  inspect(c.inexact, content="false")
}

///|
test "binary16: NaN payload survives decode->encode, not through f64" {
  // A NaN's payload is part of the byte-level identity (PLAN.md §1.1), so the
  // field-preserving encode is what keeps it. Going through f64 cannot, and
  // that asymmetry is asserted rather than hidden.
  let d = Binary16::decode(0x7E01)
  inspect(d.kind.label(), content="nan")
  inspect(d.nan_payload(), content="513")
  inspect(d.is_quiet_nan(), content="true")
  inspect(d.encode(), content="32257")
  for payload in 1..<1024 {
    let bits = (0x7C00 | payload).to_uint16()
    let p = Binary16::decode(bits)
    inspect(p.kind.label(), content="nan")
    inspect(p.encode(), content=bits.to_string())
  }
}
