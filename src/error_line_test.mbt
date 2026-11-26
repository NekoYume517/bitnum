///|
/// BN-19-1 (CLI side): a rejection line quotes the caller's argument, and it has
/// to stay one line whatever the argument holds.
///
/// The failure this locks out, measured before the fix:
///
/// ```
/// $ bitnum bits decimal64 "1<CR><LF>2"
/// bitnum: cannot parse '1
/// 2': junk after the number
/// exit=1
/// ```
///
/// A reader that looks for `bitnum:` on stderr — or a script that counts lines —
/// sees the caller's data standing in for the tool's verdict. `printable_text`
/// now spells every non-printing unit as `\u{XXXX}`, both here and in the
/// `unknown format` / `not a number` sentences, which share it.
///
/// The assertion is on `BitnumError::describe` (and on the same sentence built by
/// the two `main.mbt` sites that do not go through the variant) rather than on
/// captured stderr, because `println` cannot be captured from a whitebox test.
/// The line count is the part that matters: one sentence, one line.
test "error line: a CRLF inside the argument stays on one line" {
  let cr = (0x000D).unsafe_to_char().to_string()
  let lf = (0x000A).unsafe_to_char().to_string()
  let text = "1" + cr + lf + "2"
  let msg = try {
    let _ = parse_decimal(text[:])
    "accepted"
  } catch {
    e => e.describe()
  }
  inspect(msg.contains(cr), content="false")
  inspect(msg.contains(lf), content="false")
  inspect(
    msg,
    content="cannot parse '1\\u{000D}\\u{000A}2': junk after the number",
  )
  // One sentence, therefore one line: no unit in it can move the cursor.
  let mut lines = 0
  let mut i = 0
  while i < msg.length() {
    match msg.get_char(i) {
      Some(c) => if c.to_int() == 0x0A { lines = lines + 1 }
      None => ()
    }
    i = i + 1
  }
  inspect(lines, content="0")
}

///|
test "error line: a terminal escape inside the argument is spelled, not executed" {
  let esc = (0x001B).unsafe_to_char().to_string()
  let text = "1" + esc + "[31m2"
  let msg = try {
    let _ = parse_decimal(text[:])
    "accepted"
  } catch {
    e => e.describe()
  }
  inspect(msg.contains(esc), content="false")
  inspect(msg.contains("\\u{001B}"), content="true")
}

///|
test "error line: a printable argument is still quoted verbatim" {
  // The repair must not over-escape: a reader has to be able to compare the
  // quoted text with what they typed.
  let msg = try {
    let _ = parse_decimal("1.2")
    "accepted"
  } catch {
    e => e.describe()
  }
  inspect(msg, content="accepted")
  let bad = try {
    let _ = parse_decimal("1.2.3")
    "accepted"
  } catch {
    e => e.describe()
  }
  inspect(bad, content="cannot parse '1.2.3': more than one decimal point")
}
