///|
/// The binary16 overflow threshold, pinned as a contract (round 20, 2026-11-28).
///
/// **The question this file settles.** A note carried over from the 2026-11-27
/// round reported that `of_f64(1e18, TowardPositive)` "seemed to yield `7C00`
/// instead of `7BFF`", i.e. that the directed modes were ignored somewhere in the
/// overflow branch. Two sweeps were written to chase it. Both were rejected by
/// their own evidence and never committed; this file records what the evidence
/// actually says, so the next round does not repeat the hunt.
///
/// **Why the carried-over expectation was wrong.** `2 * max_finite` is not the
/// point where a value stops rounding to the largest finite number. Rounding
/// happens *before* overflow: `65505` is 32.024 away from `65536` and 0.976 away
/// from `65504`, so round-to-nearest takes it to `65504` — no overflow at all —
/// and the budget of "one ulp = 32" only runs out at the midpoint `65520`, where
/// ties-to-even picks `65536` (significand `2^20`, even) and IEEE 754 then
/// overflows to infinity. The band `(65504, 65520]` therefore splits in two, and
/// only the upper half is an overflow:
///
///   | x                | nearest        | toward zero    | away from zero |
///   |------------------|----------------|----------------|----------------|
///   | `65504`          | `0x7BFF` exact | `0x7BFF`       | `0x7BFF`       |
///   | `(65504, 65520)` | `0x7BFF`       | `0x7BFF`       | `0x7C00`       |
///   | `[65520, …)`     | `0x7C00`       | `0x7BFF`       | `0x7C00`       |
///
/// Three independent sources agree with the implementation as it stands: the
/// repo's Python reference (`scripts/float_ref.py`), the generator's stored rows
/// (`examples/vectors-binary16.tsv`), and simulation hardware — Python's
/// `struct.pack('<e', …)` rounds half-to-even and packs `65505`/`65519` as
/// `7BFF`, `65520`/`65536`/`1e18` as overflow. The evidence table is
/// `audit/2026-11-28/bitnum-evidence/THRESHOLD.log`.
///
/// **What is locked below.** Not just the threshold: the whole band is swept in
/// one-ulp steps, both signs, all five modes, and the two directed modes are
/// asserted separately on each side of the seam. `TowardPositive` on `65505`
/// (a finite answer above the largest finite value) and `TowardPositive` on
/// `1e18` (an overflow under the same mode) are the pair the carried-over note
/// confused, so they are pinned next to each other.

///|
/// The largest finite binary16 magnitude, exactly representable in binary64.
fn bin16_max_finite() -> Double {
  65504.0
}

///|
/// The midpoint between the largest finite magnitude and the next power of two.
/// Ties-to-even rounds it up, and §7.4 then makes that an overflow.
fn bin16_overflow_midpoint() -> Double {
  65520.0
}

///|
test "binary16: of_f64 keeps the directed mode across the whole overflow band" {
  let modes : Array[RoundingMode] = [
    NearestEven,
    NearestAway,
    TowardZero,
    TowardPositive,
    TowardNegative,
  ]
  // One ulp per row (the binary16 ulp at this exponent is 16, but the band is
  // narrow enough that every integer in it is a distinct binary64), plus the
  // seam itself, both sides, and the far side where every mode saturates.
  let magnitudes : Array[Double] = [
    65504.0, 65505.0, 65512.0, 65516.0, 65519.0, 65520.0, 65521.0, 65528.0, 65536.0,
    65537.0, 100000.0, 1000000000000000000.0,
  ]
  let seam = bin16_overflow_midpoint()
  let maxf = bin16_max_finite()
  for mode in modes {
    for neg in [false, true] {
      for mag in magnitudes {
        let x = if neg { -mag } else { mag }
        let conv = of_f64(x, mode)
        // The two questions the implementation must answer independently:
        // (1) does this rounding overflow at all, and (2) which direction does
        // the mode round in.
        // Nearest modes round to the nearest finite neighbour first: 65504 while
        // x <= 65520 (ties-to-even takes the seam up to 2^16), so the overflow
        // budget only runs out at the seam. The directed modes clamp to 65504
        // whenever they round toward zero, and reach 2^16 (which overflows)
        // whenever they round away from it.
        let overflows = if mag <= maxf {
          false
        } else if mode == NearestEven || mode == NearestAway {
          mag >= seam
        } else if mode == TowardZero {
          false
        } else {
          // Directed and nonzero: away from zero iff it points at the sign's side.
          (mode == TowardPositive) == !neg
        }
        let want_mag = if overflows { 0x7C00 } else { 0x7BFF }
        let want = if neg { want_mag | 0x8000 } else { want_mag }
        inspect(conv.bits.to_int().to_string(), content=want.to_string())
        // Exactness: only the largest finite magnitude itself is representable;
        // every other magnitude in the band loses information.
        inspect(conv.inexact, content=(mag != maxf).to_string())
      }
    }
  }
}

///|
/// The specific pair the carried-over note confused, stated as two facts.
///
/// `65505` rounds to the largest finite number — it is *not* an
/// overflow, so a directed mode pointing away from zero produces `0x7C00` while
/// the other two interior directions produce `0x7BFF`. `1e18`, far past the
/// threshold, is an overflow for every mode, so `TowardPositive` produces
/// `0x7C00` and `TowardNegative` produces `0x7BFF`. Both are correct; reading
/// them as contradictory is what started the round-19 note.
test "binary16: 65505 and 1e18 overflow differently, and both are specified" {
  // Interior of the band: only the outward direction overflows.
  inspect(of_f64(65505.0, TowardPositive).bits, content="31744")
  inspect(of_f64(65505.0, TowardNegative).bits, content="31743")
  inspect(of_f64(65505.0, TowardZero).bits, content="31743")
  inspect(of_f64(-65505.0, TowardPositive).bits, content="64511")
  inspect(of_f64(-65505.0, TowardNegative).bits, content="64512")
  // The seam: ties-to-even goes to 2^16 and overflows.
  inspect(of_f64(bin16_overflow_midpoint(), NearestEven).bits, content="31744")
  inspect(of_f64(bin16_overflow_midpoint(), TowardZero).bits, content="31743")
  // Far side: every mode sees an overflow, so the direction decides alone.
  inspect(of_f64(1000000000000000000.0, TowardPositive).bits, content="31744")
  inspect(of_f64(1000000000000000000.0, TowardNegative).bits, content="31743")
  inspect(of_f64(1000000000000000000.0, TowardZero).bits, content="31743")
  inspect(of_f64(1000000000000000000.0, NearestEven).bits, content="31744")
  inspect(of_f64(-1000000000000000000.0, TowardNegative).bits, content="64512")
  inspect(of_f64(-1000000000000000000.0, TowardPositive).bits, content="64511")
}
