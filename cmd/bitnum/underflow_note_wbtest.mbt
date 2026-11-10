///|
/// BN-B10 (2026-11-10 audit, P3): a literal below binary64's range was reported as
/// an exact zero.
///
/// `bits binary16 1e-999` printed `0000`, exit 0, and nothing on stderr — the same
/// output as `bits binary16 0`. But `1e-999` is not zero: it is a nonzero number
/// whose magnitude is below binary64's smallest subnormal (`5e-324`), so the *parse*
/// underflows to zero before any codec sees it. `of_f64` then converts a zero
/// exactly, and the inexact flag — which is where every other note comes from —
/// never has anything to report.
///
/// Compare `bits binary16 1e-320`, which is a legal binary64 subnormal and therefore
/// reaches the codec, which does flag the rounding: `rounded (inexact)`. The gap
/// between those two outputs is the defect: an input that was rounded silently
/// looked exact.
test "bits: a literal below binary64's range says it underflowed" {
  match binary16_bits("1e-999") {
    BitsHex(hex, note) => {
      inspect(hex, content="0000")
      inspect(note.contains("1e-999"), content="true")
      inspect(note.contains("too small for binary64"), content="true")
      inspect(note.contains("inexact"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // The sign survives, exactly as it does on the overflow side.
  match binary16_bits("-1e-999") {
    BitsHex(hex, note) => {
      inspect(hex, content="8000")
      inspect(note.contains("-1e-999"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // bfloat16 shares the reader, so it must report the same condition.
  match bfloat16_bits("1e-999") {
    BitsHex(hex, note) => {
      inspect(hex, content="0000")
      inspect(note.contains("too small for binary64"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
}

///|
/// The new branch must not fire on anything that really is zero. `0`, `0.0`, `-0`,
/// `0e-999` and `+0.000` all denote zero, so their conversion is exact and the note
/// stays silent — otherwise every zero would start claiming an underflow.
test "bits: the underflow note never fires on a zero literal" {
  let zeros : Array[String] = [
    "0", "0.0", "-0", "+0", "0e-999", "+0.000", "0e999",
  ]
  for text in zeros {
    match binary16_bits(text) {
      BitsHex(_, note) => inspect(note, content="")
      BitsRejected(r) => inspect(r, content="unexpected rejection")
    }
  }
  // -0 keeps its sign through the zero path, unchanged by the fix.
  match binary16_bits("-0") {
    BitsHex(hex, _) => inspect(hex, content="8000")
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
}

///|
/// A legal binary64 subnormal still reaches the codec and keeps the ordinary
/// rounding note. The two underflow diagnoses are different — one happened in the
/// parse, one in the codec — and the assertions keep them from being merged.
test "bits: a binary64-representable underflow keeps the ordinary note" {
  match binary16_bits("1e-320") {
    BitsHex(hex, note) => {
      inspect(hex, content="0000")
      inspect(note, content="rounded (inexact)")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // And a value that underflows to a *subnormal* rather than to zero reports only
  // the ordinary note as well.
  match binary16_bits("1e-30") {
    BitsHex(hex, note) => {
      inspect(hex, content="0000")
      inspect(note, content="rounded (inexact)")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
}

///|
/// Exit 0, as on the overflow side: nothing was rejected, the standard has a defined
/// answer for an underflow, and the note is what makes the rounding visible.
test "bits: the underflow keeps exit 0" {
  inspect(cmd_bits("binary16", "1e-999") catch { _ => -1 }, content="0")
  inspect(cmd_bits("binary16", "-1e-999") catch { _ => -1 }, content="0")
  inspect(cmd_bits("bfloat16", "1e-999") catch { _ => -1 }, content="0")
}
