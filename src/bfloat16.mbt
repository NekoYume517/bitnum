///|
/// `bfloat16` — the high 16 bits of an IEEE 754 binary32 (PLAN.md §3).
///
/// The reason this file exists as its own module rather than two lines of
/// shifting is that bfloat16 has **two** narrowing conversions with different
/// results, and conflating them is the only real way to get bfloat16 wrong:
///
///   `of_f32_truncate`  drops the low 16 bits, up to 2^-8 relative error
///   `of_f32_round`     rounds to nearest, ties to even, half that error
///
/// They are separate functions with separate names so a caller cannot pick up
/// the wrong one by accident, and the tests assert *both* on values where they
/// differ. Widening (`to_f32`) is exact for every pattern: zero-extend the
/// significand and the value is unchanged.

///|
/// Number of bit patterns — the exhaustive-test domain.
pub let bfloat16_patterns : Int32 = 65536

///|
/// Significand field width.
pub let bfloat16_sig_bits : Int32 = 7

///|
/// Exponent field width.
pub let bfloat16_exp_bits : Int32 = 8

///|
/// Exponent bias.
pub let bfloat16_bias : Int32 = 127

///|
/// The decoded view of one bfloat16 bit pattern.
#derive(Eq, Debug)
pub(all) struct BFloat16 {
  sign : Int32
  exponent : Int32
  significand : Int32
  kind : FloatClass
}

///|
/// Split a 16-bit pattern into fields. Total on all 65536 inputs.
pub fn BFloat16::decode(bits : UInt16) -> BFloat16 {
  let u = bits.to_uint()
  let sign = ((u >> 15) & 1).to_int()
  let exponent = ((u >> 7) & 0xFF).to_int()
  let significand = (u & 0x7F).to_int()
  let kind = if exponent == 0xFF {
    if significand == 0 {
      Infinity
    } else {
      Nan
    }
  } else if exponent == 0 {
    if significand == 0 {
      Zero
    } else {
      Subnormal
    }
  } else {
    Normal
  }
  BFloat16::{ sign, exponent, significand, kind, }
}

///|
/// Reassemble the pattern from its fields; lossless by construction.
///
/// **Declared precondition for a hand-built struct** (2026-11-21 audit): `sign` is
/// 0 or 1, `exponent` is 0..255, `significand` is 0..127. The fields are public and
/// this function has no `raise` channel: it does not validate and it does not
/// normalise, it ORs the fields and keeps the low 16 bits. `kind` is not read — it is
/// `decode`'s conclusion, not an input. Pinned by `encode_precondition_test.mbt`.
pub fn BFloat16::encode(self : BFloat16) -> UInt16 {
  let u = (self.sign << 15) | (self.exponent << 7) | self.significand
  u.to_uint16()
}

///|
/// Convenience alias for the round-trip.
pub fn BFloat16::bits(self : BFloat16) -> UInt16 {
  self.encode()
}

///|
/// Widen to binary32. Exact for every pattern, including NaN payloads: the
/// significand is zero-extended and nothing is shifted out.
///
/// Safe to call from any backend: a signaling NaN stays *signaling* (`to_f32(0x7F81)`
/// is `0x7F810000` on wasm, wasm-gc and js alike), because the pattern is built by
/// `bfloat16_to_f32_bits` and the bits below bit 16 are never touched by an
/// arithmetic operation. `Binary16::to_f64` on 0.1.20261117 quantized a signaling
/// NaN on the js backend; the same hazard is why this function is written this way
/// (2026-11-30 toolchain 1.0 audit, BN-p).
pub fn BFloat16::to_f32(self : BFloat16) -> Float {
  Float::reinterpret_from_uint(self.to_f32_bits())
}

///|
/// The binary32 bit pattern `self.to_f32()` decodes from.
///
/// For a NaN this is the *only* way to observe the payload: any hop through a
/// `Float` value object is free to quiet the NaN (`is_nan` sees a NaN either way,
/// so nothing catches it).
pub fn BFloat16::to_f32_bits(self : BFloat16) -> UInt32 {
  bfloat16_to_f32_bits(self.encode())
}

///|
/// Widen to binary64 via the exact binary32 value.
pub fn BFloat16::to_f64(self : BFloat16) -> Double {
  self.to_f32().to_double()
}

