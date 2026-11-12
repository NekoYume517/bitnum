# bitnum — API 契约

> 本文件记录的是**实际存在的**公开 API。签名逐条取自 `src/pkg.generated.mbti`
> （`moon info` 生成），不是设计稿。要复核：`moon info` 后看 `src/pkg.generated.mbti`。

模块名：`NekoYume517/bitnum`，库包：`src`，CLI 包：`cmd/bitnum`。

## 0. 全局约定

**不猜。** 无法精确表示时，要么返回带定位信息的错误，要么按**显式传入的**舍入模式
舍入并把结果标成 `inexact`。这两种结果不混用（PLAN.md §1.3）。

**位序按 IEEE 754-2008 §3.4**：整个编码视为无符号整数，最高位为符号位。

**不含 `moonbitlang/x/decimal`**：十进制三元组用 core 的 `BigInt` 自己实现
（PLAN.md §1.4）。

**BID 编码不在范围内**，理由见 PLAN.md §4.5，本文不提供相关 API。

## 1. 公共词汇 `src/bits.mbt`

```moonbit
pub(all) enum RoundingMode {
  NearestEven      // 就近，平局取偶
  NearestAway      // 就近，平局远离零
  TowardZero
  TowardPositive
  TowardNegative
} derive(Eq, Debug)

pub(all) enum FloatClass { Zero; Subnormal; Normal; Infinity; Nan } derive(Eq, Debug)
pub fn FloatClass::label(Self) -> String        // "zero" / "subnormal" / ...

pub(all) struct FloatConversion {
  bits : UInt16      // 结果位模式
  inexact : Bool     // 源值是否被舍入
} derive(Eq, Debug)

pub fn datum_class_label(FloatClass) -> String  // IEEE §2.1.3 粗分类："finite" / "infinity" / "nan"
```

`FloatClass` 与 `datum_class_label` **同时存在且都不多余**：前者区分次正规数与正规数，
后者是标准 §2.1.3 的 *class*（zero / subnormal / normal 统称 finite）。CLI 两处都打印 ——
`kind=finite` 配指数行的 `(subnormal)`。

位工具（公开供审计，不是内部函数）：

```moonbit
pub fn popcount64(UInt64) -> Int
pub fn clz64(UInt64) -> Int              // 零返回 64，故 bit_length64(0) == 0
pub fn bit_length64(UInt64) -> Int
pub fn low_mask64(Int) -> UInt64         // n<=0 → 0，n>=64 → 全 1（容器极限，不是钳制）
pub fn pow2_exact(Int) -> Double         // 精确折半/倍增，不用 @math.pow
pub fn bit_length_big(BigInt) -> Int
pub fn big_slice(BigInt, Int, Int) -> BigInt
pub fn big_splice(BigInt, BigInt, Int) -> BigInt
pub fn digit_count_big(BigInt) -> Int
pub fn zero_of_sign(Bool) -> Double
pub fn infinity_double() -> Double
pub fn quiet_nan_double() -> Double
```

`pow2_exact` 用精确折半构建，因为 libm 的 `pow` 只保证 1 ulp 内准确 —— 那个精度不足以
声称 65536 项 binary16 表精确。

## 2. binary16 `src/binary16.mbt`

```moonbit
pub let binary16_patterns : Int = 65536
pub let binary16_exp_bits : Int = 5
pub let binary16_sig_bits : Int = 10
pub let binary16_bias : Int = 15

pub(all) struct Binary16 {
  sign : Int           // 原始符号位
  exponent : Int       // 原始 5 位指数域，0..31，**不是**减过 bias 的
  significand : Int    // 原始 10 位尾数域
  kind : FloatClass
} derive(Eq, Debug)

pub fn Binary16::decode(UInt16) -> Binary16     // 全 65536 输入无 panic
pub fn Binary16::encode(Binary16) -> UInt16     // 唯一编码器，故往返按构造成立
pub fn Binary16::bits(Binary16) -> UInt16
pub fn Binary16::to_f64(Binary16) -> Double     // 对每个位模式精确
pub fn of_f64(Double, RoundingMode) -> FloatConversion raise BitnumError

pub fn Binary16::is_special(Binary16) -> Bool
pub fn Binary16::is_quiet_nan(Binary16) -> Bool
pub fn Binary16::nan_payload(Binary16) -> Int
```

