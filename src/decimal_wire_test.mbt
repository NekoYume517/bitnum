///|
/// Special values, the combination-field edge cases, and every error branch.
///
/// The hex constants here come from the official `dectest` files, not from this
/// implementation — see `scripts/decimal_ref.py` and the quoted line numbers. That
/// matters most for the `#79000000 -> Infinity` family: a decoder that only accepts
/// combination `11110` rejects perfectly legal encodings, and no amount of
/// round-trip testing on finite values would reveal it.

///|
test "decimal wire: Infinity is the whole 11110-leading family, per dectest" {
  // dsEncode.decTest lines 216-224: 0x78, 0x79, 0x7a, 0x7b all decode as Infinity.
  // The standard treats the combination field as Infinity when its top five bits
  // are 11110 *and* the exponent continuation is ignored, so any pattern whose
  // leading six bits are 11110 is Infinity regardless of the exponent bits.
  let f : DecimalFormat = Decimal32
  for hex in ["78000000", "79000000", "7A000000", "7B000000"] {
    let d = f.decode_raw(f.from_hex(hex))
    inspect(d.value.kind.label(), content="infinity")
    inspect(d.value.negative, content="false")
  }
  // And the negative form keeps the sign (dsEncode line 238).
  let neg = f.decode_raw(f.from_hex("F8000000"))
  inspect(neg.value.kind.label(), content="infinity")
  inspect(neg.value.negative, content="true")
  // Encoder canonicalises to 0x78 (dectest line 216).
  inspect(f.to_hex(f.encode_raw(Decimal::infinity(false))), content="78000000")
  inspect(f.to_hex(f.encode_raw(Decimal::infinity(true))), content="F8000000")
}

///|
test "decimal wire: NaN signaling bits follow dectest, not the binary convention" {
  // dsEncode lines 227-235:
  //   #7c000000 -> NaN      (first bit below the combination is 0)
  //   #7d000000 -> NaN
  //   #7e000000 -> sNaN     (first bit below the combination is 1)
  //   #7f7fffff -> sNaN999999
  let f : DecimalFormat = Decimal32
  let quiet = f.decode_raw(f.from_hex("7C000000"))
  inspect(quiet.value.kind.label(), content="nan")
  let quiet2 = f.decode_raw(f.from_hex("7D000000"))
  inspect(quiet2.value.kind.label(), content="nan")
  let signal = f.decode_raw(f.from_hex("7E000000"))
  inspect(signal.value.kind.label(), content="signaling-nan")
  let signal_payload = f.decode_raw(f.from_hex("7F7FFFFF"))
  inspect(signal_payload.value.kind.label(), content="signaling-nan")
  // Encoder: a quiet NaN with no payload is exactly 0x7c000000.
  inspect(
    f.to_hex(f.encode_raw(Decimal::nan(false, BigInt::from_int(0)))),
    content="7C000000",
  )
  let snan = Decimal::{
    negative: false,
    coefficient: BigInt::from_int(0),
    exponent: 0,
    kind: DSignalingNan,
  }
  inspect(f.to_hex(f.encode_raw(snan)), content="7E000000")
}

///|
test "decimal wire: NaN payload round-trips within capacity" {
  let f : DecimalFormat = Decimal32
  // decimal32 reserves 1 bit for the signaling flag out of the 26 bits below the
  // combination, so 25 bits of payload fit.
  inspect(f.nan_payload_bits(), content="25")
  let payload = BigInt::from_string("33554431", radix=10)
  let v = Decimal::nan(false, payload)
  let round = f.decode_raw(f.encode_raw(v)).value
  inspect(round.kind.label(), content="nan")
  inspect(round.coefficient.equal(payload), content="true")
}

///|
test "decimal wire: combination field leading digit 8 and 9 path" {
  // The `11` branch carries digits 8 and 9. A coefficient whose leading digit is 8
  // or 9 must not be confused with Infinity/NaN, and must still decode to itself.
  let f : DecimalFormat = Decimal64
  for coef in ["8", "9", "88", "99", "8999999999999999", "9000000000000001"] {
    let c = BigInt::from_string(coef, radix=10)
    let v = Decimal::{
      negative: false,
      coefficient: c,
      exponent: 0,
      kind: DFinite,
    }
    let hex = f.to_hex(f.encode_raw(v))
    let back = f.decode_raw(f.from_hex(hex))
    inspect(back.value.kind.label(), content="finite")
    inspect(back.value.coefficient.equal(c), content="true")
    inspect(back.value.exponent, content="0")
    inspect(back.redundant_groups, content="0")
  }
}

