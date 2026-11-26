///|
/// Priority ② (round 21, 2026-11-29): **signal bit × payload beyond the field ×
/// field width**, as a boundary sweep.
///
/// Round 20 covered this only at anchor points. The question it left open is the one
/// behind the defect this round found: the payload's digits come from the
/// *coefficient continuation field*, while the bits between that field and the
/// signaling flag are payload-but-not-digits. This file pins down, for every format,
/// exactly where the field stops and what happens on each side.
///
/// **The widths, from §3.5.2 and the combination-field layout.** A decimal interchange
/// format is `sign(1) + combination(5) + exponent-continuation(ec) + coefficient-
/// continuation(cc)`. For a NaN the combination field is `11111` and the bit right
/// after it is the *signaling* flag, so the payload bits are `ec - 1` (the rest of the
/// exponent-continuation slot) plus `cc` (the coefficient-continuation field):
///
/// | format     | total | ec | cc  | payload bits    | digit groups |
/// |------------|-------|----|-----|-----------------|--------------|
/// | decimal32  | 32    | 6  | 20  | 5 + 20 = 25     | 20/10 = 2    |
/// | decimal64  | 64    | 8  | 50  | 7 + 50 = 57     | 50/10 = 5    |
/// | decimal128 | 128   | 12 | 110 | 11 + 110 = 121  | 110/10 = 11  |
///
/// The three split into two shapes, and that split is the whole subject:
///
///   - **decimal64 / decimal128**: `cc` is a multiple of ten, so every digit group lies
///     inside the field. A payload that sets bits above the field still renders from the
///     field alone — there is no group for them to join.
///   - **decimal32**: `cc = 20` is two groups, but the payload is 25 bits. Five bits sit
///     above the field and belong to no group, so they must not add digits (that is the
///     `NaN891999999` defect class the previous commit fixed).
///
/// The authority for both halves is `dsEncode.decTest`: `decs518 apply #7fffffff ->
/// sNaN999999` sets all 25 payload bits and still prints six digits, and `decs519 apply
/// #7fffffff -> #7e03fcff` shows the encoder dropping the five bits above the field —
/// they carry nothing. `ddEncode decd538` and `dqEncode decq538` give the same rule at
/// 15 and 33 digits for the wider formats.
///
/// **How the patterns are made.** Through `Decimal` + `encode_raw`, not by packing bits
/// by hand: the encoder is the authority on where the signal flag and the field sit, so
/// a hand-rolled layout in a test would be one more place to get it wrong. The sweep
/// then steps the payload across the field boundary group by group — empty, one bit, one
/// group, a bit in the next group, all groups, and all groups with the spare bits above
/// the field also set — in both the quiet and the signaling state.

///|
/// One case: the payload, the spare bits above the field, quiet?, the class, the exact
/// value text, and why.
type SignalCase = (String, Int32, Bool, String, String, String)

///|
/// The payload field width in whole digits for a format: `cc/10 * 3` digits.
fn field_digits(f : DecimalFormat) -> Int32 {
  f.coef_cont_bits() / 10 * 3
}

///|
/// Encode a NaN with the given field payload and spare bits above the field, and return
/// its hex. `spare` is OR'd into the bits between the field and the signal flag.
fn nan_hex_with_spare(
  f : DecimalFormat,
  payload : BigInt,
  spare : Int32,
  quiet : Bool,
) -> String raise {
  // `encode_raw` writes the canonical form (spare bits zero), so the spare bits are
  // applied on top of the encoded pattern — their position is `coef_cont_bits()`.
  let canonical = f.encode_raw(Decimal::{
    negative: false,
    coefficient: payload,
    exponent: 0,
    kind: if quiet {
      DNan
    } else {
      DSignalingNan
    },
  })
  let lifted = canonical | (BigInt::from_int(spare) << f.coef_cont_bits())
  f.to_hex(lifted)
}

