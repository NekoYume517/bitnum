///|
/// `value` 行的 NaN token 必须带上诊断 payload，且 payload 是 **DPD 数字**，
/// 不是续域的整数值。
///
/// 依据是 IEEE 754-2008 §3.5.2 与 §5.12.1：
///
///   - NaN 的 payload 位于组合字段以下（sNaN/signaling 位之下），以 **DPD 编码
///     的十进制数字**承载；
///   - to-scientific-string 对 NaN 写作 `NaN<digits>` / `sNaN<digits>`，
///     零 payload 才省略数字。
///
/// 官方 `dectest` 直接钉死这条要求，下面每个期望值都抄自官方文件：
///
///   ddEncode.decTest decd545  NaN12345              -> #7c000000000049c5
///   ddEncode.decTest decd518  #7fffffffffffffff     -> sNaN999999999999999
///   ddEncode.decTest decd538  #ffffffffffffffff     -> -sNaN999999999999999
///   dsEncode.decTest decs4xx  #7fffffff             -> sNaN999999
///
/// 修复前的现象：`7C000000000049C5` 打印 `payload=18885`（续域的整数值）与
/// `value=NaN`（把 payload 整个丢了）。两个数都不是标准要的数字串 `12345`，
/// 而 `payload=18885` 更像是一个"看起来合理"的十进制数，所以肉眼看不出错。
///
/// 为什么测试全绿时发现不了：库侧只断言 `coefficient`/`payload` 字段的**整数**
/// 往返，而 `describe_decimal` 的 value 行此前没有任何一条测试断言过带 payload
/// 的 NaN —— `DEMO.md` 抄的也是 `value=sNaN`，于是文档与实现互相背书。
test "decimal: the value token carries the NaN payload as DPD digits, per dectest" {
  let f64 : DecimalFormat = Decimal64
  let cases : Array[(String, String)] = [
    ("7C00000000000001", "NaN1"),
    ("7C00000000000012", "NaN12"),
    ("7C00000000000079", "NaN79"),
    ("7C000000000049C5", "NaN12345"),
    ("7C00000000028E56", "NaN123456"),
    ("7C000000000F7FDF", "NaN799799"),
    ("7C03DFF7FDFF7FDF", "NaN799799799799799"),
    ("7C00FF3FCFF3FCFF", "NaN999999999999999"),
    ("7E00000000000001", "sNaN1"),
    ("7E000000000049C5", "sNaN12345"),
    ("FE000000000049C5", "-sNaN12345"),
    ("FC000000000049C5", "-NaN12345"),
    ("7C00000000000000", "NaN"),
    ("7E00000000000000", "sNaN"),
  ]
  let mut bad = 0
  let log : Array[String] = []
  for (hex, want) in cases {
    let raw = f64.from_hex(hex) catch {
      _ => {
        bad = bad + 1
        continue
      }
    }
    let v = f64.decode_raw(raw).value
    let got = v.to_scientific_string_of_width(f64.coef_cont_bits())
    if got != want {
      bad = bad + 1
      log.push("\{hex}: got '\{got}' want '\{want}'")
    }
  }
  // decimal32 与 decimal128 同一条规则，宽度不同而已。
  let f32 : DecimalFormat = Decimal32
  let raw32 = f32.from_hex("7F7FFFFF") catch { _ => BigInt::from_int(0) }
  let got32 = f32.decode_raw(raw32).value.to_scientific_string_of_width(
    f32.coef_cont_bits(),
  )
  if got32 != "sNaN999999" {
    bad = bad + 1
    log.push("7F7FFFFF (decimal32): got '\{got32}' want 'sNaN999999'")
  }
  for m in log {
    println(m)
  }
  inspect(bad, content="0")
}