解码器**总是**报告存储的原始域，不把指数规范化。这是 `kind` 保持诚实的原因：
一次解码不会凭空造出一个正规化指数。

`of_f64` 的溢出规则（PLAN.md §2）：就近模式 → ±Inf；`TowardZero` → ±max。
`Towards...` 定向模式只有在方向指向远离零时才溢出到 Inf。

**下溢端对称（BN-B1，修复自 2026-11-10 审计）**：`|x| < 2^-35` 时（含**全部**
binary64 次正规数）舍入位移 ≥ 64 位，四种向内的情形落带符号的零，
`TowardPositive` 遇到正值、`TowardNegative` 遇到负值则落到**该符号的最小次正规数**
`0x0001` / `0x8001`（IEEE 754-2008 §4.3.3：非同值向外舍入即最小次正规数）。
五种模式一律标 `inexact`。分界正好在 `2^-35` / `2^-36` 之间，向量表两侧都钉住。

**NaN 的不对称（有测试锁定，不是遗漏）**：`decode → encode` 保留 10 位 payload；
`decode → to_f64 → of_f64` 不能，binary64 的 52 位 payload 塞不进 10 位，所以
`of_f64` 按 PLAN.md §2 产出规范安静 NaN `0x7E00`（保留符号）并标 `inexact`。
65536 个模式里只有 2 个（两个规范安静 NaN）是这条路径的不动点。

## 3. bfloat16 `src/bfloat16.mbt`

```moonbit
pub let bfloat16_patterns : Int = 65536
pub let bfloat16_exp_bits : Int = 8
pub let bfloat16_sig_bits : Int = 7
pub let bfloat16_bias : Int = 127

pub(all) struct BFloat16 { sign; exponent; significand; kind : FloatClass }

pub fn BFloat16::decode(UInt16) -> BFloat16
pub fn BFloat16::encode(BFloat16) -> UInt16
pub fn BFloat16::bits(BFloat16) -> UInt16
pub fn BFloat16::to_f32(BFloat16) -> Float        // 精确：尾数零扩展
pub fn BFloat16::to_f64(BFloat16) -> Double

pub fn of_f32_truncate(Float) -> UInt16                          // 截断，丢弃低 16 位
pub fn of_f32(Float, RoundingMode) -> FloatConversion            // 显式舍入
pub fn of_f32_round(Float) -> FloatConversion                    // = of_f32(_, NearestEven)
pub fn truncate_round_differ(Float) -> Bool                     // 两者是否分歧
```

`of_f32_truncate` 与 `of_f32` 是**两个不同的函数**，不是同一个加了开关：
截断最多 2^-8 相对误差，就近舍入是一半。它们分别有名字，调用方不会误取。

截断对 NaN 的类保持：若 NaN 的 payload 全落在被丢弃的低 16 位，
截断会把 NaN 变成 Inf —— 那是截断唯一能改变数据类的地方，必须防止。
所以判定基于**源值**（`exp == 0xFF && mantissa != 0`），不是截断后的模式：
截断后的模式里 Inf 和 payload 耗尽的 NaN 都显示 `sig == 0`，分不开。

**bfloat16 没有 binary64 直连入口，这是有意的**（BN-B12，补声明自 2026-11-10 审计）。
库只提供 binary32 → bfloat16（`of_f32` / `of_f32_truncate`），所以
`Double → bfloat16` 必然经过 `Double → Float` 这一步，而这一步是**平台转换**、
不在本包内。于是 CLI 的 `bits bfloat16` 是 `double → float → bf16` 的**双舍入**，
与 `double → bf16` 一次舍到 8 位有效数字在边界情形下可能不同。
`of_f32` 本身是单舍入且已被 5 种模式 × 向量表覆盖；双舍入只出现在 CLI 这条
由两段组成的路径上，属于已声明的简化（另见 docs/implementation.md §10），
不是未发现的缺陷。要用单舍入，调用方拿到的应该是 binary32 而非 binary64。

