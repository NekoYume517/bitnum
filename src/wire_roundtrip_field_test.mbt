///|
/// The whole combination × exponent-continuation field space of all three widths,
/// decode → encode, byte for byte.
///
/// `decode_raw` and `encode_raw` are the only pair of functions that see every
/// legal pattern, and the field space is small enough to cover exhaustively:
/// 32 combination values × `2^exp_cont` exponent continuations × three widths,
/// with four coefficient continuations apiece (all zeros, the per-group canonical
/// all-9s code `dpd(9,9,9) = 0x0FF`, a mixed canonical code, and the all-ones
/// continuation that is *entirely* redundant codes). That is 565248 patterns,
/// and it is the coverage the earlier sweep only sampled: the 2026-11-17 report
/// recorded "1200 random decimal32 patterns" while this is every combination field
/// on every width.
///
/// Three outcomes are possible and all three are asserted here, because folding
/// them together is how a real mismatch would hide:
///
///   - **byte identity**, for every finite pattern whose coefficient groups are all
///     canonical — the ordinary case, and by far the majority;
///   - **a redundant DPD group**, reported by `DecodedDecimal::redundant_groups`, so
///     the encoder is expected to write the canonical spelling instead (PLAN.md §4.4);
///   - **the Infinity family**, where `11110` makes the rest of the pattern carry no
///     value so the encoder writes only the canonical form (PLAN.md §1.1).
///
/// What is *not* allowed — and what this test is for — is a pattern in none of those
/// three classes coming back different, or `encode_raw` refusing a datum that
/// `decode_raw` just produced. The second one matters because the encoder applies
/// two ceilings the decoder never checks (`max_exponent_for` and `check_biased`);
/// if a decodable pattern could fall outside them, `bitnum check` would report a
/// data error instead of a verdict on a legal wire pattern.
test "decimal wire: the whole field space decodes to a datum the encoder accepts" {
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  let failures : Array[String] = []
  let mut qtotal = 0
  let mut redundant = 0
  let mut padding = 0
  let mut unequal = 0
  for f in formats {
    let ecmax = (1 << f.exp_cont_bits()) - 1
    let groups = (f.digits() - 1) / 3
    let all_ones = (BigInt::from_int(1) << f.coef_cont_bits()) -
      BigInt::from_int(1)
    // `dpd(9,9,9)` is `0x0FF`; repeating it gives a canonical all-9s continuation.
    let mut nines = BigInt::from_int(0)
    for _ in 0..<groups {
      nines = (nines << 10) + BigInt::from_int(0x0FF)
    }
    for comb in 0..<32 {
      for exp_cont in 0..<=ecmax {
        for
          cc in [BigInt::from_int(0), all_ones, nines, BigInt::from_int(0x155)] {
          let raw = (BigInt::from_int(comb) << (f.bits() - 6)) +
            (BigInt::from_int(exp_cont) << f.coef_cont_bits()) +
            cc
          qtotal = qtotal + 1
          let decoded = f.decode_raw(raw) catch {
            _ => {
              failures.push("decode refused \{f.name()} \{f.to_hex(raw)}")
              continue
            }
          }
          let back = f.encode_raw(decoded.value) catch {
            e => {
              failures.push(
                "encode refused \{f.name()} \{f.to_hex(raw)}: \{e.describe()}",
              )
              continue
            }
          }
          if back.compare(raw) != 0 {
            unequal = unequal + 1
            if decoded.redundant_groups > 0 {
              redundant = redundant + 1
            } else if decoded.value.kind == DInfinity {
              padding = padding + 1
            } else {
              failures.push(
                "silent rewrite \{f.name()} \{f.to_hex(raw)} -> \{f.to_hex(back)}",
              )
            }
          }
        }
      }
    }
  }
  let sb = StringBuilder()
  for i in 0..<failures.length() {
    if i >= 6 {
      break
    }
    sb.write_string(failures[i])
    sb.write_string(" | ")
  }
  inspect(failures.length(), content="0")
  inspect(sb.to_string(), content="")
  // The population itself, so a loop that silently stopped iterating cannot pass:
  // 3 widths x 32 x (64 + 256 + 4096) x 4 = 565248.
  inspect(qtotal, content="565248")
  // Every byte difference must be accounted for by one of the two documented
  // exemptions — a redundant DPD group, or the Infinity family's ignored bits — and
  // both classes must actually be non-empty, or the three-way split would be
  // vacuously satisfied by a loop that never ran.
  inspect(unequal, content="\{redundant + padding}")
  inspect(redundant, content="132480")
  inspect(padding, content="17661")
}
