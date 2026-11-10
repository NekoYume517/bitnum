///|
/// BN-B6 (2026-11-10 audit, P3): the `--help` examples named formats that do not
/// exist on the command line.
///
/// Three of the four examples read `@lib.Decimal64` / `@lib.Decimal32` — the
/// *library's* type names in MoonBit source spelling — while `check_format` accepts
/// only `decimal32, decimal64, decimal128`. Copied verbatim, the examples exit 2 with
/// "unknown format". A help text is the one place a user is guaranteed to copy from,
/// so an example that cannot run is a defect even though no code path is wrong.
///
/// The assertion is on the example lines rather than on the whole text, so the prose
/// above them stays free to change.
test "help: every example names a format the parser accepts" {
  let text = usage_text()
  // No MoonBit package qualification belongs in a shell example.
  inspect(text.contains("@lib."), content="false")
  // Each format named in the `formats:` line must be one `check_format` accepts,
  // and conversely.
  let declared = [
    "binary16", "bfloat16", "decimal32", "decimal64", "decimal128",
  ]
  for name in declared {
    inspect(check_format(name) is Some(_), content="true")
    inspect(text.contains(name), content="true")
  }
  // And every example line must be runnable: the first argument after the
  // subcommand is always one of the five names. Only the `Examples:` block is
  // scanned — the title line also contains the word `bitnum`, and so do the usage
  // lines, which name `<format>` instead of a format.
  let mut in_examples = false
  let mut examples = 0
  for line in text.split("\n") {
    let l = line.to_owned()
    if l.has_prefix("Examples:") {
      in_examples = true
      continue
    }
    if not(in_examples) {
      continue
    }
    if not(l.has_prefix("  bitnum ")) {
      continue
    }
    // "  bitnum value decimal64 A2300000000003D0" -> words[2] is the format.
    let words = l.split(" ").filter(fn(w) { w.length() > 0 }).collect()
    if words.length() < 3 {
      continue
    }
    let fmt = words[2].to_owned()
    let known = fmt == "binary16" ||
      fmt == "bfloat16" ||
      fmt == "decimal32" ||
      fmt == "decimal64" ||
      fmt == "decimal128"
    if not(known) {
      // Anything else is a broken example; report it by text so the diff is legible.
      inspect(fmt, content="<one of the five format names>")
    }
    examples = examples + 1
  }
  // The examples did not silently disappear.
  inspect(examples, content="4")
}
