///|
/// The `bits` command is the one CLI path that hands caller text to
/// `parse_decimal`, and `parse_decimal` walked the argument by code-unit index
/// with `get_char(i).unwrap()`. A lone surrogate makes `get_char` answer `None`
/// (it is a code unit, not a character), so the walk aborted:
///
/// ```
/// $ bitnum bits decimal32 <lone U+D800>
/// PanicError
///     at moonbit_panic
///     at ??? (…)
/// exit=-1073740791                  # not 1, not 2: the process died
/// ```
///
/// `hex_input_wbtest.mbt` (2026-11-17) fixed the same shape in `hex_digit`, and
/// `hex_surrogate_test.mbt` (2026-11-23) fixed it again inside `from_hex` — both
/// on the `value`/`check` side. Neither touches `bits`, which is why the third
/// copy survived two rounds of "the unwrap is fixed": the entry points are
/// separate, and so were the fixes.
///
/// Every exit code here has to land in the documented `0 / 1 / 2` contract, so
/// the assertion is on the return value of the command, not on the message.
test "bits: a lone surrogate in a decimal literal is a data error, not an abort" {
  let lone : Array[Int32] = [0xD800, 0xDBFF, 0xDC00, 0xDFFF]
  let formats : Array[String] = ["decimal32", "decimal64", "decimal128"]
  for format in formats {
    for code in lone {
      let ch = code.unsafe_to_char()
      let shapes : Array[Array[Char]] = [
        [ch],
        ['-', ch],
        [ch, '1'],
        ['1', ch],
        ['1', '.', ch],
        ['1', 'e', ch],
        ['1', 'e', '-', ch],
        ['1', 'e', '5', ch],
      ]
      for units in shapes {
        let text = String::from_array(units)
        let code_out : Int32 = cmd_bits(format, text) catch { _ => -1 }
        inspect(code_out, content="1")
      }
    }
  }
  // The binary formats never reached the decimal parser: their reader is
  // `parse_double`, which rejects non-ASCII text before any indexed walk. This
  // is the shape that always worked, kept as the control.
  let lo : Int32 = 0xDC00
  let control : Int32 = cmd_bits(
    "binary16",
    String::from_array(['1', lo.unsafe_to_char()]),
  ) catch {
    _ => -1
  }
  inspect(control, content="1")
  // And the fix must not have narrowed the grammar: these still parse.
  let ones : Array[String] = ["1.5", "1e5"]
  for ok in ones {
    let parsed : Int32 = cmd_bits("decimal32", ok) catch { _ => -1 }
    inspect(parsed, content="0")
  }
  let negative : Int32 = cmd_bits("decimal64", "-7.50") catch { _ => -1 }
  inspect(negative, content="0")
}