## 4. 十进制三元组 `src/decimal.mbt`

```moonbit
pub(all) enum DecimalKind { DFinite; DInfinity; DNan; DSignalingNan } derive(Eq, Debug)
pub fn DecimalKind::label(Self) -> String

pub(all) struct Decimal {
  negative : Bool
  coefficient : BigInt     // >= 0；符号独立
  exponent : Int
  kind : DecimalKind
} derive(Eq, Debug)

pub fn Decimal::make(Bool, BigInt, Int) -> Decimal raise BitnumError   // 拒绝负系数
pub fn Decimal::zero(Bool, Int) -> Decimal
pub fn Decimal::infinity(Bool) -> Decimal
pub fn Decimal::nan(Bool, BigInt) -> Decimal

pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool     // 符号位，不是"小于零"
pub fn Decimal::digit_count(Self) -> Int
pub fn Decimal::adjusted_exponent(Self) -> Int64     // 需要 33 位，见下
pub fn Decimal::to_scientific_string(Self) -> String

pub fn parse_decimal(StringView) -> Decimal raise BitnumError
pub fn numerically_equal(Decimal, Decimal) -> Bool
```

`adjusted_exponent` 返回 `Int64`，不是 `Int`：它是 `exponent + digits - 1`，而
容器容纳任意 `Int32` 指数与最多 34 位系数，所以这个和需要 33 位。用 `Int`（32 位）
计算会把 `parse_decimal("10e2147483647")` 的调整指数 `2147483648` 绕成
`-2147483648`，于是它与 `1e-2147483648` 被判为「数值相等」，渲染成
`1.0E-2147483648`。格式自身的指数范围（90 / 369 / 6111）离这个边界很远，
所以任何只在格式域内取值的测试都看不见它。

变体名带 `D` 前缀（`DInfinity`、`DNan`）是因为它们和 `FloatClass` 的
`Infinity`/`Nan` 同包，不限定就是歧义。

`Decimal` **只承载精确三元组**：无 context、无 preferred exponent、无隐式舍入
（PLAN.md §4.1）。系数是 `BigInt`，因为 decimal128 有 34 位，窄化成 64 位会让格式无法实现。

`to_scientific_string` 是标准 §5.12.1 的 to-scientific-string：`exponent <= 0` 且
`adjusted >= -6` 用普通记数法，否则科学记数法。边界正好在 `-6`：
`-0.00000750`（adjusted -6）是普通形式，`-7.50E-7`（adjusted -7）是科学形式。
568 条向量的 `original_text` 列逐字符锁定这一点。

`parse_decimal` **故意不接受** `NaN` / `Infinity`（那不是数字，由 wire 层从字段构造，
或由 `Decimal::infinity` / `Decimal::nan` 构造），也不接受十六进制、下划线、空白。
一个比文法更宽容的解析器会让调用方错误和解码器缺陷无法区分。

`numerically_equal` 忽略尾随零填充（`1.0` 与 `1.00` 数值相等）但**不**忽略符号或指数。
标准把 `1.0` 和 `1.00` 当作不同三元组，本包也保持这个区分，所以两个比较函数都存在，
没有一个叫裸 `equal`。

## 5. DPD `src/dpd.mbt`

```moonbit
pub let dpd_redundant_codes : Array[Int]      // 24 个，升序

pub fn dpd_encode3(Int, Int, Int) -> Int                       // 10 位
pub fn dpd_decode3(Int) -> (Int, Int, Int)                      // 全 1024 输入无 panic
pub fn dpd_decode3_checked(Int) -> (Int, Int, Int, Bool)        // 第 4 项 = 是否冗余
pub fn dpd_is_canonical(Int) -> Bool
pub fn dpd_triple_text(Int) -> String                           // "8,8,8"
```

