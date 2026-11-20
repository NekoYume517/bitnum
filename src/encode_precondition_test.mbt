///|
/// `encode` is a bit reassembly, not a datum gate — the *declared* shape of the
/// binary side.
///
/// `Binary16` / `BFloat16` are `pub(all)` with four public fields, so a library user
/// can build a register no pattern decodes to. Unlike `Decimal`, these types have no
/// `raise` channel on the encoder, and adding one would change the architecture for a
/// hole only hand-built data can reach (the decoder never produces an out-of-range
/// field). So the precondition is declared in the doc and pinned here: the fields are
/// ORed and the low 16 bits are kept, `kind` is not read, and nothing is normalised.
/// A caller who wants a datum gate has `decode → encode`, which is total.
test "binary16: encode reassembles fields and does not validate them" {
  // In range: the reassembly is the pattern, field for field.
  let anchors : Array[(Binary16, Int32)] = [
    (Binary16::{ sign: 0, exponent: 0, significand: 0, kind: Zero, }, 0x0000),
    (Binary16::{ sign: 1, exponent: 0, significand: 0, kind: Zero, }, 0x8000),
    (Binary16::{ sign: 1, exponent: 16, significand: 0, kind: Normal, }, 0xC000),
    (
      Binary16::{ sign: 0, exponent: 31, significand: 0, kind: Infinity, },
      0x7C00,
    ),
    (Binary16::{ sign: 1, exponent: 31, significand: 512, kind: Nan, }, 0xFE00),
    (
      Binary16::{ sign: 0, exponent: 0, significand: 1, kind: Subnormal, },
      0x0001,
    ),
  ]
  for pair in anchors {
    inspect(pair.0.encode().to_int(), content="\{pair.1}")
  }
  // Out of range: `sign = 2` sets bit 16, `exponent = 99` sets bits 16..10, and the
  // low 16 bits of the OR are 0x9F88. Nothing is normalised: the pattern decodes to
  // sign 1 / exponent 7 / significand 904 — none of the three fields that were
  // written, and a perfectly ordinary normal number.
  let wild = Binary16::{
    sign: 2,
    exponent: 99,
    significand: 5000,
    kind: Normal,
  }
  inspect(wild.encode().to_int(), content="40840")
  let back = Binary16::decode(wild.encode())
  inspect(back.sign, content="1")
  inspect(back.exponent, content="7")
  inspect(back.significand, content="904")
  inspect(back.kind.label(), content="normal")
  // `kind` is decode's conclusion, not an input: a struct whose `kind` says infinity
  // but whose fields are all zero encodes to +0 and decodes back as zero.
  let lying = Binary16::{
    sign: 0,
    exponent: 0,
    significand: 0,
    kind: Infinity,
  }
  inspect(lying.encode().to_int(), content="0")
  inspect(Binary16::decode(lying.encode()).kind.label(), content="zero")
}

///|
/// The same rule on bfloat16, whose fields are 8 and 7 bits wide.
test "bfloat16: encode reassembles fields and does not validate them" {
  let anchors : Array[(BFloat16, Int32)] = [
    (BFloat16::{ sign: 0, exponent: 0, significand: 0, kind: Zero, }, 0x0000),
    (BFloat16::{ sign: 1, exponent: 0, significand: 0, kind: Zero, }, 0x8000),
    (
      BFloat16::{ sign: 0, exponent: 127, significand: 0, kind: Normal, },
      0x3F80,
    ),
    (
      BFloat16::{ sign: 0, exponent: 255, significand: 0, kind: Infinity, },
      0x7F80,
    ),
    (BFloat16::{ sign: 1, exponent: 255, significand: 64, kind: Nan, }, 0xFFC0),
    (
      BFloat16::{ sign: 0, exponent: 0, significand: 1, kind: Subnormal, },
      0x0001,
    ),
  ]
  for pair in anchors {
    inspect(pair.0.encode().to_int(), content="\{pair.1}")
  }
  // `sign = 3` overflows the sign bit, `exponent = 300` overflows the 8-bit exponent,
  // and `significand = 200` overflows the 7-bit significand; the 16-bit OR is 0x96C8,
  // which decodes to a normal number although `kind` says zero.
  let wild = BFloat16::{ sign: 3, exponent: 300, significand: 200, kind: Zero, }
  inspect(wild.encode().to_int(), content="38600")
  inspect(BFloat16::decode(wild.encode()).kind.label(), content="normal")
}
