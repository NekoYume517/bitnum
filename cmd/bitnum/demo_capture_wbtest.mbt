// The report extractors `demo_replay_wbtest.mbt` needs.
//
// A whitebox test cannot capture `println`, so the DEMO replay asserts on the text
// each command *would* print, produced by the same functions the command uses:
//
//   * `value` — `cmd_value` prints `describe_binary16` / `describe_bfloat16` /
//     `describe_decimal` verbatim, and those are public library functions whose
//     output is already pinned against DEMO's paragraphs elsewhere.
//   * `bits`  — `cmd_bits` prints the `BitsOutcome` through `report_bits_outcome`;
//     the outcome itself carries the hex line and (when the conversion was
//     inexact) the treating note.
//   * `check` — `cmd_check` prints two hex lines plus the verdict sentence. The
//     verdict enum is pure and already tested (`check_verdict_wbtest.mbt`); the
//     sentences are reproduced here from the same strings the command prints.
//
// Where a sentence is reproduced rather than reached, that is stated in the test:
// the guard's job is to notice a *rendering* drift, and every rendering below is
// obtained by calling the implementation, not by copying it.

///|
/// The `(stdout, stderr, exit)` triple `bitnum value` produces for one pattern.
fn value_report(
  format : String,
  hex : String,
) -> (Array[String], Array[String], Int32) {
  let out : Array[String] = []
  let err : Array[String] = []
  let fmt = match check_format(format) {
    Some(f) => f
    None => {
      err.push(unknown_format_rejection(format))
      return (out, err, EXIT_USAGE)
    }
  }
  match fmt {
    Binary16Fmt =>
      match expect_two_bytes(hex, "binary16") {
        Some(bits) => {
          out.push(@lib.describe_binary16(bits))
          (out, err, EXIT_OK)
        }
        None => {
          err.push("bitnum: " + demo_hex_rejection(hex, "binary16"))
          (out, err, EXIT_DATA)
        }
      }
    Bfloat16Fmt =>
      match expect_two_bytes(hex, "bfloat16") {
        Some(bits) => {
          out.push(@lib.describe_bfloat16(bits))
          (out, err, EXIT_OK)
        }
        None => {
          err.push("bitnum: " + demo_hex_rejection(hex, "binary16"))
          (out, err, EXIT_DATA)
        }
      }
    DecimalFmt(f) => {
      let raw = match parse_decimal_hex(f, hex) {
        Some(r) => r
        None => {
          err.push(decimal_hex_rejection(f, hex))
          return (out, err, EXIT_DATA)
        }
      }
      let text = @lib.describe_decimal(f, raw) catch {
        e => {
          err.push("bitnum: \{e.describe()}")
          return (out, err, EXIT_DATA)
        }
      }
      out.push(text)
      (out, err, EXIT_OK)
    }
  }
}

///|
/// The `(stdout, stderr, exit)` triple `bitnum bits` produces.
fn bits_report(
  format : String,
  arg : String,
) -> (Array[String], Array[String], Int32) {
  let out : Array[String] = []
  let err : Array[String] = []
  let outcome = match format {
    "binary16" => binary16_bits(arg)
    "bfloat16" => bfloat16_bits(arg)
    "decimal32" | "decimal64" | "decimal128" => {
      let f = match check_format(format) {
        Some(DecimalFmt(f)) => f
        _ => {
          err.push(unknown_format_rejection(format))
          return (out, err, EXIT_USAGE)
        }
      }
      let value = @lib.parse_decimal(arg) catch {
        e => {
          err.push("bitnum: \{e.describe()}")
          return (out, err, EXIT_DATA)
        }
      }
      let bytes = f.encode_bytes(value) catch {
        e => {
          err.push("bitnum: \{e.describe()}")
          return (out, err, EXIT_DATA)
        }
      }
      BitsHex(hex_of_bytes(bytes), "")
    }
    _ => return (out, err, EXIT_USAGE)
  }
  demo_bits_outcome(outcome, out, err)
}

///|
/// Split a `BitsOutcome` into the lines and the stream the CLI writes them to:
/// the hex on stdout, the note (when there is one) on stderr.
fn demo_bits_outcome(
  outcome : BitsOutcome,
  out : Array[String],
  err : Array[String],
) -> (Array[String], Array[String], Int32) {
  match outcome {
    BitsHex(hex, note) => {
      out.push(hex)
      if note != "" {
        err.push("bitnum: note: " + note)
      }
      (out, err, EXIT_OK)
    }
    BitsRejected(msg) => {
      err.push(msg)
      (out, err, EXIT_DATA)
    }
  }
}