用 **Cowlishaw 布尔方程**，不是 1000 项查表（PLAN.md §4.2）。理由是可审计性：
方程能逐行对照标准表格，查表只能和另一张表对差。

**24 个冗余码被接受，不是错误**（PLAN.md §4.4）。10 位有 1024 种组合，只有 1000 是三元组的像。
标准把多出来的 24 个解码成固定的 8/9 序列，官方 `dectest` 的编码套件里每个格式正好有
24 条这样的用例。所以 `dpd_decode3` 接受它们；`dpd_encode3` 永远产生不了它们
（穷举 1000 个输入锁定了注入性）。

## 6. 线格式 `src/decimal_wire.mbt`

```moonbit
pub(all) enum DecimalFormat { Decimal32; Decimal64; Decimal128 } derive(Eq, Debug)

// 几何（编译器算出来的派生量，不是硬编码的第二份表）
pub fn DecimalFormat::bits(Self) -> Int
pub fn DecimalFormat::byte_width(Self) -> Int
pub fn DecimalFormat::exp_cont_bits(Self) -> Int
pub fn DecimalFormat::coef_cont_bits(Self) -> Int      // = bits - 1 - 5 - exp_cont
pub fn DecimalFormat::digits(Self) -> Int
pub fn DecimalFormat::bias(Self) -> Int
pub fn DecimalFormat::name(Self) -> String

// 指数范围
pub fn DecimalFormat::biased_exponent_field_max(Self) -> Int   // 2^(exp_cont+2)-1：域容量
pub fn DecimalFormat::biased_exponent_max(Self) -> Int         // Emax+bias：合法上限
pub fn DecimalFormat::emax(Self) -> Int                        // 96 / 384 / 6144
pub fn DecimalFormat::emin(Self) -> Int                        // -95 / -383 / -6143
pub fn DecimalFormat::etin_y(Self) -> Int                      // -101 / -398 / -6176
pub fn DecimalFormat::emax_top(Self) -> Int                    // 90 / 369 / 6111
pub fn DecimalFormat::max_exponent_for(Self, BigInt) -> Int
pub fn DecimalFormat::nan_payload_bits(Self) -> Int
pub fn DecimalFormat::geometry_is_consistent(Self) -> Bool      // 自检，测试调用

// 编解码
pub(all) struct DecodedDecimal {
  value : Decimal
  redundant_groups : Int      // 有几个系数分组是非规范 DPD 码
} derive(Eq, Debug)

pub fn DecimalFormat::decode_raw(Self, BigInt) -> DecodedDecimal raise BitnumError
pub fn DecimalFormat::encode_raw(Self, Decimal) -> BigInt raise BitnumError
pub fn DecimalFormat::decode_bytes(Self, Bytes) -> DecodedDecimal raise BitnumError
pub fn DecimalFormat::encode_bytes(Self, Decimal) -> Bytes raise BitnumError
pub fn DecimalFormat::to_hex(Self, BigInt) -> String
pub fn DecimalFormat::from_hex(Self, String) -> BigInt raise BitnumError
pub fn DecimalFormat::hex_width(Self) -> Int
```

**`decode_raw` / `encode_raw` 的容器约定**：`raw` 是 BigInt，右对齐在低 `bits` 位。
高出的位置被**拒绝**（`TruncatedInput`），不截断。一个约定服务三种格式，不用三份位运算。

**`from_hex` 要求精确宽度**（BN-2/P2，修复自 2026-11-04 审计）：长度 ≠ `hex_width()`
一律 `TruncatedInput(width, got)`，**不补前导零**。理由：十六进制串是字节串的拼写，
短一个字符就是短一个字节。