///|
test "decimal wire: zero keeps its exponent and sign through the wire" {
  // Zero has no leading digit, so the combination field's digit bits are 0 and the
  // exponent is whatever was asked for. Both -0 and the exponent must survive:
  // they are part of the value's identity in this format.
  let f : DecimalFormat = Decimal64
  for exp in [-398, -100, -1, 0, 1, 100, 369] {
    let v = Decimal::zero(false, exp)
    let back = f.decode_raw(f.encode_raw(v)).value
    inspect(back.is_zero(), content="true")
    inspect(back.exponent, content=exp.to_string())
    inspect(back.negative, content="false")
  }
  let nz = f.decode_raw(f.encode_raw(Decimal::zero(true, -3))).value
  inspect(nz.is_zero(), content="true")
  inspect(nz.negative, content="true")
  inspect(nz.exponent, content="-3")
}

///|
test "decimal wire: byte order is big-endian and matches dectest hex" {
  let f : DecimalFormat = Decimal64
  let v = Decimal::make(true, BigInt::from_int(750), -2)
  let bytes = f.encode_bytes(v)
  inspect(bytes.length(), content="8")
  // dectest ddEncode line 50: -7.50 is #A2300000000003D0.
  inspect(bytes[0].to_int(), content="162")
  inspect(bytes[1].to_int(), content="48")
  inspect(bytes[6].to_int(), content="3")
  inspect(bytes[7].to_int(), content="208")
  let back = f.decode_bytes(bytes).value
  inspect(back.negative, content="true")
  inspect(back.coefficient.to_string(), content="750")
  inspect(back.exponent, content="-2")
  inspect(back.to_scientific_string(), content="-7.50")
}

///|
test "decimal wire: short byte input is rejected with both lengths" {
  let f : DecimalFormat = Decimal128
  let r = try {
    let _ = f.decode_bytes(b"\x00\x00\x00")
    "no error"
  } catch {
    TruncatedInput(needed, got) => "needed \{needed}, got \{got}"
    _ => "wrong error variant"
  }
  inspect(r, content="needed 16, got 3")
}

///|
test "decimal wire: oversized coefficient is rejected with digit counts" {
  let f : DecimalFormat = Decimal32
  // 8 digits into a 7-digit format.
  let v = Decimal::{
    negative: false,
    coefficient: BigInt::from_int(12345678),
    exponent: 0,
    kind: DFinite,
  }
  let r = try {
    let _ = f.encode_raw(v)
    "no error"
  } catch {
    CoefficientTooLarge(digits, capacity) => "\{digits} into \{capacity}"
    _ => "wrong error variant"
  }
  inspect(r, content="8 into 7")
}

///|
test "decimal wire: exponent outside the biased range is rejected with bounds" {
  let f : DecimalFormat = Decimal32
  // Emax is 96, so 97 biased to 198 exceeds the legal maximum 197.
  let v = Decimal::{
    negative: false,
    coefficient: BigInt::from_int(1),
    exponent: 97,
    kind: DFinite,
  }
  let r = try {
    let _ = f.encode_raw(v)
    "no error"
  } catch {
    ExponentOutOfRange(value, min, max) => "\{value} in [\{min}, \{max}]"
    _ => "wrong error variant"
  }
  inspect(r, content="198 in [0, 197]")
  // And below: exponent -102 biases to -1.
  let v2 = Decimal::{
    negative: false,
    coefficient: BigInt::from_int(1),
    exponent: -102,
    kind: DFinite,
  }
  let r2 = try {
    let _ = f.encode_raw(v2)
    "no error"
  } catch {
    ExponentOutOfRange(value, min, max) => "\{value} in [\{min}, \{max}]"
    _ => "wrong error variant"
  }
  inspect(r2, content="-1 in [0, 197]")
  // The maximum exponent depends on the digit count, so the endpoint check has to
  // use a coefficient that actually fills the format. dectest pins this down:
  // `0e+10000` clamps to `0E+90` for decimal32, and the largest finite value is
  // `9.999999E+96`, which is coefficient 9999999 at exponent 90 — not at 96.
  // `9999999E+96` would be `9.999999E+102`, past Emax, and must be refused.
  let full = BigInt::from_int(9999999)
  let mut accepted = 0
  for exp in [-101, 90] {
    let _ = try {
      let _ = f.encode_raw(Decimal::{
        negative: false,
        coefficient: full,
        exponent: exp,
        kind: DFinite,
      })
      accepted = accepted + 1
    } catch {
      _ => ()
    }
  }
  inspect(accepted, content="2")
  let too_high = try {
    let _ = f.encode_raw(Decimal::{
      negative: false,
      coefficient: full,
      exponent: 96,
      kind: DFinite,
    })
    "no error"
  } catch {
    ExponentOutOfRange(value, min, max) => "\{value} in [\{min}, \{max}]"
    _ => "wrong error variant"
  }
  inspect(too_high, content="96 in [-101, 90]")
  // With a single digit the ceiling drops to Emax - 6 = 90, so 96 must be refused.
  let narrow = try {
    let _ = f.encode_raw(Decimal::{
      negative: false,
      coefficient: BigInt::from_int(1),
      exponent: 96,
      kind: DFinite,
    })
    "no error"
  } catch {
    ExponentOutOfRange(value, min, max) => "\{value} in [\{min}, \{max}]"
    _ => "wrong error variant"
  }
  inspect(narrow, content="96 in [-101, 90]")
  inspect(f.max_exponent_for(BigInt::from_int(0)), content="90")
  inspect(f.max_exponent_for(full), content="90")
  // A 1-digit coefficient still gets 90: the branch ceiling binds before the
  // adjusted-exponent ceiling does.
  inspect(f.max_exponent_for(BigInt::from_int(1)), content="90")
}

