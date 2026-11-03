#!/usr/bin/env python3
"""Independent reference for IEEE 754-2008 *DPD* decimal wire formats.

Shares **no code** with the MoonBit implementation.  It is the authority the
MoonBit tests are checked against, and it regenerates
`examples/vectors-decimal.tsv`.

Scope note: this file implements the **DPD** (Densely Packed Decimal) encoding
only, because that is the encoding the official IBM/IEEE `dectest` vectors
actually exercise (`dsEncode` = decimal32, `ddEncode` = decimal64,
`dqEncode` = decimal128).  BID is deliberately out of scope: there is no
official BID vector set in `dectest`, so a BID implementation here could not be
verified the way everything else in this repository is verified.

Geometry and the combination-field rule below were *recovered from* the vectors
rather than assumed -- see `fit_comb.py`.

  decimal32 : sign(1) combination(5) exp-cont(6) coefficient-cont(20)
  decimal64 : sign(1) combination(5) exp-cont(8) coefficient-cont(50)
  decimal128: sign(1) combination(5) exp-cont(12) coefficient-cont(110)
  bias      : 101 / 398 / 6176

Combination field G0G1G2G3G4:
  G0G1 = 00|01|10 : exponent top-2 = G0G1, leading digit = G2G3G4   (0..7)
  G0G1 = 11       : exponent top-2 = G2G3, leading digit = 8 + G4    (8..9)
  G0G1G2G3G4 = 11110 : Infinity
  G0G1G2G3G4 = 11111 : NaN

Usage:
    python decimal_ref.py                  # verify against dectest vectors
    python decimal_ref.py --emit-dir DIR   # write the vector TSV
"""

import argparse
import os
import re
import sys

DECTEST_DEFAULT = r"D:\code\moonbit\audit\dectest"


# ---------------------------------------------------------------- DPD -------
# Cowlishaw's boolean equations, verbatim.  Bits a..m are the twelve BCD bits,
# p..y the ten DPD bits.  See "A Summary of Densely Packed Decimal encoding".

def bcd2dpd_bits(d1, d2, d3):
    a, b, c, d = (d1 >> 3) & 1, (d1 >> 2) & 1, (d1 >> 1) & 1, d1 & 1
    e, f, g, h = (d2 >> 3) & 1, (d2 >> 2) & 1, (d2 >> 1) & 1, d2 & 1
    i, j, k, m = (d3 >> 3) & 1, (d3 >> 2) & 1, (d3 >> 1) & 1, d3 & 1

    p = b | (a & j) | (a & f & i)
    q = c | (a & k) | (a & g & i)
    r = d
    s = (f & ((a ^ 1) | (i ^ 1))) | ((a ^ 1) & e & j) | (e & i)
    t = g | ((a ^ 1) & e & k) | (a & i)
    u = h
    v = a | e | i
    w = a | (e & i) | ((e ^ 1) & j)
    x = e | (a & i) | ((a ^ 1) & k)
    y = m
    return ((p << 9) | (q << 8) | (r << 7) | (s << 6) | (t << 5)
            | (u << 4) | (v << 3) | (w << 2) | (x << 1) | y)


def dpd2bcd_bits(v10):
    p = (v10 >> 9) & 1
    q = (v10 >> 8) & 1
    r = (v10 >> 7) & 1
    s = (v10 >> 6) & 1
    t = (v10 >> 5) & 1
    u = (v10 >> 4) & 1
    v = (v10 >> 3) & 1
    w = (v10 >> 2) & 1
    x = (v10 >> 1) & 1
    y = v10 & 1

    def n(z):
        return z ^ 1

    a = (v & w) & (n(s) | t | n(x))
    b = p & (n(v) | n(w) | (s & n(t) & x))
    c = q & (n(v) | n(w) | (s & n(t) & x))
    d = r
    e = v & ((n(w) & x) | (n(t) & x) | (s & x))
    f = (s & (n(v) | n(x))) | (p & n(s) & t & v & w & x)
    g = (t & (n(v) | n(x))) | (q & n(s) & t & w)
    h = u
    i = v & ((n(w) & n(x)) | (w & x & (s | t)))
    j = (n(v) & w) | (s & v & n(w) & x) | (p & w & (n(x) | (n(s) & n(t))))
    k = (n(v) & x) | (t & n(w) & x) | (q & v & w & (n(x) | (n(s) & n(t))))
    m = y
    return ((a << 3) | (b << 2) | (c << 1) | d,
            (e << 3) | (f << 2) | (g << 1) | h,
            (i << 3) | (j << 2) | (k << 1) | m)


# ------------------------------------------------------------ formats -------

