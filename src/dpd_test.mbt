///|
/// DPD coverage: PLAN.md §8 requires all 1000 triples to round-trip, the 24
/// redundant codes to resolve to the standard's 8/9 sequences, and the encoder's
/// value range to exclude those 24 codes.

///|
test "dpd: all 1000 triples round-trip" {
  let mut failures = 0
  let mut first_bad = ""
  for d1 in 0..<10 {
    for d2 in 0..<10 {
      for d3 in 0..<10 {
        let bits = dpd_encode3(d1, d2, d3)
        let (e1, e2, e3) = dpd_decode3(bits)
        if e1 != d1 || e2 != d2 || e3 != d3 {
          failures = failures + 1
          if first_bad == "" {
            first_bad = "\{d1},\{d2},\{d3} -> \{e1},\{e2},\{e3}"
          }
        }
      }
    }
  }
  inspect(failures, content="0")
  inspect(first_bad, content="")
  if failures > 0 {
    println(first_bad)
  }
}

///|
test "dpd: encoder is injective on the 1000 triples" {
  // Injectivity is the property that makes the 24 codes unreachable: if two
  // distinct triples collided, the encoder would still be total but the decoder
  // could not be its inverse. Counting distinct outputs proves it directly.
  let seen : Map[Int32, Bool] = Map([])
  let mut collisions = 0
  for d1 in 0..<10 {
    for d2 in 0..<10 {
      for d3 in 0..<10 {
        let bits = dpd_encode3(d1, d2, d3)
        if seen.get(bits).is_some() {
          collisions = collisions + 1
        } else {
          seen[bits] = true
        }
      }
    }
  }
  inspect(collisions, content="0")
  inspect(seen.size(), content="1000")
}

///|
test "dpd: encoder never emits a redundant code" {
  // The 24 codes are enumerated independently of the equations, so this is a
  // real cross-check rather than a restatement of the encoder's own logic.
  let redundant : Map[Int32, Bool] = Map([])
  for c in dpd_redundant_codes {
    redundant[c] = true
  }
  inspect(redundant.size(), content="24")
  let mut hits = 0
  for d1 in 0..<10 {
    for d2 in 0..<10 {
      for d3 in 0..<10 {
        let bits = dpd_encode3(d1, d2, d3)
        if redundant.get(bits).is_some() {
          hits = hits + 1
        }
        if bits >= 1024 {
          hits = hits + 1
        }
      }
    }
  }
  inspect(hits, content="0")
}

///|
test "dpd: exactly 24 of the 1024 codes are non-canonical" {
  let mut non_canonical = 0
  let listed : Array[Int32] = []
  for bits in 0..<1024 {
    if not(dpd_is_canonical(bits)) {
      non_canonical = non_canonical + 1
      listed.push(bits)
    }
  }
  inspect(non_canonical, content="24")
  // And they are exactly the published list, bit for bit.
  inspect(listed.length(), content="24")
  let mut mismatched = 0
  for i in 0..<24 {
    if listed[i] != dpd_redundant_codes[i] {
      mismatched = mismatched + 1
    }
  }
  inspect(mismatched, content="0")
}

///|
test "dpd: the 24 redundant codes decode to the standard's 8/9 sequences" {
  // The full mapping, spelled out. Each code maps into the 8-slot group, and the
  // three codes that share a triple differ only in bits that the equations
  // ignore for those inputs.
  let expected : Array[(Int32, Int32, Int32, Int32)] = [
    // (code, d1, d2, d3)
    (0x16E, 8, 8, 8),
    (0x16F, 8, 8, 9),
    (0x17E, 8, 9, 8),
    (0x17F, 8, 9, 9),
    (0x1EE, 9, 8, 8),
    (0x1EF, 9, 8, 9),
    (0x1FE, 9, 9, 8),
    (0x1FF, 9, 9, 9),
    (0x26E, 8, 8, 8),
    (0x26F, 8, 8, 9),
    (0x27E, 8, 9, 8),
    (0x27F, 8, 9, 9),
    (0x2EE, 9, 8, 8),
    (0x2EF, 9, 8, 9),
    (0x2FE, 9, 9, 8),
    (0x2FF, 9, 9, 9),
    (0x36E, 8, 8, 8),
    (0x36F, 8, 8, 9),
    (0x37E, 8, 9, 8),
    (0x37F, 8, 9, 9),
    (0x3EE, 9, 8, 8),
    (0x3EF, 9, 8, 9),
    (0x3FE, 9, 9, 8),
    (0x3FF, 9, 9, 9),
  ]
  let mut mismatched = 0
  for e in expected {
    let (code, d1, d2, d3) = e
    let (g1, g2, g3) = dpd_decode3(code)
    if g1 != d1 || g2 != d2 || g3 != d3 {
      mismatched = mismatched + 1
      println("code \{code}: got \{g1},\{g2},\{g3}, want \{d1},\{d2},\{d3}")
    }
  }
  inspect(mismatched, content="0")
  // The redundant flag must be set for all of them, and the canonical codes must
  // not be.
  let mut flagged = 0
  for e in expected {
    let (code, _, _, _) = e
    let (_, _, _, redundant) = dpd_decode3_checked(code)
    if redundant {
      flagged = flagged + 1
    }
  }
  inspect(flagged, content="24")
  let (_, _, _, canon_redundant) = dpd_decode3_checked(dpd_encode3(7, 4, 2))
  inspect(canon_redundant, content="false")
}

