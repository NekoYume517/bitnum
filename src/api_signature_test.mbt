///|
/// `Decimal::to_scientific_string` 是**既有公开 API**，它的签名必须是
/// `-> String`（不带 `raise`）。带上 `raise` 会让每一个下游调用方都不得不包
/// `try`，而函数体里根本没有需要报错的路径——`render_finite` 本身就是
/// `-> String`，会 raise 的 `nan_payload_digits` 只有**带宽度**的新入口才经过。
///
/// 判据用 `pkg.generated.mbti`——编译器自己的签名记录——而不是代码文本：
/// 源码里写 `-> String` 还是 `-> String raise BitnumError`，`.mbti` 会如实写下来。
/// 这一点很关键：MoonBit 把 `raise` 当作**可推断**错误，不包 `try` 直接调用在
/// 源码层也能编过（我第一版测试就是想靠"编不过"来判，结果它是绿的——那种判据
/// 根本不成立）。所以只能对着签名表断言。
///
/// 同时钉住**行为**不变：非零 payload 仍打印 raw 续域整数，带宽度版本才出 DPD
/// 数字；两个入口的分工由本测试与 `nan_payload_token_test.mbt` 一起锁死。
test "to_scientific_string keeps its non-raising public signature" {
  let mbti = @fs.read_file_to_string("src/pkg.generated.mbti") catch {
    _ => ""
  }
  let mut bad = 0
  let log : Array[String] = []
  // 既有入口：必须恰好是 `-> String`，且这一行不得出现 `raise`。
  let legacy_prefix = "pub fn Decimal::to_scientific_string(Self) -> String"
  let mut found_legacy = false
  // 带宽度入口：**应**带 raise（它要读 DPD 组，nan_payload_digits 可报错）。
  let width_prefix = "pub fn Decimal::to_scientific_string_of_width(Self, Int32) -> String raise BitnumError"
  let mut found_width = false
  for line in mbti.split("\n") {
    let t = line.trim()
    if t.has_prefix(legacy_prefix) {
      // 必须是整行结束，多出 ` raise BitnumError` 即判失败。
      found_legacy = true
      if t != legacy_prefix {
        bad = bad + 1
        log.push("legacy signature changed: '\{t}'")
      }
    }
    if t.has_prefix(width_prefix) {
      found_width = true
    }
  }
  if not(found_legacy) {
    bad = bad + 1
    log.push("legacy signature line missing from pkg.generated.mbti")
  }
  if not(found_width) {
    bad = bad + 1
    log.push("width-aware signature line missing or lost its raise")
  }
  // 行为不回归：既有入口的全部形态。
  let finite = Decimal::make(false, BigInt::from_int(150), -2) catch {
    _ => Decimal::zero(false, 0)
  }
  inspect(finite.to_scientific_string(), content="1.50")
  inspect(Decimal::infinity(false).to_scientific_string(), content="Infinity")
  inspect(Decimal::infinity(true).to_scientific_string(), content="-Infinity")
  inspect(Decimal::zero(true, 0).to_scientific_string(), content="-0")
  inspect(
    Decimal::nan(false, BigInt::from_int(0)).to_scientific_string(),
    content="NaN",
  )
  for m in log {
    println(m)
  }
  inspect(bad, content="0")
}