///|
test "decimal32: signal bit and payloads crossing the field boundary" {
  let f : DecimalFormat = Decimal32
  let cases : Array[SignalCase] = [
    ("0", 0, true, "nan", "NaN", "quiet, empty field"),
    ("0", 0, false, "signaling-nan", "sNaN", "signaling, empty field"),
    ("1", 0, true, "nan", "NaN1", "quiet, bit 0 of the field"),
    ("1", 0, false, "signaling-nan", "sNaN1", "signaling, bit 0 of the field"),
    ("1023", 0, true, "nan", "NaN999", "quiet, one whole group"),
    ("1023", 0, false, "signaling-nan", "sNaN999", "signaling, one whole group"),
    (
      "1025", 0, true, "nan", "NaN1001", "quiet, bit 0 of each group: groups 001|001 -> 1001",
    ),
    ("1048575", 0, true, "nan", "NaN999999", "quiet, both groups full"),
    ("1048575", 0, false, "signaling-nan", "sNaN999999", "signaling, both full"),
    // The spare five bits, alone and stacked on a full field.
    ("0", 31, true, "nan", "NaN", "quiet, only spare bits set"),
    ("0", 31, false, "signaling-nan", "sNaN", "signaling, only spare bits"),
    ("1048575", 31, true, "nan", "NaN999999", "quiet, full field + spare bits"),
    (
      "1048575", 31, false, "signaling-nan", "sNaN999999", "signaling, full + spare",
    ),
  ]
  let bad : Array[String] = []
  for c in cases {
    let (payload, spare, quiet, want_kind, want_text, why) = c
    let value = BigInt::from_string(payload, radix=10)
    let hex = nan_hex_with_spare(f, value, spare, quiet) catch {
      e => {
        bad.push("\{why}: encode raised (\{e})")
        continue
      }
    }
    let d = f.decode_raw(f.from_hex(hex)) catch {
      e => {
        bad.push("\{why}: decode raised (\{e.describe()})")
        continue
      }
    }
    if d.value.kind.label() != want_kind {
      bad.push("\{why}: kind '\{d.value.kind.label()}' want '\{want_kind}'")
    }
    let got = d.value.to_scientific_string_of_width(f.coef_cont_bits()) catch {
      e => "<raise \{e.describe()}>"
    }
    if got != want_text {
      bad.push("\{why} (\{hex}): '\{got}' want '\{want_text}'")
    }
    // The digit count is the invariant: a non-zero field renders `3 * cc/10` digits at
    // most, and the spare bits never add any.
    if got.length() > want_kind.length() + 1 {
      let digits = got.length() - want_kind.length()
      if digits > field_digits(f) {
        bad.push(
          "\{why} (\{hex}): '\{got}' carries \{digits} digits, field holds only \{field_digits(f)}",
        )
      }
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} row(s) disagree; first: \{bad[0]}")
  }
}

///|
test "decimal64: seven spare payload bits never become a sixth digit group" {
  let f : DecimalFormat = Decimal64
  let all_field = (BigInt::from_int(1) << f.coef_cont_bits()) -
    BigInt::from_int(1)
  let cases : Array[(BigInt, String)] = [
    (BigInt::from_int(0), "empty field"),
    (BigInt::from_int(1), "one bit"),
    (all_field, "every field bit set"),
  ]
  let bad : Array[String] = []
  for shape in cases {
    let (value, why) = shape
    for quiet in [true, false] {
      // spare 0, 1, and every spare bit (7 of them for decimal64).
      for spare in [0, 1, 0x7F] {
        let hex = nan_hex_with_spare(f, value, spare, quiet) catch {
          e => {
            bad.push("\{why}: encode raised (\{e})")
            continue
          }
        }
        let d = f.decode_raw(f.from_hex(hex)) catch {
          e => {
            bad.push("\{why}: decode raised (\{e.describe()})")
            continue
          }
        }
        let prefix = if quiet { "NaN" } else { "sNaN" }
        // The canonical rendering of the same field, which must not depend on `spare`.
        let reference = Decimal::{
          negative: false,
          coefficient: value,
          exponent: 0,
          kind: if quiet {
            DNan
          } else {
            DSignalingNan
          },
        }.to_scientific_string_of_width(f.coef_cont_bits()) catch {
          e => "<raise \{e.describe()}>"
        }
        let got = d.value.to_scientific_string_of_width(f.coef_cont_bits()) catch {
          e => "<raise \{e.describe()}>"
        }
        if got != reference {
          bad.push(
            "\{why}, spare=\{spare}, quiet=\{quiet}: '\{got}' vs '\{reference}'",
          )
        }
        if !got.has_prefix(prefix) {
          bad.push("\{why}, spare=\{spare}: '\{got}' lacks prefix '\{prefix}'")
        }
        if got.length() - prefix.length() > field_digits(f) {
          bad.push(
            "\{why}, spare=\{spare}: '\{got}' exceeds \{field_digits(f)} digits",
          )
        }
      }
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} row(s) disagree; first: \{bad[0]}")
  }
}

