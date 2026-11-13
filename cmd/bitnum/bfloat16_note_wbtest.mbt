///|
/// BN-B4 (2026-11-10 audit, P2): bfloat16 lost the inexact note on the
/// binary32-range overflow.
///
/// `bfloat16_convert` narrowed through `Float::from_double(x)` *before* asking the
/// codec anything. `1e39` is a perfectly good binary64 but past binary32's maximum,
/// so the narrowing produced an f32 infinity — and `of_f32` sees an infinity, which
/// it reports as an exact conversion of an infinity. The result was:
///
///   $ bitnum bits bfloat16 1e39
///   7F80
///                                            exit 0, empty stderr
///
/// Meanwhile `1e999` — the same class of input, just further out — takes the
/// binary64 overflow path and gets a full note. API.md §9 asks for one behaviour:
/// a rounded result is reported on stderr.
///
/// The fix compares the magnitude with binary32's largest finite value before the
/// narrowing, so the overflow is diagnosed on the value the user wrote.
test "bits: bfloat16 reports the binary32-range overflow on stderr" {
  match bfloat16_bits("1e39") {
    BitsHex(hex, note) => {
      inspect(hex, content="7F80")
      inspect(note.contains("1e39"), content="true")
      inspect(note.contains("binary32"), content="true")
      inspect(note.contains("inexact"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  match bfloat16_bits("-1e39") {
    BitsHex(hex, note) => {
      inspect(hex, content="FF80")
      inspect(note.contains("-1e39"), content="true")
      inspect(note.contains("binary32"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // 3.5e38 is likewise past binary32's 3.4028235e38 maximum.
  match bfloat16_bits("3.5e38") {
    BitsHex(hex, note) => {
      inspect(hex, content="7F80")
      inspect(note.contains("binary32"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
}

///|
/// The new note must not fire on values binary32 can hold: `3.0e38` narrows
/// fine and overflows only at bfloat16, which is the pre-existing
/// `rounded (inexact)` case. Asserting both keeps the new branch from swallowing
/// the old one.
test "bits: bfloat16 keeps the ordinary rounding note below the binary32 ceiling" {
  match bfloat16_bits("3.0e38") {
    BitsHex(hex, note) => {
      inspect(hex, content="7F62")
      inspect(note, content="rounded (inexact)")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // Exactly at the ceiling and just below it: no note at all for the largest
  // binary32 finite value, because widening it to bfloat16 rounds but the note
  // must still be the ordinary one.
  match bfloat16_bits("1.0") {
    BitsHex(hex, note) => {
      inspect(hex, content="3F80")
      inspect(note, content="")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
}

///|
/// Exit code stays 0: nothing was rejected. IEEE 754 §7.4 has a defined answer for
/// an overflow (round-to-nearest goes to infinity), and the note is what makes it
/// visible — the same contract `1e999` already had.
test "bits: the binary32 overflow keeps exit 0 and only adds a note" {
  inspect(cmd_bits("bfloat16", "1e39") catch { _ => -1 }, content="0")
  inspect(cmd_bits("bfloat16", "-1e39") catch { _ => -1 }, content="0")
  inspect(cmd_bits("bfloat16", "3.5e38") catch { _ => -1 }, content="0")
  // The binary16 path already reported this class correctly; keeping the
  // assertion here documents that the two formats now agree.
  inspect(cmd_bits("binary16", "1e39") catch { _ => -1 }, content="0")
}

///|
/// D3 (2026-11-13 audit, P3): the *underflow* end of the same two-step narrowing
/// was still silent.
///
/// BN-B4 fixed the binary32 **overflow** by looking at what the narrowing actually
/// produced, because `of_f32` sees an f32 infinity and calls it exact. The mirror
/// case was never covered: `Float::from_double(1e-46)` is `0.0`, `of_f32` sees an
/// exact zero, and `bits_note` therefore says nothing at all —
///
///   $ bitnum bits bfloat16 1e-46
///   0000
///   (exit 0, empty stderr)
///
/// which is byte-for-byte the output of `bits bfloat16 0`. `binary16` on the same
/// literal reports `rounded (inexact)`, and API.md §9 promises a note whenever the
/// result was rounded, so the two formats disagree about the same class of input.
/// The literal is nonzero; the zero is a rounding result, and it has to say so.
test "bits: bfloat16 reports the binary32-range underflow on stderr" {
  match bfloat16_bits("1e-46") {
    BitsHex(hex, note) => {
      inspect(hex, content="0000")
      inspect(note.contains("1e-46"), content="true")
      inspect(note.contains("too small for binary32"), content="true")
      inspect(note.contains("inexact"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // The sign survives the narrowing, exactly as on the overflow side.
  match bfloat16_bits("-1e-46") {
    BitsHex(hex, note) => {
      inspect(hex, content="8000")
      inspect(note.contains("-1e-46"), content="true")
      inspect(note.contains("too small for binary32"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // `1e-320` is a legal binary64 subnormal and also below binary32's smallest
  // subnormal, so it takes the same path.
  match bfloat16_bits("1e-320") {
    BitsHex(hex, note) => {
      inspect(hex, content="0000")
      inspect(note.contains("too small for binary32"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // Exit code stays 0: nothing was rejected (IEEE 754 has a defined answer for an
  // underflow), the note is what makes the rounding visible.
  inspect(cmd_bits("bfloat16", "1e-46") catch { _ => -1 }, content="0")
}

///|
/// The new branch must not swallow the two diagnoses around it: a literal that
/// binary32 *can* hold keeps the ordinary `rounded (inexact)` note (the rounding
/// then happened in `of_f32`, which does flag it), and a literal that binary64
/// already collapsed to zero keeps the parse-underflow wording.
test "bits: the binary32 underflow note is confined to the f32-to-zero band" {
  // 1e-42 narrows to an f32 subnormal, so `of_f32` reports the rounding itself.
  match bfloat16_bits("1e-42") {
    BitsHex(hex, note) => {
      inspect(hex, content="0000")
      inspect(note, content="rounded (inexact)")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // Below binary64's range the parse already rounded to zero: that note comes
  // first and names binary64.
  match bfloat16_bits("1e-999") {
    BitsHex(hex, note) => {
      inspect(hex, content="0000")
      inspect(note.contains("too small for binary64"), content="true")
      inspect(note.contains("binary32"), content="false")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // A literal that really is zero stays silent.
  for text in ["0", "-0", "0e-999"] {
    match bfloat16_bits(text) {
      BitsHex(_, note) => inspect(note, content="")
      BitsRejected(r) => inspect(r, content="unexpected rejection")
    }
  }
}

///|
/// The boundary is where round-to-nearest actually turns into an f32 infinity, not
/// where the magnitude passes binary32's largest finite value. `3.4028235e38` is
/// slightly *above* `0x7F7FFFFF` yet still rounds back down to it, so the literals
/// must not be blamed on binary32: the note stays the ordinary
/// `rounded (inexact)` that bfloat16 itself produces (its 8-bit significand does
/// round `0x7F7FFFFF` up to the infinity).
///
/// This is why the detection inspects the narrowed value instead of comparing
/// magnitudes against a constant: a `mag > max` test would wrongly report
/// `binary32` here, and would need an exact 17-digit decimal constant to even be
/// right about the boundary.
test "bits: the binary32 note starts at the f32 infinity, not at max finite" {
  match bfloat16_bits("3.4028235e38") {
    BitsHex(hex, note) => {
      inspect(hex, content="7F80")
      // bfloat16 rounds it to infinity on its own, so the note is the ordinary one.
      inspect(note, content="rounded (inexact)")
      inspect(note.contains("binary32"), content="false")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // A step past the tie between `0x7F7FFFFF` and the overflow threshold becomes an
  // f32 infinity, and *that* is what the binary32 note is for.
  match bfloat16_bits("3.40282356779734e38") {
    BitsHex(hex, note) => {
      inspect(hex, content="7F80")
      inspect(note.contains("binary32"), content="true")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  // Infinities and NaNs are already non-finite, so their conversion is exact and
  // the new note must not fire for them.
  match bfloat16_bits("inf") {
    BitsHex(hex, note) => {
      inspect(hex, content="7F80")
      inspect(note, content="")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
  match bfloat16_bits("nan") {
    BitsHex(hex, note) => {
      inspect(hex, content="7FC0")
      inspect(note.contains("binary32"), content="false")
    }
    BitsRejected(r) => inspect(r, content="unexpected rejection")
  }
}
