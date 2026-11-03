# bitnum — 实现规格（v1）

> 本文件是实现的**契约**。实现必须逐条满足，测试必须逐条锁定。
> 位序按 IEEE 754-2008 §3.4：把整个编码视为无符号整数，最高位为符号位。

## 0. 范围与命名

```
src/
  bits.mbt        位级工具：取位段、组装、popcount、clz（内部）
  error.mbt       错误类型
  binary16.mbt    IEEE 754-2008 binary16（半精度）
  bfloat16.mbt    bfloat16（Google TPU 格式）
  decimal.mbt     十进制三元组 (sign, coefficient, exponent) + 渲染
  dpd.mbt         Densely Packed Decimal（3 数字 ↔ 10 位）
  decimal_wire.mbt decimal32/64/128 的组合字段 + DPD 线格式
  format.mbt      诊断用的字段分解与人类可读渲染（非往返依赖）
```

**范围内**：binary16、bfloat16、decimal32/64/128（**DPD 编码**）。
**明确不在范围内**：BID 编码。理由见 §4.5——`dectest` 官方套件里没有 BID 向量，
没有权威可对照的 BID 实现无法按本项目其它部分的同一标准验证，因此不做，
而不是做一个「看起来对但没被证明」的 BID。

## 1. 硬约束（违反即为缺陷）

1. **字节级往返**：对任意合法编码 `b`，`encode(decode(b)) == b`。覆盖两种零、
   次正规数、NaN payload、十进制非规范码。
2. **非规范输入不静默修正**：DPD 的 24 个冗余码、组合字段的非法值，`decode`
   必须按规范定义处理或报错，绝不自行「修正成最近的合法值」。
3. **不猜**：无法精确表示时返回显式错误，或按**显式声明的舍入模式**舍入并在
   结果里标记 `inexact`。两者不能混。
4. **不依赖外部数值实现**：不得 import `moonbitlang/x/decimal`。只用 core
   （`bigint` 允许，`Double::reinterpret_as_uint64` 允许）。
5. **权威向量是唯一基准**：十进制部分必须与 `examples/vectors-decimal.tsv`
   逐项一致。该表由 `scripts/decimal_ref.py` 独立生成，且该脚本对官方
   `dectest` 套件 568 条向量全绿（见 §6）。

## 2. binary16（IEEE 754-2008 §3.6）

布局：`s(1) e(5) m(10)`，bias 15。

| 条件 | 语义 |
|---|---|
| `e == 0, m == 0` | ±0 |
| `e == 0, m != 0` | 次正规，`(-1)^s × 2^-14 × (m / 2^10)` |
| `1 <= e <= 30` | 正规，`(-1)^s × 2^(e-15) × (1 + m/2^10)` |
| `e == 31, m == 0` | ±Infinity |
| `e == 31, m != 0` | NaN，`m` 最高位为 quiet 位 |

要求：
- `to_f64` / `of_f64(rounding)`，五种舍入：`NearestEven` / `NearestAway` /
  `TowardZero` / `TowardPositive` / `TowardNegative`。
- 溢出：`NearestEven` 超过最大有限值的一半间距 → ±Inf；`TowardZero` → ±max。
- NaN 传播：`of_f64` 遇 NaN 产 `0x7E00`（安静 NaN 默认 payload）；
  `decode` 保留原始 payload。
- **锚点**：`0x3C00 = 1.0`、`0x3555 ≈ 0.333251953125`、`0x0001 = 2^-24`、
  `0x7BFF = 65504`、`0x0400 = 2^-14`、`0x7C00 = +Inf`、`0xFC00 = -Inf`。

## 3. bfloat16

布局：`s(1) e(8) m(7)`，bias 127——即 binary32 的高 16 位。

要求：
- `of_f32_truncate`（截断）与 `of_f32_round(NearestEven)` 必须**显式区分**，
  截断最多带来 2^-8 相对误差。
- `to_f32` 精确（尾数零扩展）。
- **锚点**：`0x3F80 = 1.0`、`0x4000 = 2.0`、`0x7F80 = +Inf`、`0xFF80 = -Inf`、
  `0x7FC0 = 安静 NaN`、`0x0001 = 2^-133`。

## 4. 十进制

### 4.1 三元组

```
Decimal { negative : Bool, coefficient : BigInt, exponent : Int }
```

`coefficient >= 0`，符号独立，值 = `(-1)^negative × coef × 10^exp`。
**无 context、无隐式舍入**——这里 `Decimal` 只承载「精确的三元组」。

### 4.2 DPD（Cowlishaw 布尔式，IEEE 754-2008 Table 3.3）

每 3 个十进制位压进 10 位。实现必须用**布尔方程**而不是 1000 项查表，
以便逐位可审计：

```
p = b | (a&j) | (a&f&i)          a = (v&w) & (~s|t|~x)
q = c | (a&k) | (a&g&i)          b = p & (~v|~w|(s&~t&x))
r = d                            c = q & (~v|~w|(s&~t&x))
s = (f&(~a|~i))|(~a&e&j)|(e&i)   d = r
t = g | (~a&e&k) | (a&i)         e = v & ((~w&x)|(~t&x)|(s&x))
u = h                            f = (s&(~v|~x)) | (p&~s&t&v&w&x)
v = a | e | i                    g = (t&(~v|~x)) | (q&~s&t&w)
w = a | (e&i) | (~e&j)           h = u
x = e | (a&i) | (~a&k)           i = v & ((~w&~x)|(w&x&(s|t)))
y = m                            j = (~v&w)|(s&v&~w&x)|(p&w&(~x|(~s&~t)))
                                 k = (~v&x)|(t&~w&x)|(q&v&w&(~x|(~s&~t)))
                                 m = y
```

