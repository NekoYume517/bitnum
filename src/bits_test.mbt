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
