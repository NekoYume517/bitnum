///|
/// Human-readable rendering: field breakdowns and value text.
///
/// This layer is for diagnostics only — nothing in the codecs depends on it, and
/// no round-trip claim rests on it (PLAN.md §0). It exists so `bitnum value` can
/// print *why* a pattern means what it means rather than just the number, which is
/// the difference between a debugging aid and an oracle.

///|
/// The field breakdown PLAN.md §7 requires for binary formats: raw fields, the
/// class, and the exact value.
pub fn describe_binary16(bits : UInt16) -> String {
  let d = Binary16::decode(bits)
  let sb = StringBuilder()
  sb.write_string("sign=\{d.sign}  exponent=\{d.exponent}")
  if d.kind == Subnormal {
    sb.write_string(" (subnormal)")
  } else if d.kind == Normal {
    sb.write_string(" (normal)")
  } else if d.kind == Zero {
    sb.write_string(" (zero)")
  } else if d.kind == Infinity {
    sb.write_string(" (infinity)")
  } else {
    sb.write_string(" (nan)")
  }
  sb.write_string("  significand=\{d.significand}\n")
  let value_text = signed_value_text(d.kind, d.sign, d.to_f64())
  sb.write_string("kind=\{datum_class_label(d.kind)}  value=\{value_text}")
  sb.write_string(annotate_binary16(d))
  sb.to_string()
}

///|
/// A parenthetical exact hint for the anchor values, so the printed line carries the
/// interpretation and not just the digits. Empty for everything else: inventing a
/// comment for arbitrary patterns would be noise.
///
/// Every hint carries the datum's sign, because every hint names a *value*: `(-0)`,
/// `(-infinity)`, `(-2^1)`. The zero and infinity pairs always did; the power-of-two
/// hints did not, which printed `value=-2   (2^1)` — one line disagreeing with itself
/// about the sign. The `(-0)` / `(0)` pair now only restates what the value text
/// spells, and is kept so the set stays symmetrical.
fn annotate_binary16(d : Binary16) -> String {
  if d.kind == Zero {
    if d.sign == 1 {
      "   (-0)"
    } else {
      "   (0)"
    }
  } else if d.kind == Infinity {
    if d.sign == 1 {
      "   (-infinity)"
    } else {
      "   (infinity)"
    }
  } else if d.kind == Subnormal && d.significand == 1 {
    signed_hint(d.sign, "2^-24")
  } else if d.kind == Normal && d.significand == 0 {
    // `exponent == 15` gives `2^0` without a special case.
    signed_hint(d.sign, "2^\{d.exponent - 15}")
  } else {
    ""
  }
}

///|
/// One parenthetical hint, with the sign inside the parentheses the way `(-0)` and
/// `(-infinity)` spell theirs.
fn signed_hint(sign : Int32, body : String) -> String {
  if sign == 1 {
    "   (-" + body + ")"
  } else {
    "   (" + body + ")"
  }
}

///|
/// Field breakdown for bfloat16.
///
/// The annotation set mirrors `describe_binary16` on purpose: the `value`
/// command must diagnose the same datum the same way in both binary containers.
/// The value line also keeps a negative NaN's sign (`-NaN`), matching the
/// decimal renderer — `Double::to_string` has no sign for NaN, and dropping it
/// here would make `value` the one place the wire's sign bit disappears.
pub fn describe_bfloat16(bits : UInt16) -> String {
  let d = BFloat16::decode(bits)
  let sb = StringBuilder()
  sb.write_string("sign=\{d.sign}  exponent=\{d.exponent}")
  if d.kind == Subnormal {
    sb.write_string(" (subnormal)")
  } else if d.kind == Normal {
    sb.write_string(" (normal)")
  } else if d.kind == Zero {
    sb.write_string(" (zero)")
  } else if d.kind == Infinity {
    sb.write_string(" (infinity)")
  } else {
    sb.write_string(" (nan)")
  }
  sb.write_string("  significand=\{d.significand}\n")
  let value_text = signed_value_text(d.kind, d.sign, d.to_f64())
  sb.write_string("kind=\{datum_class_label(d.kind)}  value=\{value_text}")
  sb.write_string(annotate_bfloat16(d))
  sb.to_string()
}

