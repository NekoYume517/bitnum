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
/// `2^k` as a Double, built by exact repeated doubling so the result is exact
/// for every `k` in the binary64 normal range. `@math.pow` is not used: libm
/// `pow` is only accurate to within an ulp, which is not good enough to claim
/// exactness for the 65536-value binary16 table.
pub fn pow2_exact(k : Int32) -> Double {
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
/// Bits `[offset, offset + width)` of a BigInt, as a non-negative BigInt.
pub fn big_slice(v : BigInt, offset : Int32, width : Int32) -> BigInt {
  let shifted = v >> offset
  if width >= 0 {
    BigInt::land(shifted, (BigInt::from_int(1) << width) - BigInt::from_int(1))
  } else {
    BigInt::from_int(0)
  }
}

///|
/// `from << width | to` for non-negative BigInts.
pub fn big_splice(from : BigInt, to : BigInt, width : Int32) -> BigInt {
  (from << width) + to
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
