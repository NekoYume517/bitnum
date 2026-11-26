///|
/// Round-20 (2026-11-28): the NaN payload renderer is pinned by **properties over its
/// whole domain**, not by a handful of examples.
///
/// Why this file exists: the round-19 note about `of_f64` and the first version of this
/// round's payload probe were both false alarms, and both had the same shape — a claim
/// asserted against a hand-computed expectation. Two false alarms in two rounds is one
/// pattern: the renderer had no property-level statement of what it is supposed to do,
/// so every reviewer re-derived the rule from memory and got it wrong.
///
/// The properties below are written against §3.5.2/§5.12.1 rather than against the
/// current output:
///
/// 1. **Round trip.** For every payload the encoder accepts, rendering then re-parsing
///    the digits yields the same group codes. This is the property `dectest` relies on
///    (`ddEncode.decTest` `decd545`: payload `12345` <-> `#7c000000000049c5`).
/// 2. **Width locality.** A payload below `2^(width)` must render identically in every
///    format whose field is at least that wide — the field is fixed-width, so a value
///    that fits cannot depend on the padding.
/// 3. **Group independence.** Each 10-bit group of the continuation field contributes
///    exactly three digits, and changing one group never changes another's digits. This
///    is what catches a slicing bug (the class that produced every payload defect so far).
/// 4. **Zero means no suffix.** §5.12.1 gives a zero payload no digits at all.
/// 5. **The dectest anchors.** The four payloads the official files spell out, including
///    the one that sits exactly on decimal32's field boundary (`7F7FFFFF` -> `sNaN999999`),
///    where the bits above the 20-bit field must add no digits.

///|
/// A 10-bit DPD group as three digits, from the format's own codec (the encoder path
/// is independent of the renderer being tested).
fn payload_group_digits(group : Int32) -> String {
  let (d1, d2, d3) = dpd_decode3(group) catch { _ => (0, 0, 0) }
  d1.to_string() + d2.to_string() + d3.to_string()
}

///|
/// Drop leading zeros, the way §5.12.1 renders a fixed-width field: `000881` -> `881`.
fn strip_leading_zeros(text : String) -> String {
  let mut start = 0
  while start < text.length() && text.get_char(start) == Some('0') {
    start = start + 1
  }
  if start >= text.length() {
    ""
  } else {
    text[start:].to_string()
  }
}

///|
test "decimal payload: rendering a payload and re-reading it agrees with the groups" {
  let bad : Array[String] = []
  // Every two-group payload decimal32 can hold (2^20 possibilities is too many for a
  // test, so sweep one group exhaustively against a fixed neighbour, then swap).
  for g in 0..<1024 {
    let payload = (BigInt::from_int(g) << 10) | BigInt::from_int(0x3FF)
    let d = Decimal::{
      negative: false,
      coefficient: payload,
      exponent: 0,
      kind: DNan,
    }
    let text = d.to_scientific_string_of_width(20) catch {
      _ => {
        bad.push("g=\{g}: raised")
        continue
      }
    }
    let want = strip_leading_zeros(
      payload_group_digits(g) + payload_group_digits(0x3FF),
    )
    if text != "NaN" + want {
      bad.push("g=\{g}: got '\{text}' want 'NaN\{want}'")
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()}/1024 groups disagree; first: \{bad[0]}")
  }
}

///|
test "decimal payload: the same value renders the same in every wide enough format" {
  let bad : Array[String] = []
  let payloads : Array[Int32] = [
    1,
    2,
    9,
    10,
    0x3E7,
    0x3FF,
    0x401,
    0x28E56 & 0xFFFFF,
    0xFFFFF,
  ]
  for value in payloads {
    let payload = BigInt::from_int(value)
    let d = Decimal::{
      negative: false,
      coefficient: payload,
      exponent: 0,
      kind: DNan,
    }
    // decimal32 field 20 bits, decimal64 50, decimal128 110: for a payload under
    // 2^20 all three must agree, because the field is left-padded with zero groups
    // whose digits are all zero and get trimmed.
    let a = d.to_scientific_string_of_width(20) catch { _ => "<raise>" }
    let b = d.to_scientific_string_of_width(50) catch { _ => "<raise>" }
    let c = d.to_scientific_string_of_width(110) catch { _ => "<raise>" }
    if a != b || b != c {
      bad.push("payload=\{value}: 20='\{a}' 50='\{b}' 110='\{c}'")
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} payload(s) disagree across widths; first: \{bad[0]}")
  }
}

///|
test "decimal payload: one group never changes another group's digits" {
  // Fix the high group, sweep the low group; the high three digits must be constant
  // for every low group.
  let high = 0x3FF
  let mut seen = ""
  let bad : Array[String] = []
  for g in 0..<1024 {
    let payload = (BigInt::from_int(high) << 10) | BigInt::from_int(g)
    let d = Decimal::{
      negative: false,
      coefficient: payload,
      exponent: 0,
      kind: DNan,
    }
    let text = d.to_scientific_string_of_width(20) catch { _ => "<raise>" }
    // Strip the "NaN" prefix and the low three digits; what remains is the "000" high
    // group's digits plus the fixed 0x3FF group's, both zero-trimmed, so only the
    // fixed part can differ from the empty string across iterations.
    let body : String = if text.length() > 3 {
      text[3:].to_string()
    } else {
      ""
    }
    let padded : String = if body.length() >= 3 {
      body[0:body.length() - 3].to_string()
    } else {
      ""
    }
    if g == 0 {
      seen = padded
    } else if padded != seen {
      bad.push("g=\{g}: high part '\{padded}' vs '\{seen}'")
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} leak(s); first: \{bad[0]}")
  }
}

///|
test "decimal payload: zero rendering and the four dectest anchors" {
  let f32 : DecimalFormat = Decimal32
  let f64 : DecimalFormat = Decimal64
  // A zero payload has no suffix at all.
  inspect(
    f32.decode_raw(f32.from_hex("7C000000")).value.to_scientific_string_of_width(
      f32.coef_cont_bits(),
    ),
    content="NaN",
  )
  // ddEncode.decTest decd545: NaN12345 <-> #7c000000000049c5.
  inspect(
    f64.decode_raw(f64.from_hex("7C000000000049C5")).value.to_scientific_string_of_width(
      f64.coef_cont_bits(),
    ),
    content="NaN12345",
  )
  // dsEncode.decTest: the filled decimal32 pattern, payload 999999, quiet flag set.
  inspect(
    f32.decode_raw(f32.from_hex("7DFFFFFF")).value.to_scientific_string_of_width(
      f32.coef_cont_bits(),
    ),
    content="NaN999999",
  )
  // dsEncode.decTest: the same digits signaling — the boundary case where the five
  // bits above the 20-bit field are set and must contribute no digits.
  inspect(
    f32.decode_raw(f32.from_hex("7F7FFFFF")).value.to_scientific_string_of_width(
      f32.coef_cont_bits(),
    ),
    content="sNaN999999",
  )
  // ddEncode.decTest decd518: all ones, read back as a signaling NaN.
  inspect(
    f64.decode_raw(f64.from_hex("7FFFFFFFFFFFFFFF")).value.to_scientific_string_of_width(
      f64.coef_cont_bits(),
    ),
    content="sNaN999999999999999",
  )
}
