///|
/// Exhaustive bfloat16 coverage: PLAN.md §8 requires all 65536 patterns and that
/// `to_f32` matches the high 16 bits of the binary32 pattern.
///
/// The round-trip is trivially true by construction (decode splits fields, encode
/// reassembles), so the interesting assertion is the widening: bfloat16 → binary32
/// must be *exact*, meaning the low 16 bits of the widening are zero and the high
/// 16 bits are the original pattern.

///|
test "bfloat16: all 65536 patterns decode->encode byte-identical" {
  let mut failures = 0
  let mut first_bad = -1
  for i in 0..<65536 {
    let bits = i.to_uint16()
    let d = BFloat16::decode(bits)
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
test "bfloat16: to_f32 equals the pattern in the high 16 bits" {
  let mut high_mismatch = 0
  let mut low_dirty = 0
  for i in 0..<65536 {
    let bits = i.to_uint16()
    let f = BFloat16::decode(bits).to_f32()
    let u = f.reinterpret_as_uint()
    let high = (u >> 16) & 0xFFFF
    let low = u & 0xFFFF
    if high != bits.to_uint() {
      high_mismatch = high_mismatch + 1
    }
    if low != 0 {
      low_dirty = low_dirty + 1
    }
  }
  inspect(high_mismatch, content="0")
  inspect(low_dirty, content="0")
}

///|
test "bfloat16: widening carries every pattern back, quieting signaling NaNs" {
  // Widening puts the 7 stored bits at the top of binary32's 23-bit field, so 16
  // low bits are zero and re-narrowing drops no payload — `inexact` is false
  // everywhere. The only patterns whose bits change are the *signaling* NaNs
  // (quiet bit clear): narrowing sets the quiet bit, per IEEE 754 §6.2. That is
  // not a loss of information, so it is not "inexact", and conflating the two
  // would make the flag unusable.
  let mut unchanged = 0
  let mut quieted = 0
  let mut inexact_any = 0
  let mut unexpected = 0
  for i in 0..<65536 {
    let bits = i.to_uint16()
    let d = BFloat16::decode(bits)
    let conv = of_f32(d.to_f32(), NearestEven)
    if conv.inexact {
      inexact_any = inexact_any + 1
    }
    if conv.bits.to_uint() == bits.to_uint() {
      unchanged = unchanged + 1
    } else if d.kind == Nan && (d.significand & 0x40) == 0 {
      // Signaling NaN in, quiet NaN out, payload untouched: only bit 6 was set.
      let expected = bits.to_uint() | 0x40
      if conv.bits.to_uint() == expected {
        quieted = quieted + 1
      } else {
        unexpected = unexpected + 1
      }
    } else {
      unexpected = unexpected + 1
    }
  }
  // 126 signaling NaNs = 2 signs x 63 payloads; the other 65410 are unchanged.
  inspect(unchanged, content="65410")
  inspect(quieted, content="126")
  inspect(inexact_any, content="0")
  inspect(unexpected, content="0")
}

///|
test "bfloat16: class partition covers all 65536 patterns" {
  let mut zero = 0
  let mut sub = 0
  let mut normal = 0
  let mut inf = 0
  let mut nan = 0
  for i in 0..<65536 {
    match BFloat16::decode(i.to_uint16()).kind {
      Zero => zero = zero + 1
      Subnormal => sub = sub + 1
      Normal => normal = normal + 1
      Infinity => inf = inf + 1
      Nan => nan = nan + 1
    }
  }
  // 2 zeros, 2*127 subnormals, 2*254*128 normals, 2 infinities, 2*127 NaNs.
  inspect(zero, content="2")
  inspect(sub, content="254")
  inspect(normal, content="65024")
  inspect(inf, content="2")
  inspect(nan, content="254")
}

///|
test "bfloat16: PLAN.md §3 anchors" {
  let one = BFloat16::decode(0x3F80).to_f32().to_double()
  let d1 = one - 1.0
  assert_true(d1.abs() < 0.0000000000001)
  let two = BFloat16::decode(0x4000).to_f32().to_double()
  let d2 = two - 2.0
  assert_true(d2.abs() < 0.0000000000001)
  inspect(BFloat16::decode(0x7F80).kind.label(), content="infinity")
  inspect(BFloat16::decode(0xFF80).kind.label(), content="infinity")
  inspect(BFloat16::decode(0xFF80).sign, content="1")
  inspect(BFloat16::decode(0x7FC0).kind.label(), content="nan")
  // 0x0001 = 2^-133, the smallest subnormal.
  let tiny = BFloat16::decode(0x0001).to_f32().to_double()
  inspect(BFloat16::decode(0x0001).kind.label(), content="subnormal")
  let dt = tiny - pow2_exact(-133)
  assert_true(dt.abs() < 0.0000000000000000000000000000000000000000001)
}

///|
test "bfloat16: widening is idempotent under both narrowing functions" {
  // On values that are *already* bfloat16, truncation and rounding must agree —
  // that is what makes the two genuinely different only on inputs that need
  // narrowing. Infinities and NaNs are included because those are exactly the
  // classes a naive truncation gets wrong.
  let mut differ = 0
  let mut agree = 0
  for i in 0..<65536 {
    let f = BFloat16::decode(i.to_uint16()).to_f32()
    if truncate_round_differ(f) {
      differ = differ + 1
    } else {
      agree = agree + 1
    }
  }
  inspect(differ, content="126")
  inspect(agree, content="65410")
}

///|
test "bfloat16: truncation error is bounded by one ulp, rounding by half" {
  // 1.0 + 2^-8 is exactly halfway between two bfloat16 values; truncation drops
  // toward zero while nearest-even keeps 1.0 (even significand).
  let halfway = Float::reinterpret_from_uint(0x3F808000U)
  let t = of_f32_truncate(halfway)
  let r = of_f32_round(halfway).bits
  inspect(t, content="16256")
  inspect(r, content="16256")
  assert_true(not(truncate_round_differ(halfway)))
  // Just above the halfway point: rounding must move up, truncation must not.
  let above = Float::reinterpret_from_uint(0x3F808001U)
  inspect(of_f32_truncate(above), content="16256")
  inspect(of_f32_round(above).bits, content="16257")
  assert_true(truncate_round_differ(above))
  // Just below the halfway point: both stay put.
  let below = Float::reinterpret_from_uint(0x3F807FFFU)
  inspect(of_f32_truncate(below), content="16256")
  inspect(of_f32_round(below).bits, content="16256")
}

///|
test "bfloat16: truncating a NaN keeps it a NaN, truncating infinity keeps it infinity" {
  // A binary32 NaN whose payload lives entirely in the discarded low 16 bits
  // would truncate into an infinity — that is the one place truncation can
  // change the datum class, and it must not.
  let nan_low_payload = Float::reinterpret_from_uint(0x7F800001U)
  inspect(nan_low_payload.is_nan(), content="true")
  let t = of_f32_truncate(nan_low_payload)
  inspect(BFloat16::decode(t).kind.label(), content="nan")
  inspect(t, content="32704")
  // And a NaN with payload bits that survive truncation keeps them.
  let nan_high_payload = Float::reinterpret_from_uint(0x7FC02000U)
  let t2 = of_f32_truncate(nan_high_payload)
  inspect(t2.to_uint(), content="32704")
  inspect(BFloat16::decode(t2).kind.label(), content="nan")
}

///|
test "bfloat16: regression — truncating infinity must not produce a NaN" {
  // The bug: the class test looked at the *truncated* pattern, where an
  // infinity (0x7F800000) and a payload-starved NaN both show `sig == 0`, so
  // +Infinity truncated to 0x7FC0 — a NaN. Now the test is on the source value.
  let pos_inf = Float::reinterpret_from_uint(0x7F800000U)
  let neg_inf = Float::reinterpret_from_uint(0xFF800000U)
  inspect(of_f32_truncate(pos_inf), content="32640")
  inspect(of_f32_truncate(neg_inf), content="65408")
  inspect(
    BFloat16::decode(of_f32_truncate(pos_inf)).kind.label(),
    content="infinity",
  )
  inspect(
    BFloat16::decode(of_f32_truncate(neg_inf)).kind.label(),
    content="infinity",
  )
  inspect(BFloat16::decode(of_f32_truncate(neg_inf)).sign, content="1")
  // Exactly-representable finite values must survive truncation untouched too.
  // `Double::to_float` was removed from core; 1.0f is exact either way.
  let one : Float = 1.0
  inspect(of_f32_truncate(one), content="16256")
  inspect(BFloat16::decode(of_f32_truncate(one)).kind.label(), content="normal")
}

///|
test "bfloat16: overflow modes" {
  // 3.4e38 is above the largest finite bfloat16; nearest modes go to infinity,
  // inward-directed modes go to max finite.
  let big = Float::reinterpret_from_uint(0x7F7FFFFFU)
  inspect(of_f32(big, NearestEven).bits.to_uint(), content="32640")
  inspect(of_f32(big, NearestAway).bits.to_uint(), content="32640")
  inspect(of_f32(big, TowardZero).bits.to_uint(), content="32639")
  inspect(of_f32(big, TowardPositive).bits.to_uint(), content="32640")
  inspect(of_f32(big, TowardNegative).bits.to_uint(), content="32639")
  let neg_big = Float::reinterpret_from_uint(0xFF7FFFFFU)
  inspect(of_f32(neg_big, TowardZero).bits.to_uint(), content="65407")
  inspect(of_f32(neg_big, TowardPositive).bits.to_uint(), content="65407")
  inspect(of_f32(neg_big, TowardNegative).bits.to_uint(), content="65408")
}

///|
test "bfloat16: binary32 subnormal rounds into bfloat16 zero, inexact" {
  // The smallest binary32 subnormal is 2^-149, far below bfloat16's 2^-133
  // quantum. It must become zero and say so.
  let tiny = Float::reinterpret_from_uint(0x00000001U)
  let conv = of_f32(tiny, NearestEven)
  inspect(conv.bits.to_uint(), content="0")
  inspect(conv.inexact, content="true")
  // Signed zero is still distinguished.
  let ntiny = Float::reinterpret_from_uint(0x80000001U)
  let cneg = of_f32(ntiny, NearestEven)
  inspect(cneg.bits.to_uint(), content="32768")
  inspect(cneg.inexact, content="true")
}

///|
test "bfloat16: binary32 zero stays exact signed zero" {
  let zero : Float = 0.0
  inspect(of_f32(zero, NearestEven).bits.to_uint(), content="0")
  inspect(of_f32(zero, NearestEven).inexact, content="false")
  let nz = of_f32(Float::reinterpret_from_uint(0x80000000U), NearestEven)
  inspect(nz.bits.to_uint(), content="32768")
  inspect(nz.inexact, content="false")
}

///|
test "bfloat16: binary32 smallest normal rounds to smallest bfloat16 normal" {
  // 2^-126 is the smallest normal in both formats, so it must be exact.
  let min_normal = Float::reinterpret_from_uint(0x00800000U)
  let conv = of_f32(min_normal, NearestEven)
  inspect(conv.bits.to_uint(), content="128")
  inspect(conv.inexact, content="false")
  inspect(BFloat16::decode(conv.bits).kind.label(), content="normal")
}
