# bitnum 实现说明

记录**算错过的**地方。每一条都对应一次真实的失败：一条红测试、或一段跑出来才发现
不对的输出。没有一条是"预防性"的猜测。

## 1. 两个指数上限同时生效，取小者

这是全项目错得最久的一处，也是唯一一处我一度把非法值写进"权威表"的地方。

最初我把合法偏置指数上限写成 `Emax + bias`（197 / 782 / 12320）。**错**。真实上限是：

```
Emax_top = 3 * 2^exp_cont - 1 - bias   =  90 / 369 / 6111
```

两个上限同时存在，机制完全不同：

| 上限 | 来自哪里 | 为什么 |
|---|---|---|
| `adjusted <= Emax` | 标准 | 调整指数 = 指数 + 有效位数 - 1，不得超过 Emax |
| `exp_top <= 2` | 组合字段 | `00/01/10` 形式只有 2 位指数；`11` 分支里 `exp_top == 3` 会写出 `111xx`，而 `11110`/`11111` 是 Inf/NaN |

两者在**满精度处恰好重合**：`Emax - (p-1) == Emax_top`。这就是格式自洽的地方 ——
要够到 `Emax` 必须有 p 位有效数字，而那 p 位已经把指数压到组合字段放得下的位置。
低于满精度时，组合字段上限赢。

后果，以及怎么发现的：

1. `bitnum table decimal32` 的"largest finite"行打印出 `7C53FCFF = 9.999999E+102`。
   `9.999999E+102` 超过 `Emax = 96` —— 一个 **表格里** 的数字违反了标准。
   表是 CLI 现场编码出来的，所以是编码器的问题，不是打印的问题。
2. 用 `scripts/decimal_ref.py` 反查：`dec(0x77F3FCFF)` 给出 `(0, 9999999, 90)`。
   真正的 decimal32 最大有限值是 `9.999999E+96`，即系数 `9999999`、指数 **90** 而不是 96。
3. 统计 `examples/vectors-decimal.tsv` 的指数范围：
   decimal32 `-101..90`、decimal64 `-398..369`、decimal128 `-6176..6111` ——
   三个上界**正好**等于 `Emax_top`。568 条权威向量里没有一个指数超过 90/369/6111。

`Emax + bias` 这个数本身没错（它是 `197`），错的是把它当"合法上限"用：
那个数是**字段容量**，标准故意让它比合法范围宽。域比合法值宽这件事不是缺陷，
正是让 `11` 分支无歧义的原因。现在两个数分别是
`biased_exponent_field_max`（容量）和 `biased_exponent_max`（合法），名字不同、用途不同。

零是这条规则最尖锐的例子：零的有效位数算 1，所以零的指数上限是 `Emax_top`
（90 / 369 / 6111），不是 `Emax`。`dectest` 直接给出答案：

```
ddBase.decTest:1089  toSci  0e+10000  ->  0E+369  Clamped
dqBase.decTest:1066  toSci  0e+10000  ->  0E+6111 Clamped
dsBase.decTest:1045  toSci  0e+10000  ->  0E+90   Clamped
```

**`scripts/decimal_ref.py` 曾经有同一个缺陷**，现已**修好**（不是绕开）：它当时乐于
把零编码到指数 384（`enc(DEC64, False, 0, 384) = 0x6038000000000000`），因为
`dectest` 的**编码**套件里没有这种向量，所以从没被触发。

修法与 MoonBit 侧的规则对齐，但**分两步**，第二步我第一次写错了：

1. 加入零的 `Etop` 上限（`Emax - (p-1)`），拒绝 `0e+384`；
2. 我顺手把「调整指数 ≤ Emax」也加进去，但**把 Emax 写成了 `Etop`** ——
   `exact` 从 123 掉到 109，因为 `9.999999E+96` 这类合法满精度值被误拒。
   `Emax` 是格式常量（96 / 384 / 6144），**不是**从字段宽度推出来的。
   第三次我又把 `Etiny` 写成 `Emax - 2(p-1)`（84 而不是 -101），
   `exact` 掉到 23，立刻暴露。

改完后 `python scripts/decimal_ref.py` 回到 123/189/184 exact + 24×3
noncanonical、0 fail，并且 `--emit-dir` 重新生成的
`examples/vectors-decimal.tsv` 与改动前**逐字节相同**
（SHA256 `02CA5BC5…E673F95F`）—— 说明这个缺陷确实从未污染任何一条向量。