///|
/// Truncating narrowing from binary32: keep the top 16 bits, discard the rest.
///
/// This is the hardware-cheap conversion and it is **not** the same function as
/// `of_f32_round`. It is exposed separately because some formats (and some
/// accelerators) really do truncate, and a caller that wants truncation should
/// not have to spell it as "round with a special mode" and hope.
///
/// A binary32 NaN truncated this way loses whatever payload lived in the
/// discarded low 16 bits. It stays a NaN because the class test is on the
/// *source* value, not on the truncated pattern: testing the truncated pattern
/// would see `exp_field == 0xFF && sig == 0` for an infinity and for a
/// payload-starved NaN alike, and could not tell them apart.
pub fn of_f32_truncate(f : Float) -> UInt16 {
  of_f32_truncate_pattern(Float::reinterpret_as_uint(f))
}

///|
/// `of_f32_truncate` on a binary32 **bit pattern**, so the input can be a pattern
/// this toolchain cannot carry through a value — a signaling NaN on the js backend
/// is a quiet NaN the moment it is a `Float`, and this entry point is how a test
/// states what truncation does to the pattern itself on every backend
/// (2026-11-30 toolchain 1.0 audit, BN-p).
pub fn of_f32_truncate_pattern(u : UInt32) -> UInt16 {
  let high = (u >> 16) & 0xFFFF
  let exp_field = ((u >> 23) & 0xFF).to_int()
  let mantissa = u & 0x7FFFFF
  if exp_field == 0xFF && mantissa != 0 && (high & 0x7F) == 0 {
    // A NaN whose payload sat entirely in the discarded bits. Truncating would
    // mint an infinity out of a NaN, so force the canonical quiet NaN.
    let sign = (u >> 31) & 1
    ((sign << 15) | 0x7FC0).to_uint16()
  } else {
    high.to_uint16()
  }
}

///|
/// Rounding narrowing from binary32 with an explicit mode.
///
/// Worth naming precisely: binary32's exponent range is *wider* than bfloat16's
/// significand but the same width as its exponent, so only the significand is
/// rounded — except at the two ends, where a binary32 normal can round into a
/// bfloat16 subnormal, and a binary32 value near the top can round to infinity.
/// All three cases go through the same exact integer rounding as binary16.
pub fn of_f32(f : Float, mode : RoundingMode) -> FloatConversion {
  of_f32_pattern(Float::reinterpret_as_uint(f), mode)
}

///|
/// `of_f32` on a binary32 **bit pattern** — the same reason as
/// `of_f32_truncate_pattern`: a quieting conversion is specified on the pattern, and
/// on the js backend a signaling pattern cannot reach it through a `Float` value.
pub fn of_f32_pattern(u : UInt32, mode : RoundingMode) -> FloatConversion {
  let sign = ((u >> 31) & 1).to_int()
  let exp_field = ((u >> 23) & 0xFF).to_int()
  let mantissa = u & 0x7FFFFF

  if exp_field == 0xFF {
    if mantissa == 0 {
      let bits = (sign << 15) | 0x7F80
      return FloatConversion::{ bits: bits.to_uint16(), inexact: false, }
    }
    // NaN: keep the payload bits that fit (6 of them), force the quiet bit.
    // `inexact` is true only when payload information was actually discarded —
    // marking every NaN inexact would make the flag mean "was a NaN" instead of
    // "was lossy", and the vector table distinguishes the two.
    let payload = ((mantissa >> 16) & 0x3F).to_int()
    let dropped = (mantissa & 0xFFFF) != 0
    let bits = (sign << 15) | 0x7FC0 | payload
    return FloatConversion::{ bits: bits.to_uint16(), inexact: dropped, }
  }

  if exp_field == 0 && mantissa == 0 {
    let bits = sign << 15
    return FloatConversion::{ bits: bits.to_uint16(), inexact: false, }
  }

  let (m, e) = if exp_field == 0 {
    (mantissa.to_uint64(), -149)
  } else {
    ((mantissa | 0x800000).to_uint64(), exp_field - 127 - 23)
  }
  let bl = bit_length64(m)
  let p = bl - 1 + e

  if p < -126 {
    // bfloat16 subnormal: quantum is 2^-133.
    let (n, inexact) = round_to_quantum(m, e, -133, mode, sign == 1)
    if n >= 0x80UL {
      let bits = (sign << 15) | 0x0080
      return FloatConversion::{ bits: bits.to_uint16(), inexact, }
    }
    let bits = (sign << 15) | n.to_int()
    return FloatConversion::{ bits: bits.to_uint16(), inexact, }
  }

  let (sig, inexact) = round_to_quantum(m, e, p - 7, mode, sign == 1)
  let mut sig = sig
  let mut exp = p + 127
  if sig >= 0x100UL {
    sig = sig >> 1
    exp = exp + 1
  }
  if exp > 254 {
    let bits = if overflow_to_infinity(mode, sign == 1) {
      (sign << 15) | 0x7F80
    } else {
      (sign << 15) | 0x7F7F
    }
    return FloatConversion::{ bits: bits.to_uint16(), inexact: true, }
  }
  let bits = (sign << 15) | (exp << 7) | (sig.to_int() - 0x80)
  FloatConversion::{ bits: bits.to_uint16(), inexact, }
}

