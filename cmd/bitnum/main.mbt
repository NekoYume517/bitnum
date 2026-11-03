// bitnum — CLI per PLAN.md §7.
//
//   bitnum value <format> <hexbytes>   bytes -> field breakdown + value
//   bitnum bits  <format> <value>      human expression -> hex bytes
//   bitnum table <format>              boundary value table
//   bitnum check <format> <hexbytes>   round-trip check
//
// Exit codes: 0 success / 1 data error / 2 usage error.
//
// Argument parsing is hand-written, like the sibling copybook project: four
// subcommands with positional arguments do not need a parser, and a generic one
// would obscure the fact that `bits` takes an expression while `value` takes hex.

///|
const EXIT_OK : Int32 = 0

///|
const EXIT_DATA : Int32 = 1

///|
const EXIT_USAGE : Int32 = 2

///|
fn usage_text() -> String {
  let sb = StringBuilder()
  sb.write_string(
    "bitnum — exact bit-level codecs for numeric interchange formats\n\n",
  )
  sb.write_string("Usage:\n")
  sb.write_string(
    "  bitnum value <format> <hexbytes>    bytes -> field breakdown + value\n",
  )
  sb.write_string(
    "  bitnum bits  <format> <value>       human expression -> hex bytes\n",
  )
  sb.write_string(
    "  bitnum table <format>               boundary value table\n",
  )
  sb.write_string("  bitnum check <format> <hexbytes>    round-trip check\n\n")
  sb.write_string(
    "formats: binary16, bfloat16, decimal32, decimal64, decimal128\n\n",
  )
  sb.write_string("Examples:\n")
  sb.write_string("  bitnum value binary16 0001\n")
  sb.write_string("  bitnum value @lib.Decimal64 A2300000000003D0\n")
  sb.write_string("  bitnum bits  @lib.Decimal64 -7.50\n")
  sb.write_string("  bitnum table @lib.Decimal32\n")
  sb.to_string()
}

///|
fn main raise {
  let args = @env.args()
  if args.length() < 2 {
    eprintln(usage_text())
    @sys.exit(EXIT_USAGE)
  }
  let code = dispatch(args)
  @sys.exit(code)
}

///|
fn dispatch(args : Array[String]) -> Int32 raise {
  let cmd = args[1]
  if cmd == "-h" || cmd == "--help" || cmd == "help" {
    println(usage_text())
    return EXIT_OK
  }
  if cmd == "value" && args.length() == 4 {
    return cmd_value(args[2], args[3])
  }
  if cmd == "bits" && args.length() == 4 {
    return cmd_bits(args[2], args[3])
  }
  if cmd == "table" && args.length() == 3 {
    return cmd_table(args[2])
  }
  if cmd == "check" && args.length() == 4 {
    return cmd_check(args[2], args[3])
  }
  eprintln("bitnum: bad command or wrong argument count\n")
  eprintln(usage_text())
  EXIT_USAGE
}

///|
/// The five formats the CLI accepts.
enum FormatName {
  Binary16Fmt
  Bfloat16Fmt
  DecimalFmt(@lib.DecimalFormat)
}

///|
/// Parse the format name, or report and return None.
fn check_format(name : String) -> FormatName? {
  match name {
    "binary16" => Some(Binary16Fmt)
    "bfloat16" => Some(Bfloat16Fmt)
    "decimal32" => Some(DecimalFmt(@lib.Decimal32))
    "decimal64" => Some(DecimalFmt(@lib.Decimal64))
    "decimal128" => Some(DecimalFmt(@lib.Decimal128))
    _ => {
      eprintln(
        "bitnum: unknown format '\{name}' (expected binary16, bfloat16, decimal32, decimal64, decimal128)",
      )
      None
    }
  }
}

///|
/// Parse a hex byte string into bytes, rejecting an odd length and a non-hex
/// character.
fn parse_hex_bytes(text : String) -> Bytes? {
  if text.length() % 2 != 0 {
    eprintln(
      "bitnum: hex input must have an even number of digits, got \{text.length()}",
    )
    return None
  }
  let n = text.length() / 2
  let out = Array::make(n, b'\x00')
  let upper = text.to_upper()
  for i in 0..<n {
    let hi = hex_digit(upper, i * 2)
    let lo = hex_digit(upper, i * 2 + 1)
    match (hi, lo) {
      (Some(h), Some(l)) => out[i] = ((h << 4) | l).to_byte()
      _ => {
        eprintln("bitnum: non-hex character in '\{text}'")
        return None
      }
    }
  }
  Some(Bytes::from_array(out))
}

