#!/usr/bin/env python3
"""Derive (do not assume) the decimal combination-field rule from dectest.

The MoonBit implementation follows a rule that this script *fitted* to the
official vectors, rather than a rule transcribed from memory.  Running it is
how the rule in PLAN.md §4.3 was established.

It assumes only the container geometry (sign bit, 5-bit combination field,
exponent continuation width, coefficient continuation width, and the bias) and
then reports, for every vector, whether the leading significand digit is small
(0..7) or large (8..9), what the encoded exponent is, and what the 5-bit
combination field actually holds.  The printed table makes the rule visible:

    G0G1 = 00|01|10  ->  exponent top-2 = G0G1,  leading digit = G2G3G4
    G0G1 = 11        ->  exponent top-2 = G2G3,  leading digit = 8 + G4

Usage:
    python fit_comb.py [--dectest DIR]
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decimal_ref import DEC32, DEC64, DEC128, DECTEST_DEFAULT, load_pairs, parse_number

SUITES = [("dsEncode.decTest", DEC32, 8),
          ("ddEncode.decTest", DEC64, 16),
          ("dqEncode.decTest", DEC128, 32)]


def comb_of(fmt, raw):
    return (raw >> (fmt.bits - 6)) & 0x1F


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dectest", default=DECTEST_DEFAULT)
    args = ap.parse_args()

    for fname, fmt, hexlen in SUITES:
        path = os.path.join(args.dectest, fname)
        if not os.path.exists(path):
            print(f"missing {path}")
            continue

        rows = []
        for raw, text in load_pairs(path, hexlen):
            pn = parse_number(text)
            if pn is None:
                continue
            neg, coeff, exp = pn
            if coeff >= 10 ** fmt.coef_digits:
                continue
            msd = int(str(coeff).rjust(fmt.coef_digits, "0")[0])
            exp_enc = exp + fmt.bias
            rows.append((raw, msd, exp_enc, comb_of(fmt, raw)))

        print(f"=== {fmt.name}  vectors={len(rows)}  "
              f"exp_cont={fmt.exp_cont} coef_cont={fmt.coef_cont} bias={fmt.bias} ===")

        # Group by category so the two branches of the rule are visible.
        small, large = [], []
        for raw, msd, exp_enc, comb in rows:
            (large if msd >= 8 else small).append((msd, exp_enc, comb))

        def check(bucket, label, msd_fn, top_fn):
            bad = 0
            for msd, exp_enc, comb in bucket:
                if msd_fn(msd, comb) != msd:
                    bad += 1
                if top_fn(comb) != (exp_enc >> fmt.exp_cont):
                    bad += 1
            print(f"  {label:6} n={len(bucket):4}  rule violations={bad}")

        if small:
            check(small, "small",
                  lambda msd, comb: comb & 7,
                  lambda comb: comb >> 3)
        if large:
            check(large, "large",
                  lambda msd, comb: 8 + (comb & 1),
                  lambda comb: (comb >> 1) & 0b11)

        # Show one worked example from each branch, if present.
        for label, bucket in (("small", small), ("large", large)):
            if bucket:
                msd, exp_enc, comb = bucket[0]
                print(f"    e.g. {label}: msd={msd} exp_enc={exp_enc} "
                      f"comb={comb:05b}")


if __name__ == "__main__":
    main()