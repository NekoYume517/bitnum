///|
/// The package's single error type.
///
/// Every variant carries the *numbers needed to reproduce the rejection*: which
/// code, which value, which range. A bare "invalid input" would leave the caller
/// unable to tell a malformed container from a value the container honestly
/// cannot hold, and this package refuses to conflate the two (PLAN.md §1.2).

///|
#derive(Debug)
pub(all) suberror BitnumError {
  /// A DPD code that no 3-digit triple maps to. `code` is the 10-bit value,
  /// `resolved` describes the 8/9 sequence the decoder produced for it.
  DpdRedundantCodeAccepted(UInt32, String)
  /// A combination-field value that is not Infinity/NaN and not a digit prefix.
  CombinationInvalid(UInt32)
  /// `digits` decimal digits wanted, `capacity` available in this format.
  CoefficientTooLarge(Int32, Int32)
  /// `value`, `min`, `max` of the biased exponent slot for this format.
  ///
  /// `Int64` for the same reason as `UnbiasedExponentOutOfRange`: the biased value
  /// is `exponent + bias`, and an exponent that is a legal `Int32` can still make
  /// that sum leave `Int32` — `1e2147483647` wants a biased `2147483748`. Reporting
  /// the wrapped `-2147483548` instead describes a number the caller never wrote
  /// (BN-B3).
  ExponentOutOfRange(Int64, Int64, Int64)
  /// `value`, `min`, `max` of a **true** (unbiased) exponent that the format
  /// cannot carry. Separate from `ExponentOutOfRange` on purpose: the two checks
  /// ask different questions — one bounds the biased field, the other bounds the
  /// mathematical exponent — and sharing one wording made the message
  /// self-contradictory (`biased exponent 96 out of range [-101, 90]`, where 96 is
  /// a true exponent and the bounds are true exponents).
  ///
  /// The fields are `Int64` because the value this reports can legitimately exceed
  /// `Int32`: `parse_decimal` sums a fractional-digit count with an explicit
  /// exponent, and `0.01e-2147483647` wants `-2147483649`. Narrowing the report
  /// back to `Int32` would wrap it into a different, plausible number — exactly
  /// the defect this variant exists to report (BN-B3).
  ///
  /// When the magnitude is too wide even for `Int64` (`1e9999999999999999999`),
  /// the reported value **saturates** to `Int64::MIN` / `Int64::MAX` with the
  /// input's own sign, and the bounds are always the container's
  /// `[-2147483648, 2147483647]`. Saturating is honest about degree ("far past
  /// the container") and never mints a number by wrapping; the alternative —
  /// reporting the scanned prefix — was a weaker assertion that also ruled out
  /// negative lower bounds (2026-11-12 audit, C1).
  UnbiasedExponentOutOfRange(Int64, Int64, Int64)
  /// Source and target of a conversion that cannot be represented exactly — a
  /// *semantic* rejection: the input was understood, and the container is too small.
  InexactConversion(String)
  /// Text that no parser in this package can read at all: a decimal literal the
  /// grammar refuses, or a hex string with a non-hex character.
  ///
  /// Kept apart from `InexactConversion` because the two say different things and a
  /// shared prefix made both wrong (BN-B9). `nan` is not a number that got rounded;
  /// it is text the parser refused, and "cannot represent no digits in nan exactly"
  /// describes neither. The fields are the offending text and *why* it was refused,
  /// so `describe()` owns the whole sentence and no fragment has to be a
  /// grammatical part of one.
  UnparsableInput(String, String)
  /// `needed` units required, `got` units supplied.
  ///
  /// The unit is the **entry point's own count**, not one fixed unit: the two
  /// raisers count different things — `decode_bytes` counts bytes,
  /// `from_hex` counts hex digits (its `needed` is `hex_width()`, its `got`
  /// is `text.length()`). One variant serves both, so the sentence stays
  /// unit-neutral (`needed N, got M`) and each raiser's doc comment owns the
  /// unit; a sentence that named either unit would lie to the other caller —
  /// `from_hex`'s old `need 16 bytes, got 15` described decimal64's 8-byte
  /// container in bytes it never counted (2026-11-23 audit). The CLI
  /// translates the pair at its boundary (`decimal64 is 16 hex digits, got
  /// 15`), and `wire_width_message_test.mbt` builds the byte-count sentence
  /// from the fields for the caller the unit really fits. A bit pattern
  /// wider than its format is a different quantity with its own variant,
  /// `WirePatternTooWide`.
  TruncatedInput(Int32, Int32)
  /// A wire pattern wider than the format: `width` bits supplied, `capacity` bits
  /// the format holds.
  ///
  /// Split out of `TruncatedInput` for the reason BN-B5 split the two exponent
  /// variants: one wording covering two quantities said `need 32 bytes, got 33`
  /// about a **decimal32**, which is four bytes wide. `decode_raw` takes a bit
  /// string, so its report speaks bits (2026-11-17 audit, BN-p).
  WirePatternTooWide(Int32, Int32)
  /// Payload width `width` requested, container holds `capacity`.
  NanPayloadTooLarge(Int32, Int32)
  /// A decimal digit buffer whose length is not a multiple of three, which no
  /// DPD continuation field can hold.
  DpdDigitGroupMisaligned(Int32)
  /// A DPD code outside the ten-bit domain `0..1023`.
  ///
  /// The decode side reads `bits >> 9 .. bits >> 0`, so a wider argument used to be
  /// masked instead of refused: `dpd_decode3(1024)` answered `(0, 0, 0)`, a statement
  /// about 1024's low bits rather than about a DPD code. `code` is the argument as
  /// given, so the report names the number the caller wrote (2026-11-17 audit).
  DpdCodeOutOfRange(Int32)
}

