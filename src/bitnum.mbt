///|
/// bitnum — exact bit-level codecs for numeric interchange formats.
///
/// The package is organised in four layers with a single-direction dependency:
///
///   binary16 / bfloat16  →  shared float helpers
///   decimal (coefficient, scale)  →  DPD / BID wire encodings
///
/// Every encoder is paired with a decoder and the pair is required to satisfy
/// `decode(encode(x)) == x` *at the byte level*, including sign of zero,
/// subnormals and NaN payloads.

///|
pub let version : String = "0.1.0"
