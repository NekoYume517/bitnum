///|
/// The exponent-boundary and over-capacity families are format-generic code
/// paths in `encode_raw`, but until 2026-11-15 they were locked only on
/// decimal32 — the exact "one width proves the family" gap the 2026-11-13
/// audit's lesson warns about. Everything here is expected green: the point is
/// that a future regression in the shared path shows up as a diff on every
/// width, not just the smallest one. Every expected message and hex below was
/// first observed through the CLI probes (audit 2026-11-15,
/// probe-exp-boundaries-d64-d128.log / probe-overcapacity-with-exp.log), then
/// pinned here.

///|
/// decimal64: one past each ceiling is rejected with the same variant and the
/// same direction decimal32 uses; the ceilings themselves encode.
test "decimal wire: the exponent-boundary family holds on decimal64" {
  let f : DecimalFormat = Decimal64
  // One past Emax_top for a narrow coefficient: the true-exponent variant,
  // bounds in true exponents.
  let above = try {
    let _ = f.encode_raw(parse_decimal("1e370"))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(above, content="exponent 370 out of range [-398, 369]")
  // The ceiling itself encodes: biased 767, exp_top 2 — the legal maximum.
  inspect(
    f.to_hex(f.encode_raw(parse_decimal("1e369"))),
    content="43FC000000000001",
  )
  // One below Etiny: the biased slot is what cannot hold it, so the biased
  // variant speaks (check_biased runs first, unchanged since D4).
  let below = try {
    let _ = f.encode_raw(parse_decimal("1e-399"))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(below, content="biased exponent -1 out of range [0, 1023]")
  // Etiny itself is the smallest subnormal and encodes.
  inspect(
    f.to_hex(f.encode_raw(parse_decimal("1e-398"))),
    content="0000000000000001",
  )
  // Zero shares the ceilings: its digit count is 1, so Emax_top binds.
  let zero_above = try {
    let _ = f.encode_raw(parse_decimal("0e370"))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(zero_above, content="exponent 370 out of range [-398, 369]")
  inspect(
    f.to_hex(f.encode_raw(parse_decimal("0e369"))),
    content="43FC000000000000",
  )
  // The largest finite at full precision and one past its ceiling.
  let top = try {
    let _ = f.encode_raw(parse_decimal("9999999999999999e384"))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(top, content="exponent 384 out of range [-398, 369]")
  inspect(
    f.to_hex(f.encode_raw(parse_decimal("9999999999999999e369"))),
    content="77FCFF3FCFF3FCFF",
  )
}

///|
/// decimal128: the same family at the widest width, including the over-capacity
/// ordering D4 established (capacity before the digit-dependent ceiling, biased
/// slot before both).
test "decimal wire: the exponent-boundary family holds on decimal128" {
  let f : DecimalFormat = Decimal128
  let above = try {
    let _ = f.encode_raw(parse_decimal("1e6112"))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(above, content="exponent 6112 out of range [-6176, 6111]")
  inspect(
    f.to_hex(f.encode_raw(parse_decimal("1e6111"))),
    content="43FFC000000000000000000000000001",
  )
  let below = try {
    let _ = f.encode_raw(parse_decimal("1e-6177"))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(below, content="biased exponent -1 out of range [0, 16383]")
  inspect(
    f.to_hex(f.encode_raw(parse_decimal("1e-6176"))),
    content="00000000000000000000000000000001",
  )
  let zero_above = try {
    let _ = f.encode_raw(parse_decimal("0e6112"))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(zero_above, content="exponent 6112 out of range [-6176, 6111]")
  inspect(
    f.to_hex(f.encode_raw(parse_decimal("0e6111"))),
    content="43FFC000000000000000000000000000",
  )
  let top = try {
    let _ = f.encode_raw(
      parse_decimal("9999999999999999999999999999999999e6144"),
    )
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(top, content="exponent 6144 out of range [-6176, 6111]")
  inspect(
    f.to_hex(
      f.encode_raw(parse_decimal("9999999999999999999999999999999999e6111")),
    ),
    content="77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
  )
}

///|
/// Over-capacity coefficients name the coefficient on every width (D4's fix is
/// format-generic; decimal32 was the only width it was locked on).
test "decimal wire: an over-capacity coefficient is named on every width" {
  // decimal64: one digit past the 16-digit container.
  let f64 : DecimalFormat = Decimal64
  let wide64 = try {
    let _ = f64.encode_raw(parse_decimal("11111111111111111"))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(
    wide64,
    content="coefficient has 17 decimal digits, this format holds 16",
  )
  // Far past it, at an exponent that also sinks the derived ceiling: capacity
  // is the obstacle no exponent can rescue, so it wins over exp_limit.
  let far64 = try {
    let _ = f64.encode_raw(parse_decimal(String::make(800, '1')))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(
    far64,
    content="coefficient has 800 decimal digits, this format holds 16",
  )
  // But when the biased value does not fit the exponent field at all, the biased
  // gate speaks first — the ordering D4 kept in place. `e400` biases to 798, which
  // is inside the 10-bit field, so that input is the *coefficient* failure above;
  // the field gate needs an exponent past the capacity (1000 biases to 1398).
  let slot64 = try {
    let _ = f64.encode_raw(parse_decimal(String::make(800, '1') + "e1000"))
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(slot64, content="biased exponent 1398 out of range [0, 1023]")
  // decimal128: 34-digit container, one past.
  let f128 : DecimalFormat = Decimal128
  let wide128 = try {
    let _ = f128.encode_raw(
      parse_decimal("11111111111111111111111111111111111"),
    )
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(
    wide128,
    content="coefficient has 35 decimal digits, this format holds 34",
  )
}
