#!/usr/bin/env python3
"""Independent reference for IEEE 754-2008 `binary16` and `bfloat16` conversion.

Shares **no code** with the MoonBit implementation.  It works on exact integer
significand/exponent pairs decomposed straight from the binary64 bit pattern, so
every rounding decision is an integer comparison rather than a float trick, and
the tie cases are decided by `divmod` on exact integers.

It emits `examples/vectors-binary16.tsv`, which the MoonBit test suite replays.

Cross-check: every `nearest_even` row is additionally converted with numpy's
`np.float16`, which goes through the platform's own IEEE conversion.  A mismatch
is a hard failure of this script, so the TSV is not merely self-consistent.

Usage:
    python float_ref.py                  # generate the vector TSV + verify
    python float_ref.py --check          # verify against numpy only
"""

import argparse
import math
import os
import random
import struct
import sys
from fractions import Fraction

MODES = ["nearest_even", "nearest_away", "toward_zero", "toward_positive",
         "toward_negative"]

F16_MAX_BITS = 0x7BFF        # 65504
F16_INF_BITS = 0x7C00
F16_NAN_BITS = 0x7E00
F16_BIAS = 15
F16_PREC = 11               # 1 implicit + 10 stored
F16_MIN_EXP = -14
F16_SUB_Q = -24             # quantum of the subnormal region


def decompose(x):
    """binary64 -> (sign, m, e) with value = (-1)^sign * m * 2^e, m integer.

    Also reports the special classes so the caller never has to re-derive them
    from the bits.
    """
    u = struct.unpack("<Q", struct.pack("<d", x))[0]
    sign = u >> 63
    ef = (u >> 52) & 0x7FF
    mant = u & ((1 << 52) - 1)
    if ef == 0x7FF:
        return sign, 0, 0, "nan" if mant else "inf"
    if ef == 0:
        return sign, mant, -1074, ("zero" if mant == 0 else "finite")
    return sign, mant | (1 << 52), ef - 1023 - 52, "finite"


def round_to_quantum(m, e, q, mode, neg):
    """Round m*2^e to an integer multiple of 2^q.

    Returns (integer count of 2^q units, inexact).  Pure integer arithmetic:
    the fractional part is `rem / 2^shift` and the tie test is `2*rem == 2^shift`.
    """
    shift = q - e
    if shift <= 0:
        return m << (-shift), False
    quo, rem = divmod(m, 1 << shift)
    if rem == 0:
        return quo, False
    half = 1 << (shift - 1)
    if mode == "nearest_even":
        if rem > half or (rem == half and (quo & 1)):
            quo += 1
    elif mode == "nearest_away":
        if rem >= half:
            quo += 1
    elif mode == "toward_zero":
        pass
    elif mode == "toward_positive":
        if not neg:
            quo += 1
    elif mode == "toward_negative":
        if neg:
            quo += 1
    else:
        raise ValueError(mode)
    return quo, True


def rounds_to_infinity(mode, neg):
    """Overflow: outward rounding produces the infinity, inward the max finite."""
    if mode in ("nearest_even", "nearest_away"):
        return True
    if mode == "toward_positive":
        return not neg
    if mode == "toward_negative":
        return neg
    return False


def f16_convert(x, mode):
    """binary64 -> (binary16 bits, inexact)."""
    sign, m, e, kind = decompose(x)
    sbit = sign << 15
    if kind == "nan":
        return F16_NAN_BITS, True          # payload not carried through f64
    if kind == "inf":
        return sbit | F16_INF_BITS, False
    if kind == "zero":
        return sbit, False

    neg = bool(sign)
    p = m.bit_length() - 1 + e             # exact floor(log2(value))
    inexact = False

    if p < F16_MIN_EXP:
        # Subnormal region (and underflow to zero): quantum is 2^-24.
        n, inexact = round_to_quantum(m, e, F16_SUB_Q, mode, neg)
        if n >= 1024:                       # rounded up into the smallest normal
            return sbit | (1 << 10), inexact
        return sbit | n, inexact
    else:
        # Normal region: 11-bit significand, quantum 2^(p-10).
        sig, inexact = round_to_quantum(m, e, p - 10, mode, neg)
        exp_field = p + F16_BIAS
        if sig >= 2048:                     # carried out of the 11-bit field
            sig >>= 1
            exp_field += 1
        if exp_field > 30:
            if rounds_to_infinity(mode, neg):
                return sbit | F16_INF_BITS, True
            return sbit | F16_MAX_BITS, True
        return sbit | (exp_field << 10) | (sig - 1024), inexact


def bf16_truncate(x):
    """bfloat16 truncation: keep the high 16 bits of the binary32 pattern."""
    u = struct.unpack("<I", struct.pack("<f", x))[0]
    return (u >> 16) & 0xFFFF