这个过程本身就是结论：**独立参考实现也会有洞**，而「交叉验证」不等于
「信任另一个实现」。三次改动的中间态都被 `exact` 计数立刻抓住，这是
因为有权威套件在，而不是因为我看得仔细。

## 2. binary64 次正规输入会把移位算成 1050 位

`of_f64` 把 `m * 2^e` 四舍五入到 2^q 的整数倍，用整数商余：

```moonbit
let shift = q - e
if shift <= 0 { return (m << (-shift), false) }
let divisor = 1UL << shift        // ← 这里
```

binary16 次正规区的量子是 `q = -24`。当输入是 **binary64 的次正规数** 时 `e = -1074`，
于是 `shift = 1050`。`1UL << 1050` 在 64 位无符号里是**环绕的**，`divisor` 变成
某个没有意义的小数，商余全错 —— 不是溢出成 0，是给出一个"看起来合理"的错误计数。

发现方式：穷举 65536 个 binary16 模式的 `decode → to_f64 → of_f64` 往返，
期望 0 失败，实际 2044 失败，日志第一行是

```
pattern <bits> kind=... val=<v> back=<错误位模式>
```

修法不是加大位宽，是显式处理那一段 —— 但**不能一律返回零**。
`m * 2^e` 确实小于 `2^q`，所以商是 0、也没有平局可断；可「落到哪个零」是
舍入模式的决定，不是这段守卫的决定。2026-11-10 审计 BN-B1 在这里又发现一层：
第一版无条件返回 `(0UL, …)`，于是 `TowardPositive` 遇到正的 `2^-36` 给出
`0x0000` 而不是 IEEE 754-2008 §4.3.3 要求的 `0x0001`（最小次正规数），
`TowardNegative` 遇到负值同理给 `0x8000` 而不是 `0x8001`。

正确形式是让模式参与：

```moonbit
if shift >= 64 {
    if m == 0UL { return (0UL, false) }
    let away = match mode {
        TowardPositive => not(neg)
        TowardNegative => neg
        _ => false
    }
    return (if away { 1UL } else { 0UL }, true)
}
```

这不是防御性补丁：`of_f64` 真的会走到这里，回归测试在 `2^-35` / `2^-36` /
`5.0 × 2^-1074` 三档上逐一断言 —— 向内三种模式（`NearestEven` / `NearestAway` /
`TowardZero`）给带符号的零，向外两种（`TowardPositive` 对正值、
`TowardNegative` 对负值）给到该符号的最小次正规数，五种模式的 `inexact` 全部为
`true`。分界之所以锐利，是因为它就是 `shift == 64`：`2^-35` 仍走 64 位移位路径，
`2^-36` 不走，所以两侧都被钉住。

## 3. bfloat16 截断把 +Infinity 变成 NaN

`of_f32_truncate` 的第一版这样判断"这个 NaN 会不会被截没"：

```moonbit
let high = (u >> 16) & 0xFFFF
let exp_field = (high >> 7) & 0xFF
let sig = high & 0x7F
if exp_field == 0xFF && sig == 0 { /* payload 没了，补一个规范 NaN */ }
```

判断用的是**截断后**的 `high`。但 `+Infinity`（`0x7F800000`）截断后正是 `0x7F80`，
与"payload 全落在低 16 位的 NaN"截断后完全一样（`exp == 0xFF, sig == 0`）。
于是 `+Infinity` 被"修"成了 `0x7FC0` —— 一个 NaN。

类判定必须基于**源值**：

```moonbit
if exp_field == 0xFF && mantissa != 0 && (high & 0x7F) == 0 { ... }
```

只有源值自己知道它是 Infinity（`mantissa == 0`）还是 NaN（`mantissa != 0`）。
回归测试直接钉住 `+Inf`/`-Inf` 截断后仍是 infinity、符号保留。

第二个相关的错：`of_f32` 对**每个** NaN 都报 `inexact`。那让这个标志变成
"输入是 NaN"而不是"输入有损"，两者含义完全不同。现在只在低 16 位 payload 真的
被丢弃时（`(mantissa & 0xFFFF) != 0`）才报 `inexact`。

