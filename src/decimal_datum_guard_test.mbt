///|
/// The wire encoder's datum guard is **one** gate, not four.
///
/// `Decimal` is `pub(all)` with four public fields, so a library user can build
/// a datum without going through `Decimal::make` — the same "public hand-built
/// structure is not the same domain as the parser" hole the 2026-11-13 audit
/// opened for copybook. `coefficient` is documented as non-negative (the sign
/// lives in `negative`) and `Decimal::make` enforces it, but `encode_raw` matched
/// on `kind` and only the two NaN branches ran a check: `check_payload` rejects a
/// negative NaN payload. The finite branch trusted `coefficient`, so a negative
/// one was read as two decimal digits (`digit_at` on `'-'` returns -3), fed into
/// the DPD equations, and written out as a plausible but unrelated pattern.
///
/// Reviewing this after the fact: the NaN guard and the constructor guard were
/// the same judgement written twice, and the third place — the wire entry —
/// had neither. That is why the fix is a single `check_datum` at the top of
/// `encode_raw` rather than a fourth copy of the sentence: a kind-specific
/// guard per branch is exactly how this got missed.

///|
fn encode_error_text(f : DecimalFormat, v : Decimal) -> String {
  try {
    let _ = f.encode_raw(v)
    "no error"
  } catch {
    e => e.describe()
  }
}

///|
fn negative_coefficient(kind : DecimalKind) -> Decimal {
  Decimal::{
    negative: false,
    coefficient: BigInt::from_int(-5),
    exponent: 0,
    kind,
  }
}

///|
test "decimal wire: a negative coefficient is rejected on every datum kind" {
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  for f in formats {
    // Finite: the branch that used to write the garbage pattern.
    inspect(
      encode_error_text(f, negative_coefficient(DFinite)),
      content="cannot represent a negative coefficient (the sign lives in `negative`) exactly",
    )
    // Infinity carries no coefficient at all, so a negative one is a datum the
    // caller built wrong; the same gate says so instead of ignoring the field.
    inspect(
      encode_error_text(f, negative_coefficient(DInfinity)),
      content="cannot represent a negative coefficient (the sign lives in `negative`) exactly",
    )
    // NaN / sNaN keep the wording they already had: there the coefficient *is*
    // the diagnostic payload, and "payload" is the noun the wrapper completes.
    let nan_text = "cannot represent a negative NaN payload (payloads are non-negative) exactly"
    inspect(encode_error_text(f, negative_coefficient(DNan)), content=nan_text)
    inspect(
      encode_error_text(f, negative_coefficient(DSignalingNan)),
      content=nan_text,
    )
  }
}

///|
/// The guard must be a gate, not a rewrite: a legal datum still encodes to the
/// same bits it did before, and the payload-width rejection keeps its own
/// variant and its own numbers (the sign check runs first, so the width case
/// must still be reached with a non-negative payload).
test "decimal wire: the datum guard does not disturb legal encodings" {
  let f : DecimalFormat = Decimal64
  inspect(
    f.to_hex(f.encode_raw(Decimal::make(true, BigInt::from_int(750), -2))),
    content="A2300000000003D0",
  )
  inspect(
    f.to_hex(f.encode_raw(Decimal::zero(true, 0))),
    content="A238000000000000",
  )
  inspect(
    f.to_hex(f.encode_raw(Decimal::infinity(false))),
    content="7800000000000000",
  )
  inspect(
    f.to_hex(f.encode_raw(Decimal::nan(false, BigInt::from_int(0)))),
    content="7C00000000000000",
  )
  // Payload too wide is still a *width* complaint, not a sign one.
  let f32 : DecimalFormat = Decimal32
  let too_wide = Decimal::nan(false, BigInt::from_int(1) << 25)
  let text = try {
    let _ = f32.encode_raw(too_wide)
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(text, content="NaN payload needs 26 bits, container holds 25")
}

///|
/// The rendering side reads the same field. `digit_count` counts the `'-'` as a
/// digit and `to_scientific_string` copies it through, so a hand-built negative
/// coefficient does not merely fail to encode — it renders a sign the datum says
/// it does not have. Pinned here so the documented precondition ("coefficient
/// is non-negative") has a witness at the one place a reader will look.
test "decimal: a negative coefficient is a documented precondition of the datum" {
  let v = negative_coefficient(DFinite)
  // 2 digits, not 1: the minus sign is counted.
  inspect(v.digit_count(), content="2")
  // The rendered text disagrees with `negative == false`.
  inspect(v.to_scientific_string(), content="-5")
  inspect(v.negative, content="false")
}
