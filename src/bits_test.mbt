///|
/// `big_splice` is documented as `from << width | to`, and the difference between
/// `|` and `+` shows up exactly where a caller would rely on the document: when
/// `to` already occupies more than `width` bits.
///
/// `bits.mbt` calls itself out as "auditable bit helpers, public for review", so a
/// documented formula that the code does not implement is the one defect a reader
/// of this file cannot see — the code reads fine, the sentence reads fine, and
/// only a test of the formula itself distinguishes them. (2026-11-17 audit.)
test "bits: big_splice implements the documented splice" {
  let one = BigInt::from_int(1)
  let four = BigInt::from_int(4)
  // `1 << 2 | 4` is 4: the low field is two bits wide and `4` overflows it, so the
  // bits land in the same place and the OR keeps them there. The old `+` gave 8.
  inspect(big_splice(one, four, 2).to_string(), content="4")
  // The ordinary disjoint case must agree in both spellings.
  inspect(big_splice(one, BigInt::from_int(1), 2).to_string(), content="5")
  inspect(
    big_splice(BigInt::from_int(3), BigInt::from_int(2), 4).to_string(),
    content="50",
  )
  // Zero fields are identities on the low side.
  inspect(big_splice(BigInt::from_int(0), four, 0).to_string(), content="4")
}

///|
/// `big_slice` is the inverse direction of the same convention and is used by the
/// wire codec with derived offsets, so its boundaries are worth one assertion:
/// `n <= 0` is the empty field rather than a shift by a negative amount.
test "bits: big_slice takes the documented window" {
  let v = BigInt::from_int(0b101101)
  inspect(big_slice(v, 0, 3).to_string(), content="5")
  inspect(big_slice(v, 3, 3).to_string(), content="5")
  inspect(big_slice(v, 0, -1).to_string(), content="0")
  inspect(big_slice(v, 0, 0).to_string(), content="0")
  // Past the end is empty, not an error: the caller derives the offset from the
  // container geometry, so out-of-range means "no bits here".
  inspect(big_slice(v, 40, 4).to_string(), content="0")
}

///|
/// `pow2_exact` is public "for audit", so its domain has to be stated and enforced
/// rather than assumed.
///
/// The implementation is exact repeated doubling — exact for every `k` whose result
/// is a binary64 at all (`[-1074, 1023]`) — but it is a *loop* over `|k|`, so
/// `pow2_exact(Int32::MAX)` is 2^31 multiplications and `pow2_exact(Int32::MIN)`
/// negates to the same count. There was no bound and no mention of one: the same
/// "unbounded work in a public helper" shape `low_mask64` documents its way out of
/// in this very file, except `low_mask64` states its container limit and this did
/// not (2026-11-17 audit, BN-h).
///
/// Outside the exact range the answer is not a power of two either (it saturates to
/// `0` or `infinity`), so the guard rejects instead of returning a number nobody
/// asked for.
test "bits: pow2_exact declares and enforces its domain" {
  // Endpoints of the exact range, asserted by bit pattern: "exact" is checked, not
  // merely "close".
  inspect(
    pow2_exact(1023).reinterpret_as_uint64().to_string(),
    content="9214364837600034816",
  )
  inspect(pow2_exact(-1074).reinterpret_as_uint64().to_string(), content="1")
  inspect(pow2_exact(0), content="1")
  inspect(pow2_exact(1), content="2")
  inspect(pow2_exact(-1), content="0.5")
  // One past each end, and then the far ends: a rejection with the range in the
  // message, never a saturated `infinity` / `0`, and it returns immediately.
  for k in [1024, -1075, 2147483647, -2147483648] {
    inspect(pow2_message(k), content="exponent \{k} out of range [-1074, 1023]")
  }
}

///|
/// The rejection text of `pow2_exact k`, or `"no error"` when it returned.
fn pow2_message(k : Int32) -> String {
  try {
    let _ = pow2_exact(k)
    "no error"
  } catch {
    e => e.describe()
  }
}
