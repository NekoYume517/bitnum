///|
/// Bit-level helpers shared by every codec in this package, plus the two
/// vocabulary types they have in common.
///
/// Nothing here guesses. A shift width or a mask width is either derived from
/// the container geometry or rejected; no function silently clamps a field to
/// a legal-looking value.

///|
/// IEEE 754-2008 §4.3 rounding-direction attributes.
///
/// The five modes are required up front (PLAN.md §2) because "round to nearest,
/// ties to even" is *not* what a printf-style conversion does and the difference
/// is visible at every one of the 65536 binary16 boundaries.
#derive(Eq, Debug)
pub(all) enum RoundingMode {
  NearestEven
  NearestAway
  TowardZero
  TowardPositive
  TowardNegative
}

///|
/// The five kinds of binary floating-point datum (IEEE 754-2008 §2.1.3), with
/// `Zero` and `Subnormal` kept apart: they share an exponent field of zero but
/// behave differently, and conflating them is the classic binary16 bug.
#derive(Eq, Debug)
pub(all) enum FloatClass {
  Zero
  Subnormal
  Normal
  Infinity
  Nan
}

///|
/// Canonical spelling, used by the CLI's field breakdown and by tests that want
/// a stable name rather than a derived representation.
pub fn FloatClass::label(self : FloatClass) -> String {
  match self {
    Zero => "zero"
    Subnormal => "subnormal"
    Normal => "normal"
    Infinity => "infinity"
    Nan => "nan"
  }
}

///|
/// Result of a rounding conversion: the produced bit pattern and whether the
/// source value was representable exactly (PLAN.md §1.3 — an inexact result is
/// *marked*, never returned silently).
#derive(Eq, Debug)
pub(all) struct FloatConversion {
  bits : UInt16
  inexact : Bool
}

///|
/// Number of set bits in a 64-bit word.
pub fn popcount64(v : UInt64) -> Int32 {
  v.popcnt()
}

///|
/// Number of leading zero bits; 64 for zero, so `bit_length64(0) == 0`.
pub fn clz64(v : UInt64) -> Int32 {
  v.clz()
}

///|
/// Position of the most significant set bit plus one; 0 for zero.
pub fn bit_length64(v : UInt64) -> Int32 {
  64 - v.clz()
}

///|
/// Mask with the low `n` bits set. `n <= 0` gives 0, `n >= 64` gives all ones —
/// the natural limit of the container, not a clamp of a caller's value.
pub fn low_mask64(n : Int32) -> UInt64 {
  if n <= 0 {
    0UL
  } else if n >= 64 {
    0xFFFFFFFFFFFFFFFFUL
  } else {
    (1UL << n) - 1UL
  }
}

///|
/// `2^exponent` as a Double by **exponent-field construction**, exact for every
/// `exponent` in `[-1022, 1023]` — the whole normal binade range of binary64.
///
/// The operand is built from its bit pattern (sign 0, biased exponent
/// `exponent + 1023`, zero significand), so the result carries the all-zero
/// fraction that makes it a power of two *by definition* rather than by
/// arithmetic luck. It needs no arithmetic instruction at all, which is the
/// point: see `pow2_doubling` (2026-11-30 toolchain-1.0 audit, BN-p).
///
/// The domain is narrower than `pow2_exact`'s on the negative side — the
/// subnormal range `[-1074, -1023]` has no exponent field to borrow. Callers
/// that reach it go through the doubling loop instead.
fn pow2_normal(exponent : Int32) -> Double {
  let biased = (exponent + 1023).to_uint64()
  (biased << 52).reinterpret_as_double()
}

///|
/// `2^k` as a Double, exact for every `k` in `[-1074, 1023]` — binary64's exact
/// power-of-two range, from the smallest subnormal to the largest finite binade.
///
/// Rather than `@math.pow`: libm `pow` is only accurate to within an ulp, which is
/// not good enough to claim exactness for the 65536-value binary16 table. The domain
/// is checked rather than assumed — the fallback work is `|k|` iterations, so an
/// unbounded `k` is an unbounded loop, and outside the range the result stops being a
/// power of two as well (it saturates to `0` or `infinity`). Rejecting states both
/// facts instead of returning a number nobody asked for (2026-11-17 audit, BN-h).
///
/// **The normal binade is not computed by arithmetic at all** (2026-11-30 toolchain
/// 1.0 audit, BN-p): `k >= -1022` goes to `pow2_normal`, which builds the pattern.
/// Two reasons, and both were measured:
///
/// 1. *Backend invariance.* A `Float`/`Double` that only ever travels through
///    `reinterpret_*` and integer literals is re-emitted unrounded, so the pattern
///    is the same on wasm, wasm-gc and js. An arithmetic result is not: JS has one
///    number type and implements `Float` as binary64 narrowed afterwards, while
///    wasm's `f32` has its own rounding. Under `moonc v1.0.0-rc1` the old
///    double-then-narrow spelling of `Binary16::to_f64` lost the last bit on the
///    js backend for 2 of 65536 patterns.
/// 2. *Cost.* The loop is `|k|` iterations; the construction is one shift. The
///    subnormal tail `[-1074, -1023]` cannot be built from an exponent field and
///    still uses the loop — it is 52 iterations at worst, and it *must* stay
///    arithmetic: a subnormal power of two needs a non-zero fraction, so the
///    pattern route would have to divide anyway.
pub fn pow2_exact(k : Int32) -> Double raise BitnumError {
  if k < -1074 || k > 1023 {
    raise UnbiasedExponentOutOfRange(k.to_int64(), -1074L, 1023L)
  }
  if k >= -1022 {
    pow2_normal(k)
  } else {
    pow2_doubling(k)
  }
}

