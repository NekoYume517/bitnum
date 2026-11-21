///|
/// 独立 oracle 的全域数值比对：`decode -> to_f64` 必须与「按 IEEE 754 字段
/// 手工算出的精确值」逐位相等。
///
/// 为什么需要它：`binary16_test.mbt` 已经穷举了 `decode -> encode`（位模式
/// 恒等）与类别划分，但**没有一个穷举的数值 oracle**。位模式恒等只能证明
/// 解码器没有丢字段；它证明不了 `to_f64` 的指数偏置、次正规缩放或符号处理
/// 是对的 —— 只要错误在 `to_f64` 内部，位模式往返照样全绿。
///
/// oracle 只做**精确**运算（乘 2 的幂、整数乘法），因此 `==` 是精确比较，
/// 不存在容差问题：binary16 的每个值都能被 Double 精确表示。
///
/// 零要单独判：`0.0 == -0.0` 在数值上成立，所以符号位靠 `1.0 / v` 区分。

///|
fn bin16_oracle(bits : Int32) -> Double raise BitnumError {
  let sign = (bits >> 15) & 1
  let exp = (bits >> 10) & 0x1F
  let frac = bits & 0x3FF
  let magnitude = if exp == 0 {
    // 次正规：frac * 2^-24（含 frac = 0 的零）
    frac.to_double() * pow2_exact(-24)
  } else {
    // 正规：(1024 + frac) * 2^(exp-25)，1024+frac 是整数、乘 2 的幂精确
    (1024 + frac).to_double() * pow2_exact(exp - 25)
  }
  if sign == 1 {
    -magnitude
  } else {
    magnitude
  }
}

///|
test "binary16: to_f64 matches an independent exact oracle on all 63488 non-NaN patterns" {
  let mut failures = 0
  let mut first_bad = -1
  let mut checked = 0
  for i in 0..<65536 {
    let d = Binary16::decode(i.to_uint16())
    if d.is_special() {
      // inf / nan 由 specials_token_test 覆盖，这里只比有限域
      continue
    }
    checked = checked + 1
    let got = d.to_f64()
    let want = bin16_oracle(i)
    // 零的符号：0.0 == -0.0，必须靠倒数区分
    let ok = if want == 0.0 { 1.0 / got == 1.0 / want } else { got == want }
    if !ok {
      failures = failures + 1
      if first_bad < 0 {
        first_bad = i
      }
    }
  }
  inspect(checked, content="63488")
  inspect(failures, content="0")
  inspect(first_bad, content="-1")
}

///|
fn bf16_oracle(bits : Int32) -> Double raise BitnumError {
  let sign = (bits >> 15) & 1
  let exp = (bits >> 7) & 0xFF
  let frac = bits & 0x7F
  let magnitude = if exp == 0 {
    frac.to_double() * pow2_exact(-133)
  } else {
    (128 + frac).to_double() * pow2_exact(exp - 134)
  }
  if sign == 1 {
    -magnitude
  } else {
    magnitude
  }
}

///|
test "bfloat16: to_f64 matches an independent exact oracle on all 65280 finite patterns" {
  let mut failures = 0
  let mut first_bad = -1
  let mut checked = 0
  for i in 0..<65536 {
    // exp 全 1 是 inf/nan 两族（frac = 0 → inf），oracle 只管有限域
    if ((i >> 7) & 0xFF) == 0xFF {
      continue
    }
    let d = BFloat16::decode(i.to_uint16())
    checked = checked + 1
    let got = d.to_f64()
    let want = bf16_oracle(i)
    let ok = if want == 0.0 { 1.0 / got == 1.0 / want } else { got == want }
    if !ok {
      failures = failures + 1
      if first_bad < 0 {
        first_bad = i
      }
      println("bf16 mismatch: bits=\{i} got=\{got} want=\{want}")
    }
  }
  inspect(checked, content="65280")
  inspect(failures, content="0")
  inspect(first_bad, content="-1")
}
