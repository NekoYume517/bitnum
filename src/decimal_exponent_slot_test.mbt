///|
/// Which biased exponents can exist at all.
///
/// Three different numbers live near the top of the exponent field, and only one of
/// them is a statement about data:
///
/// * `2^(exp_cont+2) - 1` (255 / 1023 / 16383) is what the field can *hold*. The
///   biased-exponent gate answers "does this biased value fit the encoding?", so this
///   is the range the gate reports.
/// * `Emax_top + bias` (191 / 767 / 12287) is the largest biased exponent any finite
///   datum can have: reaching `Emax` needs `p` significant digits, and those digits
///   already push the exponent down into what the combination field can hold.
/// * `Emax + bias` (197 / 782 / 12320) is `Emax`'s own biased encoding. **No datum
///   attains it**: the slot that would carry it is `111xx`, which is the infinity /
///   NaN branch.
///
/// This table is the criterion. For every biased value in the field, either the datum
/// encodes and the exponent survives the round trip, or exactly one gate refuses it —
/// and the bound that gate prints is true of the quantity it names.
test "decimal wire: the biased exponent gate reports the field capacity" {
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  for f in formats {
    let ecb = f.exp_cont_bits()
    let capacity = (BigInt::from_int(1) << (ecb + 2)).to_int() - 1
    let reachable = 3 * (BigInt::from_int(1) << ecb).to_int() - 1
    let bias = f.bias()
    let emax_top = f.emax_top()
    let etiny = f.etin_y()
    // The gate table comes first: it is the claim that can be wrong on its own, and
    // the geometry identities below are the arithmetic the table is built from.
    // A datum with one significant digit: the digit-count ceiling cannot bite, so the
    // only question left is where the biased value itself stops fitting.
    let one = BigInt::from_int(1)
    let mut encoded = 0
    let mut refused_by_ceiling = 0
    let limit = capacity + 2
    for biased in 0..<limit {
      let exponent = biased - bias
      let outcome = try {
        let raw = f.encode_raw(Decimal::make(false, one, exponent))
        let back = f.decode_raw(raw)
        if back.value.exponent != exponent {
          "exponent \{back.value.exponent} came back for \{exponent}"
        } else if back.redundant_groups != 0 {
          "redundant groups came back for \{exponent}"
        } else {
          "ok"
        }
      } catch {
        ExponentOutOfRange(value, min, max) => "\{value} in [\{min}, \{max}]"
        UnbiasedExponentOutOfRange(value, min, max) =>
          "exponent \{value} in [\{min}, \{max}]"
        err => "wrong variant: \{err.describe()}"
      }
      if biased <= reachable {
        inspect(outcome, content="ok")
        encoded += 1
      } else if biased <= capacity {
        inspect(
          outcome,
          content="exponent \{exponent} in [\{etiny}, \{emax_top}]",
        )
        refused_by_ceiling += 1
      } else {
        inspect(outcome, content="\{biased} in [0, \{capacity}]")
      }
    }
    inspect(encoded, content="\{reachable + 1}")
    inspect(refused_by_ceiling, content="\{capacity - reachable}")
    // Below zero the biased value does not fit an unsigned field at all, so the field
    // gate is the one that speaks, and it names the capacity.
    let too_low = try {
      let _ = f.encode_raw(Decimal::make(false, one, etiny - 1))
      "no error"
    } catch {
      ExponentOutOfRange(value, min, max) => "\{value} in [\{min}, \{max}]"
      err => "wrong variant: \{err.describe()}"
    }
    inspect(too_low, content="-1 in [0, \{capacity}]")
    // The three numbers the table is built from, pinned as arithmetic rather than as
    // literals: the capacity is the field, the legal ceiling is `Emax_top + bias`, and
    // `biased_exponent_max` is the legal ceiling — not `Emax + bias`.
    inspect(f.biased_exponent_field_max(), content="\{capacity}")
    inspect(f.biased_exponent_max(), content="\{emax_top + bias}")
    inspect(reachable, content="\{emax_top + bias}")
    // `Emax + bias` sits *above* the legal ceiling, and the gap is exactly the six (or
    // fifteen, or thirty-three) biased values that no finite datum can reach. That gap
    // is why `Emax + bias` was the wrong bound, not a second ceiling to enforce.
    inspect(f.emax() + bias > f.biased_exponent_max(), content="true")
  }
}
