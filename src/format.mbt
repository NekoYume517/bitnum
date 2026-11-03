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
  sb.write_string(
    "kind=\{datum_class_label(d.kind)}  value=\{format_double(d.to_f64())}",
  )
  sb.write_string(annotate_binary16(d))
  sb.to_string()
}

///|
/// A parenthetical exact hint for the anchor values, so the printed line carries the
/// interpretation and not just the digits. Empty for everything else: inventing a
/// comment for arbitrary patterns would be noise.
fn annotate_binary16(d : Binary16) -> String {
  if d.kind == Zero {
    if d.sign == 1 {
      "   (-0)"
    } else {
      "   (0)"
    }
  } else if d.kind == Subnormal && d.significand == 1 {
    "   (2^-24)"
  } else if d.kind == Normal && d.significand == 0 && d.exponent == 15 {
    "   (2^0)"
  } else if d.kind == Normal && d.significand == 0 {
    "   (2^\{d.exponent - 15})"
  } else if d.kind == Infinity {
    if d.sign == 1 {
      "   (-infinity)"
    } else {
      "   (infinity)"
    }
  } else {
    ""
  }
}

///|
/// Field breakdown for bfloat16.
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
  sb.write_string(
    "kind=\{datum_class_label(d.kind)}  value=\{format_double(d.to_f64())}",
  )
  if d.kind == Subnormal && d.significand == 1 {
    sb.write_string("   (2^-133)")
  } else if d.kind == Normal && d.significand == 0 && d.exponent == 127 {
    sb.write_string("   (2^0)")
  }
  sb.to_string()
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
    _ => {
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
/// The exponent is padded to at least two digits (`e-08`, not `e-8`) to match the
/// spelling in PLAN.md §7's worked example, which is the binding form for this
/// output. `Double::to_string` emits a single digit, so the padding is applied here
/// rather than by using the platform formatter.
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
/// Pad a single-digit exponent to two digits: `5.9e-8` -> `5.9e-08`.
///
/// Only the exponent tail is touched, and only when it is one or two characters
/// wide, so a mantissa containing the letter `e` (impossible in decimal output, but
/// cheap to rule out) cannot be mangled.
fn pad_exponent(text : String) -> String {
  let marker = find_exponent_marker(text)
  if marker < 0 {
    return text
  }
  let head = text[0:marker].to_owned()
  let tail = text[marker + 1:text.length()].to_owned()
  let sign = if tail.length() > 0 && tail.get_char(0).unwrap() == '-' {
    "-"
  } else {
    ""
  }
  let digits = if sign == "" { tail } else { tail[1:].to_owned() }
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
  format_double(Binary16::decode(bits).to_f64())
}

///|
/// The value of a bfloat16 pattern, as text.
pub fn bfloat16_value_text(bits : UInt16) -> String {
  format_double(BFloat16::decode(bits).to_f64())
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
