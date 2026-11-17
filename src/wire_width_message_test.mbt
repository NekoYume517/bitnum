///|
/// `decode_raw`'s container is a **bit pattern**, and the width it rejects on is a
/// bit width. It used to report that rejection through `TruncatedInput`, whose
/// documented fields are byte counts (`error.mbt`: "`needed` bytes required,
/// `got` bytes supplied") and whose sentence is `need N bytes, got M` — so the
/// library's own wording told a decimal32 caller the format holds **32 bytes**
/// when it holds four, and told decimal128 it holds 128 (2026-11-17 audit, BN-p).
/// The sibling entry points really do count bytes (`decode_bytes`) or hex digits
/// (`from_hex`), which is why one variant served all three; but that is the same
/// "one wording, two quantities" defect BN-B5 removed from the two exponent
/// variants, and the same reason BN-n rejected `TruncatedInput(width, -1)` for a
/// negative pattern: the caller supplied a bit string, so the report has to speak
/// bits.
test "decimal wire: a too-wide pattern is reported in bits, not in bytes" {
  let cases : Array[(DecimalFormat, Int32, String)] = [
    (Decimal32, 33, "wire pattern needs 33 bits, this format holds 32"),
    (Decimal64, 65, "wire pattern needs 65 bits, this format holds 64"),
    (Decimal128, 129, "wire pattern needs 129 bits, this format holds 128"),
  ]
  for entry in cases {
    let (f, bit, want) = entry
    let too_wide = BigInt::from_int(1) << (bit - 1)
    let msg = try {
      let _ = f.decode_raw(too_wide)
      "no error"
    } catch {
      TruncatedInput(needed, got) =>
        "still a byte count: need \{needed} bytes, got \{got}"
      e => e.describe()
    }
    inspect(msg, content=want)
  }
  // The boundary itself stays accepted: `2^bits - 1` is the widest pattern.
  for entry in cases {
    let (f, bit, _) = entry
    let widest = (BigInt::from_int(1) << (bit - 1)) - BigInt::from_int(1)
    inspect(f.decode_raw(widest).value.kind.label(), content="signaling-nan")
  }
  // `decode_bytes` and `from_hex` keep their byte/hex-digit wording: those
  // entries really are counting bytes and hex digits.
  let f32 : DecimalFormat = Decimal32
  let bytes = try {
    let _ = f32.decode_bytes(b"\x00\x00\x00\x00\x00")
    "no error"
  } catch {
    TruncatedInput(needed, got) => "need \{needed} bytes, got \{got}"
    _ => "wrong error variant"
  }
  inspect(bytes, content="need 4 bytes, got 5")
}
