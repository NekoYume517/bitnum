///|
/// BN-B5 (2026-11-10 audit, P3): the `ExponentOutOfRange` message had two
/// meanings for one field name.
///
/// Two independent checks raise this error:
///
///   - `check_biased` rejects a *biased* exponent outside `[0, Emax + bias]`
///   - the `exp_limit` branch rejects a *true* exponent above `Emax_top` /
///     `Emax - (digits - 1)`
///
/// `describe()` called the first field "biased exponent" unconditionally, so the
/// second check printed `biased exponent 96 out of range [-101, 90]` — a number
/// that is not a biased exponent at all sitting next to bounds that are true
/// exponents. The reader cannot tell which quantity was out of range, and the
/// bounds contradict the label.
///
/// The fix is wording at the raise site, not a new variant: the two branches ask
/// genuinely different questions, and `describe()` should say which one. This test
/// pins both spellings so a future refactor cannot collapse them again.
test "decimal wire: the two exponent rejections word the range they checked" {
  let f : DecimalFormat = Decimal32
  // exp_limit branch: a *true* exponent above Emax_top. `9999999E+96` is
  // 9.999999E+102, past Emax, and 96 is the true exponent — not the biased 197.
  let full = BigInt::from_int(9999999)
  let too_high = try {
    let _ = f.encode_raw(Decimal::{
      negative: false,
      coefficient: full,
      exponent: 96,
      kind: DFinite,
    })
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(too_high, content="exponent 96 out of range [-101, 90]")
  // The same branch on a narrow coefficient: still a true exponent.
  let narrow = try {
    let _ = f.encode_raw(Decimal::{
      negative: false,
      coefficient: BigInt::from_int(1),
      exponent: 96,
      kind: DFinite,
    })
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(narrow, content="exponent 96 out of range [-101, 90]")
}

///|
/// The biased branch keeps its own wording, because it really is talking about
/// the biased exponent: `97` biases to `198`, one past the legal maximum `197`.
/// Both spellings must coexist — flattening them to one wording would lose which
/// quantity the bounds belong to.
test "decimal wire: the biased rejection still says biased" {
  let f : DecimalFormat = Decimal32
  let above = try {
    let _ = f.encode_raw(Decimal::{
      negative: false,
      coefficient: BigInt::from_int(1),
      exponent: 97,
      kind: DFinite,
    })
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(above, content="biased exponent 198 out of range [0, 197]")
  let below = try {
    let _ = f.encode_raw(Decimal::{
      negative: false,
      coefficient: BigInt::from_int(1),
      exponent: -102,
      kind: DFinite,
    })
    "no error"
  } catch {
    e => e.describe()
  }
  inspect(below, content="biased exponent -1 out of range [0, 197]")
}