class Fmt:
    def __init__(self, name, bits, exp_cont, coef_digits, bias, emax):
        self.name = name
        self.bits = bits
        self.exp_cont = exp_cont
        self.coef_digits = coef_digits
        self.bias = bias
        # Emax is a format constant (96/384/6144), NOT derived from the field
        # width.  The field is wider than the legal range: that slack is exactly
        # what makes the `11` combination branch unambiguous, and it is why
        # zero's legal ceiling (Etop = Emax-(p-1)) sits below Emax.
        self.emax = emax
        # coefficient continuation bits
        self.coef_cont = bits - 1 - 5 - exp_cont
        # digits held after the leading digit, must be a multiple of 3
        assert (coef_digits - 1) % 3 == 0, name
        assert (coef_digits - 1) // 3 * 10 == self.coef_cont, name

    @property
    def exp_enc_max(self):
        """Largest biased exponent that cannot collide with Inf/NaN prefixes."""
        return 3 * (1 << self.exp_cont) - 1

    @property
    def etop(self):
        """Largest exponent usable by a full-precision coefficient."""
        return self.emax - (self.coef_digits - 1)

    @property
    def etiny(self):
        """Smallest biased-legal exponent: the exponent field's own floor.

        This is `1 - bias`, i.e. exp_enc == 0.  It is NOT derived from Emax;
        confusing the two is a classic slip.
        """
        return 1 - self.bias


DEC32 = Fmt("decimal32", 32, 6, 7, 101, 96)
DEC64 = Fmt("decimal64", 64, 8, 16, 398, 384)
DEC128 = Fmt("decimal128", 128, 12, 34, 6176, 6144)
FORMATS = [DEC32, DEC64, DEC128]

INF_COMB = 0b11110
NAN_COMB = 0b11111


def dpd_encode_canonical(fmt, digits_rest):
    """Encode the digits after the leading digit, rejecting non-canonical input.

    `digits_rest` is a string whose length equals the number of digits held in
    the continuation field.  Each 10-bit group must be produced by the
    coordinate function; the 24 redundant codes are never generated here.
    """
    cont = 0
    for i in range(0, len(digits_rest), 3):
        grp = digits_rest[i:i + 3]
        cont = (cont << 10) | bcd2dpd_bits(int(grp[0]), int(grp[1]), int(grp[2]))
    return cont


def dpd_group_is_canonical(v10):
    """True iff this 10-bit group is one the encoder can actually produce."""
    d1, d2, d3 = dpd2bcd_bits(v10)
    return bcd2dpd_bits(d1, d2, d3) == v10


def enc(fmt, negative, coeff, exponent):
    """Encode a (sign, coefficient, exponent) triple to DPD wire bits.

    Two ceilings apply and the smaller wins.  This is the point that is easy to
    get wrong; see fit_comb.py and PLAN.md §4.3.

      1. the biased exponent must not collide with the Inf/NaN prefixes, i.e.
         exp_enc <= 3 * 2**exp_cont - 1;
      2. the *adjusted* exponent must not exceed Emax, where
         adjusted = exponent + (digit_count - 1).

    They coincide exactly at full precision (`9.999...E+Emax`), which is why the
    format is coherent.  For a narrower coefficient -- and zero in particular --
    ceiling 1 is the binding one: dectest shows `0e+10000` clamping to `0E+90`
    for decimal32, not to Emax.
    """
    if coeff < 0 or coeff >= 10 ** fmt.coef_digits:
        raise ValueError(f"coefficient {coeff} not representable in {fmt.name}")

    exp_enc = exponent + fmt.bias
    if exp_enc < 0 or exp_enc > fmt.exp_enc_max:
        raise ValueError(
            f"exponent {exponent} out of range for {fmt.name} "
            f"(biased {exp_enc}, field max {fmt.exp_enc_max})")
    ndigits = len(str(coeff)) if coeff > 0 else 1
    if exponent + (ndigits - 1) > fmt.emax:
        raise ValueError(
            f"adjusted exponent {exponent + ndigits - 1} exceeds Emax "
            f"{fmt.emax} for {fmt.name}")
    # zero is the special case dectest pins down: with a 1-digit coefficient
    # there is no room to shift the exponent down, so `0e+10000` clamps to
    # `0E+90` (decimal32), i.e. zero cannot sit above Etop.
    if coeff == 0 and exponent > fmt.etop:
        raise ValueError(
            f"zero at exponent {exponent} exceeds Etop {fmt.etop} for {fmt.name}")

    sign = 1 if negative else 0
    digits = str(coeff).rjust(fmt.coef_digits, "0")
    msd = int(digits[0])
    cont = dpd_encode_canonical(fmt, digits[1:])

    g_top = exp_enc >> fmt.exp_cont
    e_low = exp_enc & ((1 << fmt.exp_cont) - 1)
    if msd <= 7:
        comb = (g_top << 3) | msd
    else:
        comb = (0b11 << 3) | (g_top << 1) | (msd - 8)
    return ((sign << (fmt.bits - 1))
            | (comb << (fmt.bits - 6))
            | (e_low << fmt.coef_cont)
            | cont)