///|
test "decimal128: eleven spare payload bits never become a twelfth group" {
  let f : DecimalFormat = Decimal128
  let all_field = (BigInt::from_int(1) << f.coef_cont_bits()) -
    BigInt::from_int(1)
  let cases : Array[(BigInt, String)] = [
    (BigInt::from_int(0), "empty field"),
    (BigInt::from_int(1), "one bit"),
    (all_field, "every field bit set"),
  ]
  let bad : Array[String] = []
  for shape in cases {
    let (value, why) = shape
    for quiet in [true, false] {
      for spare in [0, 1, 0x7FF] {
        let hex = nan_hex_with_spare(f, value, spare, quiet) catch {
          e => {
            bad.push("\{why}: encode raised (\{e})")
            continue
          }
        }
        let d = f.decode_raw(f.from_hex(hex)) catch {
          e => {
            bad.push("\{why}: decode raised (\{e.describe()})")
            continue
          }
        }
        let reference = Decimal::{
          negative: false,
          coefficient: value,
          exponent: 0,
          kind: if quiet {
            DNan
          } else {
            DSignalingNan
          },
        }.to_scientific_string_of_width(f.coef_cont_bits()) catch {
          e => "<raise \{e.describe()}>"
        }
        let got = d.value.to_scientific_string_of_width(f.coef_cont_bits()) catch {
          e => "<raise \{e.describe()}>"
        }
        if got != reference {
          bad.push(
            "\{why}, spare=\{spare}, quiet=\{quiet}: '\{got}' vs '\{reference}'",
          )
        }
        if got.length() - (if quiet { 3 } else { 4 }) > field_digits(f) {
          bad.push(
            "\{why}, spare=\{spare}: '\{got}' exceeds \{field_digits(f)} digits",
          )
        }
      }
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} row(s) disagree; first: \{bad[0]}")
  }
}

///|
/// The geometry table itself, asserted from the format constants rather than copied.
/// If a field width ever changes, this fails before any rendering test does.
test "decimal: payload bits are ec - 1 plus cc, and digit groups come from cc alone" {
  let f32 : DecimalFormat = Decimal32
  let f64 : DecimalFormat = Decimal64
  let f128 : DecimalFormat = Decimal128
  let rows : Array[(DecimalFormat, Int32, Int32, Int32)] = [
    (f32, 32, 6, 20),
    (f64, 64, 8, 50),
    (f128, 128, 12, 110),
  ]
  for row in rows {
    let (f, total, ec, cc) = row
    inspect(f.bits(), content=total.to_string())
    inspect(f.exp_cont_bits(), content=ec.to_string())
    inspect(f.coef_cont_bits(), content=cc.to_string())
    // 1 sign + 5 combination + ec + cc == total.
    inspect((1 + 5 + ec + cc).to_string(), content=total.to_string())
    // nan_payload_bits counts payload-but-not-digits: (ec - 1) + cc.
    inspect((ec - 1 + cc).to_string(), content=f.nan_payload_bits().to_string())
    // Digits come from cc alone: 3 per whole group.
    inspect(field_digits(f).to_string(), content=(cc / 10 * 3).to_string())
  }
}
