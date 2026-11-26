///|
/// A rejection message is text for a human, and a `String` can hold code units
/// that are *not characters*: a lone surrogate. `UnparsableInput` quotes the
/// caller's text verbatim, so the message inherited the hole and the runtime's
/// UTF-8 encoder met a sequence it cannot encode:
///
/// ```
/// $ bitnum bits binary16 <lone U+D800>     # wasm backend
/// RuntimeError: unreachable    at moonbit.fprintln
/// $ bitnum bits binary16 <lone U+D800>     # native
/// (the message line is dropped, exit 1)
/// ```
///
/// The error's own field keeps the caller's text verbatim — a caller locating
/// the offending code unit needs it — and the *message* renders each unit that
/// is not a character as U+FFFD, which is what every other tool does with an
/// unpaired unit and what makes the message printable on every backend.
///
/// This is the residual `docs/implementation.md` records as 未修 (2026-11-23):
/// `from_hex` stopped aborting there, but the sentence it raises could not be
/// printed.

///|
/// Number of code units in `text` that do not decode to a character.
fn orphan_units(text : String) -> Int32 {
  let mut i = 0
  let mut holes = 0
  while i < text.length() {
    match text.get_char(i) {
      Some(c) => i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
      None => {
        holes = holes + 1
        i = i + 1
      }
    }
  }
  holes
}

///|
/// `Decimal32.from_hex` on a width-correct string whose slot 1 is `ch`.
fn hex_with_at_one(ch : Char) -> String {
  String::from_array(['0', ch, '0', '0', '0', '0', '0', '0'])
}

///|
test "message: an unparsable input carrying a lone surrogate renders printable text" {
  let f : DecimalFormat = Decimal32
  let lone : Array[Int32] = [0xD800, 0xDBFF, 0xDC00, 0xDFFF]
  for code in lone {
    let ch = code.unsafe_to_char()
    let text = hex_with_at_one(ch)
    inspect(text.length(), content="8")
    inspect(orphan_units(text), content="1")
    let msg = try {
      let _ = f.from_hex(text)
      "accepted"
    } catch {
      e => e.describe()
    }
    // No code unit of the message is left without a character, so printing it
    // cannot trap on any backend.
    inspect(orphan_units(msg), content="0")
    // Exactly the one unit is spelled out; the rest still reads as before.
    // (2026-11 round 19: the spelling is `\u{D800}`, not U+FFFD — the unit is
    // named, so a reader can see *which* unit was rejected instead of only that
    // something was. See `printable_text_test.mbt`.)
    inspect(msg.contains("\u{FFFD}"), content="false")
    let spelled = "\\u{" + code.to_string(radix=16).to_upper() + "}"
    inspect(msg.contains(spelled), content="true")
    inspect(msg.contains("cannot parse '0"), content="true")
    inspect(msg.contains("0': non-hex character"), content="true")
    // The error's field is untouched: a caller can still find the unit.
    let field = try {
      let _ = f.from_hex(text)
      "accepted"
    } catch {
      UnparsableInput(t, _) => if t == text { "verbatim" } else { "rewritten" }
      _ => "wrong variant"
    }
    inspect(field, content="verbatim")
  }
  // Well-formed text is quoted unchanged, astral characters included: an
  // emoji is a character, and rendering it as U+FFFD would be a lie about it.
  let ok = String::from_array(['0', '0', 'a', '🐛', 'b', '0', '0'])
  inspect(ok.length(), content="8")
  inspect(orphan_units(ok), content="0")
  let ok_msg = try {
    let _ = f.from_hex(ok)
    "accepted"
  } catch {
    e => e.describe()
  }
  inspect(ok_msg.contains("'00a🐛b00'"), content="true")
  inspect(ok_msg.contains("\u{FFFD}"), content="false")
  // A variant that never carries text renders unchanged.
  let short = try {
    let _ = f.from_hex("00")
    "accepted"
  } catch {
    e => e.describe()
  }
  inspect(short, content="needed 8, got 2")
}