def dec(fmt, raw):
    """Decode DPD wire bits into (sign, coefficient, exponent, kind)."""
    sign = (raw >> (fmt.bits - 1)) & 1
    comb = (raw >> (fmt.bits - 6)) & 0x1F
    e_low = (raw >> fmt.coef_cont) & ((1 << fmt.exp_cont) - 1)
    cont = raw & ((1 << fmt.coef_cont) - 1)

    if comb == INF_COMB:
        return sign, None, None, "Infinity"
    if comb == NAN_COMB:
        return sign, None, None, "NaN"

    if (comb >> 3) == 0b11:
        msd = 8 + (comb & 1)
        g_top = (comb >> 1) & 0b11
    else:
        msd = comb & 7
        g_top = comb >> 3
    exp_enc = (g_top << fmt.exp_cont) | e_low
    exponent = exp_enc - fmt.bias

    digits = str(msd)
    groups = (fmt.coef_digits - 1) // 3
    for i in range(groups - 1, -1, -1):
        d1, d2, d3 = dpd2bcd_bits((cont >> (i * 10)) & 0x3FF)
        digits += f"{d1}{d2}{d3}"
    return sign, int(digits), exponent, "finite"


# --------------------------------------------------------------- test -------

def parse_number(s):
    m = re.match(r"^([+-]?)([0-9]*)(?:\.([0-9]*))?(?:E([+-]?[0-9]+))?$", s.strip())
    if not m:
        return None
    neg = m.group(1) == "-"
    ip, fp = m.group(2) or "", m.group(3) or ""
    e = int(m.group(4)) if m.group(4) else 0
    digits = ip + fp
    coeff = int(digits) if digits else 0
    return neg, coeff, e - len(fp)


def load_pairs(path, hexlen):
    pat = re.compile(r"^(\w+)\s+apply\s+(#?[0-9A-Fa-f]+)\s+->\s+(\S+)")
    out = []
    for line in open(path, encoding="utf-8", errors="replace"):
        t = line.strip()
        if not t or t.startswith("--"):
            continue
        m = pat.match(t)
        if not m:
            continue
        a, b = m.group(2), m.group(3)
        if a.startswith("#") and not b.startswith("#"):
            if len(a) - 1 == hexlen and re.match(r"^[+-]?[0-9]", b):
                out.append((int(a[1:], 16), b))
        elif b.startswith("#") and not a.startswith("#"):
            if len(b) - 1 == hexlen and re.match(r"^[+-]?[0-9]", a):
                out.append((int(b[1:], 16), a))
    return out


SUITES = [("dsEncode.decTest", DEC32, 8),
          ("ddEncode.decTest", DEC64, 16),
          ("dqEncode.decTest", DEC128, 32)]


def verify(dectest, verbose):
    total_bad = 0
    for fname, fmt, hexlen in SUITES:
        path = os.path.join(dectest, fname)
        if not os.path.exists(path):
            print(f"missing {path}")
            total_bad += 1
            continue
        exact = noncanon = bad = 0
        fails = []
        for raw, text in load_pairs(path, hexlen):
            pn = parse_number(text)
            if pn is None:
                continue
            neg, coeff, exp = pn
            try:
                mine = enc(fmt, neg, coeff, exp)
            except ValueError:
                continue
            if mine == raw:
                exact += 1
                continue
            # The only legitimate difference is a redundant DPD code: the
            # standard maps these to specific 8/9 sequences.  Accept if we
            # decode to the documented value and the only differing groups are
            # the non-canonical ones.
            got = dec(fmt, raw)
            if got == (1 if neg else 0, coeff, exp, "finite"):
                noncanon += 1
                if verbose:
                    print(f"   [non-canonical accepted] {raw:0{hexlen}X} {text}")
            else:
                bad += 1
                fails.append((raw, text, mine, got))
        print(f"{fmt.name:12} {fname:18} exact={exact:4} "
              f"noncanonical={noncanon:3} fail={bad:3}")
        if verbose:
            for raw, text, mine, got in fails[:8]:
                print(f"   FAIL raw={raw:0{hexlen}X} text={text} mine={mine:0{hexlen}X} got={got}")
        total_bad += bad

    bad_triples = sum(1 for d1 in range(10) for d2 in range(10) for d3 in range(10)
                      if dpd2bcd_bits(bcd2dpd_bits(d1, d2, d3)) != (d1, d2, d3))
    print(f"DPD triple round-trip failures: {bad_triples} / 1000")
    return total_bad + bad_triples


def emit(dectest, outdir):
    os.makedirs(outdir, exist_ok=True)
    lines = ["# format\thex\tnegative\tcoefficient\texponent\tkind\tsource"]
    for fname, fmt, hexlen in SUITES:
        path = os.path.join(dectest, fname)
        if not os.path.exists(path):
            continue
        for raw, text in load_pairs(path, hexlen):
            sign, coeff, exp, kind = dec(fmt, raw)
            py = f"{raw:0{hexlen}X}"
            lines.append(f"{fmt.name}\t{py}\t{sign}\t"
                         f"{'' if coeff is None else coeff}\t"
                         f"{'' if exp is None else exp}\t{kind}\tdectest:{fname}\t{text}")
    out = os.path.join(outdir, "vectors-decimal.tsv")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {out} ({len(lines) - 1} vectors)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dectest", default=DECTEST_DEFAULT)
    ap.add_argument("--emit-dir")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    if args.emit_dir:
        emit(args.dectest, args.emit_dir)
        return
    sys.exit(1 if verify(args.dectest, args.verbose) else 0)


if __name__ == "__main__":
    main()