///|
test "decimal wire: NaN payload wider than the container is rejected" {
  let f : DecimalFormat = Decimal32
  let too_big = BigInt::from_int(1) << 25
  let v = Decimal::nan(false, too_big)
  let r = try {
    let _ = f.encode_raw(v)
    "no error"
  } catch {
    NanPayloadTooLarge(width, capacity) =>
      "width \{width}, capacity \{capacity}"
    _ => "wrong error variant"
  }
  inspect(r, content="width 26, capacity 25")
}

///|
test "decimal wire: hex parsing rejects junk and over-wide input" {
  let f : DecimalFormat = Decimal32
  let junk = try {
    let _ = f.from_hex("78ZZ0000")
    "no error"
  } catch {
    InexactConversion(msg) => msg
    _ => "wrong error variant"
  }
  inspect(junk.length() > 0, content="true")
  let wide = try {
    let _ = f.from_hex("7800000000000000")
    "no error"
  } catch {
    TruncatedInput(needed, got) => "\{needed} vs \{got}"
    _ => "wrong error variant"
  }
  inspect(wide, content="8 vs 16")
}

///|
/// BN-2: a hex string of the wrong length is rejected, not right-aligned into
/// the container.
///
/// The defect: `from_hex` only rejected input *wider* than the format, so
/// `A2300000000003D` (15 characters, a dropped trailing digit) was parsed as
/// `0A2300000000003D` and decoded as a completely different number, exit 0. The
/// binary formats already refused this (`binary16` on 3 characters reports
/// "hex input must have an even number of digits"), and `decode_bytes` already
/// refuses a short buffer with `TruncatedInput`, so `from_hex` was the one path
/// that guessed.
///
/// An exact width is required, not "pad with leading zeros": a wire pattern is a
/// byte string, and a short one is a short byte string. Padding would make the
/// typo above silently meaningful, which is the behaviour PLAN.md §1.2 forbids.
test "decimal wire: hex of the wrong length is rejected, not zero-padded" {
  let f64 : DecimalFormat = Decimal64
  let width = f64.hex_width()
  inspect(width, content="16")
  // Short by one: the dropped-digit case from the audit.
  let short = try {
    let _ = f64.from_hex("A2300000000003D")
    "no error"
  } catch {
    TruncatedInput(needed, got) => "\{needed} vs \{got}"
    _ => "wrong error variant"
  }
  inspect(short, content="16 vs 15")
  // Half a container is still wrong, even though it is a whole number of bytes.
  let halved = try {
    let _ = f64.from_hex("A2300000")
    "no error"
  } catch {
    TruncatedInput(needed, got) => "\{needed} vs \{got}"
    _ => "wrong error variant"
  }
  inspect(halved, content="16 vs 8")
  // Empty input is not "zero" either.
  let empty = try {
    let _ = f64.from_hex("")
    "no error"
  } catch {
    TruncatedInput(needed, got) => "\{needed} vs \{got}"
    _ => "wrong error variant"
  }
  inspect(empty, content="16 vs 0")
  // Longer is rejected on the same variant, with the same numbers.
  let long = try {
    let _ = f64.from_hex("A2300000000003D0A")
    "no error"
  } catch {
    TruncatedInput(needed, got) => "\{needed} vs \{got}"
    _ => "wrong error variant"
  }
  inspect(long, content="16 vs 17")
  // The exact width still parses, and to the value the audit's typo was NOT.
  let exact = f64.decode_raw(f64.from_hex("A2300000000003D0"))
  inspect(exact.value.coefficient.to_string(), content="750")
  inspect(exact.value.exponent, content="-2")
  inspect(exact.value.negative, content="true")
}

