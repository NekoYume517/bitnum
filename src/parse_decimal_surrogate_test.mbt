///|
/// `parse_decimal` walks the string by index and reads each code unit with
/// `get_char(i).unwrap()`. `get_char` answers `None` for a code unit that is
/// *not a character* — a lone surrogate — so the walk aborted the process
/// instead of rejecting the text:
///
/// ```
/// parse_decimal(String::from_array([0xD800.unsafe_to_char()]))
/// -> PanicError / Option::unwrap   (native abort, wasm trap; not a raise)
/// bitnum bits decimal32 <lone U+D800>  -> exit -1073740791, outside 0..2
/// ```
///
/// This is the defect `from_hex` had (2026-11-23, `hex_surrogate_test.mbt`), and
/// it survived that fix because the fix was one entry point deep: the `bits`
/// path never touches `from_hex`. `parse_decimal` is `pub`, takes a
/// `StringView`, and a native `argv` carries a lone surrogate straight through,
/// so the CLI reaches it even though no well-formed text contains one.
///
/// The rejection reuses the existing sentences: a missing character is not a
/// digit, not a sign and not a decimal point, so it reads as junk exactly where
/// any other non-numeric character does.
test "decimal parse: an unpaired surrogate is a clean rejection, not a panic" {
  let lone : Array[Int32] = [
    0xD800, // first high surrogate
     0xDBFF, // last high surrogate
     0xDC00, // first low surrogate
     0xDFFF, // last low surrogate
  ]
  for code in lone {
    let ch = code.unsafe_to_char()
    let cases : Array[(String, String)] = [
      (String::from_array([ch]), "no digits"),
      (String::from_array(['-', ch]), "no digits"),
      (String::from_array([ch, '1']), "no digits"),
      (String::from_array(['1', ch]), "junk after the number"),
      (String::from_array(['1', '.', ch]), "junk after the number"),
      (String::from_array(['1', 'e', ch]), "junk after the exponent"),
      (String::from_array(['1', 'e', '-', ch]), "junk after the exponent"),
      (String::from_array(['1', 'e', '5', ch]), "junk after the exponent"),
    ]
    for case in cases {
      let (text, want) = case
      let outcome = try {
        let _ = parse_decimal(text[:])
        "accepted"
      } catch {
        UnparsableInput(t, why) => {
          // The message must quote the original text, surrogate and all, the way
          // `from_hex`'s does — the caller has to be able to find the unit.
          inspect(t == text, content="true")
          why
        }
        e => "wrong variant: \{e.describe()}"
      }
      inspect(outcome, content=want)
    }
  }
}

///|
/// The sweep `hex_scalar_sweep_test.mbt` does for hex strings, over the decimal
/// grammar: every BMP scalar in the second slot of `1<c>` is either a digit that
/// joins the coefficient, a decimal point, an exponent marker, or the documented
/// junk rejection. Nothing else, and never an abort.
test "decimal parse: every BMP scalar in the middle of a numeral is answered" {
  let mut digits = 0
  let mut points = 0
  let mut markers = 0
  let mut junks = 0
  let mut c = 0
  while c < 0x10000 {
    // Surrogates are not scalars and cannot appear in a decoded string.
    if c < 0xD800 || c > 0xDFFF {
      let ch = c.unsafe_to_char()
      let text = String::from_array(['1', ch])
      let outcome = try {
        let d = parse_decimal(text[:])
        if d.kind != DFinite || d.negative || d.exponent != 0 {
          "wrong value: \{d.to_scientific_string()}"
        } else if ch >= '0' && ch <= '9' {
          if d.coefficient.compare_int(10 + (ch.to_int() - '0'.to_int())) == 0 {
            "digit"
          } else {
            "wrong digit: \{d.coefficient}"
          }
        } else if ch == '.' {
          if d.coefficient.compare_int(1) == 0 {
            "point"
          } else {
            "wrong point: \{d.coefficient}"
          }
        } else {
          "unexpected acceptance: \{d.to_scientific_string()}"
        }
      } catch {
        UnparsableInput(_, why) =>
          if ch == 'e' || ch == 'E' {
            if why == "exponent with no digits" {
              "marker"
            } else {
              "wrong why: \{why}"
            }
          } else if (ch >= '0' && ch <= '9') || ch == '.' {
            "unexpected rejection: \{why}"
          } else if why == "junk after the number" {
            "junk"
          } else {
            "wrong why: \{why}"
          }
        e => "wrong variant: \{e.describe()}"
      }
      match outcome {
        "digit" => digits += 1
        "point" => points += 1
        "marker" => markers += 1
        "junk" => junks += 1
        _ => inspect(outcome, content="digit")
      }
    }
    c += 1
  }
  inspect(digits, content="10")
  inspect(points, content="1")
  inspect(markers, content="2")
  inspect(junks, content="\{0x10000 - 0x800 - 13}")
}

///|
/// The first slot of a numeral: a digit or a sign may start it, a point may
/// start a fractional numeral, everything else is `no digits`. Same totality
/// argument, same reachable set, other end of the string.
test "decimal parse: every BMP scalar in the first slot of a numeral is answered" {
  let mut signs = 0
  let mut points = 0
  let mut no_digits = 0
  let mut c = 0
  while c < 0x10000 {
    if c < 0xD800 || c > 0xDFFF {
      let ch = c.unsafe_to_char()
      let text = String::from_array([ch, '1'])
      let outcome = try {
        let d = parse_decimal(text[:])
        if d.kind != DFinite {
          "wrong kind"
        } else if ch == '.' {
          if d.coefficient.compare_int(1) == 0 && d.exponent == -1 {
            "point"
          } else {
            "wrong point: \{d.to_scientific_string()}"
          }
        } else if ch >= '0' && ch <= '9' {
          if d.coefficient.compare_int(10 * (ch.to_int() - '0'.to_int()) + 1) ==
            0 {
            "sign"
          } else {
            "wrong digit: \{d.coefficient}"
          }
        } else if ch == '-' {
          if d.negative && d.coefficient.compare_int(1) == 0 {
            "sign"
          } else {
            "wrong negative sign: \{d.to_scientific_string()}"
          }
        } else if ch == '+' {
          if not(d.negative) && d.coefficient.compare_int(1) == 0 {
            "sign"
          } else {
            "wrong positive sign: \{d.to_scientific_string()}"
          }
        } else {
          "unexpected acceptance: \{d.to_scientific_string()}"
        }
      } catch {
        UnparsableInput(_, why) =>
          if why == "no digits" {
            "no digits"
          } else {
            "wrong why: \{why}"
          }
        e => "wrong variant: \{e.describe()}"
      }
      match outcome {
        "sign" => signs += 1
        "point" => points += 1
        "no digits" => no_digits += 1
        _ => inspect(outcome, content="sign")
      }
    }
    c += 1
  }
  // 10 digits plus the two signs; the point is counted on its own.
  inspect(signs, content="12")
  inspect(points, content="1")
  inspect(no_digits, content="\{0x10000 - 0x800 - 13}")
}