///|
fn hex_digit(text : String, i : Int32) -> Int32? {
  let c = text.get_char(i).unwrap()
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Two bytes, most significant first, to a UInt16.
fn bytes_to_u16(b : Bytes) -> UInt16 {
  ((b[0].to_int() << 8) | b[1].to_int()).to_uint16()
}

///|
/// `bitnum value <format> <hexbytes>`
fn cmd_value(format_name : String, hex : String) -> Int32 raise {
  let fmt = match check_format(format_name) {
    Some(f) => f
    None => return EXIT_USAGE
  }
  match fmt {
    Binary16Fmt =>
      match expect_two_bytes(hex, "binary16") {
        Some(bits) => {
          println(@lib.describe_binary16(bits))
          EXIT_OK
        }
        None => EXIT_DATA
      }
    Bfloat16Fmt =>
      match expect_two_bytes(hex, "bfloat16") {
        Some(bits) => {
          println(@lib.describe_bfloat16(bits))
          EXIT_OK
        }
        None => EXIT_DATA
      }
    DecimalFmt(f) => {
      let raw = f.from_hex(hex) catch {
        e => {
          eprintln("bitnum: \{e.describe()}")
          return EXIT_DATA
        }
      }
      let text = @lib.describe_decimal(f, raw) catch {
        e => {
          eprintln("bitnum: \{e.describe()}")
          return EXIT_DATA
        }
      }
      println(text)
      EXIT_OK
    }
  }
}

///|
/// Decode two bytes of hex, reporting a length mismatch in the format's own terms.
fn expect_two_bytes(hex : String, format_name : String) -> UInt16? {
  match parse_hex_bytes(hex) {
    Some(b) =>
      if b.length() != 2 {
        eprintln("bitnum: \{format_name} is 2 bytes, got \{b.length()}")
        None
      } else {
        Some(bytes_to_u16(b))
      }
    None => None
  }
}

///|
/// `bitnum bits <format> <value>`
///
/// For the binary formats the input is a decimal number converted in the format's
/// own rounding (nearest, ties to even) — the only sensible reading of "human
/// expression" for a float. A rounded result is reported on stderr so a piped
/// stdout stays clean.
fn cmd_bits(format_name : String, text : String) -> Int32 raise {
  let fmt = match check_format(format_name) {
    Some(f) => f
    None => return EXIT_USAGE
  }
  match fmt {
    Binary16Fmt => {
      let x = parse_double_text(text)
      let conv = @lib.of_f64(x, @lib.NearestEven) catch {
        e => {
          eprintln("bitnum: \{e.describe()}")
          return EXIT_DATA
        }
      }
      println(hex_of_bytes(word_to_bytes(conv.bits.to_uint(), 2)))
      if conv.inexact {
        eprintln("bitnum: note: rounded (inexact)")
      }
      EXIT_OK
    }
    Bfloat16Fmt => {
      let x = parse_double_text(text)
      let conv = @lib.of_f32(x.to_float(), @lib.NearestEven)
      println(hex_of_bytes(word_to_bytes(conv.bits.to_uint(), 2)))
      if conv.inexact {
        eprintln("bitnum: note: rounded (inexact)")
      }
      EXIT_OK
    }
    DecimalFmt(f) => {
      let value = @lib.parse_decimal(text) catch {
        e => {
          eprintln("bitnum: \{e.describe()}")
          return EXIT_DATA
        }
      }
      let bytes = f.encode_bytes(value) catch {
        e => {
          eprintln("bitnum: \{e.describe()}")
          return EXIT_DATA
        }
      }
      println(hex_of_bytes(bytes))
      EXIT_OK
    }
  }
}

///|
/// Parse a decimal number for the binary formats. The IEEE spellings of the
/// specials are accepted because probing them is the point of `bits`.
fn parse_double_text(text : String) -> Double {
  match text {
    "nan" | "NaN" => @lib.quiet_nan_double()
    "inf" | "Infinity" | "+Infinity" => @lib.infinity_double()
    "-inf" | "-Infinity" => -@lib.infinity_double()
    _ => parse_double_or_zero(text)
  }
}

///|
/// Format a word as big-endian hex bytes, zero-padded to `width`.
fn word_to_bytes(word : UInt32, width : Int32) -> Bytes {
  let out = Array::make(width, b'\x00')
  let mut v = word
  let mut i = width - 1
  while i >= 0 {
    out[i] = (v & 0xFFU).to_byte()
    v = v >> 8
    i = i - 1
  }
  Bytes::from_array(out)
}

///|
/// Upper-case hex of a byte string, no separators.
fn hex_of_bytes(b : Bytes) -> String {
  let sb = StringBuilder()
  for i in 0..<b.length() {
    let v = b[i].to_int()
    sb.write_char(hex_char(v >> 4))
    sb.write_char(hex_char(v & 0xF))
  }
  sb.to_string()
}

///|
fn hex_char(n : Int32) -> Char {
  if n < 10 {
    Char::from_int('0'.to_int() + n)
  } else {
    Char::from_int('A'.to_int() + n - 10)
  }
}

///|
/// Four-digit hex of a 16-bit word.
fn hex16(bits : UInt16) -> String {
  hex_of_bytes(word_to_bytes(bits.to_uint(), 2))
}

///|
/// `bitnum table <format>` — the boundary value table.
///
/// Every row is produced by encoding a decoded value, so the table documents what
/// the format can represent. The note column is prose; the value column is the
/// standard's own to-scientific-string form.
fn cmd_table(format_name : String) -> Int32 raise {
  let fmt = match check_format(format_name) {
    Some(f) => f
    None => return EXIT_USAGE
  }
  match fmt {
    Binary16Fmt => {
      println(
        "binary16 boundary values (IEEE 754-2008: s(1) e(5) m(10), bias 15)",
      )
      println(
        @lib.pad_left("bits", 6) +
        "  " +
        @lib.pad_right("class", 10) +
        "  value",
      )
      let rows : Array[(UInt16, String)] = [
        (0x0000, "zero"),
        (0x8000, "negative zero"),
        (0x0001, "min subnormal, 2^-24"),
        (0x03FF, "max subnormal"),
        (0x0400, "min normal, 2^-14"),
        (0x3C00, "one"),
        (0x3555, "one third, rounded"),
        (0x7BFF, "max finite, 65504"),
        (0x7C00, "+infinity"),
        (0xFC00, "-infinity"),
        (0x7E00, "quiet NaN, zero payload"),
      ]
      for row in rows {
        let (bits, note) = row
        let d = @lib.Binary16::decode(bits)
        println(
          hex16(bits) +
          "  " +
          @lib.pad_right(d.kind.label(), 10) +
          "  " +
          @lib.pad_left(@lib.binary16_value_text(bits), 12) +
          "   (" +
          note +
          ")",
        )
      }
      EXIT_OK
    }
    Bfloat16Fmt => {
      println(
        "bfloat16 boundary values (high 16 bits of binary32: s(1) e(8) m(7), bias 127)",
      )
      println(
        @lib.pad_left("bits", 6) +
        "  " +
        @lib.pad_right("class", 10) +
        "  value",
      )
      let rows : Array[(UInt16, String)] = [
        (0x0000, "zero"),
        (0x8000, "negative zero"),
        (0x0001, "min subnormal, 2^-133"),
        (0x007F, "max subnormal"),
        (0x0080, "min normal, 2^-126"),
        (0x3F80, "one"),
        (0x4000, "two"),
        (0x7F7F, "max finite"),
        (0x7F80, "+infinity"),
        (0xFF80, "-infinity"),
        (0x7FC0, "quiet NaN, zero payload"),
      ]
      for row in rows {
        let (bits, note) = row
        let d = @lib.BFloat16::decode(bits)
        println(
          hex16(bits) +
          "  " +
          @lib.pad_right(d.kind.label(), 10) +
          "  " +
          @lib.pad_left(@lib.bfloat16_value_text(bits), 12) +
          "   (" +
          note +
          ")",
        )
      }
      EXIT_OK
    }
    DecimalFmt(f) => {
      println(
        "\{f.name()} boundary values (DPD: \{f.bits()} bits, \{f.digits()} digits, bias \{f.bias()})",
      )
      let max_coef = max_coefficient(f)
      let largest = @lib.Decimal::make(
        false,
        max_coef,
        f.max_exponent_for(max_coef),
      )
      let rows : Array[(@lib.Decimal, String)] = [
        (@lib.Decimal::zero(false, f.etin_y()), "zero at Etiny"),
        (@lib.Decimal::zero(true, 0), "negative zero"),
        (
          @lib.Decimal::make(false, @bigint.BigInt::from_int(1), f.etin_y()),
          "smallest subnormal",
        ),
        (
          @lib.Decimal::make(false, @bigint.BigInt::from_int(1), f.emin()),
          "smallest normal",
        ),
        (@lib.Decimal::make(false, @bigint.BigInt::from_int(1), 0), "one"),
        (
          @lib.Decimal::make(true, @bigint.BigInt::from_int(1), 0),
          "negative one",
        ),
        (@lib.Decimal::make(false, max_coef, 0), "largest coefficient"),
        (largest, "largest finite"),
        (@lib.Decimal::infinity(false), "+infinity"),
        (@lib.Decimal::infinity(true), "-infinity"),
        (@lib.Decimal::nan(false, @bigint.BigInt::from_int(0)), "quiet NaN"),
      ]
      println(
        @lib.pad_right("hex", f.hex_width()) +
        "  " +
        @lib.pad_right("class", 10) +
        "  value",
      )
      for row in rows {
        let (v, note) = row
        let bytes = f.encode_bytes(v) catch {
          e => {
            eprintln("bitnum: \{e.describe()}")
            return EXIT_DATA
          }
        }
        println(
          hex_of_bytes(bytes) +
          "  " +
          @lib.pad_right(v.kind.label(), 10) +
          "  " +
          @lib.pad_right(v.to_scientific_string(), 26) +
          "  (" +
          note +
          ")",
        )
      }
      println("")
      println(
        "Emax=\{f.emax()}  Emin=\{f.emin()}  Etiny=\{f.etin_y()}  Emax_top=\{f.emax_top()}",
      )
      // Two ceilings apply and the smaller wins, so both are printed rather than a
      // single misleading "max exponent" line:
      //   adjusted <= Emax   (why the largest finite sits at Emax - p + 1)
      //   exp_top  <= 2      (why zero and narrow coefficients cap at Emax_top)
      // They coincide at full precision, which is the coherence the format relies on.
      println(
        "max exponent: \{f.emax()} with a \{f.digits()}-digit coefficient, \{f.emax_top()} for anything narrower (zero included)",
      )
      EXIT_OK
    }
  }
}

///|
/// `10^digits - 1` as a BigInt.
fn max_coefficient(f : @lib.DecimalFormat) -> BigInt {
  let ten = @bigint.BigInt::from_int(10)
  let p = ten.pow(@bigint.BigInt::from_int(f.digits()))
  p - @bigint.BigInt::from_int(1)
}

///|
/// `bitnum check <format> <hexbytes>`
///
/// Round-trip: decode the bytes, re-encode the value, compare byte for byte. Exit 1
/// when it does not hold. A non-canonical DPD input legitimately fails this check —
/// the encoder can never produce a redundant code — so that case is reported as a
/// distinct outcome instead of being folded into a silent pass.
fn cmd_check(format_name : String, hex : String) -> Int32 raise {
  let fmt = match check_format(format_name) {
    Some(f) => f
    None => return EXIT_USAGE
  }
  match fmt {
    Binary16Fmt =>
      match expect_two_bytes(hex, "binary16") {
        Some(bits) => {
          let back = @lib.Binary16::decode(bits).encode()
          report_bits_check(hex16(bits), hex16(back), bits == back)
        }
        None => EXIT_DATA
      }
    Bfloat16Fmt =>
      match expect_two_bytes(hex, "bfloat16") {
        Some(bits) => {
          let back = @lib.BFloat16::decode(bits).encode()
          report_bits_check(hex16(bits), hex16(back), bits == back)
        }
        None => EXIT_DATA
      }
    DecimalFmt(f) => {
      let raw = f.from_hex(hex) catch {
        e => {
          eprintln("bitnum: \{e.describe()}")
          return EXIT_DATA
        }
      }
      let decoded = f.decode_raw(raw) catch {
        e => {
          eprintln("bitnum: \{e.describe()}")
          return EXIT_DATA
        }
      }
      if decoded.redundant_groups > 0 {
        println("in    \{f.to_hex(raw)}")
        println(
          "out   (no canonical bytes: \{decoded.redundant_groups} non-canonical DPD group(s))",
        )
        println("value \{decoded.value.to_scientific_string()}")
        println(
          "result: non-canonical input accepted — the encoder never emits redundant DPD codes, so this pattern has no canonical form (PLAN.md §4.4)",
        )
        return EXIT_DATA
      }
      let back = f.encode_raw(decoded.value) catch {
        e => {
          eprintln("bitnum: \{e.describe()}")
          return EXIT_DATA
        }
      }
      let same = back.compare(raw) == 0
      report_bits_check(f.to_hex(raw), f.to_hex(back), same)
    }
  }
}

///|
fn report_bits_check(
  input_hex : String,
  output_hex : String,
  same : Bool,
) -> Int32 {
  println("in    \{input_hex}")
  println("out   \{output_hex}")
  if same {
    println("result: round-trip ok")
    EXIT_OK
  } else {
    println("result: MISMATCH")
    EXIT_DATA
  }
}

///|
/// Parse a Double, substituting zero on a syntax error.
///
/// The CLI deliberately has no separate "that is not a number" exit path for the
/// binary formats: a bad literal is a usage error, and dispatch already handles
/// argument-shape errors. Substituting zero keeps the conversion path total while
/// the error stays visible as a wrong value rather than a crash — and every real
/// value is still produced by of_f64/of_f32.
fn parse_double_or_zero(text : String) -> Double {
  let v : Double? = Some(parse_double_sv(text)) catch { _ => None }
  match v {
    Some(d) => d
    None => 0.0
  }
}

///|
/// Bridge to core's StringView parser, which is a free function rather than a
/// method on String.
fn parse_double_sv(text : String) -> Double raise {
  @strconv.parse_double(text[:])
}
