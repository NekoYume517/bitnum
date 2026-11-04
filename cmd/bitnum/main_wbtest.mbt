///|
/// Whitebox on purpose: BN-1 was invisible in the hex output, because an
/// unreadable literal encoded as `0000` and exited 0. A test that only looked at
/// the printed hex would pass both before and after the fix, so these assertions
/// reach the exit code, the stdout/stderr split, and the reader's classification
/// instead.

///|
/// A literal `bits` cannot read is a data error — exit 1, the code the decimal
/// branch already uses for the same class of input — never a quiet `+0`.
test "bits: a malformed literal is a data error, not a silent +0" {
  inspect(cmd_bits("binary16", "xyz") catch { _ => -1 }, content="1")
  inspect(cmd_bits("binary16", "1.2.3") catch { _ => -1 }, content="1")
  inspect(cmd_bits("binary16", "1e") catch { _ => -1 }, content="1")
  inspect(cmd_bits("binary16", "") catch { _ => -1 }, content="1")
  inspect(cmd_bits("bfloat16", "xyz") catch { _ => -1 }, content="1")
  inspect(cmd_bits("bfloat16", "1.2.3") catch { _ => -1 }, content="1")
}

///|
/// A literal that *is* a number but is too large for binary64 follows
/// IEEE 754 §7.4: round-to-nearest overflows to ±infinity, which then encodes as
/// `7C00` / `FC00`. It must not be folded into `+0` along with the syntax errors.
///
/// Exit stays 0 because nothing was rejected — the standard has a defined answer
/// for overflow, and `of_f64` produces it.
test "bits: an out-of-range literal overflows to infinity, not to zero" {
  inspect(cmd_bits("binary16", "1e999") catch { _ => -1 }, content="0")
  inspect(cmd_bits("binary16", "-1e999") catch { _ => -1 }, content="0")
  inspect(cmd_bits("bfloat16", "1e999") catch { _ => -1 }, content="0")
  inspect(cmd_bits("bfloat16", "-1e999") catch { _ => -1 }, content="0")
}

///|
/// The classification that separates "not a number" from "too large", plus the
/// hex the two paths must produce. `1e999` reaching `of_f64` as infinity is the
/// difference between a rejected literal and a correct overflow.
test "bits: reading a literal tells syntax errors from overflow" {
  inspect(read_double_literal("xyz") is LiteralSyntaxError, content="true")
  inspect(read_double_literal("1.2.3") is LiteralSyntaxError, content="true")
  inspect(read_double_literal("") is LiteralSyntaxError, content="true")
  inspect(read_double_literal("0x10") is LiteralSyntaxError, content="true")
  inspect(read_double_literal("1e999") is LiteralOverflow(_), content="true")
  inspect(read_double_literal("-1e999") is LiteralOverflow(_), content="true")
  inspect(read_double_literal("1e309") is LiteralOverflow(_), content="true")
  // Well-formed and in range: read as a plain number.
  inspect(read_double_literal("1.0") is LiteralOk(_), content="true")
  // Underflow is not an error in binary64, so it stays a plain number.
  inspect(read_double_literal("1e-999") is LiteralOk(_), content="true")
}

///|
/// The overflow value keeps the literal's sign, so `-1e999` cannot quietly
/// become positive infinity on its way through the fallback.
test "bits: the overflowed value keeps the literal's sign" {
  match read_double_literal("-1e999") {
    LiteralOverflow(x) => inspect(x < 0.0, content="true")
    _ => inspect("not an overflow", content="LiteralOverflow")
  }
  match read_double_literal("1e999") {
    LiteralOverflow(x) => inspect(x > 0.0, content="true")
    _ => inspect("not an overflow", content="LiteralOverflow")
  }
}

///|
/// The hex and the note, byte for byte. `0.1` keeps reporting `rounded
/// (inexact)` on the same wording as before, so a scripted caller notices no
/// change; the overflow note names the input so `7C00` cannot be mistaken for a
/// faithful conversion of the user's number.
test "bits: binary16 hex and notes" {
  match binary16_bits("1.0") {
    BitsHex(hex, note) => {
      inspect(hex, content="3C00")
      inspect(note, content="")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  match binary16_bits("0.1") {
    BitsHex(hex, note) => {
      inspect(hex, content="2E66")
      inspect(note, content="rounded (inexact)")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  match binary16_bits("1e999") {
    BitsHex(hex, note) => {
      inspect(hex, content="7C00")
      inspect(note.contains("1e999"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  match binary16_bits("-1e999") {
    BitsHex(hex, note) => {
      inspect(hex, content="FC00")
      inspect(note.contains("-1e999"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // 70000 is a fine binary64 but overflows binary16: the rounding note appears
  // and the result is infinity, which is the pre-existing documented behaviour.
  match binary16_bits("70000") {
    BitsHex(hex, note) => {
      inspect(hex, content="7C00")
      inspect(note, content="rounded (inexact)")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // Negative zero keeps its sign (PLAN.md §2).
  match binary16_bits("-0") {
    BitsHex(hex, note) => {
      inspect(hex, content="8000")
      inspect(note, content="")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // A literal exactly at the largest finite binary16 stays exact and silent.
  match binary16_bits("65504") {
    BitsHex(hex, note) => {
      inspect(hex, content="7BFF")
      inspect(note, content="")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
}

///|
/// The rejection text names the input, so a caller piping stderr can tell which
/// argument was wrong (PLAN.md §5: errors carry the numbers needed to locate the
/// rejection).
test "bits: the rejection names the offending literal" {
  match binary16_bits("xyz") {
    BitsRejected(r) => inspect(r.contains("xyz"), content="true")
    BitsHex(_, _) => inspect("not rejected", content="rejected")
  }
  match bfloat16_bits("1.2.3") {
    BitsRejected(r) => inspect(r.contains("1.2.3"), content="true")
    BitsHex(_, _) => inspect("not rejected", content="rejected")
  }
}

///|
/// bfloat16 shares the reader but has its own container: the same overflow lands
/// on `7F80` because bfloat16's exponent field is 8 bits wide.
test "bits: bfloat16 hex and notes" {
  match bfloat16_bits("1.0") {
    BitsHex(hex, note) => {
      inspect(hex, content="3F80")
      inspect(note, content="")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  match bfloat16_bits("1e999") {
    BitsHex(hex, note) => {
      inspect(hex, content="7F80")
      inspect(note.contains("1e999"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  match bfloat16_bits("-1e999") {
    BitsHex(hex, note) => {
      inspect(hex, content="FF80")
      inspect(note.contains("-1e999"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
}

///|
/// The documented special spellings keep working — they are values, not syntax
/// errors, and they must not be routed through the "too large" note.
test "bits: the documented special spellings still convert exactly" {
  match binary16_bits("inf") {
    BitsHex(hex, note) => {
      inspect(hex, content="7C00")
      inspect(note, content="")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  match binary16_bits("-inf") {
    BitsHex(hex, note) => {
      inspect(hex, content="FC00")
      inspect(note, content="")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  match binary16_bits("nan") {
    BitsHex(hex, note) => {
      inspect(hex, content="7E00")
      // binary16 cannot carry binary64's payload, so the conversion is lossy.
      inspect(note, content="rounded (inexact)")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
}
