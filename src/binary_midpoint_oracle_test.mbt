///|
/// TEMPORARY AUDIT PROBE (Lead, 2026-11-12) — delete before committing.
///
/// Exhaustive midpoint oracle for the two binary formats. It never consults a
/// reference implementation: for every pair of adjacent representable values
/// `(a, b)` the exact midpoint `(a + b) / 2` is representable in the wider
/// format (binary16 needs 12 significand bits, binary64 has 53; bfloat16 needs
/// 9, binary32 has 24), so IEEE 754-2008 §4.3 fixes every directed result and
/// the ties-to-even rule fixes the nearest one. `next_down(mid)` / `next_up(mid)`
/// pin the same seam one binary64 ulp away, where no tie is involved.

///|
fn next_up_d(x : Double) -> Double {
  let u = x.reinterpret_as_uint64()
  if x == 0.0 {
    0x0000000000000001UL.reinterpret_as_double()
  } else if u >> 63 == 1UL {
    (u - 1UL).reinterpret_as_double()
  } else {
    (u + 1UL).reinterpret_as_double()
  }
}

///|
fn next_down_d(x : Double) -> Double {
  let u = x.reinterpret_as_uint64()
  if x == 0.0 {
    0x8000000000000001UL.reinterpret_as_double()
  } else if u >> 63 == 1UL {
    (u + 1UL).reinterpret_as_double()
  } else {
    (u - 1UL).reinterpret_as_double()
  }
}

///|
test "PROBE binary16 midpoint oracle: every gap, both signs, five modes" {
  let modes : Array[RoundingMode] = [
    NearestEven,
    NearestAway,
    TowardZero,
    TowardPositive,
    TowardNegative,
  ]
  let mut bad = 0
  let log : Array[String] = []
  // p runs over every finite non-negative binary16 bit pattern whose successor
  // is also finite; 0x7BFF -> 2^16 (overflow) is excluded on purpose because
  // the ties-to-even answer at that specific midpoint is library policy.
  for p in 0..<0x7BFF {
    let a = Binary16::decode(p.to_uint16()).to_f64()
    let b = Binary16::decode((p + 1).to_uint16()).to_f64()
    let mid = (a + b) / 2.0
    let even_lo = p % 2 == 0
    let near = if even_lo { p } else { p + 1 }
    // positive side
    let pos_want : Array[Int32] = [near, p + 1, p, p + 1, p]
    for mi in 0..<5 {
      let got = of_f64(mid, modes[mi]).bits.to_int()
      let inexact = of_f64(mid, modes[mi]).inexact
      if got != pos_want[mi] || !inexact {
        bad = bad + 1
        if log.length() < 16 {
          log.push(
            "pos p=\{p} mi=\{mi} got=\{got} want=\{pos_want[mi]} inexact=\{inexact}",
          )
        }
      }
    }
    // negative side: magnitude grows downward
    let neg_mid = -mid
    let neg_want : Array[Int32] = [
      0x8000 + near,
      0x8000 + p + 1,
      0x8000 + p,
      0x8000 + p,
      0x8000 + p + 1,
    ]
    for mi in 0..<5 {
      let got = of_f64(neg_mid, modes[mi]).bits.to_int()
      let inexact = of_f64(neg_mid, modes[mi]).inexact
      if got != neg_want[mi] || !inexact {
        bad = bad + 1
        if log.length() < 16 {
          log.push(
            "neg p=\{p} mi=\{mi} got=\{got} want=\{neg_want[mi]} inexact=\{inexact}",
          )
        }
      }
    }
    // one binary64 ulp off the seam: no tie, so nearest is unambiguous
    let below = next_down_d(mid)
    let above = next_up_d(mid)
    if of_f64(below, NearestEven).bits.to_int() != p {
      bad = bad + 1
      if log.length() < 16 {
        log.push(
          "seam-below p=\{p} got=\{of_f64(below, NearestEven).bits.to_int()} want=\{p}",
        )
      }
    }
    if of_f64(above, NearestEven).bits.to_int() != p + 1 {
      bad = bad + 1
      if log.length() < 16 {
        log.push(
          "seam-above p=\{p} got=\{of_f64(above, NearestEven).bits.to_int()} want=\{p + 1}",
        )
      }
    }
  }
  for m in log {
    println(m)
  }
  inspect(bad, content="0")
}