```
A2300000000003D    (15 位，漏掉末位)  -> 拒绝，不解读为 0A2300000000003D
A2300000000003D0   (16 位，正确)      -> 正常解析
```

修复前只拒「比格式宽」，于是漏一位的输入被右对齐成完全不同的数、退出 0 —— 而
`decode_bytes` 对短 buffer 早就报 `TruncatedInput`，同一个错误形态在两个入口不一致。
补零会让上面那个手误变成「有意义」，正是 PLAN.md §1.2 禁止的静默修正。

**`decode_bytes` 现在同样要求精确宽度**（BN-B13，2026-11-11 审计）：修复前它只判
`got < needed`，9 字节的 buffer 会被当成 decimal64 —— 前 8 字节解出一个值，尾部
垃圾无声丢弃。这与 `from_hex` 对超长串的处理正好相反，而两个入口处理的本来就是
同一份输入。现在两边都报 `TruncatedInput(width, got)`：**多出来的字节不是填充**，
和漏一个字节一样，都是「这不是一个 decimal64」。

CLI 层把 `TruncatedInput` 翻译成十六进制术语：`decimal64 is 16 hex digits, got 15`。
库的措辞按字节计（`decode_bytes` 需要字节），CLI 的按 hex 字符计 —— 在边界翻译，
两边都不说错单位。

**两个指数上限同时生效，取小者** —— 这是全项目最容易搞错的一处：

| 上限 | 依据 | 效果 |
|---|---|---|
| `adjusted <= Emax` | 标准：调整指数不得超过 Emax | 七位系数在 `99...9` 时指数 ≤ 90 |
| `exp_top <= 2` | 组合字段 `00/01/10` 只有 2 位；`11` 分支里 `exp_top == 3` 会撞 `11110`/`11111`（Inf/NaN） | 指数 ≤ `Emax_top` = 90 / 369 / 6111 |

两者在满精度处**恰好重合**（`Emax - (p-1) == Emax_top`），这就是格式自洽的地方：
要够到 `Emax` 必须有 p 位有效数字，而那 p 位已经把指数压到组合字段放得下的位置。
低于满精度时组合字段上限赢 —— 所以 `dectest` 把 `0e+10000` 钳到
`0E+90 / 0E+369 / 0E+6111`，而不是钳到 `Emax`。

**NaN 布局是二进制直觉的反面**。NaN 时组合字段是 `11111`，其下一位是 **signaling 标志**
（`0` = quiet），再往下才是诊断 payload。`ddEncode.decTest` 直接钉死：

```
0x7c00000000000000 -> NaN       （signaling 位为 0）
0x7e00000000000000 -> sNaN      （signaling 位为 1）
```

二进制格式里安静位是**置位**的那个，照类比推出一个"看起来对"的 payload 在这里是错的。

**Infinity 是 `11110` 开头的整个族**，不是只有 `0x78`。`dsEncode.decTest` 里
`0x78 / 0x79 / 0x7a / 0x7b` 全是 Infinity，因为组合字段为 `11110` 时指数续域被忽略。
只认 `0x78` 的解码器会拒掉合法编码，而纯有限值的往返测试发现不了这个。

## 7. 渲染 `src/format.mbt`

```moonbit
pub fn describe_binary16(UInt16) -> String
pub fn describe_bfloat16(UInt16) -> String
pub fn describe_decimal(DecimalFormat, BigInt) -> String raise BitnumError
pub fn format_double(Double) -> String
pub fn binary16_value_text(UInt16) -> String
pub fn bfloat16_value_text(UInt16) -> String
pub fn pad_left(String, Int) -> String
pub fn pad_right(String, Int) -> String
```

这一层只服务诊断：编解码器不依赖它，任何往返声明也不建立在它上面（PLAN.md §0）。
它存在的理由是让 `bitnum value` 能打印**为什么**一个模式是这个值，而不只是那个数。

## 8. 错误 `src/error.mbt`