///|
/// `of_f32` specialised to round-to-nearest-ties-to-even, the mode with a
/// dedicated name because it is what numeric libraries mean by "round".
pub fn of_f32_round(f : Float) -> FloatConversion {
  of_f32(f, NearestEven)
}

///|
/// The pattern `BFloat16::to_f32` is specified to produce for one bfloat16
/// pattern — computed **without ever forming a `Float`** (2026-11-30 toolchain
/// 1.0 audit, BN-p).
///
/// This is the definition `to_f32` was always trying to state: sign to bit 31,
/// exponent to bits 30..23, the 7-bit significand to bits 22..16, and zeros below.
///
/// It is spelled out here because the bit-level spelling is *portable* and the
/// arithmetic one is not. Widening is `reinterpret(Float, bits << 16)`, and a
/// bfloat16 signaling NaN widened that way is a signaling NaN in binary32: whether
/// the quiet bit then survives depends on which backend moved the value, because
/// JS has one number type and normalises any NaN it touches to the canonical quiet
/// one. Under `moonc v1.0.0-rc1` the wasm backend answered `0x7F810000` for
/// `to_f32(0x7F81)` and the js backend `0x7FC00000`. THE SAME SPLIT EXISTED ON
/// 0.1.20261117 — it was latent, not introduced by 1.0 — but it is what made
/// bfloat16 the one format whose backend results were not interchangeable, so it
/// is closed here rather than documented as a platform difference.
pub fn bfloat16_to_f32_bits(bits : UInt16) -> UInt32 {
  bits.to_uint() << 16
}

///|
/// The bit pattern a `Float` **is**, for a binary32 bit string, as this toolchain's
/// library reads one back — and the reason that condition has a name.
///
/// `Float::reinterpret_from_uint(p).reinterpret_as_uint()` is the only spelling of
/// "build this pattern, read it back" this toolchain offers, and it is not a bit copy
/// on every backend: the js target keeps no f32, the value goes through a JS number,
/// and a NaN in a JS number is always quiet with its payload squeezed into 7 bits.
/// So the round trip *normalises* a NaN — measured, `0x7F810000` comes back
/// `0x7FC00000` — and leaves every non-NaN pattern alone.
///
/// It does not collapse the two directions, though: a signaling NaN makes the round
/// trip quiet the pattern, but *any* quiet NaN is already its own round trip, so the
/// round trip is the identity on all three backends for patterns without a quiet
/// bit. Everything the library converts — widening results, powers of two — is in
/// that class on wasm, so the round trip is exactly `reinterpret_as_uint` there;
/// on js it is the normalisation the backend performs anyway.
pub fn f32_pattern(f : Float) -> UInt32 {
  Float::reinterpret_from_uint(Float::reinterpret_as_uint(f)).reinterpret_as_uint()
}

///|
/// Whether `f32_pattern` is the identity on this backend's *values* — i.e. whether a
/// `Float` this toolchain gives you back can still be a signaling NaN. True on wasm
/// and wasm-gc (the reinterpret is a load), false on js (there is no f32 to keep it
/// signaling in). The bfloat16 tests use it to assert what the value route is
/// specified to produce per backend; the library itself never branches on it.
pub fn f32_pattern_keeps_signaling(f : Float) -> Bool {
  f32_pattern(f) == Float::reinterpret_as_uint(f)
}

///|
/// Whether the truncating and rounding conversions disagree on this input.
/// Used by the tests to prove the two are genuinely different functions rather
/// than one delegating to the other.
pub fn truncate_round_differ(f : Float) -> Bool {
  let t = of_f32_truncate(f).to_uint()
  let r = of_f32_round(f).bits.to_uint()
  t != r
}