///|
/// One binary32 ulp up: the seam has to be probed in float space, because a
/// binary64 ulp away from a float midpoint rounds straight back onto it.
fn next_up_f(x : Float) -> Float {
  let u = x.reinterpret_as_uint()
  if x == 0.0F {
    Float::reinterpret_from_uint(0x00000001U)
  } else if u >> 31 == 1U {
    Float::reinterpret_from_uint(u - 1U)
  } else {
    Float::reinterpret_from_uint(u + 1U)
  }
}

///|
fn next_down_f(x : Float) -> Float {
  let u = x.reinterpret_as_uint()
  if x == 0.0F {
    Float::reinterpret_from_uint(0x80000001U)
  } else if u >> 31 == 1U {
    Float::reinterpret_from_uint(u + 1U)
  } else {
    Float::reinterpret_from_uint(u - 1U)
  }
}

///|
test "PROBE bfloat16 midpoint oracle: every gap, both signs, five modes" {
  let modes : Array[RoundingMode] = [
    NearestEven,
    NearestAway,
    TowardZero,
    TowardPositive,
    TowardNegative,
  ]
  let mut bad = 0
  let log : Array[String] = []
  for p in 0..<0x7F7F {
    let a = BFloat16::decode(p.to_uint16()).to_f64()
    let b = BFloat16::decode((p + 1).to_uint16()).to_f64()
    let mid = Float::from_double((a + b) / 2.0)
    let mid_d = mid.to_double()
    if mid_d != (a + b) / 2.0 {
      bad = bad + 1
      if log.length() < 16 {
        log.push("mid not exact at p=\{p}: \{mid_d} vs \{(a + b) / 2.0}")
      }
    }
    let even_lo = p % 2 == 0
    let near = if even_lo { p } else { p + 1 }
    let pos_want : Array[Int32] = [near, p + 1, p, p + 1, p]
    for mi in 0..<5 {
      let conv = of_f32(mid, modes[mi])
      let got = conv.bits.to_int()
      if got != pos_want[mi] || !conv.inexact {
        bad = bad + 1
        if log.length() < 16 {
          log.push(
            "pos p=\{p} mi=\{mi} got=\{got} want=\{pos_want[mi]} inexact=\{conv.inexact}",
          )
        }
      }
    }
    let neg_mid = -mid
    let neg_want : Array[Int32] = [
      0x8000 + near,
      0x8000 + p + 1,
      0x8000 + p,
      0x8000 + p,
      0x8000 + p + 1,
    ]
    for mi in 0..<5 {
      let conv = of_f32(neg_mid, modes[mi])
      let got = conv.bits.to_int()
      if got != neg_want[mi] || !conv.inexact {
        bad = bad + 1
        if log.length() < 16 {
          log.push(
            "neg p=\{p} mi=\{mi} got=\{got} want=\{neg_want[mi]} inexact=\{conv.inexact}",
          )
        }
      }
    }
    // seam, in float space, and only where the neighbour stays finite
    if p < 0x7F7E {
      let below = next_down_f(mid)
      let above = next_up_f(mid)
      if of_f32(below, NearestEven).bits.to_int() != p {
        bad = bad + 1
        if log.length() < 16 {
          log.push(
            "seam-below p=\{p} got=\{of_f32(below, NearestEven).bits.to_int()} want=\{p}",
          )
        }
      }
      if of_f32(above, NearestEven).bits.to_int() != p + 1 {
        bad = bad + 1
        if log.length() < 16 {
          log.push(
            "seam-above p=\{p} got=\{of_f32(above, NearestEven).bits.to_int()} want=\{p + 1}",
          )
        }
      }
    }
  }
  for m in log {
    println(m)
  }
  inspect(bad, content="0")
}