///|
test "dpd: decode is total on all 1024 codes and never panics" {
  // Redundant codes must be accepted, not rejected (PLAN.md §4.4). "Accepted"
  // means: produce a digit triple, and every digit is in range.
  let mut bad_digit = 0
  for bits in 0..<1024 {
    let (d1, d2, d3) = dpd_decode3(bits)
    if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 {
      bad_digit = bad_digit + 1
    }
  }
  inspect(bad_digit, content="0")
}

///|
test "dpd: known encodings, cross-checked against the Python reference" {
  // Values taken from `scripts/decimal_ref.py` (`bcd2dpd_bits`), i.e. from the
  // encoder that passes the official `dectest` suite — not from this
  // implementation. Hand-guessing these is exactly the mistake this test exists
  // to prevent: `(9,9,9)` is 255, not the tempting decimal-looking 999.
  inspect(dpd_encode3(0, 0, 0), content="0")
  inspect(dpd_encode3(0, 0, 1), content="1")
  inspect(dpd_encode3(0, 1, 0), content="16")
  inspect(dpd_encode3(1, 0, 0), content="128")
  inspect(dpd_encode3(9, 9, 9), content="255")
  inspect(dpd_encode3(8, 8, 8), content="110")
  inspect(dpd_encode3(8, 1, 1), content="29")
  inspect(dpd_encode3(5, 5, 5), content="725")
  inspect(dpd_encode3(7, 4, 2), content="962")
}

///|
test "dpd: ten-bit range and the 24 codes are the published list" {
  // Guards against a transcription slip in the constant: each listed code must
  // be non-canonical, and each non-canonical code must be listed.
  let mut listed_wrong = 0
  for c in dpd_redundant_codes {
    if dpd_is_canonical(c) {
      listed_wrong = listed_wrong + 1
    }
    if c < 0 || c >= 1024 {
      listed_wrong = listed_wrong + 1
    }
  }
  inspect(listed_wrong, content="0")
}

///|
/// A DPD code is ten bits wide, and the decode side used to *truncate* anything
/// wider instead of refusing it.
///
/// `dpd_decode3(1024)` returned `(0, 0, 0)` — the low ten bits of 1024 — so
/// `dpd_triple_text(1024)` said `"0,0,0"` and `dpd_is_canonical(1024)` said `false`,
/// neither of which is a statement about the argument. `API.md` §5 declares the
/// domain as ten bits; a silent mask is the decoder inventing an input, which is the
/// direction PLAN.md §1.2 forbids ("never silently correct a non-canonical input").
/// The encoder side keeps its documented precondition (the 2026-11-15 audit left
/// `dpd_encode3` as a library-level precondition), so this is the decode half of the
/// same ruling (2026-11-17 audit, BN-i).
///
/// No internal caller depended on the truncation: the wire codec takes its code from
/// `big_slice(raw, shift, 10)`, the tests iterate `0..<1024`, and the three public
/// wrappers are only ever called with in-range codes. The masked core therefore moved
/// into a private `dpd_decode10` and every public entry point checks first.
test "dpd: the decode side refuses a code that is not ten bits" {
  let rejected = "DPD code 1024 is not a 10-bit code (0..1023)"
  inspect(dpdp_message_ok(), content="ok")
  // One past the top, and one below the bottom: the same rejection, naming the code.
  inspect(dpd_decode_message(1024), content=rejected)
  inspect(
    dpd_decode_message(-1),
    content="DPD code -1 is not a 10-bit code (0..1023)",
  )
  // Every public wrapper answers the same way, so no entry point keeps the mask.
  inspect(
    dpd_checked_message(2000),
    content="DPD code 2000 is not a 10-bit code (0..1023)",
  )
  inspect(
    dpd_canonical_message(1024),
    content="DPD code 1024 is not a 10-bit code (0..1023)",
  )
  inspect(
    dpd_text_message(-5),
    content="DPD code -5 is not a 10-bit code (0..1023)",
  )
  // The whole domain still works, including both ends, and the top code is still
  // the redundant one it always was.
  let (d1, d2, d3) = dpd_decode3(1023)
  inspect(d1, content="9")
  inspect(d2, content="9")
  inspect(d3, content="9")
  inspect(dpd_decode3_checked(1023).3, content="true")
  inspect(dpd_decode3_checked(255).3, content="false")
  inspect(dpd_is_canonical(0), content="true")
  inspect(dpd_triple_text(1023), content="9,9,9")
}

///|
/// Outcome helper: `"ok"` when the whole domain decodes, otherwise the first
/// failure, so a regression that rejects a legal code shows up here too.
fn dpdp_message_ok() -> String raise BitnumError {
  for bits in 0..<1024 {
    let (d1, d2, d3) = dpd_decode3(bits)
    if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 {
      return "bad digits at \{bits}"
    }
  }
  "ok"
}

///|
fn dpd_decode_message(bits : Int32) -> String {
  try {
    let _ = dpd_decode3(bits)
    "no error"
  } catch {
    e => e.describe()
  }
}

///|
fn dpd_checked_message(bits : Int32) -> String {
  try {
    let _ = dpd_decode3_checked(bits)
    "no error"
  } catch {
    e => e.describe()
  }
}

///|
fn dpd_canonical_message(bits : Int32) -> String {
  try {
    let _ = dpd_is_canonical(bits)
    "no error"
  } catch {
    e => e.describe()
  }
}

///|
fn dpd_text_message(bits : Int32) -> String {
  try {
    let _ = dpd_triple_text(bits)
    "no error"
  } catch {
    e => e.describe()
  }
}
