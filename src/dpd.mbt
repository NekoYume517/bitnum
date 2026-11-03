///|
/// Densely Packed Decimal (Cowlishaw), IEEE 754-2008 §3.5.2 /
/// "A Summary of Densely Packed Decimal Encoding".
///
/// Three decimal digits become ten bits. The implementation follows the
/// published boolean equations rather than a 1000-entry table, for one reason
/// that matters for review: the equations are auditable line by line against the
/// standard's own tables, while a table can only be checked by diffing it against
/// another table — which proves nothing about either.
///
/// Bit naming follows the standard exactly, so this file can be read beside it:
///
///   input digits  d1 = a b c d, d2 = e f g h, d3 = i j k m   (most significant first)
///   output bits   p q r s t u v w x y                        (bit 9 .. bit 0)
///
/// `m` is the fourth bit of the third digit, not `l`: the standard skips `l` to
/// avoid confusion with `1` in print.
///
/// Redundant codes: ten bits have 1024 combinations, but only 1000 are images of
/// a digit triple. The 24 extras are **not** errors — the standard decodes them
/// to a fixed 8/9 sequence, and the official `dectest` encode suites contain
/// exactly 24 of them per format. So `dpd_decode3` accepts them and reports
/// which 8/9 sequence came out; `dpd_encode3` can never produce them, which is
/// asserted over the whole input domain.

///|
/// The 24 DPD codes that are not images of any digit triple, least first.
///
/// They all decode to triples made only of 8s and 9s: the standard spends the
/// spare combinations there so that the largest digits stay representable in the
/// densest form.
pub let dpd_redundant_codes : Array[Int32] = [
  0x16E, 0x16F, 0x17E, 0x17F, 0x1EE, 0x1EF, 0x1FE, 0x1FF, 0x26E, 0x26F, 0x27E, 0x27F,
  0x2EE, 0x2EF, 0x2FE, 0x2FF, 0x36E, 0x36F, 0x37E, 0x37F, 0x3EE, 0x3EF, 0x3FE, 0x3FF,
]

///|
/// Whether a 10-bit code is one the encoder can produce.
pub fn dpd_is_canonical(bits : Int32) -> Bool {
  let (d1, d2, d3) = dpd_decode3(bits)
  dpd_encode3(d1, d2, d3) == bits
}

///|
/// Encode three decimal digits (each 0..9) into a 10-bit DPD code.
///
/// The value range is exactly the 1000 images of the digit cube; the 24
/// redundant codes are unreachable, because the equations are injective on
/// digits 0..9 (proved by the exhaustive test over all 1000 inputs).
pub fn dpd_encode3(d1 : Int32, d2 : Int32, d3 : Int32) -> Int32 {
  // a,b,c,d are d1's bits from most to least significant, and so on.
  let a = (d1 >> 3) & 1
  let b = (d1 >> 2) & 1
  let c = (d1 >> 1) & 1
  let d = d1 & 1
  let e = (d2 >> 3) & 1
  let f = (d2 >> 2) & 1
  let g = (d2 >> 1) & 1
  let h = d2 & 1
  let i = (d3 >> 3) & 1
  let j = (d3 >> 2) & 1
  let k = (d3 >> 1) & 1
  let m = d3 & 1

  // PLAN.md §4.2, left column, verbatim.
  let p = b | (a & j) | (a & f & i)
  let q = c | (a & k) | (a & g & i)
  let r = d
  let s = (f & ((a ^ 1) | (i ^ 1))) | ((a ^ 1) & e & j) | (e & i)
  let t = g | ((a ^ 1) & e & k) | (a & i)
  let u = h
  let v = a | e | i
  let w = a | (e & i) | ((e ^ 1) & j)
  let x = e | (a & i) | ((a ^ 1) & k)
  let y = m

  (p << 9) |
  (q << 8) |
  (r << 7) |
  (s << 6) |
  (t << 5) |
  (u << 4) |
  (v << 3) |
  (w << 2) |
  (x << 1) |
  y
}

///|
/// Decode a 10-bit DPD code into three decimal digits.
///
/// Total on all 1024 codes, including the 24 redundant ones: the equations are
/// designed so that every bit pattern resolves to *some* digit triple, and for
/// the redundant codes that triple is the documented 8/9 sequence. Callers who
/// need to know whether the input was canonical use `dpd_is_canonical`.
pub fn dpd_decode3(bits : Int32) -> (Int32, Int32, Int32) {
  let p = (bits >> 9) & 1
  let q = (bits >> 8) & 1
  let r = (bits >> 7) & 1
  let s = (bits >> 6) & 1
  let t = (bits >> 5) & 1
  let u = (bits >> 4) & 1
  let v = (bits >> 3) & 1
  let w = (bits >> 2) & 1
  let x = (bits >> 1) & 1
  let y = bits & 1

  // PLAN.md §4.2, right column, verbatim. `n(z)` is "not z"; written as a local
  // helper because the equations use it 30+ times and `~` on Int is not the
  // logical negation of a 0/1 bit.
  let a = v & w & (n(s) | t | n(x))
  let b = p & (n(v) | n(w) | (s & n(t) & x))
  let c = q & (n(v) | n(w) | (s & n(t) & x))
  let dd = r
  let e = v & ((n(w) & x) | (n(t) & x) | (s & x))
  let f = (s & (n(v) | n(x))) | (p & n(s) & t & v & w & x)
  let g = (t & (n(v) | n(x))) | (q & n(s) & t & w)
  let h = u
  let i = v & ((n(w) & n(x)) | (w & x & (s | t)))
  let j = (n(v) & w) | (s & v & n(w) & x) | (p & w & (n(x) | (n(s) & n(t))))
  let k = (n(v) & x) | (t & n(w) & x) | (q & v & w & (n(x) | (n(s) & n(t))))
  let m = y

  let d1 = (a << 3) | (b << 2) | (c << 1) | dd
  let d2 = (e << 3) | (f << 2) | (g << 1) | h
  let d3 = (i << 3) | (j << 2) | (k << 1) | m
  (d1, d2, d3)
}

///|
/// Logical negation of a single bit.
fn n(z : Int32) -> Int32 {
  z ^ 1
}

///|
/// Decode a 10-bit DPD code, reporting whether it was a redundant code.
///
/// This is the entry point the decimal wire layer uses, because the standard
/// requires the redundant codes to be *accepted* (not rejected, not silently
/// replaced) while still being distinguishable for auditing.
pub fn dpd_decode3_checked(bits : Int32) -> (Int32, Int32, Int32, Bool) {
  let (d1, d2, d3) = dpd_decode3(bits)
  let redundant = dpd_encode3(d1, d2, d3) != bits
  (d1, d2, d3, redundant)
}

///|
/// Render the digit triple of a redundant code as the standard spells it, e.g.
/// `"8,8,8"`. Used in error/audit output so a report names the sequence instead
/// of just the code.
pub fn dpd_triple_text(bits : Int32) -> String {
  let (d1, d2, d3) = dpd_decode3(bits)
  "\{d1},\{d2},\{d3}"
}