```moonbit
pub(all) suberror BitnumError {
  DpdRedundantCodeAccepted(UInt, String)    // 哪个码、解成什么
  CombinationInvalid(UInt)
  CoefficientTooLarge(Int, Int)             // 位数, 容器可容位数
  ExponentOutOfRange(Int, Int, Int)         // 偏置指数域：值, min, max
  UnbiasedExponentOutOfRange(Int64, Int64, Int64)  // 真指数：值, min, max
  InexactConversion(String)                 // 语义类：源→目标描述
  UnparsableInput(String, String)           // 词法类：原文本, 拒绝原因
  TruncatedInput(Int, Int)                  // 需要, 实际
  NanPayloadTooLarge(Int, Int)              // payload 位宽, 容器容量
  DpdDigitGroupMisaligned(Int)              // 分组长度不是 3 的倍数
} derive(Debug)

pub fn BitnumError::describe(Self) -> String   // CLI 用的措辞，库和 CLI 不会漂移
```

每条都携带**足够定位的信息**（哪个码、哪个范围、需要多少字节），不是一句话。
`DpdDigitGroupMisaligned` 是对 PLAN.md §5 的追加，与 copybook 的
`RecordRemainder` 同类 —— 属于补充而非签名变更。

**两个指数变体不是重复**（BN-B5，修复自 2026-11-10 审计）。编码器守两道独立的门：

| 变体 | 检查的是什么 | 措辞 |
|---|---|---|
| `ExponentOutOfRange` | **偏置**指数域 `[0, Emax+bias]` | `biased exponent 198 out of range [0, 197]` |
| `UnbiasedExponentOutOfRange` | **真**指数 `[Etiny, Emax_top]`（按位数收紧） | `exponent 96 out of range [-101, 90]` |

共用一句 `biased exponent …` 会让第二道门印出 `biased exponent 96 out of range
[-101, 90]` —— 一个不是偏置指数的数，配一组真指数的界，读者无法判断到底哪个量越界。
`UnbiasedExponentOutOfRange` 的字段是 `Int64`：`parse_decimal` 的代数和可以合法超出
`Int32`（`0.01e-2147483647` 要的是 `-2147483649`），把报告窄化回 `Int32` 会把真指数
回绕成另一个看起来正常的数（BN-B3）。

**幅度连 `Int64` 都装不下时，这条路径报告饱和值**（2026-11-12 审计，C1）：
`1e99999999999999999999999999` 这类输入的指数位串本身超界，`digits_to_int64` 的
守卫不再报「已扫描前缀 + 界 `[0, 2147483647]`」，而是报告
`Int64::MAX`（正号）或 `Int64::MIN`（负号）—— **符号与输入一致**、界固定为容器的
真实界 `[-2147483648, 2147483647]`：

```
exponent 9223372036854775807 out of range [-2147483648, 2147483647]     # 1e999…
exponent -9223372036854775808 out of range [-2147483648, 2147483647]    # 1e-999…
```

饱和是「程度」的诚实表达（输入远超容器），也不会由回绕铸出一个数。旧措辞既没说
容器界，锁它的用例又只断言「消息里没有减号」—— 一个代理断言，它同时禁掉了负数
下界（`[-2147483648, …]`），属于用代理测真意图。

**词法拒绝与语义拒绝是两句话**（BN-B9，修复自 2026-11-10 审计）：

| 变体 | 用在 | 措辞 |
|---|---|---|
| `UnparsableInput` | 语法读不出来的文本（`nan`、`1.2.3`、`+`）与非 hex 字符 | `cannot parse '1.2.3': more than one decimal point` |
| `InexactConversion` | 值看得懂、容器装不下（负系数等） | `cannot represent … exactly` |

两者原先共用 `cannot represent … exactly` 外壳，于是语法错误被说成「没能精确表示」，
得到 `cannot represent no digits in nan exactly`、`cannot represent more than one
decimal point: 1.2.3 exactly` 这类既不成立也读不通的句子。`UnparsableInput` 的第二个
字段是拒绝原因（`no digits` / `sign with no digits` / …），整句由 `describe()` 组织，
所以没有任何片段需要充当某个句子的语法成分。

