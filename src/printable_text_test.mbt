///|
/// BN-19-1: rejection wording quotes the caller's input, and the CLI's rejection
/// sentence must stay one line.
///
/// `printable_text` exists because a `String` can carry code units that are not
/// characters (a lone surrogate has no UTF-8 form, so the wasm backend traps at
/// `fprintln` and the native one drops the line). It repaired exactly that case.
/// Every *other* non-printing unit still went through verbatim, and two of them
/// are worse than a dropped character because the message still prints:
///
/// * `U+000D U+000A` — `bitnum bits decimal64` with an argument holding a CRLF
///   writes `bitnum: cannot parse '1` on one line and `2': junk after the number`
///   on the next. The caller's data becomes a second line of the tool's own
///   output, which is exactly where a scripted reader looks for the verdict.
/// * `U+0001`, `U+001B` — an ESC sequence in an argument repaints the terminal;
///   the message claims to quote the input and instead executes it.
///
/// The rule this test pins: **a rejection is one line, and every invisible unit in
/// the quoted input is spelled `\u{XXXX}`**. Printable non-ASCII is quoted
/// unchanged (an emoji really is a character — `EscapeInvalidUtf8` covers the
/// opposite direction); a lone surrogate is named by its code unit instead of
/// being folded into U+FFFD, so a reader can still see which unit was rejected.

///|
test "rejection wording keeps a multi-line argument on one line" {
  let cr = (0x000D).unsafe_to_char().to_string()
  let lf = (0x000A).unsafe_to_char().to_string()
  let crlf = "1" + cr + lf + "2"
  let shown = printable_text(crlf)
  inspect(shown.contains("\u{000D}"), content="false")
  inspect(shown.contains("\u{000A}"), content="false")
  inspect(shown, content="1\\u{000D}\\u{000A}2")
}

///|
test "rejection wording escapes the control and format categories" {
  // C0 controls other than CR/LF, the ESC that starts a terminal sequence,
  // DEL, the C1 range, a bidi override, a zero-width space, a BOM, and U+FFFD
  // itself (a caller's own replacement character is still not text the reader
  // wrote).
  let cases : Array[(Int32, String)] = [
    (0x0001, "\\u{0001}"),
    (0x0009, "\\u{0009}"),
    (0x001B, "\\u{001B}"),
    (0x007F, "\\u{007F}"),
    (0x0085, "\\u{0085}"),
    (0x202E, "\\u{202E}"),
    (0x200B, "\\u{200B}"),
    (0xFEFF, "\\u{FEFF}"),
    (0xFFFD, "\\u{FFFD}"),
  ]
  for pair in cases {
    let (unit, spelled) = pair
    inspect(printable_text(unit.unsafe_to_char().to_string()), content=spelled)
  }
}

///|
test "rejection wording keeps characters a human can read" {
  for
    text in ["1.23", "a b", "-7.50", "é", "🐛", "中文", "A2300000000003D0"] {
    inspect(printable_text(text), content=text)
  }
}

///|
test "rejection wording names a lone surrogate by its code unit" {
  // A lone surrogate can only be built with `Int::unsafe_to_char`; no literal
  // escape and no argv path can produce one.
  inspect(
    printable_text((0xD800).unsafe_to_char().to_string()),
    content="\\u{D800}",
  )
  inspect(
    printable_text((0xDFFF).unsafe_to_char().to_string()),
    content="\\u{DFFF}",
  )
}

///|
test "rejection wording does not split an astral character" {
  // An astral scalar occupies two code units; the walk must step over the low
  // half instead of reading it as a missing character and emitting U+FFFD.
  let text = "x🐛y"
  inspect(printable_text(text), content=text)
  inspect(printable_text(text).length(), content="4")
}
