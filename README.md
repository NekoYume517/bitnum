# bitnum

**IEEE 754 数值交换格式的位级编解码器：binary16、bfloat16、decimal32/64/128（DPD）。**

[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.20261102-blueviolet)](https://www.moonbitlang.com/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

---

## 为什么

有三种"小数"在真实系统里每天出现，而且**同一个数值的字节完全不同**：

| 格式 | `1.5` 的字节 | 谁在用它 |
|---|---|---|
| binary16 | `3E00` | 移动 GPU 纹理、ML 权重、颜色扩展范围 |
| bfloat16 | `3FC0` | TPU / 现代加速器的训练数据 |
| decimal64 | `2234000000000015` | 金融金额、计费、税务 |

前两个是二进制浮点，第三个是**十进制**浮点：`0.1` 能精确表示，因为系数和指数都是十进制。
这正是钱不能用 `double` 存的原因，也是 decimal32/64/128 存在的理由。

三者都容易在同一个地方出错：**字节布局**。binary16 是 `s(1) e(5) m(10)`；
bfloat16 就是 binary32 的高 16 位；decimal 有个五位"组合字段"把指数的高位和首位数字
挤在一起，剩下的大半是 DPD 压缩的十进制数字。猜错一位，数字就完全不同，而且**不报错**。

`bitnum` 把这件事做成一个**可测试、可复现**的编解码器：每种格式都成对实现 decode/encode，
并用权威向量闭锁。

## 安装与运行

**作为库依赖**：

```bash
moon add NekoYume517/bitnum
```

```moonbit
// binary16 位模式 → 字段分解 → 精确值
let d = @bitnum.Binary16::decode(0x3C00)
let v = d.to_f64()                    // 1.0，精确

// 十进制三元组 → decimal64 线格式
// `Decimal64` 是枚举变体，先绑定到 let 再调用方法；编码/解码都可失败（raise）。
let fmt : @bitnum.DecimalFormat = @bitnum.Decimal64
let value = @bitnum.Decimal::make(true, @bigint.BigInt::from_int(750), -2)
try {
  let bytes = fmt.encode_bytes(value)   // A2 30 00 00 00 00 03 D0
  let back = fmt.decode_bytes(bytes)    // coefficient 750, exponent -2
  ...
} catch {
  e => println(e.describe())
}
```

**作为命令行工具**（源码运行）：

```bash
moon check
moon test
moon run cmd/bitnum -- value decimal64 A2300000000003D0
```

## 用法

```bash
# 字节 → 字段分解 + 数值（不只是数值：看得到 sign/exponent/significand）
bitnum value binary16 0001
bitnum value decimal64 A2300000000003D0

# 人类表达式 → 字节
bitnum bits binary16 1.0
bitnum bits decimal32 1.23

# 边界值表（每个格式的上溢/下溢/零/Inf/NaN）
bitnum table decimal32

# 往返自检
bitnum check binary16 7E00
```

`bits` 对读不出来的字面量**报错退出 1**，不会静默换成 `+0`；而超出 binary64 的字面量
按 IEEE 754 §7.4 溢出到 ±Inf 并给出说明（退出码 0，标准对这种输入有确定答案）：

```
$ bitnum bits binary16 xyz
bitnum: not a number: 'xyz'
exit=1

$ bitnum bits binary16 1e999
7C00
bitnum: note: '1e999' is too large for binary64; rounded to infinity (inexact)
exit=0
```

`value` / `check` 的十六进制串必须**正好是该格式的宽度**，短一位就报错，不补前导零：

```
$ bitnum value decimal64 A2300000000003D
bitnum: decimal64 is 16 hex digits, got 15
exit=1
```

`value` 打印**字段分解**而不只是数值：

```
$ bitnum value binary16 0001
sign=0  exponent=0 (subnormal)  significand=1
kind=finite  value=5.960464477539063e-08   (2^-24)
```

```
$ bitnum value decimal64 A2300000000003D0
sign=1  exponent=-2  coefficient=750
kind=finite  value=-7.50
```

`kind=finite` 用在次正规数上是有意的：IEEE 754-2008 §2.1.3 把 zero / subnormal / normal
统称 *finite*，细分类标在指数那一行。

`table` 给出每个格式的边界：

```
$ bitnum table decimal32
decimal32 boundary values (DPD: 32 bits, 7 digits, bias 101)
hex       class       value
00000000  finite      0E-101                      (zero at Etiny)
A2500000  finite      -0                          (negative zero)
00000001  finite      1E-101                      (smallest subnormal)
00600001  finite      1E-95                       (smallest normal)
22500001  finite      1                           (one)
A2500001  finite      -1                          (negative one)
6E53FCFF  finite      9999999                     (largest coefficient)
77F3FCFF  finite      9.999999E+96                (largest finite)
78000000  infinity    Infinity                    (+infinity)
F8000000  infinity    -Infinity                   (-infinity)
7C000000  nan         NaN                         (quiet NaN)

Emax=96  Emin=-95  Etiny=-101  Emax_top=90
max exponent: 96 with a 7-digit coefficient, 90 for anything narrower (zero included)
```

> 注意最大有限值是 `9.999999E+96`，不是 `9.999999E+102`。调整指数不得超过
> `Emax = 96`，所以七位系数最多配指数 90。这一行的推导以及它为什么曾经是错的，
> 见 [docs/implementation.md](docs/implementation.md) §1。

完整的实测记录（每条命令 + 真实输出）在 [docs/DEMO.md](docs/DEMO.md)。

## 目标标准与兼容范围

### 依据

- **IEEE 754-2008**：§3.4（位序）、§2.1.3（数据类）、§3.5.2（十进制组合字段）、
  §3.6（binary16 格式）、§4.3（五种舍入方向）、§5.12.1（to-scientific-string）
- **Cowlishaw, "A Summary of Densely Packed Decimal encoding"**：DPD 的十位布尔方程，
  逐项写进 `src/dpd.mbt`，可对照原文审计
- **IBM/IEEE `dectest` 套件**：十进制侧的权威字节向量

### 舍入

`of_f64` / `of_f32` 接受**显式**的 `RoundingMode`，五种方向全部实现。
不提供"默认随便舍一下"的入口。

```moonbit
pub(all) enum RoundingMode {
  NearestEven      // 就近，平局取偶（默认语义，但不是隐式）
  NearestAway
  TowardZero
  TowardPositive
  TowardNegative
}
```

结果类型把"是否被舍入"作为**数据**返回，不是事后猜：

```moonbit
pub(all) struct FloatConversion {
  bits : UInt16
  inexact : Bool
}
```

### 溢出行为

二进制格式上溢时，就近模式给 ±Infinity，`TowardZero` 给 ±max 有限值
（binary16 即 `0x7BFF`）。这在五种模式下逐条测过。

十进制侧**不**自动舍入到边界：放不下的值报 `CoefficientTooLarge` 或
`ExponentOutOfRange`，带位数和范围。标准在溢出时钳位并报 Overflow+Inexact，
那需要一整套 context 机制，本项目**明确没做**（见 [docs/implementation.md](docs/implementation.md) §10）。

## 特性矩阵

| 特性 | 状态 |
|---|---|
| binary16 位级 decode / encode | ✅ 全 65536 模式逐字节恒等 |
| binary16 `of_f64`，五种舍入 | ✅ |
| binary16 NaN payload 保留（decode→encode） | ✅ 全 1023 个 payload |
| bfloat16 位级 decode / encode | ✅ 全 65536 模式 |
| bfloat16 `of_f32_truncate`（截断） | ✅ 与舍入**分别**命名、分别测试 |
| bfloat16 `of_f32`（显式舍入） | ✅ |
| bfloat16 → binary32 精确加宽 | ✅ 低 16 位恒为零 |
| decimal32/64/128 组合字段 | ✅ 含 `11` 分支的 8/9 前导数字 |
| DPD 三元组编解码 | ✅ 1000 个输入穷举，布尔方程而非查表 |
| 24 个冗余 DPD 码 | ✅ **接受**并按标准解成 8/9 序列；编码器永不产生 |
| 十进制指数范围 | ✅ `Emax` / `Emin` / `Etiny` / `Emax_top`，与 `dectest` 钳位值一致 |
| NaN / sNaN（signaling 位） | ✅ 按 `dectest` 的 `0x7c` / `0x7e` 约定 |
| Infinity（`11110` 整个族） | ✅ `0x78`–`0x7b` 全部识别 |
| to-scientific-string 渲染 | ✅ 568 条向量的原文逐字符锁定 |
| BID 编码 | ❌ **不在范围内**，理由见下 |

### 为什么没有 BID

`dectest` 的 `dsEncode` / `ddEncode` / `dqEncode` 只覆盖 **DPD**。官方套件里没有 BID
的字节向量。做一个 BID 解码器可以"自测能过"，但无法像本项目其它部分那样被
独立权威证明；按本仓库「交叉验证而非自证」的原则，宁可划出范围，也不发
未验证的东西（PLAN.md §4.5）。如果将来拿到权威 BID 向量，再加。

## 设计要点

**绝不静默修正。** 24 个冗余 DPD 码被**接受**并按标准解成确定的 8/9 序列 —— 那是
标准规定的行为，不是"修正到最近的合法值"。而越界的系数、越界的指数、
超宽的非规范输入，一律报带定位信息的错误。

**位域是数据，不是注释。** 三种格式的几何（`exp_cont`、`coef_cont`、digits、bias）
在 `DecimalFormat` 上，派生量（`Emax`、`Etiny`、`Emax_top`）由代码算出，
`geometry_is_consistent` 逐项自检。表错了，测试立刻红。

**往返是测试基准。** 但不只有往返：

| 测试 | 规模 |
|---|---|
| binary16 decode→encode | 全部 **65536** 个位模式 |
| binary16 f64 往返 | 全部 65536（NaN payload 的不对称单独断言） |
| bfloat16 decode→encode / 加宽 | 全部 **65536** |
| DPD 三元组往返 + 注入性 | 全部 **1000** |
| DPD 码空间（含 24 冗余） | 全部 **1024** |
| 十进制权威向量 | **568**（496 精确 + 72 冗余） |
| 舍入模式 | 5 种 × 向量表 |
| 错误分支 | 每条至少一个测试 |

```
$ moon test
Total tests: 105, passed: 105, failed: 0.
```

## 证据

十进制侧不与 MoonBit 实现共享任何代码：

```
$ python scripts/decimal_ref.py
decimal32    dsEncode.decTest   exact= 123 noncanonical= 24 fail=  0
decimal64    ddEncode.decTest   exact= 189 noncanonical= 24 fail=  0
decimal128   dqEncode.decTest   exact= 184 noncanonical= 24 fail=  0
DPD triple round-trip failures: 0 / 1000
```

二进制侧由精确整数运算生成，并与**两个第三方实现**交叉核对：

```
$ python scripts/float_ref.py
numpy cross-check (nearest_even): compared=19988 mismatch=0
torch cross-check (bf16 nearest_even): compared=4973 mismatch=0
wrote examples\vectors-binary16.tsv (990 rows)
```

三份独立实现（精确整数参考、numpy 的 binary16、torch 的 bfloat16）逐位吻合。
这不是自证。

## 项目结构

```
src/
  bits.mbt          取位段、popcount、clz、精确 2^k、公共词汇类型
  error.mbt         BitnumError（八种，每种带定位信息）
  binary16.mbt      IEEE 754-2008 binary16，五种舍入
  bfloat16.mbt      bfloat16，截断与舍入**分别**实现
  decimal.mbt       十进制三元组 + to-scientific-string + 解析
  dpd.mbt           DPD 布尔方程（编码/解码/冗余码判定）
  decimal_wire.mbt  decimal32/64/128 组合字段 + DPD 线格式
  format.mbt        诊断渲染（字段分解、值文本）
  *_test.mbt        白盒测试，含四次穷举与向量回放
cmd/bitnum/
  main.mbt          CLI：value / bits / table / check
examples/
  vectors-decimal.tsv   568 条 dectest 权威向量
  vectors-binary16.tsv  990 条交叉核对向量
scripts/
  decimal_ref.py    DPD 参考实现（对 dectest 全绿），零共享代码
  float_ref.py      二进制参考实现（精确整数 + numpy/torch 交叉），零共享代码
  fit_comb.py       组合字段几何拟合
docs/
  DEMO.md           每条命令 + 真实输出
  implementation.md 算错过的地方（每节对应一次真实失败）
```

详细 API 见 [API.md](API.md)，实测记录见 [docs/DEMO.md](docs/DEMO.md)，
踩过的坑见 [docs/implementation.md](docs/implementation.md)，
MoonBit 语法要点见 [MOONBIT-GUIDE.md](MOONBIT-GUIDE.md)。

## 背景资料

- IEEE 754-2008 — 浮点算术标准（binary16 §3.6、十进制组合字段 §3.5.2）
- Mike Cowlishaw, *A Summary of Densely Packed Decimal encoding* — DPD 布尔方程
- IBM/IEEE `dectest` 十进制测试套件 — 十进制侧的唯一权威
- Google bfloat16 规范 — TPU 的 bfloat16 定义

## License

Apache-2.0，见 [LICENSE](LICENSE)。
