///|
/// Round-21 guard: `check`'s exit code over the whole Infinity family, and over the
/// NaN family, must follow the contract rather than the padding bits' mood.
///
/// `check`'s contract is byte identity (API.md §6/§7): exit 0 only when the encoder
/// writes back exactly what it read. The Infinity family is the one documented
/// exemption *from the error message*, not from the exit code — API.md says
/// explicitly "`check` 因此给出 `result: infinity family — …` 并**保持退出码 1**".
/// So `0x78` alone round-trips, and every pattern that sets any bit below the
/// combination field round-trips **by value** while failing **by bytes**.
///
/// The NaN family is the opposite shape: its bits below the combination field *are*
/// the payload, `encode_raw` preserves them, so every one of them round-trips byte for
/// byte — including the five bits above decimal32's coefficient field, which carry no
/// digits but are still carried through the encoder (that distinction is what
/// `decs519 apply #7fffffff -> #7e03fcff` shows on the encode side, and this test
/// shows on the decode-and-re-encode side).
///
/// Why a test and not a probe: while sweeping this by hand I read one row's exit code
/// off the wrong line of my own script and briefly took `0x78FFFFFF` for an exit 0.
/// The table below is the same sweep, asserted instead of eyeballed.
test "decimal32: `check` exit codes over the Infinity and NaN families" {
  let f : DecimalFormat = Decimal32
  // The Infinity family: combination `11110`, everything below ignored.
  let inf_padded : Array[String] = [
    "78080000", "78000001", "78100000", "78200000", "78400000", "78800000", "78FFFFFF",
    "79000000", "79FFFFFF", "7A123456", "7BFFFFFF",
  ]
  for hex in inf_padded {
    let raw = f.from_hex(hex)
    let decoded = f.decode_raw(raw)
    inspect(decoded.value.kind.label(), content="infinity")
    let back = f.encode_raw(decoded.value)
    // The encoder canonicalises, so the bytes differ ...
    assert_true(f.to_hex(back) != f.to_hex(raw))
    // ... and the canonical form is the one that round-trips.
    inspect(f.to_hex(back), content="78000000")
  }
  // The canonical pattern itself is the only member that round-trips byte for byte.
  let canonical = f.decode_raw(f.from_hex("78000000"))
  inspect(f.to_hex(f.encode_raw(canonical.value)), content="78000000")
  // The NaN family: payload bits are preserved, including the ones above the field.
  let nan_preserved : Array[String] = [
    "7C000000", "7C000001", "7C0003E7", "7C00000F", "7DFFFFFF", "7F7FFFFF", "7E00000F",
    "FC00000F",
  ]
  for hex in nan_preserved {
    let raw = f.from_hex(hex)
    let decoded = f.decode_raw(raw)
    let back = f.encode_raw(decoded.value)
    inspect(f.to_hex(back), content=hex)
  }
}

///|
/// The same two families in the other two formats, at the patterns the API docs name
/// (decimal64 `7880000000000000`, decimal128 `7880…`): the family is defined by the
/// combination field, so the rule cannot depend on the width.
test "decimal64/128: the Infinity family is canonicalised, the NaN family is preserved" {
  let f64 : DecimalFormat = Decimal64
  let padded64 = f64.decode_raw(f64.from_hex("7880000000000000"))
  inspect(padded64.value.kind.label(), content="infinity")
  inspect(
    f64.to_hex(f64.encode_raw(padded64.value)),
    content="7800000000000000",
  )
  let nan64 = f64.decode_raw(f64.from_hex("7C000000000049C5"))
  inspect(f64.to_hex(f64.encode_raw(nan64.value)), content="7C000000000049C5")

  let f128 : DecimalFormat = Decimal128
  let padded128 = f128.decode_raw(
    f128.from_hex("78800000000000000000000000000000"),
  )
  inspect(padded128.value.kind.label(), content="infinity")
  inspect(
    f128.to_hex(f128.encode_raw(padded128.value)),
    content="78000000000000000000000000000000",
  )
}
