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
  UnbiasedExponentOutOfRange(Int64, Int64, Int64)
  /// Source and target of a conversion that cannot be represented.
  InexactConversion(String)
  /// `needed` bytes required, `got` bytes supplied.
  TruncatedInput(Int32, Int32)
  /// Payload width `width` requested, container holds `capacity`.
  NanPayloadTooLarge(Int32, Int32)
  /// A decimal digit buffer whose length is not a multiple of three, which no
  /// DPD continuation field can hold.
  DpdDigitGroupMisaligned(Int32)
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
    TruncatedInput(needed, got) => "need \{needed} bytes, got \{got}"
    NanPayloadTooLarge(width, capacity) =>
      "NaN payload needs \{width} bits, container holds \{capacity}"
    DpdDigitGroupMisaligned(len) =>
      "digit buffer length \{len} is not a multiple of 3"
  }
}