要求：
- `dpd_encode3(d1,d2,d3) -> UInt`（10 位）与 `dpd_decode3(bits) -> (Int,Int,Int)`。
- **1000 组合法输入穷举往返**；**24 个冗余码**必须按 §4.4 语义处理，不得 panic。

### 4.3 组合字段（IEEE 754-2008 §3.5.2）

```
G0G1G2G3G4
  G0G1 = 00|01|10  → 指数高 2 位 = G0G1，首位数字 = G2G3G4（0..7）
  G0G1 = 11        → 指数高 2 位 = G2G3，首位数字 = 8 + G4（8..9）
  11110            → Infinity
  11111            → NaN
```

容器几何（已由官方向量拟合确认，见 `scripts/fit_comb.py`）：

| 格式 | 总位 | 指数续 位 | 系数续 位 | 有效位 | bias |
|---|---|---|---|---|---|
| decimal32 | 32 | 6 | 20 | 7 | 101 |
| decimal64 | 64 | 8 | 50 | 16 | 398 |
| decimal128 | 128 | 12 | 110 | 34 | 6176 |

### 4.4 冗余 DPD 码

10 位有 1024 个组合，其中 24 个不是合法三元组的像。标准的处理是：解码时把它们
映射为**特定的 8/9 序列**（不是任意值，也不是报错）。`dectest` 的 `dsEncode` /
`ddEncode` / `dqEncode` 各有 24 条这样的用例，恰好对应。

要求：
- `decode` 接受这 24 个码并按 Cowlishaw 方程（§4.2 右列）解出确定的 8/9 序列。
- `encode`**永不产生**这 24 个码（布尔编码器的值域天然排除它们，加一条断言锁定）。

### 4.5 为什么没有 BID

`dectest` 的 `ddEncode` / `dqEncode` / `dsEncode` 只覆盖 DPD。官方套件中没有
BID 的字节向量。做一个 BID 解码器可以「跑通自测」，但无法像其它部分那样被
独立权威证明；按本仓库「交叉验证而非自证」的原则，宁可划出范围也不发未验证的东西。
如果将来拿到权威 BID 向量，再加。

## 5. 错误设计

```
pub(all) suberror BitnumError {
  DpdRedundantCodeAccepted(UInt, String)  // 记录：哪个码、解成什么
  CombinationInvalid(UInt)
  CoefficientTooLarge(Int, Int)           // 位数, 容器可容位数
  ExponentOutOfRange(Int, Int, Int)       // 值, min, max
  InexactConversion(String)               // 源→目标描述
  TruncatedInput(Int, Int)                // 需要字节, 实际字节
  NanPayloadTooLarge(Int, Int)            // payload 位宽, 容器可容位宽
}
```

错误必须携带**足够定位的信息**（哪个码、哪个范围），不能只给一句话。

## 6. 权威向量（必须逐项通过）

`examples/vectors-decimal.tsv`，568 条，字段：

```
format  hex  negative  coefficient  exponent  kind  source  original_text
```

来源：`scripts/decimal_ref.py` 解析官方 `dectest` 套件生成。该脚本的自检状态：

```
decimal32    dsEncode.decTest   exact= 123 noncanonical= 24 fail=  0
decimal64    ddEncode.decTest   exact= 189 noncanonical= 24 fail=  0
decimal128   dqEncode.decTest   exact= 184 noncanonical= 24 fail=  0
DPD triple round-trip failures: 0 / 1000
```

MoonBit 侧必须对同一张表全绿，并额外断言「非规范码被解成与参考相同的 8/9 序列」。

## 7. CLI（`cmd/bitnum`）

```
bitnum value <format> <hexbytes>        # 字节 → 字段分解 + 数值
bitnum bits  <format> <value>           # 人类表达式 → 十六进制字节
bitnum table <format>                   # 边界值表
bitnum check <format> <hexbytes>        # 往返校验
```

`format ∈ {binary16, bfloat16, decimal32, decimal64, decimal128}`

`value` 必须输出**字段分解**而不只是数值：

```
$ bitnum value binary16 0001
sign=0  exponent=0 (subnormal)  significand=1
kind=finite  value=5.960464477539063e-08   (2^-24)

$ bitnum value decimal64 A2300000000003D0
sign=1  exponent=-2  coefficient=750
kind=finite  value=-7.50
```

`check` 不往返时退出码 1。

## 8. 测试要求

- binary16：全部 **65536** 个位模式 `decode → encode` 逐字节恒等（必做，很快）
- bfloat16：全部 **65536** 个位模式，`to_f32` 与 `f32` 高 16 位一致
- DPD：1000 合法三元组穷举往返 + 24 冗余码语义 + 编码器值域断言
- 十进制：`vectors-decimal.tsv` 568 条逐项（decode 侧 + 能表示的 encode 侧）
- 舍入：5 种模式 × 一组代表向量逐项断言
- 每个错误分支至少一条测试