///|
/// The doubling loop without the domain check: **precondition** `-1074 <= k <= 1023`.
///
/// Private because the precondition is what makes it safe. The two call sites in
/// `Binary16::to_f64` pass `-24` and `exponent - 25`, where the exponent field is
/// `1..30` by construction, and neither function can raise. A public entry point
/// that skipped the check would be the unbounded loop again.
fn pow2_doubling(k : Int32) -> Double {
  let mut r = 1.0
  if k >= 0 {
    for _ in 0..<k {
      r = r * 2.0
    }
  } else {
    for _ in 0..<-k {
      r = r / 2.0
    }
  }
  r
}

///|
/// Bit length of a BigInt; 0 for zero.
pub fn bit_length_big(v : BigInt) -> Int32 {
  v.bit_length()
}

///|
/// Bits `[offset, offset + width)` of a **non-negative** BigInt, as a non-negative
/// BigInt.
///
/// The window is **total** (2026-11-17 audit, BN-o) in both `offset` and `width`: a
/// non-negative integer has no bits below bit 0 and none past its most significant
/// set bit, so every window that leaves the number's own bit string is empty — a
/// negative `offset`, a negative `width`, or a start past the end. Only one of those
/// three used to be answered: `width < 0` returned zero while a negative `offset`
/// reached `BigInt::shr`, which raises core's `negative shift count`. Since this
/// function returns a `BigInt` and is not declared `raise`, that error cannot be
/// caught by the caller — the process dies. It is the same "state the domain"
/// question `to_hex` and `low_mask64` answer, applied to the other dimension.
///
/// The **value** direction is declared here and nowhere else: `v >= 0`. A negative
/// BigInt has no most significant set bit to stop at — its two's-complement form is an
/// infinite string of ones — so the empty-window reasoning above describes nothing for
/// it, and `bit_length()` does not even agree with itself (`-1` answers 0, `-6`
/// answers 3). What the code then returns (`0`, the arithmetic shift's own negative
/// value, or a masked window, depending on the arguments) is not one rule, and this
/// function has no `raise` channel to reject the input with. Every caller in this
/// package hands over a non-negative value: `decode_raw` is the only producer of wire
/// bits and it rejects a negative pattern before any slicing (2026-11-21 audit), so
/// this is a declared precondition — the same shape as `dpd_encode3`'s digit range.
pub fn big_slice(v : BigInt, offset : Int32, width : Int32) -> BigInt {
  let value_bits = v.bit_length()
  if offset < 0 || width <= 0 || offset >= value_bits {
    return BigInt::from_int(0)
  }
  let shifted = v >> offset
  let remaining = value_bits - offset
  if width >= remaining {
    shifted
  } else {
    BigInt::land(shifted, (BigInt::from_int(1) << width) - BigInt::from_int(1))
  }
}

///|
/// `from << width | to` for non-negative BigInts — the OR the formula says, not an
/// addition that only agrees when `to` fits in `width` bits.
///
/// The two spellings differ exactly where a caller would trust the document: with
/// `to >= 2^width` the bits overlap, `|` keeps them in place and `+` carries out of
/// the field (`big_splice(1, 4, 2)` is 4 documented, 8 added). The formula is the
/// contract here, so the code follows it (2026-11-17 audit).
///
/// A negative `width` is pinned to `0` rather than shifted (2026-11-17 audit,
/// BN-o): `from << width` raised core's `negative shift count`, which — with no
/// `raise` in this signature — terminated the caller's process. Pinning to the
/// nearest legal width keeps the answer on the formula, `from << 0 | to` =
/// `from | to`, the same value `width == 0` produces, so the pin is continuous
/// and invents no arithmetic of its own.
pub fn big_splice(from : BigInt, to : BigInt, width : Int32) -> BigInt {
  let w = if width < 0 { 0 } else { width }
  if from.is_zero() {
    to
  } else {
    BigInt::lor(from << w, to)
  }
}

///|
/// Decimal digit count of a non-negative BigInt (0 has one digit).
pub fn digit_count_big(v : BigInt) -> Int32 {
  if v.is_zero() {
    1
  } else {
    v.to_string(radix=10).length()
  }
}