///|
/// Every format, because the width is per-format and a single-format test could
/// pass while decimal128 stayed permissive.
test "decimal wire: every format requires its own exact hex width" {
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  let widths : Array[Int32] = [8, 16, 32]
  for i in 0..<formats.length() {
    let f = formats[i]
    inspect(f.hex_width(), content=widths[i].to_string())
    // One character short must be rejected in each format.
    let text = String::make(widths[i] - 1, '0')
    let r = try {
      let _ = f.from_hex(text)
      "no error"
    } catch {
      TruncatedInput(needed, got) => "\{needed} vs \{got}"
      _ => "wrong error variant"
    }
    inspect(r, content="\{widths[i]} vs \{widths[i] - 1}")
    // The exact width of zeros is the zero pattern, and must parse.
    let zero = f.from_hex(String::make(widths[i], '0'))
    inspect(zero.compare_int(0), content="0")
  }
}

///|
test "decimal: raw input wider than the format is rejected, not truncated" {
  let f : DecimalFormat = Decimal32
  let too_wide = BigInt::from_int(1) << 32
  let r = try {
    let _ = f.decode_raw(too_wide)
    "no error"
  } catch {
    TruncatedInput(needed, got) => "\{needed} vs \{got}"
    _ => "wrong error variant"
  }
  inspect(r, content="32 vs 33")
}

///|
test "decimal: constructor rejects a negative coefficient" {
  let r = try {
    let _ = Decimal::make(false, BigInt::from_int(-1), 0)
    "no error"
  } catch {
    InexactConversion(msg) => msg
    _ => "wrong error variant"
  }
  inspect(r.length() > 0, content="true")
}

///|
test "decimal: parser rejects what the grammar does not allow" {
  let cases : Array[String] = [
    "", "-", "abc", "1.2.3", "1e", "1e+", "1x", "12 34", "NaN", "Infinity",
  ]
  let mut rejected = 0
  for c in cases {
    let ok = try {
      let _ = parse_decimal(c)
      true
    } catch {
      _ => false
    }
    if not(ok) {
      rejected = rejected + 1
    }
  }
  inspect(rejected, content="10")
}

///|
test "decimal: parser accepts the forms the grammar allows" {
  let a = parse_decimal("1.23")
  inspect(a.coefficient.to_string(), content="123")
  inspect(a.exponent, content="-2")
  let b = parse_decimal("-1.23E+4")
  inspect(b.negative, content="true")
  inspect(b.coefficient.to_string(), content="123")
  inspect(b.exponent, content="2")
  let c = parse_decimal("+0")
  inspect(c.coefficient.to_string(), content="0")
  inspect(c.negative, content="false")
  let d = parse_decimal("-7.50e-7")
  inspect(d.exponent, content="-9")
  inspect(d.to_scientific_string(), content="-7.50E-7")
}

///|
test "decimal: to_scientific_string boundary at adjusted == -6" {
  // The whole rule set turns on this one comparison, so pin both sides of it.
  let a = Decimal::make(false, BigInt::from_int(750), -8)
  inspect(a.adjusted_exponent(), content="-6")
  inspect(a.to_scientific_string(), content="0.00000750")
  let b = Decimal::make(false, BigInt::from_int(750), -9)
  inspect(b.adjusted_exponent(), content="-7")
  inspect(b.to_scientific_string(), content="7.50E-7")
  // Positive exponents always use scientific notation when exponent > 0.
  let c = Decimal::make(false, BigInt::from_int(750), 1)
  inspect(c.to_scientific_string(), content="7.50E+3")
  let d = Decimal::make(false, BigInt::from_int(1234567), 90)
  inspect(d.to_scientific_string(), content="1.234567E+96")
}

///|
test "decimal: numerically_equal ignores padding, not sign or exponent" {
  let a = parse_decimal("1.0")
  let b = parse_decimal("1.00")
  inspect(numerically_equal(a, b), content="true")
  let c = parse_decimal("-1.0")
  inspect(numerically_equal(a, c), content="false")
  let d = parse_decimal("10")
  inspect(numerically_equal(a, d), content="false")
  // Zeros of either sign compare numerically equal but stay distinguishable.
  let z = Decimal::zero(false, 0)
  let nz = Decimal::zero(true, 0)
  inspect(numerically_equal(z, nz), content="true")
  inspect(z.negative == nz.negative, content="false")
}
