///|
/// BN-B11 (2026-11-10 audit, P3): the two `bits` paths had different lexical
/// sources and nobody said so.
///
/// `binary16` / `bfloat16` go through core `strconv.parse_double` (plus a handful of
/// special-value spellings the CLI recognises itself), while `decimal32/64/128` go
/// through this package's `parse_decimal`. The two therefore accept different
/// spellings — `1_000` is a number to the first and junk to the second, `NAN` is a
/// value to the first and unparsable to the second — and API.md §9 documented only
/// part of the union, so the real acceptance set was undefined and free to drift.
///
/// This file pins the **actual** acceptance set as measured, one assertion per
/// spelling, so any future change to either lexer shows up as a test diff instead of
/// as a documentation lie. The doc side of the fix is API.md §9's table.
///
/// Nothing here asserts a *desirable* spelling: the point is to record what the code
/// does, not to wish it did something else.
test "bits: the binary-format lexer accepts these spellings" {
  let accepted : Array[(String, String, String)] = [
    // (literal, binary16 hex, bfloat16 hex)
    ("1.0", "3C00", "3F80"),
    ("0", "0000", "0000"),
    ("-0", "8000", "8000"),
    ("+0", "0000", "0000"),
    // Leading `+`, bare fraction, trailing point, leading zeros.
    ("+1.0", "3C00", "3F80"),
    (".5", "3800", "3F00"),
    ("5.", "4500", "40A0"),
    ("+.5", "3800", "3F00"),
    ("-.5", "B800", "BF00"),
    ("00012", "4A00", "4140"),
    // Digit separators are accepted anywhere a digit is, including inside the
    // exponent — that is core's lexer, not ours.
    ("1_000", "63D0", "447A"),
    ("1_0", "4900", "4120"),
    ("1_000.5", "63D1", "447A"),
    ("1_0e1", "5640", "42C8"),
    ("000_1", "3C00", "3F80"),
    // `E` and `e` are interchangeable, with an optional exponent sign.
    ("1E3", "63D0", "447A"),
    ("1e+3", "63D0", "447A"),
    ("1.0e3", "63D0", "447A"),
  ]
  for entry in accepted {
    let (lit, want16, wantb) = entry
    match binary16_bits(lit) {
      BitsHex(hex, _) => inspect(hex, content=want16)
      BitsRejected(r) => inspect("rejected: \{r}", content="accepted")
    }
    match bfloat16_bits(lit) {
      BitsHex(hex, _) => inspect(hex, content=wantb)
      BitsRejected(r) => inspect("rejected: \{r}", content="accepted")
    }
  }
}

///|
/// The special-value spellings, case-insensitively, with optional signs. This is the
/// set the CLI recognises itself, before core's lexer is consulted, so it is the part
/// most likely to drift.
test "bits: the binary-format lexer accepts these special-value spellings" {
  let infinities : Array[String] = [
    "inf", "Inf", "INF", "infinity", "Infinity", "INFINITY", "+inf", "+Infinity",
    "+INFINITY",
  ]
  for lit in infinities {
    match binary16_bits(lit) {
      BitsHex(hex, note) => {
        inspect(hex, content="7C00")
        // An infinity is exact for binary16: no rounding happened, so no note.
        inspect(note, content="")
      }
      BitsRejected(r) => inspect("rejected: \{r}", content="accepted")
    }
    match bfloat16_bits(lit) {
      BitsHex(hex, _) => inspect(hex, content="7F80")
      BitsRejected(r) => inspect("rejected: \{r}", content="accepted")
    }
  }
  let negative : Array[String] = ["-inf", "-Infinity", "-INFINITY"]
  for lit in negative {
    match binary16_bits(lit) {
      BitsHex(hex, _) => inspect(hex, content="FC00")
      BitsRejected(r) => inspect("rejected: \{r}", content="accepted")
    }
    match bfloat16_bits(lit) {
      BitsHex(hex, _) => inspect(hex, content="FF80")
      BitsRejected(r) => inspect("rejected: \{r}", content="accepted")
    }
  }
  // NaNs: accepted with or without a sign, and always the canonical quiet NaN. The
  // sign prefix is lexically accepted but does not produce a *signed* NaN — `-nan` is
  // handed to core's parser, which drops the sign, so this is 0x7E00 and not 0xFE00.
  // Recording that asymmetry is the point of this test.
  let nans : Array[String] = ["nan", "NaN", "NAN", "+nan", "-nan", "-NAN"]
  for lit in nans {
    match binary16_bits(lit) {
      BitsHex(hex, note) => {
        inspect(hex, content="7E00")
        // binary16 cannot carry binary64's payload, so the conversion is lossy.
        inspect(note, content="rounded (inexact)")
      }
      BitsRejected(r) => inspect("rejected: \{r}", content="accepted")
    }
    match bfloat16_bits(lit) {
      BitsHex(hex, note) => {
        inspect(hex, content="7FC0")
        // All six payload bits survive, so nothing is lost.
        inspect(note, content="")
      }
      BitsRejected(r) => inspect("rejected: \{r}", content="accepted")
    }
  }
}

///|
/// The spellings the binary lexer refuses are as much a part of the contract as the
/// ones it accepts: they exit 1 with "not a number", which is what keeps a rejected
/// literal from being confused with a value.
test "bits: the binary-format lexer rejects these spellings" {
  let rejected : Array[String] = [
    // Wrong separators: core accepts `_` between digits, not doubled or dangling.
    "1__0", "_1", "1_", "_",
    // NaN payload spellings are not part of the grammar.
     "nan(123)", "NaN(0x1)", "nan()", "snan", "NaN_",
    // Near-misses of the specials.
     "infi", "nana",
    // Hex, binary, comma groups, whitespace — none of them reach the parser as a
    // number.
     "0x10", "0X10", "0b101", "0x1p3", "1,000", "  1.0", "1.0 ", "1.0e", "--1", ".",
    "e3", "xyz", "1.2.3", "",
  ]
  for lit in rejected {
    match binary16_bits(lit) {
      BitsRejected(msg) => inspect(msg.contains("not a number"), content="true")
      BitsHex(hex, _) => inspect("accepted as \{hex}", content="rejected")
    }
    match bfloat16_bits(lit) {
      BitsRejected(msg) => inspect(msg.contains("not a number"), content="true")
      BitsHex(hex, _) => inspect("accepted as \{hex}", content="rejected")
    }
  }
}

///|
/// The decimal path is a different lexer with a narrower acceptance set, and the
/// contrast is the documentation point: no separators, no special values, everything
/// else the same.
test "bits: the decimal lexer accepts a narrower set than the binary one" {
  // Shared with the binary lexer.
  let both : Array[String] = [".5", "5.", "+1.0", "-0", "00012", "1E3", "1e+3"]
  for lit in both {
    let v = @lib.parse_decimal(lit)
    inspect(v.kind == DFinite, content="true")
  }
  // Binary-only: separators and special values.
  let binary_only : Array[String] = [
    "1_000", "1_0e1", "nan", "NAN", "inf", "Infinity",
  ]
  for lit in binary_only {
    let failed = try {
      let _ = @lib.parse_decimal(lit)
      false
    } catch {
      _ => true
    }
    inspect(failed, content="true")
  }
  // Rejected by both.
  let neither : Array[String] = ["0x10", "1,000", "  1.0", "1.2.3", ""]
  for lit in neither {
    let failed = try {
      let _ = @lib.parse_decimal(lit)
      false
    } catch {
      _ => true
    }
    inspect(failed, content="true")
  }
}