## 9. CLI `cmd/bitnum/main.mbt`

```
bitnum value <format> <hexbytes>    # 字节 → 字段分解 + 数值
bitnum bits  <format> <value>       # 人类表达式 → 十六进制字节
bitnum table <format>               # 边界值表
bitnum check <format> <hexbytes>    # 往返校验
```

`format ∈ {binary16, bfloat16, decimal32, decimal64, decimal128}`
退出码：0 成功 / 1 数据错误 / 2 用法错误。

`bits` 对二进制格式走**最近偶数舍入**，并在结果被舍入时向 stderr 打一条说明
（stdout 保持干净，可管道）。十进制侧不舍入：`1.23` 精确编码成系数 123、指数 -2。

**`bits` 的非法字面量必须报错**（BN-1/P1，修复自 2026-11-04 审计）：

| 输入 | exit | stderr | 说明 |
|---|---|---|---|
| 语法错（`xyz`、`1.2.3`、`1e`、空串） | **1** | `bitnum: not a number: '<原文本>'` | 数据错误，与 `decimal` 分支口径一致；绝不静默换成 `+0`（PLAN.md §1.2） |
| 溢出（`1e999`、`1e309`） | **0** | `bitnum: note: '<原文本>' is too large for binary64; rounded to infinity (inexact)` | IEEE 754 §7.4：就近舍入溢出到 ±Inf，故 stdout 给 `7C00`/`FC00`（bfloat16 是 `7F80`/`FF80`） |
| bfloat16 二级溢出（`1e39`、`3.5e38`） | **0** | `bitnum: note: '<原文本>' is too large for binary32; rounded to infinity (inexact)` | bfloat16 是 binary32 的高半，`Double → Float` 先溢出；那一步在 `of_f32` 的 `inexact` 之外（f32 无穷转 bf16 无穷是精确的），所以单独判定（BN-B4） |
| 低于 binary64 的非零字面量（`1e-999`） | **0** | `bitnum: note: '<原文本>' is too small for binary64; rounded to zero (inexact)` | 舍入发生在 `parse_double` 内部，编解码器收到的已经是精确的零，旗标无从报告（BN-B10） |

区分这两种是修复的核心：`strconv.parse_double` 对二者都 raise `Failure`，但
`"value out of range"` 是**合法的数**、`"invalid syntax"` 是**不是数**。把两者一并折成
`+0` 会同时违反 PLAN.md §1.2（静默修正）和 §1.3（不猜）。溢出值沿用原字面量的符号，
从文本首字符读，因为此时没有已解析的值可读。

**bfloat16 的说明有两种**（BN-B4，修复自 2026-11-10 审计）：它是唯一经过
`double → float → bf16` 两次窄化的格式，而且第一次窄化的溢出对编解码器不可见 ——
f32 的无穷转成 bf16 的无穷是**精确**的，`of_f32.inexact` 因此为 `false`。
修复前 `1e39` 输出 `7F80`、stderr 空、exit 0，与 `1e999` 的完整说明不一致。
现在按第一次窄化的**实际结果**判定（不是按量级阈值：就近舍入会把略高于
`0x7F7FFFFF` 的值仍舍回它，阈值比较在那个点上是错的），说明中写
`binary32` 而不是 `binary64`，因为越界的是第二级容器。`inf` / `nan` 不走这条说明。

**两条 `bits` 路径的词法来源不同，接受集也不同**（BN-B11，补全自 2026-11-10 审计）。
这不是疏漏，是两套真实存在的记法：

