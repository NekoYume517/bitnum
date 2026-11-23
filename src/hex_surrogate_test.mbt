///|
/// An *unpaired* surrogate is the one string shape `from_hex`'s indexed walk
/// could not answer. `get_char(i)` returns `None` on a lone surrogate — it has
/// no pair to decode with — and the walk used to `unwrap()` that `None`, so the
/// whole process aborted instead of the input being rejected:
///
/// ```
/// Decimal32.from_hex(String::from_array([0xD800.unsafe_to_char(), '0' × 7]))
/// -> Error at Option::unwrap[Char]  (wasm trap / native abort, not a raise)
/// ```
///
/// Such a string can only be built with `Int::unsafe_to_char` — no argv,
/// file, or decoder in this package produces one, and the 2026-11-21 BMP sweep
/// (`hex_scalar_sweep_test.mbt`) proved every *well-formed* string is a clean
/// rejection. But "unreachable from text" is not "cannot be constructed":
/// `from_hex` is `pub` and takes a `String`, and a raise-less abort behind a
/// `raise`-declared signature is a caller's `try` that cannot catch anything.
/// The 2026-11-21 report recorded it as "unreachable but one hard spot" and
/// named the closure: make the walk total the way the CLI's `hex_digit` already
/// is. That is what this file locks (2026-11-23 audit).
///
/// The rejection is the same one every other non-hex character gets —
/// `UnparsableInput(text, "non-hex character")`, with `text` the original
/// string — so no variant is added and the CLI's wording is untouched: a missing
/// character and a non-hex character are the same fact to a hex reader.
test "hex: an unpaired surrogate is a clean rejection, not a panic" {
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  let lone : Array[Int32] = [
    0xD800, // first high surrogate
     0xDBFF, // last high surrogate
     0xDC00, // first low surrogate
     0xDFFF, // last low surrogate
  ]
  for f in formats {
    let width = f.hex_width()
    // Every slot, both ends included: the walk must not depend on where the
    // lone surrogate sits (the 2026-11-17 CLI fix found `hi`/`lo` were evaluated
    // eagerly, so the position of the bad unit mattered there).
    for pos in 0..<width {
      for code in lone {
        let text = surrogate_at(pos, width, code.unsafe_to_char())
        inspect(text.length(), content="\{width}")
        let outcome = try {
          let _ = f.from_hex(text)
          "accepted"
        } catch {
          UnparsableInput(t, why) => {
            inspect(why, content="non-hex character")
            inspect(t == text, content="true")
            "rejected"
          }
          e => "wrong variant: \{e.describe()}"
        }
        inspect(outcome, content="rejected")
      }
    }
  }
}

///|
/// The fix must not have changed what a *well-formed* string does: the exact
/// width still parses, one hex digit off either side is still the width
/// rejection, and an ordinary non-hex character is still the same variant with
/// the same fields. These are the three outcomes `from_hex` had before.
test "hex: a well-formed string keeps its three outcomes after the surrogate fix" {
  let f : DecimalFormat = Decimal32
  inspect(f.from_hex("00000000").compare_int(0), content="0")
  inspect(f.from_hex("7C000001").compare_int(0x7C000001), content="0")
  for text in ["0000000", "000000000"] {
    let outcome = try {
      let _ = f.from_hex(text)
      "accepted"
    } catch {
      TruncatedInput(needed, got) => "width \{needed} vs \{got}"
      e => "wrong variant: \{e.describe()}"
    }
    inspect(outcome, content="width 8 vs \{text.length()}")
  }
  // An astral scalar (a well-formed pair) is still rejected by the pair's *own*
  // high half before the low half is ever indexed — unchanged.
  for text in ["🐛000000", "000000🐛"] {
    let outcome = try {
      let _ = f.from_hex(text)
      "accepted"
    } catch {
      UnparsableInput(_, why) => why
      e => "wrong variant: \{e.describe()}"
    }
    inspect(outcome, content="non-hex character")
  }
}

///|
/// A `width`-code-unit string whose unit at `pos` is `ch` and whose other units
/// are `'0'`. Built from an array so a lone surrogate can be placed; a string
/// literal can never carry one.
fn surrogate_at(pos : Int32, width : Int32, ch : Char) -> String {
  let units = Array::make(width, '0')
  units[pos] = ch
  String::from_array(units)
}