///|
/// `text` with every code unit that is not a character replaced by U+FFFD.
///
/// A message is text for a human, and the runtime encodes it when it is
/// printed. A `String` can hold code units that are not characters — a lone
/// surrogate, whether injected with `unsafe_to_char` or carried in through a
/// native `argv` — and such a sequence has no UTF-8 form: the wasm backend
/// traps at `fprintln`, the native one drops the line, both behind a `raise`
/// signature that promised the caller a catchable error. `from_hex` and
/// `parse_decimal` were made total over those code units on 2026-11-23 and
/// 2026-11-24; this is the third one, the sentence they raise.
///
/// The error's **field** keeps the caller's text verbatim — that is how a caller
/// locates the offending unit — and only the rendering is repaired. U+FFFD is
/// the standard's own answer for "a unit that has no character", and a
/// well-formed astral character (an emoji, a CJK extension ideograph) passes
/// through unchanged: it *is* a character, and calling it broken would be a lie.
pub fn printable_text(text : String) -> String {
  let sb = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    match text.get_char(i) {
      Some(c) => {
        sb.write_char(c)
        // A scalar above the BMP occupies two code units; the walk must step
        // over the low half, which decodes to nothing on its own.
        i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
      }
      None => {
        sb.write_char('\u{FFFD}')
        i = i + 1
      }
    }
  }
  sb.to_string()
}

///|
/// Human-readable description, used by the CLI and by tests that want to assert
/// on the *content* of a rejection rather than merely that it happened.
pub fn BitnumError::describe(self : BitnumError) -> String {
  match self {
    DpdRedundantCodeAccepted(code, resolved) =>
      "DPD code 0x\{code.to_string(radix=16)} is redundant (no canonical 3-digit input): decodes to \{resolved}"
    CombinationInvalid(comb) =>
      "invalid combination field 0x\{comb.to_string(radix=16)}"
    CoefficientTooLarge(digits, capacity) =>
      "coefficient has \{digits} decimal digits, this format holds \{capacity}"
    ExponentOutOfRange(value, min, max) =>
      "biased exponent \{value} out of range [\{min}, \{max}]"
    UnbiasedExponentOutOfRange(value, min, max) =>
      "exponent \{value} out of range [\{min}, \{max}]"
    InexactConversion(what) => "cannot represent \{what} exactly"
    UnparsableInput(text, why) =>
      "cannot parse '\{printable_text(text)}': \{why}"
    TruncatedInput(needed, got) => "needed \{needed}, got \{got}"
    WirePatternTooWide(width, capacity) =>
      "wire pattern needs \{width} bits, this format holds \{capacity}"
    NanPayloadTooLarge(width, capacity) =>
      "NaN payload needs \{width} bits, container holds \{capacity}"
    DpdDigitGroupMisaligned(len) =>
      "digit buffer length \{len} is not a multiple of 3"
    DpdCodeOutOfRange(code) => "DPD code \{code} is not a 10-bit code (0..1023)"
  }
}