///|
/// The annotation set for bfloat16, mirroring `annotate_binary16`: negative
/// zero, infinities, the min subnormal, and exact powers of two. Every hint carries
/// the datum's sign (`(-0)`, `(-infinity)`, `(-2^1)`), for the same reason as the
/// binary16 set: one line must not disagree with itself about the sign.
fn annotate_bfloat16(d : BFloat16) -> String {
  if d.kind == Zero {
    if d.sign == 1 {
      "   (-0)"
    } else {
      "   (0)"
    }
  } else if d.kind == Infinity {
    if d.sign == 1 {
      "   (-infinity)"
    } else {
      "   (infinity)"
    }
  } else if d.kind == Subnormal && d.significand == 1 {
    signed_hint(d.sign, "2^-133")
  } else if d.kind == Normal && d.significand == 0 {
    signed_hint(d.sign, "2^\{d.exponent - 127}")
  } else {
    ""
  }
}

///|
/// The value text for a decoded binary datum, with both signs the double cannot
/// carry.
///
/// `format_double` prints `0` for negative zero and `NaN` with no sign, so `value`
/// — the one line whose job is to state the value — would drop a sign bit that the
/// wire really holds and the decoder really reports. Both signs are applied here
/// from the decoded field rather than sniffed out of the double, and they spell
/// exactly what the decimal renderer prints for the same two datums: `-0`, `-NaN`.
/// Until 2026-11-17 only the NaN half was applied, so `-0` read as `0` in the
/// binary containers and as `-0` in the decimal ones (API.md §7 claims one
/// spelling across all five).
fn signed_value_text(kind : FloatClass, sign : Int32, exact : Double) -> String {
  if sign == 1 {
    if kind == Nan {
      "-NaN"
    } else if kind == Zero {
      "-0"
    } else {
      format_double(exact)
    }
  } else {
    format_double(exact)
  }
}

///|
/// Field breakdown for a decimal wire pattern.
pub fn describe_decimal(
  fmt : DecimalFormat,
  raw : BigInt,
) -> String raise BitnumError {
  let d = fmt.decode_raw(raw)
  let v = d.value
  let sb = StringBuilder()
  match v.kind {
    DFinite => {
      sb.write_string("sign=\{if v.negative { 1 } else { 0 }}")
      sb.write_string("  exponent=\{v.exponent}")
      sb.write_string("  coefficient=\{v.coefficient}\n")
    }
    DInfinity => sb.write_string("sign=\{if v.negative { 1 } else { 0 }}\n")
    DNan | DSignalingNan => {
      sb.write_string("sign=\{if v.negative { 1 } else { 0 }}")
      sb.write_string("  payload=\{v.coefficient}\n")
    }
  }
  sb.write_string("kind=\{v.kind.label()}  value=\{v.to_scientific_string()}")
  if d.redundant_groups > 0 {
    sb.write_string(
      "   (\{d.redundant_groups} non-canonical DPD group(s); the encoder cannot produce these)",
    )
  }
  if v.kind == DInfinity {
    // Infinity owns the whole `11110`-leading family, so the `bits - 6` bits below
    // the combination field carry no value. `check` says that at length; the value
    // line used to print the same two lines for `7BFFFFFF` and `78000000`, leaving
    // a reader to notice 26 bits disappear with no note. The value token stays
    // `Infinity` on purpose — what was missing is the statement about the rest of
    // the pattern, not a different value.
    let ignored = big_slice(raw, 0, fmt.bits() - 6)
    if not(ignored.is_zero()) {
      sb.write_string(
        "   (mantissa bits set: 0x\{ignored.to_string(radix=16).to_upper()}, not part of the value; see check)",
      )
    }
  }
  sb.to_string()
}

///|
/// The three *datum classes* of IEEE 754-2008 §2.1.3, which is a coarser partition
/// than `FloatClass`: a finite datum covers zero, subnormals and normals alike.
///
/// Both exist on purpose, and the CLI prints both. PLAN.md §7's example line reads
/// `kind=finite` for a subnormal, while the exponent line annotates `(subnormal)` —
/// so the coarse class belongs on `kind` and the fine one on the exponent, which is
/// also exactly what the standard means by "class".
pub fn datum_class_label(kind : FloatClass) -> String {
  match kind {
    Zero => "finite"
    Subnormal => "finite"
    Normal => "finite"
    Infinity => "infinity"
    Nan => "nan"
  }
}