顺带一个**不是** bug 的行为，但值得写下来：把 bfloat16 加宽到 binary32 再窄回来时，
126 个 signaling NaN 会被置上安静位（`0x3F80xx` → `0x7FC0` 那条路），
位模式变了但 payload 一位没丢，所以 `inexact` 仍是 `false`。IEEE 754 §6.2 要求
窄化时 quiet signaling NaN，这不是信息损失。测试把 65410 个不变、
126 个只多了安静位、0 个 `inexact` 三个数都断言了 —— 如果只断言"往返恒等"，
这条会假红；如果只断言"不报 inexact"，就会漏掉真正该报的情况。

## 4. `exp_top` 被加了两次

十进制编码器一开始这样组装有效位：

```moonbit
let exp_field = (BigInt::from_int(exp_low) << self.coef_cont_bits()) +
  (BigInt::from_int(exp_top) << comb_shift)     // ← 错
```

`exp_top` 是**组合字段内部**的两位（`G0G1`，或 `11` 分支里的 `G2G3`）。
后面构造 `comb` 时它已经被算进去了，这里再加一次就是把它整体左移一位。

现象非常具体：`-7.50` 的 `A23003D0` 变成 `A63003D0`，`1234567` 的 `2654D2E7`
变成 `2A54D2E7` —— 都是组合字段的第 3 位被翻起来。

发现方式：568 条向量的 encode 侧逐字节比对，10 条不匹配，且都是同一个位。
这条测试（`496` 条规范行必须重新编码出**原始** hex）是唯一的发现途径 ——
decode 侧全绿，往返测试也全绿，因为两者都用同一个错误编码器。

## 5. `BigInt::to_octets` 本来就是大端

`encode_bytes` 第一版是：

```moonbit
let octets = raw.to_octets(length=nbytes)
for i in 0..<nbytes { out[i] = octets[nbytes - 1 - i] }   // ← 反转，错
```

我以为它给小端（`to_le_bytes` 那种直觉）。实测：

```
$ octets: b"\xa2\x0c>7\xa8\xef\xea\x90"   （0xA20C3E37A8EFEA90）
```

首字节就是 `0xA2`，即已经是线格式的大端序。反转之后 `A2300000000003D0` 变成
`D0030000000030A2`。测试断言了 `bytes[0] == 0xA2`、`bytes[7] == 0xD0`，
用 `dectest` 的 `ddEncode.decTest:50` 做锚。

教训：**API 名字不可靠，实测才可靠**。`to_octets` 的文档没说字节序，
我凭 `to_le_bytes` 的邻近命名猜了，猜错了。

## 6. 零的指数不能用"`exp_top << 3`"

零没有前导数字，直觉上组合字段就是 `exp_top << 3 | 0`。这在 `exp_top <= 2` 时成立，
但一旦写出 `11000`（`exp_top == 3`），解码端读回来是 **`11` 分支 + 前导数字 8**，
于是一个"零"解码成了 `8xxx...` 这样的大数。

我从两个方向堵住了它：编码端用 `max_exponent_for` 拒绝非法指数（见 §1），
解码端不需要额外防御 —— 因为没有任何合法数据能到达 `exp_top == 3`。
这正是 §1 里那句"域比合法值宽反而保证了无歧义"的具体含义。

## 7. 非规范 DPD 码：接受，但不是"没有错误"

24 个冗余码的处理不是一个可选策略，是标准规定的（PLAN.md §4.4）。三个决定：

1. **`decode` 接受它们。** `dectest` 的 `dsEncode` / `ddEncode` / `dqEncode`
   各有正好 24 条这样的用例，拒绝就是 24 条 fail。
2. **解出的值必须和参考一致**，即那 8 个 8/9 序列（`888`、`889`、`898`、`899`、
   `988`、`989`、`998`、`999`），而不是零、不是最近的合法值。
   测试里 72 条这样的向量逐条断言系数相等，而不是只断 flag。
3. **`encode` 永不产生它们。** 这不是"顺便成立"：布尔方程在 1000 个三元组上是单射的，
   测试用穷举证明 —— 1000 个输出两两不同，且都在 24 个码的补集里。