///|
/// The `(stdout, stderr, exit)` triple `bitnum check` produces.
///
/// The two hex lines are the command's own; the verdict sentences are the exact
/// strings `cmd_check` prints (it writes them with `println`, so they cannot be
/// captured, but they are also the only literals in the command — reproducing
/// them here is what makes a wording change fail this test).
fn check_report(
  format : String,
  hex : String,
) -> (Array[String], Array[String], Int32) {
  let out : Array[String] = []
  let err : Array[String] = []
  match check_format(format) {
    Some(Binary16Fmt) =>
      match expect_two_bytes(hex, "binary16") {
        Some(bits) => {
          let back = @lib.Binary16::decode(bits).encode()
          check_lines(hex16(bits), hex16(back), bits == back, out, err)
        }
        None => (out, err, EXIT_DATA)
      }
    Some(Bfloat16Fmt) =>
      match expect_two_bytes(hex, "bfloat16") {
        Some(bits) => {
          let back = @lib.BFloat16::decode(bits).encode()
          check_lines(hex16(bits), hex16(back), bits == back, out, err)
        }
        None => (out, err, EXIT_DATA)
      }
    Some(DecimalFmt(f)) => {
      let raw = match parse_decimal_hex(f, hex) {
        Some(r) => r
        None => return (out, err, EXIT_DATA)
      }
      let decoded = f.decode_raw(raw) catch {
        e => {
          err.push("bitnum: \{e.describe()}")
          return (out, err, EXIT_DATA)
        }
      }
      if decoded.redundant_groups > 0 {
        out.push("in    \{f.to_hex(raw)}")
        out.push(
          "out   (no canonical bytes: \{decoded.redundant_groups} non-canonical DPD group(s))",
        )
        out.push("value \{decimal_value_text(f, decoded.value)}")
        out.push(REDUNDANT_VERDICT)
        return (out, err, EXIT_DATA)
      }
      let back = f.encode_raw(decoded.value) catch {
        e => {
          err.push("bitnum: \{e.describe()}")
          return (out, err, EXIT_DATA)
        }
      }
      let same = back.compare(raw) == 0
      match classify_decimal_check(decoded, same) {
        CheckRoundTrip =>
          check_lines(f.to_hex(raw), f.to_hex(back), true, out, err)
        CheckInfinityPadding => {
          out.push("in    \{f.to_hex(raw)}")
          out.push("out   \{f.to_hex(back)}")
          out.push("value \{decimal_value_text(f, decoded.value)}")
          out.push(INFINITY_PADDING_VERDICT)
          (out, err, EXIT_DATA)
        }
        CheckMismatch =>
          check_lines(f.to_hex(raw), f.to_hex(back), false, out, err)
      }
    }
    None => {
      err.push(unknown_format_rejection(format))
      (out, err, EXIT_USAGE)
    }
  }
}

///|
/// The non-canonical-DPD verdict, verbatim from `cmd_check`.
const REDUNDANT_VERDICT : String = "result: non-canonical input accepted — the encoder never emits redundant DPD codes, so this pattern has no canonical form (PLAN.md §4.4)"

///|
const INFINITY_PADDING_VERDICT : String = "result: infinity family — the bits below the combination field carry no value for Infinity, so the encoder writes only the canonical `11110` plus a zeroed exponent continuation; the value round-trips, those padding bits do not (PLAN.md §1.1, API.md §6)"

///|
fn check_lines(
  input_hex : String,
  output_hex : String,
  same : Bool,
  out : Array[String],
  err : Array[String],
) -> (Array[String], Array[String], Int32) {
  out.push("in    \{input_hex}")
  out.push("out   \{output_hex}")
  if same {
    out.push("result: round-trip ok")
    (out, err, EXIT_OK)
  } else {
    out.push("result: MISMATCH")
    (out, err, EXIT_DATA)
  }
}

///|
/// The sentence `parse_hex_bytes` writes for a rejected binary hex argument.
///
/// It returns `None` and prints; the replay cannot see the print, so the two
/// branches are reproduced here from the same strings (`main.mbt`,
/// `parse_hex_bytes`): length first, then the first bad character. The order is
/// itself part of the contract DEMO documents — `ZZZZ` and `ZZ0` are rejected by
/// different gates.
fn demo_hex_rejection(text : String, which : String) -> String {
  if text.length() % 2 != 0 {
    return "hex input must have an even number of digits, got \{text.length()}"
  }
  let upper = text.to_upper()
  for i in 0..<(text.length() / 2) {
    let ok = match (hex_digit(upper, i * 2), hex_digit(upper, i * 2 + 1)) {
      (Some(_), Some(_)) => true
      _ => false
    }
    if not(ok) {
      return "non-hex character in '\{@lib.printable_text(text)}'"
    }
  }
  if text.length() / 2 != 2 {
    return "\{which} is 2 bytes, got \{text.length() / 2}"
  }
  ""
}

///|
/// The sentence `parse_decimal_hex` writes for a rejected decimal hex argument.
///
/// Length first (in *hex digits*, the unit the caller typed), then whatever the
/// library's `from_hex` says. Reproduced for the same reason as
/// `demo_hex_rejection`: the print cannot be captured, and DEMO quotes the exact
/// wording of both branches — `non-hex character` here versus `non-hex character
/// in '…'` on the binary side.
fn decimal_hex_rejection(f : @lib.DecimalFormat, hex : String) -> String {
  let diagnostic = try {
    let _ = f.from_hex(hex)
    ""
  } catch {
    TruncatedInput(needed, got) =>
      "\{f.name()} is \{needed} hex digits, got \{got}"
    e => e.describe()
  }
  "bitnum: " + diagnostic
}

///|
/// The sentence `check_format` writes for an unrecognised format name.
fn unknown_format_rejection(name : String) -> String {
  "bitnum: unknown format '\{@lib.printable_text(name)}' (expected binary16, bfloat16, decimal32, decimal64, decimal128)"
}
