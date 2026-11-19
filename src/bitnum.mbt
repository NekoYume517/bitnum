///|
/// bitnum — exact bit-level codecs for numeric interchange formats.
///
/// The package is organised in four layers with a single-direction dependency:
///
///   binary16 / bfloat16  →  shared float helpers
///   decimal (coefficient, scale)  →  DPD / BID wire encodings
///
/// Every encoder is paired with a decoder. Canonical wire patterns satisfy
/// `decode(encode(x)) == x` *at the byte level*, including sign of zero,
/// subnormals and NaN payloads. Decimal has two documented canonicalisation
/// exceptions: redundant DPD groups and Infinity's ignored bits below the
/// combination field. Those patterns preserve the decoded value, not its bytes.

///|
pub let version : String = "0.1.0"