| | 二进制格式（`binary16` / `bfloat16`） | 十进制格式（`decimal32/64/128`） |
|---|---|---|
| 词法来源 | core `strconv.parse_double` + 几个特殊值拼写 | 本包的 `parse_decimal`（IEEE 754 §5.12 的 *to-number* 形式） |
| 特殊值 | ✅ `nan` / `inf` 族（见下） | ❌ 一律拒绝：`NaN` / `Infinity` 不是数字，由 wire 层从字段构造 |
| 数字分隔符 `_` | ✅ `1_000`、`1_0e1`、`000_1`、`1e1_0` | ❌ `1_000` → `cannot parse '1_000': junk after the number` |
| 大小写 | ✅ 不敏感：`NAN`、`Inf`、`INFINITY`、`InFiNiTy` | n/a（不认特殊值） |
| 前导 `+` / 裸 `.5` / `5.` | ✅ `.5`、`5.`、`+.5`、`-.5`、`00012` | ✅ 同样接受（`0.5` 记法一致） |
| 十六进制 / 空白 / 逗号 | ❌ `0x10`、`0X10`、`  1.0`、`1.0 `、`1,000` | ❌ 同样拒绝 |

二进制侧实际接受的**特殊值拼写全集**（大小写不敏感，可带正负号）：

```
nan  NaN  NAN  +nan  -nan      -> 规范安静 NaN（binary16 0x7E00 / bfloat16 0x7FC0）
inf  Inf  INF  infinity  Infinity  INFINITY   -> 同符号的无穷
```

带 `+` / `-` 前缀都接受（`+inf`、`-Infinity`、`-nan`）。**不接受** `nan(payload)`、
`snan`、`infi` 这类扩展拼写 —— 它们不是数字，按语法错退出 1。
`nan` 转 binary16 会带 `rounded (inexact)` 说明，因为 binary16 装不下 binary64 的
payload；`inf` / `Infinity` 精确，无说明。

注意 `-nan` 的**符号会被丢掉**（得 `0x7E00` 而非 `0xFE00`）：符号前缀由 CLI 交给
core 的 `parse_double`，而它在解析时就丢弃了 NaN 的符号位。这是当前实测行为，
`lexical_wbtest.mbt` 按现状锁定；`±Infinity` 不受影响（符号自己解析）。

该接受集由 `cmd/bitnum/lexical_wbtest.mbt` 逐条锁定（接受 / 拒绝各一组断言），
防止任一侧词法器改动后文档再次飘移。

**下溢端与上溢端对称**（BN-B10，修复自 2026-11-10 审计）：`1e-999` 量级低于 binary64
的最小次正规数（`5e-324`），因此**解析阶段**就舍成零，编解码器拿到的已是精确零 ——
`inexact` 旗标此时无话可说，修复前它输出 `0000`、exit 0、stderr 空，与 `bits binary16 0`
完全一样。现在按字面量判定：**含非零数字**的字面量补
`'<原文本>' is too small for binary64; rounded to zero (inexact)`；真正表示零的
（`0`、`0.0`、`-0`、`+0`、`0e-999`）保持静默，因为它们的零是精确的。
`1e-320` 这类可表示的 binary64 次正规数仍走 `rounded (inexact)` —— 两个下溢诊断
发生的位置不同，措辞也不同。

`check` 在非规范 DPD 输入上退出 1 —— 那是**合法但无规范形式**的输入，
编码器的值域天然排除那 24 个码。它被单独说明，而不是折进"静默通过"。

**Infinity 族也单独说明**（BN-B2，修复自 2026-11-10 审计）：`check decimal32 79000000`
（以及 `7A` / `7B`、decimal64 的 `7880000000000000`、decimal128 同族）解码合法、
值仍是 Infinity，但重编码只写规范形式 `0x78`，所以字节不同。这不是缺陷 ——
组合字段为 `11110` 时其下各位不承载值（API.md §6 正是靠这一点接受这个族），
编码器写回无关位没有定义的结果。`check` 因此给出 `result: infinity family — …`
并**保持退出码 1**（契约仍是「字节恒等」，这一点没变），再打印 `value` 行确认
数值确实往返。PLAN.md §1.1 的字节恒等约束同步豁免这一族。