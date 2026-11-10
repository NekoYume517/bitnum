///|
/// BN-B9 (2026-11-10 audit, P3): lexical rejections were worded as if a rounding
/// had been refused.
///
/// `parse_decimal` reported every grammar failure through `InexactConversion`, whose
/// `describe()` wraps whatever text it is given in "cannot represent … exactly".
/// That prefix is correct for a *semantic* rejection — a value that is understood
/// and does not fit — but it turned syntactically broken text into sentences like:
///
///   bitnum: cannot represent no digits in nan exactly
///   bitnum: cannot represent more than one decimal point: 1.2.3 exactly
///   bitnum: cannot represent sign with no digits: + exactly
///
/// Nothing was rounded, and "no digits in nan" is not a description of a value. The
/// same wrapper reached `from_hex` as "cannot represent non-hex character in 78ZZ0000
/// exactly".
///
/// The fix splits the two kinds: `UnparsableInput(text, why)` for text no parser can
/// read, `InexactConversion` for a value that is understood but does not fit. The
/// assertions below pin both spellings, so a future caller cannot route a lexical
/// failure back through the rounding wording.
test "parse_decimal: a lexical rejection says it could not parse, not that it rounded" {
  let cases : Array[String] = [
    "nan", "NaN", "inf", "Infinity", "-inf", "abc", ".", "+", "1.2.3", "1e", "1e+",
    "1x", "12 34", "",
  ]
  for text in cases {
    let msg = try {
      let _ = parse_decimal(text)
      "no error"
    } catch {
      e => e.describe()
    }
    // The sentence must be about parsing. "cannot represent … exactly" would claim a
    // rounding that never happened.
    inspect(msg.contains("cannot parse"), content="true")
    inspect(msg.contains("cannot represent"), content="false")
    // And it must quote the offending text, so a caller can tell which argument was
    // wrong (PLAN.md §5).
    if text.length() > 0 {
      inspect(msg.contains(text), content="true")
    }
  }
}

///|
/// The old wordings, verbatim, must be gone. Asserting their absence catches a
/// partial revert that only fixes the `nan` case.
test "parse_decimal: the broken sentences are gone" {
  let samples : Array[(String, String)] = [
    ("nan", "no digits in nan"),
    ("1.2.3", "more than one decimal point: 1.2.3"),
    ("+", "sign with no digits: +"),
    ("1e", "sign with no digits: 1e"),
  ]
  for entry in samples {
    let (text, fragment) = entry
    let msg = try {
      let _ = parse_decimal(text)
      ""
    } catch {
      e => e.describe()
    }
    inspect(msg.contains(fragment), content="false")
  }
}

///|
/// A *semantic* rejection keeps the old wording: a negative coefficient is a value
/// the API understands and refuses, not text it cannot read. This keeps the fix from
/// flattening two different diagnoses into one.
test "decimal: a semantic rejection still says it cannot represent exactly" {
  let msg = try {
    let _ = Decimal::make(false, BigInt::from_int(-1), 0)
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(msg.has_prefix("cannot represent"), content="true")
  inspect(msg.contains("exactly"), content="true")
}

///|
/// `from_hex` had the same wrapper on its own lexical failure. A non-hex character
/// means the string could not be read as wire bits at all.
test "from_hex: a non-hex character is a parse failure, not a rounding" {
  let f : DecimalFormat = Decimal32
  let msg = try {
    let _ = f.from_hex("78ZZ0000")
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(msg.contains("cannot parse"), content="true")
  inspect(msg.contains("78ZZ0000"), content="true")
  inspect(msg.contains("cannot represent"), content="false")
}
