///|
/// 冗余 DPD 码的**位置覆盖**，以及 10 位域外的**拒绝**。
///
/// `dpd_test.mbt` 穷举了 1000 个合法三元组与 24 个冗余码的**单组**语义，但真实
/// 线格式的系数续域有 `(digits-1)/3` 组：decimal32 两组、decimal64 五组、
/// decimal128 十一组。冗余码可以落在**任意一组**，解码器逐组解 DPD；若某个位置的
/// `redundant_groups` 计数或取值走岔了，单组测试完全看不见。
///
/// 期望值来自标准，不来自被测代码：
///   - 冗余码解出的必然是**全 8/9 的三元组**（Cowlishaw §4.2 右列，`dpd.mbt:28`
///     的注释也这么写）；
///   - 编码器永远不产生它们，所以 `dpd_is_canonical` 为假；
///   - `redundant_groups` 是"解出冗余码的组数"，放一个就报 1，两组都放就该报 2。
///
/// 第二条断言（`redundant_groups == 2`）是这组里最有价值的一格：它证明这个字段
/// 是**累加**的，不是一个"是否出现过冗余码"的布尔量。第一版测试只放了单个冗余码，
/// 计数恒为 1，把"累加"和"布尔"两种实现都放过去了。
///
/// 域外码：`0..1023` 之外不是 DPD 码，必须 `raise` 而不是回答 `false`——回答
/// `false` 会让 `dpd_is_canonical(-1)` 看起来像"这不是冗余码"，而它根本不是码。
test "decimal wire: a redundant DPD code is answered in every coefficient group" {
  let redundant : Array[Int32] = dpd_redundant_codes
  // 24 个冗余码，每个解出的三元组全由 8/9 组成。
  inspect(redundant.length(), content="24")
  for code in redundant {
    let (d1, d2, d3) = dpd_decode3(code)
    if d1 < 8 || d2 < 8 || d3 < 8 {
      fail("redundant code \{code} decoded to a triple that is not all 8/9")
    }
    if dpd_is_canonical(code) {
      fail("redundant code \{code} claims to be canonical")
    }
    // 编码回它解出的三元组，必然给出**另一个**码。
    let canonical = dpd_encode3(d1, d2, d3)
    if canonical == code {
      fail("redundant code \{code} encodes back to itself")
    }
  }
  let formats : Array[DecimalFormat] = [Decimal32, Decimal64, Decimal128]
  let mut positions = 0
  for f in formats {
    let groups = (f.digits() - 1) / 3
    // 逐组、逐冗余码：只有第 gi 组是冗余码。
    for gi in 0..<groups {
      for code in redundant {
        let raw = wire_with_redundant(f, gi, code)
        let d = f.decode_raw(raw) catch {
          err =>
            fail(
              "\{f.name()} group \{gi} code \{code} was rejected: \{err.describe()}",
            )
        }
        // 只放了一处，计数必须是 1。
        if d.redundant_groups != 1 {
          fail(
            "\{f.name()} group \{gi} code \{code}: redundant_groups=\{d.redundant_groups} want 1",
          )
        }
        positions = positions + 1
      }
    }
    // 两组同时冗余：计数必须变成 2，证明它是累加而不是布尔。
    if groups >= 2 {
      let raw = wire_with_two_redundant(f, 0, 1, redundant[0], redundant[23])
      let d = f.decode_raw(raw) catch {
        err =>
          fail(
            "\{f.name()} two redundant groups was rejected: \{err.describe()}",
          )
      }
      if d.redundant_groups != 2 {
        fail(
          "\{f.name()} two redundant groups: redundant_groups=\{d.redundant_groups} want 2",
        )
      }
    }
  }
  // 2 + 5 + 11 = 18 个组位置 × 24 个冗余码
  inspect(positions, content="432")
  // 10 位域外不是 DPD 码：必须 raise，而不是回答 false。
  // 回答 false 会让 `dpd_is_canonical(-1)` 读起来像「这不是冗余码」，
  // 而它根本不是码——把域名错误伪装成布尔答案正是这里要禁的。
  for outside in [-1, 1024, 2048, -1024] {
    let refused = try {
      let _ = dpd_is_canonical(outside)
      false
    } catch {
      _ => true
    }
    if not(refused) {
      fail("dpd_is_canonical(\{outside}) did not refuse an out-of-domain code")
    }
    let decoded_refused = try {
      let _ = dpd_decode3(outside)
      false
    } catch {
      _ => true
    }
    if not(decoded_refused) {
      fail("dpd_decode3(\{outside}) did not refuse an out-of-domain code")
    }
  }
}

///|
/// 构一个纯系数的 decimal pattern：前导位 1、指数 0，第 `gi` 组放 `code`，
/// 其余组放 `000` 的规范码。
fn wire_with_redundant(f : DecimalFormat, gi : Int32, code : Int32) -> BigInt {
  let groups = (f.digits() - 1) / 3
  let mut cont = BigInt::from_int(0)
  for g in 0..<groups {
    let slot = if g == gi { code } else { dpd_encode3(0, 0, 0) }
    cont = (cont << 10) + BigInt::from_int(slot)
  }
  let biased = BigInt::from_int(0)
  (BigInt::from_int(1) << (f.bits() - 6)) +
  (biased << f.coef_cont_bits()) +
  cont
}

///|
/// 同 `wire_with_redundant`，但第 0 组与第 1 组同时冗余。
fn wire_with_two_redundant(
  f : DecimalFormat,
  g0 : Int32,
  g1 : Int32,
  c0 : Int32,
  c1 : Int32,
) -> BigInt {
  let groups = (f.digits() - 1) / 3
  let mut cont = BigInt::from_int(0)
  for g in 0..<groups {
    let slot = if g == g0 {
      c0
    } else if g == g1 {
      c1
    } else {
      dpd_encode3(0, 0, 0)
    }
    cont = (cont << 10) + BigInt::from_int(slot)
  }
  let biased = BigInt::from_int(0)
  (BigInt::from_int(1) << (f.bits() - 6)) +
  (biased << f.coef_cont_bits()) +
  cont
}
