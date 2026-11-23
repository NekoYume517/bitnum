///|
/// Every character a user can put in a hex string is either a hex digit or a clean
/// rejection — never a panic.
///
/// `DecimalFormat::from_hex` calls `get_char(i).unwrap()` on an indexed walk, and
/// `get_char` answers `None` when the index splits a surrogate pair. The safety
/// argument is structural: a well-formed string visits the *high* half of every pair
/// before the low half, and the high half is a non-hex scalar, so the walk raises
/// `UnparsableInput` before it can reach the position where `get_char` answers `None`.
/// `decode_bytes` has the same shape. This test turns that argument into data over the
/// whole BMP — every scalar except the surrogate range, in both the first and the last
/// slot of the width — so a future rewrite that indexed the string differently cannot
/// silently turn the rejection into an abort.
///
/// A string containing an *unpaired* surrogate can only be built with
/// `Int::unsafe_to_char`; no well-formed text contains one, which is what makes
/// this sweep the reachable set. Such a unit makes `get_char` answer `None`, and
/// `from_hex` used to `unwrap()` that — an abort behind a `raise` signature. It
/// is now rejected like any other non-hex character, and
/// `hex_surrogate_test.mbt` locks that for every width, slot, and surrogate end.
test "hex: every BMP scalar in a wire string is a clean rejection, not a panic" {
  let f : DecimalFormat = Decimal32
  let mut valid = 0
  let mut rejected = 0
  let mut c = 0
  while c < 0x10000 {
    // Surrogates are not scalars and cannot appear in a decoded string.
    if c < 0xD800 || c > 0xDFFF {
      let ch = c.unsafe_to_char()
      let first = String::from_array([ch, '0', '0', '0', '0', '0', '0', '0'])
      let last = String::from_array(['0', '0', '0', '0', '0', '0', '0', ch])
      for text in [first, last] {
        let outcome = try {
          let raw = f.from_hex(text)
          if raw.compare_int(0) >= 0 &&
            raw.compare(BigInt::from_int(1) << 32) < 0 {
            "ok"
          } else {
            "out of container"
          }
        } catch {
          UnparsableInput(_, _) => "rejected"
          TruncatedInput(_, _) => "rejected"
          e => "wrong error: \{e.describe()}"
        }
        if outcome == "ok" {
          valid += 1
        } else {
          inspect(outcome, content="rejected")
          rejected += 1
        }
      }
    }
    c += 1
  }
  // The hex digits are exactly the ones that parse: 22 scalars ('0'-'9', 'a'-'f',
  // 'A'-'F') in two positions.
  inspect(valid, content="44")
  inspect(rejected, content="\{2 * (0x10000 - 0x800) - 44}")
}
