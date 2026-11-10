///|
/// BN-B2 (2026-11-10 audit, P2): the Infinity family and `check`.
///
/// `check` compares bytes, and the encoder normalises every Infinity to the
/// canonical `11110` combination with a zeroed exponent continuation. That is a
/// deliberate, standard-blessed normalisation — the bits below the combination
/// field carry no value for Infinity, which is exactly why `decode_raw` accepts
/// `0x79`..`0x7B` at all (API.md §6) — but reporting it as a bare `MISMATCH`
/// makes a legal input look like a codec defect.
///
/// The verdict must therefore name the case, while the exit code keeps saying
/// "not byte-identical" (1), because that contract is what a scripted caller
/// keys on and it has not changed.
test "check: the Infinity family is reported as padding, not as a mismatch" {
  let f : @lib.DecimalFormat = @lib.Decimal32
  // The canonical form is a genuine round-trip.
  let canonical = @lib.Decimal::infinity(false)
  inspect(
    classify_decimal_check(
      f.decode_raw(f.from_hex("78000000")),
      f.encode_raw(canonical).compare(f.from_hex("78000000")) == 0,
    )
    is CheckRoundTrip,
    content="true",
  )
  // 0x79 / 0x7A / 0x7B all decode to +Infinity and all re-encode to 0x78.
  for hex in ["79000000", "7A000000", "7B000000"] {
    let raw = f.from_hex(hex)
    let decoded = f.decode_raw(raw)
    inspect(decoded.value.kind.label(), content="infinity")
    let same = f.encode_raw(decoded.value).compare(raw) == 0
    inspect(same, content="false")
    inspect(
      classify_decimal_check(decoded, same) is CheckInfinityPadding,
      content="true",
    )
  }
  // The sign is preserved through the normalisation, so the negative family
  // normalises to F8 rather than to 78.
  let neg = f.from_hex("F9000000")
  inspect(f.to_hex(f.encode_raw(f.decode_raw(neg).value)), content="F8000000")
  // decimal64 and decimal128 behave the same way; the geometry differs, the rule
  // does not.
  let d64 : @lib.DecimalFormat = @lib.Decimal64
  let raw64 = d64.from_hex("7880000000000000")
  let dec64 = d64.decode_raw(raw64)
  inspect(dec64.value.kind.label(), content="infinity")
  inspect(
    classify_decimal_check(
      dec64,
      d64.encode_raw(dec64.value).compare(raw64) == 0,
    )
    is CheckInfinityPadding,
    content="true",
  )
  let d128 : @lib.DecimalFormat = @lib.Decimal128
  let raw128 = d128.from_hex("7B000000000000000000000000000000")
  let dec128 = d128.decode_raw(raw128)
  inspect(
    classify_decimal_check(
      dec128,
      d128.encode_raw(dec128.value).compare(raw128) == 0,
    )
    is CheckInfinityPadding,
    content="true",
  )
}

///|
/// The Infinity exemption must not swallow a real mismatch: every other class
/// keeps the plain MISMATCH verdict, so a future widening of the branch cannot
/// hide a codec bug behind the new wording.
test "check: only Infinity absorbs a byte difference" {
  let f : @lib.DecimalFormat = @lib.Decimal32
  // A finite datum whose bytes do not come back: forced by hand so the
  // classifier is asked the question directly.
  let finite = f.decode_raw(f.from_hex("A23003D0"))
  inspect(finite.value.kind.label(), content="finite")
  inspect(
    classify_decimal_check(finite, false) is CheckMismatch,
    content="true",
  )
  // A NaN payload is part of the pattern and is preserved, so a NaN is never
  // classified as padding.
  let nan = f.decode_raw(f.from_hex("7C000001"))
  inspect(nan.value.kind.label(), content="nan")
  inspect(classify_decimal_check(nan, false) is CheckMismatch, content="true")
  // And the positive case still reads as a round-trip.
  inspect(
    classify_decimal_check(finite, true) is CheckRoundTrip,
    content="true",
  )
}

///|
/// The exit code is part of the contract, not an implementation detail: 1 for the
/// Infinity family, exactly as before the fix. Only the wording changed.
test "check: the Infinity family still exits 1" {
  inspect(cmd_check("decimal32", "79000000") catch { _ => -1 }, content="1")
  inspect(cmd_check("decimal32", "7B000000") catch { _ => -1 }, content="1")
  inspect(cmd_check("decimal32", "78000000") catch { _ => -1 }, content="0")
  inspect(
    cmd_check("decimal64", "7880000000000000") catch {
      _ => -1
    },
    content="1",
  )
  inspect(
    cmd_check("decimal128", "7B000000000000000000000000000000") catch {
      _ => -1
    },
    content="1",
  )
}
