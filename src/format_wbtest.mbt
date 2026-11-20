///|
/// `pad_exponent` must pad the exponent whatever its sign.
///
/// `Double::to_string` only needs the padding on the *negative* side today: it
/// switches to scientific notation at `1e21`, so every positive exponent it emits is
/// already two digits (`e+21`, `e+38`). That is exactly why the sign branch could be
/// wrong without anything noticing — `"+21"` is three characters wide, so it slips
/// through the "already two digits" test and prints correctly by accident, while the
/// one-digit positive case would have printed `e+8`. Padding both signs makes the
/// function total and the documented "at least two digits" true of every input.
test "format: pad_exponent pads both signs" {
  inspect(pad_exponent("1e8"), content="1e08")
  inspect(pad_exponent("1e+8"), content="1e+08")
  inspect(pad_exponent("1e-8"), content="1e-08")
  inspect(pad_exponent("1e21"), content="1e21")
  inspect(pad_exponent("1e+21"), content="1e+21")
  inspect(pad_exponent("1.5e-8"), content="1.5e-08")
  inspect(pad_exponent("1.5e+8"), content="1.5e+08")
  inspect(pad_exponent("100000000"), content="100000000")
  // A mantissa's `e` cannot appear in decimal output, and the scan from the right
  // keeps the exponent marker even if it did.
  inspect(pad_exponent("1e-8e+8"), content="1e-8e+08")
}

///|
/// What `pad_exponent` does with input that has no exponent digits at all.
///
/// It has no raise channel and the project's rule is that a helper reports rather
/// than guesses, so the behaviour is "untouched when there is no exponent marker, and
/// a literal `0` where a sign was given but no digits followed". None of these can be
/// produced by `Double::to_string`; they are pinned so the function cannot start
/// rewriting arbitrary strings later without a test noticing.
test "format: pad_exponent leaves non-exponent input alone" {
  // No `e` at all: returned byte for byte.
  inspect(pad_exponent(""), content="")
  inspect(pad_exponent("+"), content="+")
  inspect(pad_exponent("+abc"), content="+abc")
  inspect(pad_exponent("-Infinity"), content="-Infinity")
  // An `e` with no digits after it: the sign (if any) is kept and a `0` is inserted,
  // which is the same rule the padding follows everywhere else.
  inspect(pad_exponent("1e+"), content="1e+0")
  inspect(pad_exponent("1e-"), content="1e-0")
  inspect(pad_exponent("1e"), content="1e0")
}

///|
/// The reachable ends of `format_double`'s exponent handling, pinned so a change in
/// `Double::to_string`'s switch point shows up here rather than in `docs/DEMO.md`.
test "format: format_double pads the reachable single-digit exponent" {
  inspect(format_double(1.0e21), content="1e+21")
  inspect(format_double(1.0e-7), content="1e-07")
  inspect(format_double(1.0e-8), content="1e-08")
  inspect(format_double(-1.0e-8), content="-1e-08")
  inspect(format_double(65504.0), content="65504")
  inspect(format_double(5.960464477539063e-8), content="5.960464477539063e-08")
}
