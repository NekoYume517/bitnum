///|
/// The two bit-window helpers have no error channel — they return a `BigInt` — so
/// their domain has to be stated and *total*. `big_slice` documented one half of
/// it (`width < 0 → empty`) and aborted on the other: a negative `offset` reached
/// `BigInt::shr`, which raises core's `negative shift count`, and because the
/// function is not declared `raise` the caller cannot even catch it — the process
/// dies (2026-11-17 audit, BN-o).
///
/// The empty window is the honest answer for the same reason the width branch
/// gives one: a non-negative integer has no bits below bit 0, so `[offset,
/// offset + width)` with a negative offset contains nothing. This is the
/// container-limit convention `low_mask64` and `to_hex` already use, applied to
/// the other dimension.
test "bits: a negative window in big_slice is empty, not a negative shift" {
  let v = BigInt::from_int(255)
  // The three ways a computed window comes out empty: offset below zero, width
  // below zero, and a window that starts past the end.
  inspect(big_slice(v, -1, 4).compare_int(0), content="0")
  inspect(big_slice(v, -8, 4).compare_int(0), content="0")
  inspect(big_slice(v, 0, -1).compare_int(0), content="0")
  inspect(big_slice(v, 64, 4).compare_int(0), content="0")
  // The legal windows are untouched, including both ends of the value.
  inspect(big_slice(v, 0, 4).to_string(), content="15")
  inspect(big_slice(v, 4, 4).to_string(), content="15")
  inspect(big_slice(v, 7, 1).to_string(), content="1")
  inspect(big_slice(v, 0, 0).compare_int(0), content="0")
  // The zero value needs no special case: every window of it is empty.
  inspect(big_slice(BigInt::from_int(0), 0, 8).compare_int(0), content="0")
}

///|
/// `big_splice` is the same shape of helper — `from << width | to`, returning a
/// `BigInt` with no way to report — and a negative `width` aborted it the same
/// way. The out-of-range end is pinned to the nearest legal value, `0`, so the
/// answer is the formula at `width == 0`: the fragment stays where it is instead
/// of the shift going the other direction or the process dying.
test "bits: a negative splice width pins to zero instead of a negative shift" {
  let from = BigInt::from_int(1)
  let to = BigInt::from_int(2)
  inspect(big_splice(from, to, -1).to_string(), content="3")
  inspect(big_splice(from, to, -4).to_string(), content="3")
  // `width == 0` is the same point of the formula, so the pin is continuous.
  inspect(big_splice(from, to, 0).to_string(), content="3")
  // Legal widths are unchanged: `4 << 2 | 2` is 18, and the OR the contract
  // spells does not carry out of the field.
  inspect(big_splice(BigInt::from_int(4), to, 2).to_string(), content="18")
  // `1 << 2 | 4` is 4: `to` overlaps the field, and the OR keeps the bits in
  // place where `+` would have carried out to 8.
  inspect(big_splice(from, BigInt::from_int(4), 2).to_string(), content="4")
}
