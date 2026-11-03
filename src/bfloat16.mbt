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
pub fn BFloat16::to_f32(self : BFloat16) -> Float {
  Float::reinterpret_from_uint(self.encode().to_uint() << 16)
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
  let u = f.reinterpret_as_uint()
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
  let u = f.reinterpret_as_uint()
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
/// Whether the truncating and rounding conversions disagree on this input.
/// Used by the tests to prove the two are genuinely different functions rather
/// than one delegating to the other.
pub fn truncate_round_differ(f : Float) -> Bool {
  let t = of_f32_truncate(f).to_uint()
  let r = of_f32_round(f).bits.to_uint()
  t != r
}