///|
/// Render a Double the way the `value` line wants it: plain for integers and
/// ordinary magnitudes, scientific for the extremes.
///
/// The exponent is padded to at least two digits (`e-08`, `e+08`, not `e-8`) to
/// match the spelling in PLAN.md §7's worked example, which is the binding form for
/// this output. `Double::to_string` emits a single digit on the negative side, so the
/// padding is applied here rather than by using the platform formatter.
pub fn format_double(x : Double) -> String {
  if x.is_nan() {
    "NaN"
  } else if x.is_pos_inf() {
    "Infinity"
  } else if x.is_neg_inf() {
    "-Infinity"
  } else {
    pad_exponent(x.to_string())
  }
}

///|
/// Pad a single-digit exponent to two digits: `5.9e-8` -> `5.9e-08`, `1e+8` ->
/// `1e+08`.
///
/// Only the exponent tail is touched, and only when it is one or two characters
/// wide, so a mantissa containing the letter `e` (impossible in decimal output, but
/// cheap to rule out) cannot be mangled.
///
/// Both signs are recognized. Today only the negative side needs the padding —
/// `Double::to_string` switches to scientific notation at `1e21`, so a positive
/// exponent it emits is already two digits (`e+21`, `e+38`) — and that is exactly
/// why the `+` branch has to be spelled out rather than inferred: `"+21"` is three
/// characters wide and would have slid through the length test, so the one-digit
/// positive case (`"+8"`) would have printed `e+8` while the negative side printed
/// `e-08`. Padding both signs keeps the "at least two digits" rule a rule, not a
/// coincidence of today's threshold.
fn pad_exponent(text : String) -> String {
  let marker = find_exponent_marker(text)
  if marker < 0 {
    return text
  }
  let head = text[0:marker].to_owned()
  let tail = text[marker + 1:text.length()].to_owned()
  let mut sign = ""
  let mut digits = tail
  if tail.length() > 0 {
    match tail.get_char(0) {
      Some('-') => {
        sign = "-"
        digits = tail[1:].to_owned()
      }
      Some('+') => {
        sign = "+"
        digits = tail[1:].to_owned()
      }
      _ => ()
    }
  }
  if digits.length() >= 2 {
    head + "e" + sign + digits
  } else {
    head + "e" + sign + "0" + digits
  }
}

///|
/// Index of the `e` that starts the exponent, or -1. Scans from the right so the
/// first match is the exponent marker even if the mantissa somehow contained one.
fn find_exponent_marker(text : String) -> Int32 {
  let mut i = text.length() - 1
  while i >= 0 {
    let c = text.get_char(i).unwrap()
    if c == 'e' || c == 'E' {
      return i
    }
    if c == '.' {
      return -1
    }
    i = i - 1
  }
  -1
}

///|
/// The value of a binary16 pattern as an exact decimal string, for the table
/// command: exact means "shortest decimal that round-trips", which is what
/// `to_string` on a Double already gives for a value this narrow.
pub fn binary16_value_text(bits : UInt16) -> String {
  let d = Binary16::decode(bits)
  signed_value_text(d.kind, d.sign, d.to_f64())
}

///|
/// The value of a bfloat16 pattern, as text.
pub fn bfloat16_value_text(bits : UInt16) -> String {
  let d = BFloat16::decode(bits)
  signed_value_text(d.kind, d.sign, d.to_f64())
}

///|
/// Pad a string on the right to `width`.
pub fn pad_right(text : String, width : Int32) -> String {
  if text.length() >= width {
    text
  } else {
    text + String::make(width - text.length(), ' ')
  }
}

///|
/// Pad a string on the left to `width`.
pub fn pad_left(text : String, width : Int32) -> String {
  if text.length() >= width {
    text
  } else {
    String::make(width - text.length(), ' ') + text
  }
}