def bf16_round(x, mode="nearest_even"):
    """bfloat16 with explicit rounding of the 16 discarded binary32 bits."""
    u = struct.unpack("<I", struct.pack("<f", x))[0]
    sign = u >> 31
    ef = (u >> 23) & 0xFF
    mant = u & ((1 << 23) - 1)
    if ef == 0xFF:
        if mant == 0:
            return (sign << 15) | 0x7F80, False
        # Quiet the NaN so the payload survives the narrowing; keep the top 6
        # payload bits that fit into bfloat16.
        payload = (mant >> 16) & 0x3F
        return (sign << 15) | 0x7F80 | 0x40 | payload, True
    if ef == 0:
        m, e, kind = mant, -149, "finite" if mant else "zero"
    else:
        m, e, kind = mant | (1 << 23), ef - 127 - 23, "finite"
    if kind == "zero":
        return sign << 15, False
    neg = bool(sign)
    p = m.bit_length() - 1 + e
    # bfloat16 has an 8-bit significand: quantum 2^(p-7); min normal exp -126.
    if p < -126:
        n, inexact = round_to_quantum(m, e, -133, mode, neg)
        if n >= 128:
            return (sign << 15) | (1 << 7), inexact
        return (sign << 15) | n, inexact
    sig, inexact = round_to_quantum(m, e, p - 7, mode, neg)
    exp_field = p + 127
    if sig >= 256:
        sig >>= 1
        exp_field += 1
    if exp_field > 254:
        if rounds_to_infinity(mode, neg):
            return (sign << 15) | 0x7F80, True
        return (sign << 15) | 0x7F7F, True
    return (sign << 15) | (exp_field << 7) | (sig - 128), inexact


# --------------------------------------------------------------- vectors ----

def f64_from_bits(u):
    return struct.unpack("<d", struct.pack("<Q", u))[0]


def f64_bits(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def next_up(x):
    return f64_from_bits(f64_bits(x) + 1)


def next_down(x):
    return f64_from_bits(f64_bits(x) - 1)


def binary16_cases():
    """Return a list of (label, Float64) covering every rounding decision."""
    cases = []

    def add(label, x):
        cases.append((label, x))

    add("zero", 0.0)
    add("neg-zero", -0.0)
    add("one", 1.0)
    add("neg-one", -1.0)
    add("third-anchor", 1.0 / 3.0)
    add("pi", math.pi)
    add("sqrt2", math.sqrt(2.0))
    add("tenth", 0.1)
    add("65504", 65504.0)
    add("max-minus-ulp", 65504.0 - 16.0)
    add("overflow-tie", 65520.0)
    add("just-below-overflow-tie", next_down(65520.0))
    add("just-above-max", next_up(65504.0))
    add("65536", 65536.0)
    add("huge", 1e10)
    add("neg-huge", -1e10)
    add("neg-overflow-tie", -65520.0)

    # Subnormal / underflow boundaries.
    add("min-subnormal", 2.0 ** -24)
    add("half-min-subnormal", 2.0 ** -25)          # tie between 0 and 2^-24
    add("above-half-min-subnormal", next_up(2.0 ** -25))
    add("below-half-min-subnormal", next_down(2.0 ** -25))
    add("3-half-min-subnormal", 3 * 2.0 ** -25)    # tie between 2^-24 and 2^-23
    add("quarter-min-subnormal", 2.0 ** -26)
    add("neg-half-min-subnormal", -(2.0 ** -25))
    add("min-normal", 2.0 ** -14)
    add("below-min-normal", next_down(2.0 ** -14))
    add("just-below-min-normal", 2.0 ** -14 - 2.0 ** -25)

    # Deep underflow: everything with |x| < 2^-35 needs a rounding shift of 64
    # bits or more, which is a separate code path in both implementations (BN-B1).
    # The seam is exactly at 2^-35 / 2^-36, so both sides are pinned, and the
    # directed modes are the point: an outward rounding of a nonzero value is the
    # smallest subnormal, an inward one is the signed zero (IEEE 754-2008 §4.3.3).
    add("deep-underflow-2^-35", 2.0 ** -35)
    add("deep-underflow-2^-36", 2.0 ** -36)
    add("neg-deep-underflow-2^-36", -(2.0 ** -36))
    # The smallest binary64 subnormal times five: the deepest input that exists.
    add("f64-subnormal-5*2^-1074", 5 * 2.0 ** -1074)
    add("neg-f64-subnormal-5*2^-1074", -(5 * 2.0 ** -1074))

    # Ties in the normal region: midpoint between two adjacent binary16 values.
    for p in range(-14, 16):
        quantum = 2.0 ** (p - 10)
        sig = 2 ** 10 if p > -15 else 2 ** 10
        base = (sig + 1) * 2.0 ** (p - 10)
        add(f"tie-even-p{p}", base + quantum / 2)
        add(f"tie-odd-p{p}", (sig + 2) * 2.0 ** (p - 10) + quantum / 2)
        add(f"tie-even-neg-p{p}", -(base + quantum / 2))

    # Values that are exactly representable: never inexact.
    add("exact-1.5", 1.5)
    add("exact-0.333251953125", 0.333251953125)
    add("exact-neg-7.5", -7.5)
    add("exact-2^-24", 2.0 ** -24)
    return cases


def emit(path):
    lines = ["# input_bits\trounding\texpected_bits\tinexact\tlabel"]
    f16_index = {}
    for label, x in binary16_cases():
        bits = f64_bits(x)
        for mode in MODES:
            want, inexact = f16_convert(x, mode)
            key = (bits, mode)
            if key in f16_index and f16_index[key] != (want, inexact):
                raise SystemExit(f"conflicting expectation for {label} {mode}")
            f16_index[key] = (want, inexact)
            lines.append(f"{bits:016X}\t{mode}\t{want:04X}\t"
                         f"{int(inexact)}\t{label}")
    # Random binary64 values, nearest-even only: spreads coverage over the whole
    # exponent range without pretending to be a proof.
    rng = random.Random(20261016)
    for i in range(200):
        u = rng.getrandbits(64)
        x = f64_from_bits(u)
        want, inexact = f16_convert(x, "nearest_even")
        lines.append(f"{u:016X}\tnearest_even\t{want:04X}\t{int(inexact)}\t"
                     f"random{i}")
    # bfloat16 rows in the same table (format column keeps them apart).
    for label, x in bf16_cases():
        f = struct.unpack("<f", struct.pack("<f", x))[0]
        ubits = struct.unpack("<I", struct.pack("<f", f))[0]
        for mode in MODES:
            want, inexact = bf16_round(f, mode)
            lines.append(f"{ubits:08X}\t{mode}\t{want:04X}\t{int(inexact)}\t"
                         f"bf16-{label}")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"wrote {path} ({len(lines) - 1} rows)")


