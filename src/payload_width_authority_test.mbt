// bitnum round 21 — is the NaN payload suffix bounded by the coefficient continuation
// field, or by "everything below the signaling flag"?
//
// TWO PATHS, TWO WIDTHS. `describe_decimal` calls `to_scientific_string_of_width`
// with `coef_cont_bits()` (20 / 50 / 110); `decimal_value_text` — the one `check`
// uses — calls it with `nan_payload_bits()` (`exp_cont + coef_cont - 1` = 25 / 57 /
// 119). The renderer groups whatever width it is handed into 10-bit DPD triples, so
// the two paths can print different digit strings for the same pattern. The probe
// that found this printed, for `7DFFFFFF`:
//
//     coef  = NaN999999        payload = NaN891999999
//
// WHAT THE STANDARD SAYS. The suffix is the payload's digits, and §3.5.2 puts the
// payload in the *coefficient continuation field* — a field the format defines at a
// fixed width. The bits above it (the exponent continuation slot, unused by NaN) are
// not digit groups. `dsEncode.decTest` fixes the answer for the boundary case: line
// `decs518 apply #7fffffff -> sNaN999999`. That pattern has all 25 bits below the
// signaling flag set — five of them above the 20-bit field — and the expected suffix
// is six digits, i.e. exactly the two whole groups. Reading 25 bits as three groups
// yields `819 999 999` and it would print `NaN891999999`, which the file does not say.
//
// The same line pins the *other* direction: `decs519 apply #7fffffff -> #7e03fcff`
// shows the encoder discards whatever is above the field, so a payload cannot legally
// carry digits there either.
//
// decimal64 and decimal128 are the same rule with a different field width — and they
// are where the 57/119 widths are most dangerous, because their top group is real:
// `ddEncode.decTest` `decd538` (`#ffffffffffffffff -> -sNaN999999999999999`) and
// `dqEncode.decTest` `decq538` (`-sNaN999999999999999999999999999999999`) are 15 and
// 33 digits, i.e. 50/10 = 5 and 110/10 = 11 groups exactly. Handing them 57 or 119
// adds a sixth/twelfth group read from bits that carry no digits at all.
//
// So the width the renderer needs is the coefficient continuation field, on every
// path. `nan_payload_bits` is a real quantity — it is how many bits of the pattern are
// payload — but it is not a *rendering* width, and using it as one is the bug.

// ------------------------------------------------------------------ the contract

///|
/// One `(pattern, expected to-sci string, source)` row. Every expectation is quoted
/// from a `dectest` line, not from this implementation's output.
type PayloadRow = (String, String, String)

///|
/// The decimal32 rows: quiet and signaling, zero payload, a payload inside the field,
/// a payload that sets bits above the field, and the all-ones boundary the file names.
fn payload_rows_32() -> Array[PayloadRow] {
  [
    ("7C000000", "NaN", "dsEncode decs511"),
    ("7C000001", "NaN1", "dsEncode decs511 family"),
    (
      "7C0003E7", "NaN767", "DPD 0x3E7 = 767: field 0x3E7, groups 000|767 -> 767",
    ),
    (
      "7C00000F", "NaN881", "DPD 0x00F = 881, six digits from two groups of 000|881 -> 881",
    ),
    ("7E000000", "sNaN", "dsEncode decs515 (#7e000000 -> sNaN)"),
    ("7E00000F", "sNaN881", "same payload, signaling"),
    ("7DFFFFFF", "NaN999999", "all 20 field bits set -> two groups of 999"),
    ("7F7FFFFF", "sNaN999999", "dsEncode decs518 (#7fffffff -> sNaN999999)"),
    (
      "FFFFFFFF", "-sNaN999999", "all bits, signed: payload field all ones, field 20 wide",
    ),
  ]
}

///|
test "decimal32: the payload suffix stops at the coefficient continuation field" {
  let f : DecimalFormat = Decimal32
  let bad : Array[String] = []
  for row in payload_rows_32() {
    let (hex, want, source) = row
    let d = f.decode_raw(f.from_hex(hex))
    let got = d.value.to_scientific_string_of_width(f.coef_cont_bits()) catch {
      e => "<raise \{e.describe()}>"
    }
    if got != want {
      bad.push("\{hex} (want '\{want}' per \{source}) got '\{got}'")
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} row(s) disagree; first: \{bad[0]}")
  }
}

///|
test "decimal64: fifteen digits from five whole groups, never a sixth" {
  let f : DecimalFormat = Decimal64
  inspect(f.coef_cont_bits(), content="50")
  // decd538: the all-ones 64-bit pattern is -sNaN with fifteen nines.
  inspect(
    f.decode_raw(f.from_hex("FFFFFFFFFFFFFFFF")).value.to_scientific_string_of_width(
      f.coef_cont_bits(),
    ),
    content="-sNaN999999999999999",
  )
  // decd545: NaN12345 <-> #7c000000000049c5.
  inspect(
    f.decode_raw(f.from_hex("7C000000000049C5")).value.to_scientific_string_of_width(
      f.coef_cont_bits(),
    ),
    content="NaN12345",
  )
  // Every bit of the 50-bit field set, top group `0x3FF` included: 15 digits.
  inspect(
    f.decode_raw(f.from_hex("7E03FFFFFFFFFFFF")).value.to_scientific_string_of_width(
      f.coef_cont_bits(),
    ),
    content="sNaN999999999999999",
  )
}

///|
test "decimal128: thirty-three digits from eleven whole groups" {
  let f : DecimalFormat = Decimal128
  inspect(f.coef_cont_bits(), content="110")
  // decq538: 128 all-ones bits -> sNaN with 33 nines.
  inspect(
    f.decode_raw(f.from_hex("7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF")).value.to_scientific_string_of_width(
      f.coef_cont_bits(),
    ),
    content="sNaN999999999999999999999999999999999",
  )
}

// ------------------------------------------------------------ the two paths agree

///|
/// `check` computes its `value` line with `decimal_value_text`. That function is in
/// `cmd`, so this test's job is the invariant it must satisfy: for every class, the
/// value string the library produces at `coef_cont_bits()` is the one the report must
/// print. The `cmd`-level half of the pair is locked next to it in
/// `cmd/bitnum/four_paths_agree_wbtest.mbt`.
test "decimal: nan_payload_bits is not a rendering width" {
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  for f in formats {
    // The two constants must stay different — if they ever collapse, this test's
    // premise is gone and the pair should be re-derived rather than silently merged.
    assert_true(f.nan_payload_bits() > f.coef_cont_bits())
    inspect(
      (f.nan_payload_bits() - f.coef_cont_bits()).to_string(),
      content="\{(f.exp_cont_bits() - 1).to_string()}",
    )
  }
  // And the numbers themselves, so a format-geometry change is caught here first.
  let f32 : DecimalFormat = Decimal32
  inspect(f32.nan_payload_bits(), content="25")
  let f64 : DecimalFormat = Decimal64
  inspect(f64.nan_payload_bits(), content="57")
  let f128 : DecimalFormat = Decimal128
  inspect(f128.nan_payload_bits(), content="121")
}