`bitnum check` 对这种输入**退出 1**，但输出的措辞与真正的不匹配不同：
它说"无规范形式"，而不是"往返失败"。这两件事在数据面上完全不同：
一个说明输入合法但不在编码器值域内，一个说明有人算错了。

## 8. `FloatClass` 与 `datum_class_label` 都不是多余的

一开始只想留一个枚举，结果 CLI 的第一条输出就暴露了问题。
PLAN.md §7 的示例是：

```
sign=0  exponent=0 (subnormal)  significand=1
kind=finite  value=5.960464477539063e-08   (2^-24)
```

`kind=finite` 用在**次正规数**上。而 `FloatClass` 区分 `Subnormal` 和 `Normal`。
两者对"class"的定义不同，且都来自标准：

- IEEE 754-2008 §2.1.3 的 *class*：zero / subnormal / normal 统称 **finite**
- 本包的 `FloatClass`：把三者分开，因为它们的位域和解释规则不同

所以两个都留着：`kind` 用粗分类，指数那一行标注细分类。删掉任一个都会让输出
要么骗人（把次正规数叫 normal），要么丢信息（无法区分零和次正规数）。

## 9. 二进制 NaN 的 payload 过不了 f64

这条不是 bug，是必须说清楚的**不对称**。

binary16 有 10 位 payload，binary64 有 51 位可用 payload。看起来加宽是"无损的"，
但方向反过来不行：`of_f64` 拿到一个 binary64 NaN 时，52 位 payload 里没有
任何一位能对应回 binary16 的哪一位（标准没有规定这种映射）。所以 PLAN.md §2
规定产出规范安静 NaN `0x7E00`（保留符号）。

结果：

| 路径 | 65536 个模式里的结果 |
|---|---|
| `decode → encode` | 全部逐字节恒等（`encode` 只搬字段） |
| `decode → to_f64 → of_f64` | 63492 个不变；2044 个 NaN 塌成规范值并标 `inexact`；2 个规范安静 NaN 是不动点；0 个错位 |

两个测试分别断言这两件事，而不是用一个"往返测试"含糊覆盖。
把 NaN 从穷举里悄悄剔掉、或者放宽断言让它通过，都是把一个真实性质藏起来。

## 10. 验证方法与边界

**证据链**，每条都能自己跑：

```
python scripts/decimal_ref.py     # 对 dectest 全绿：123/189/184 exact + 24×3 noncanonical, 0 fail
python scripts/float_ref.py       # numpy 19988/19988, torch 4973/4973, 全部逐位一致
```

`decimal_ref.py` 与 MoonBit 侧**零共享代码**，`float_ref.py` 与 MoonBit 侧同样零共享，
且它自己又被 numpy 和 torch 两个第三方实现交叉验证。三份独立实现吻合，
才是"证明"，而不是"同一份逻辑跑两遍"。

**明确没做到的**：

- **BID 不在范围内**。`dectest` 里没有 BID 的字节向量，做一个"自测能过"的 BID
  无法按本项目其它部分的同一标准验证。按「交叉验证而非自证」的原则，
  宁可划出范围（PLAN.md §4.5），也不发未验证的东西。
- **紧接上溢边界的十进制舍入没有实现**。`Decimal` 只承载精确三元组；
  放不下的值报 `CoefficientTooLarge` / `ExponentOutOfRange`，不自动舍入到边界。
  标准在溢出时钳位并报 Overflow+Inexact，那需要一套 context 机制，属于另一个量级的工作。
  这里明确没做，而不是做了一半。
- **`scripts/decimal_ref.py` 的零指数缺陷已修**（详见 §1 末尾）：加了零的 `Etop`
  上限与「调整指数 ≤ Emax」两道检查，修的过程中我自己两次把 `Emax`/`Etiny`
  推错，都被 `exact` 计数立刻抓住。修完后该脚本仍对 568 条官方向量全绿，
  且重新生成的向量表与改动前逐字节相同 —— 证明缺陷从未污染基准数据。
- **`Float::to_float`（`Double` → `Float`）用了平台转换**，在 CLI 的 `bits bfloat16`
  路径上。这一处不是本包实现的，它只负责把用户输入的十进制变成 binary32；
  之后 binary32 → bfloat16 才是本包的代码。也就是说 `bits bfloat16` 的
  第一段隐含依赖平台的 binary32 转换精度，测试覆盖的是第二段。