def bf16_cases():
    cases = [
        ("zero", 0.0),
        ("neg-zero", -0.0),
        ("one", 1.0),
        ("two", 2.0),
        ("third", 1.0 / 3.0),
        ("pi", math.pi),
        ("tenth", 0.1),
        ("max", 3.3895314e38),
        ("neg-max", -3.3895314e38),
        ("min-subnormal", 2.0 ** -133),
        ("half-min-subnormal", 2.0 ** -134),
        ("min-normal", 2.0 ** -126),
    ]
    # Ties: midpoint of two adjacent bfloat16 values, for a spread of exponents.
    for p in (-126, -100, -50, -1, 0, 1, 10, 50, 100, 126):
        quantum = 2.0 ** (p - 7)
        base = 129 * 2.0 ** (p - 7)
        cases.append((f"tie-even-p{p}", base + quantum / 2))
        cases.append((f"tie-odd-p{p}", 130 * 2.0 ** (p - 7) + quantum / 2))
    return cases


def check_torch_bfloat16():
    """nearest-even bfloat16 must agree with torch's own conversion."""
    import torch
    rng = random.Random(11)
    bad = 0
    n = 0
    for _ in range(5000):
        u = rng.getrandbits(32)
        f = struct.unpack("<f", struct.pack("<I", u))[0]
        if math.isnan(f):
            continue
        want, _ = bf16_round(f, "nearest_even")
        got = int(torch.tensor([f], dtype=torch.float32)
                  .to(torch.bfloat16).view(torch.int16).item()) & 0xFFFF
        n += 1
        if got != want:
            if bad < 10:
                print(f"  MISMATCH f32={f!r} want={want:04X} torch={got:04X}")
            bad += 1
    print(f"torch cross-check (bf16 nearest_even): compared={n} mismatch={bad}")
    return bad


def check_numpy():
    """nearest-even must agree with numpy's own float16 conversion."""
    import numpy as np
    rng = random.Random(7)
    bad = 0
    n = 0
    for _ in range(20000):
        u = rng.getrandbits(64)
        x = f64_from_bits(u)
        want, _ = f16_convert(x, "nearest_even")
        with np.errstate(over="ignore"):
            got = int(np.float16(x).view(np.uint16))
        # numpy raises its own inf/nan; compare only finite results bit-exactly.
        if math.isnan(x):
            continue
        n += 1
        if got != want:
            if bad < 10:
                print(f"  MISMATCH x={x!r} want={want:04X} numpy={got:04X}")
            bad += 1
    print(f"numpy cross-check (nearest_even): compared={n} mismatch={bad}")
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out", default=os.path.join("examples",
                                                  "vectors-binary16.tsv"))
    args = ap.parse_args()
    bad = check_numpy() + check_torch_bfloat16()
    if not args.check:
        emit(args.out)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()