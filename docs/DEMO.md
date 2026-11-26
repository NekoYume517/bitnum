# bitnum 实测记录

> 本文件里的每一条输出都是**实际跑出来的**，命令在代码块第一行，输出紧随其后。
> 没有任何一行是手写的。要复核任意一条，复制 `$` 开头的命令在仓库根目录执行即可。
>
> 环境：
> ```
> $env:MOON_HOME="D:\code\moonbit\audit\toolchain\x"; $env:Path="D:\code\moonbit\audit\toolchain\x\bin;"+$env:Path
> moon 0.1.20261102 (ea07287 2026-11-02)
> moonc v0.10.19+bee578715 (2026-11-02)
> ```

## 0. 门禁

```
$ moon check
Finished. moon: ran 1 task, now up to date

$ moon test
Total tests: 201, passed: 201, failed: 0.

$ moon build --target wasm
Artifacts:
Finished. moon: no work to do

$ moon fmt
Finished. moon: ran 31 tasks, now up to date

$ moon fmt --check
Finished. moon: ran 31 tasks, now up to date
```

（`ran N tasks` 里的数字随缓存状态变化：全新 clone 上是几十个任务，增量时是 `no work
to do`。这里记的是本轮收尾那次运行的真实输出。）

**`moon fmt --check` 必须先跑一次 `moon fmt`**，顺序不能反。`--check` 的实现是把源码
和 `_build/<target>/release/format/` 下的格式化副本做 `git diff --no-index`；
如果那个目录还不存在（全新 clone、或刚删过 `_build`），它就直接失败：

```
$ moon fmt --check        # 在干净的 _build 上
error: open("...\_build\wasm-gc\release\format\src\decimal_wire.mbt"): No such file or directory
Error: failed when formatting project
```

这不是「格式不对」，是产物目录缺失。先 `moon fmt` 生成副本，再 `--check` 就正常。
CI 里如果只写 `moon fmt --check`，在 fresh runner 上会假红。

## 1. 权威向量

十进制部分的 568 条向量由 `scripts/decimal_ref.py` 生成，该脚本对官方
IBM/IEEE `dectest` 套件全绿：

```
$ python scripts/decimal_ref.py
decimal32    dsEncode.decTest   exact= 123 noncanonical= 24 fail=  0
decimal64    ddEncode.decTest   exact= 189 noncanonical= 24 fail=  0
decimal128   dqEncode.decTest   exact= 184 noncanonical= 24 fail=  0
DPD triple round-trip failures: 0 / 1000
```

`exact` 是编码器逐字节复现的行数，`noncanonical` 是必须接受、但编码器永不产生的
24 个冗余 DPD 码（每个格式 24 条），`fail` 为零。这三行是十进制侧**有限值编码**的正确性依据；Infinity / NaN / sNaN 没有向量行
（表里 568 行全是有限值），它们由 `decimal_wire_test.mbt` 的手写用例锁定，依据见
README「向量表覆盖什么、不覆盖什么」。

二进制侧的向量由 `scripts/float_ref.py` 生成，它是精确整数运算，**并与两个独立实现交叉核对**：

```
$ python scripts/float_ref.py
numpy cross-check (nearest_even): compared=19988 mismatch=0
torch cross-check (bf16 nearest_even): compared=4973 mismatch=0
wrote examples\vectors-binary16.tsv (990 rows)
```

- `numpy` 的 `float16` 走的是平台自己的 IEEE 转换，19988 条随机 binary64 输入**逐位一致**。
- `torch` 的 `bfloat16`（Google TPU 格式的原产地）4973 条**逐位一致**。

两点独立实现 + 一个精确整数参考，三者吻合。这不是自证。

## 2. `bitnum value` — 字段分解

PLAN.md §7 给的两条示例输出，逐字符吻合（第二条在这里；`sNaN` 那条的 payload
拼写在下面）：

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

其余几个边界：

```
$ bitnum value binary16 3C00
sign=0  exponent=15 (normal)  significand=0
kind=finite  value=1   (2^0)
```

```
$ bitnum value binary16 7C00
sign=0  exponent=31 (infinity)  significand=0
kind=infinity  value=Infinity   (infinity)
```

```
$ bitnum value bfloat16 7FC0
sign=0  exponent=255 (nan)  significand=64
kind=nan  value=NaN
```

```
$ bitnum value decimal32 7F7FFFFF
sign=0  payload=25165823
kind=signaling-nan  value=sNaN999999
```

`payload` 是续域那 20 位（`25165823`），`value` 里的是同一组位按 DPD 三数字分组
读出来的结果（`999999`）—— 两者是同一个量的两种拼写。这一行曾经印成裸
`value=sNaN`：渲染走的是**无宽度**入口，而 payload 的十进制拼写需要格式的字段宽度
（BN-18-1 修的就是这处，`2d14142`）；当时本文这段没跟着重跑，反而留下了「两条示例
逐字符吻合」的旧断言。现在 `cmd/bitnum/demo_replay_wbtest.mbt` 把本文全部 48 条
`$ bitnum …` 块逐行对拍，这一行再漂移会直接红。

Infinity 没有诊断 payload，所以第一行只有符号；payload 行专属于 NaN / sNaN：

```
$ bitnum value decimal32 78000000
sign=0
kind=infinity  value=Infinity
```

`value` 行的注释集与符号在两种二进制格式上逐项一致（2026-11-15 统一口径）：
bfloat16 的 -0 与 ±Infinity 现在也带 binary16 同款注释，负 NaN 的 value 行
渲染 `-NaN`，与十进制侧的 `-NaN` / `-sNaN` 同口径——修复前 bfloat16 打
`value=0` 且无注释（与 +0 在 value 行无法区分），两个二进制格式的负 NaN
都在 value 行丢符号：

2026-11-17 又补上矩阵里最后一格：**负零的 value token 也统一成 `-0`**。修复前
二进制侧打 `value=0`、把符号完全交给 `(-0)` 注释，十进制侧打 `value=-0`，同一个
`value` 字段里两种拼写 —— API.md §7 声称五种格式口径一致，所以让实现跟上声明。
`(-0)` 注释保留（与 `(0)` / `(±infinity)` 对称），只是不再独自承担保真的责任。

```
$ bitnum value bfloat16 8000
sign=1  exponent=0 (zero)  significand=0
kind=finite  value=-0   (-0)
```

```
$ bitnum value bfloat16 FF80
sign=1  exponent=255 (infinity)  significand=0
kind=infinity  value=-Infinity   (-infinity)
```

```
$ bitnum value binary16 FE01
sign=1  exponent=31 (nan)  significand=513
kind=nan  value=-NaN
```

注意 `kind=finite` 用在次正规数上：`FloatClass` 区分 `Subnormal`，但 IEEE 754-2008
§2.1.3 的 *class* 里 zero / subnormal / normal 统称 finite。两者都打印，位置不同 ——
`kind` 用粗分类，指数那一行标注 `(subnormal)`。

## 3. `bitnum bits` — 表达式到字节

```
$ bitnum bits binary16 1.0
3C00
```

```
$ bitnum bits binary16 0.1
2E66
bitnum: note: rounded (inexact)
```

0.1 不是 binary16 可表示的，`2E66` 是最近偶数舍入的结果，并且**显式声明了 inexact**
（写到 stderr，stdout 保持干净可管道）。退出码仍是 0：舍入有确定答案，不是数据错误。
（本文这一块以前多写了一行 `exit=0`；`DEMO` 只在**非零**退出时写 `exit=N`，
这一行的存在会让读者以为照抄的命令比实际少一行。`demo_replay_wbtest.mbt` 现在
逐行对拍本文全部 48 条 `bitnum` 块。）

```
$ bitnum bits bfloat16 1.0
3F80
```

```
$ bitnum bits decimal64 -7.50
A2300000000003D0
```

```
$ bitnum bits decimal32 1.23
223000A3
```

```
$ bitnum bits decimal128 1E-6176
00000000000000000000000000000001
```

十进制侧不走舍入：`1.23` 精确编码成系数 123、指数 -2。三位数原样进容器。

### 3.1 `bits` 对非法字面量的行为

`bits` 的输入分三类，**两类都不能静默变成 `+0`**（2026-11-04 审计 BN-1，P1）。

「不是数」是数据错误，退出码 1，与十进制分支同一口径：

```
$ bitnum bits binary16 xyz
bitnum: not a number: 'xyz'
exit=1
```

```
$ bitnum bits binary16 1.2.3
bitnum: not a number: '1.2.3'
exit=1
```

```
$ bitnum bits binary16 1e
bitnum: not a number: '1e'
exit=1
```

「是数但超出 binary64」按 IEEE 754 §7.4 就近舍入溢出到 ±Inf，于是编码成
`7C00` / `FC00`，退出码 0 —— 标准对这种输入有确定答案，不该拒：

```
$ bitnum bits binary16 1e999
7C00
bitnum: note: '1e999' is too large for binary64; rounded to infinity (inexact)
```

```
$ bitnum bits binary16 -1e999
FC00
bitnum: note: '-1e999' is too large for binary64; rounded to infinity (inexact)
```

下溢端是对称的（BN-B10，修复自 2026-11-10 审计）。`1e-999` 量级低于 binary64 的最小
次正规数（`5e-324`），**解析阶段**就舍成零；编解码器收到的已是精确零，`inexact` 无从
报告，修复前它与 `bits binary16 0` 的输出一模一样：

```
$ bitnum bits binary16 1e-999
0000
bitnum: note: '1e-999' is too small for binary64; rounded to zero (inexact)
```

真正表示零的字面量（`0` / `-0` / `0e-999`）仍然静默 —— 它们的零是精确的，没有舍入可
报告。可表示的 binary64 次正规数保持原来的单句 `rounded (inexact)`：

```
$ bitnum bits binary16 1e-320
0000
bitnum: note: rounded (inexact)
```

判据是字面量里**是否含非零数字**（指数部分不算），所以 `0.000e-999` 静默、
`1e-999` 与 `0.0001e-999` 都报下溢。

符号跟着原字面量走。bfloat16 的容器更宽（指数域 8 位），同样输入落在 `7F80`：

```
$ bitnum bits bfloat16 1e999
7F80
bitnum: note: '1e999' is too large for binary64; rounded to infinity (inexact)
```

bfloat16 还有**第二级**溢出，因为它要经过 `double → float → bf16` 两次窄化。
`1e39` 是合法的 binary64、却是 f32 的无穷，而 f32 无穷转 bf16 无穷是**精确**的，
所以编解码器的 `inexact` 看不见这一步。修复前它既不说明也不报错
（BN-B4，修复自 2026-11-10 审计）：

```
$ bitnum bits bfloat16 1e39
7F80
bitnum: note: '1e39' is too large for binary32; rounded to infinity (inexact)
```

说明里写 `binary32` 而不是 `binary64`：越界的是第二级容器，binary64 那一档是好的。
边界按第一次窄化的**实际结果**判定，不是按量级阈值 —— `3.4028235e38` 比
`0x7F7FFFFF` 略大却仍被就近舍回它，阈值比较在那一点上会误报。

同一处窄化的**下溢端**现在也有说明（D3，修复自 2026-11-13 审计）。`1e-46` 是
合法的 binary64，却在 `Double → Float` 这一步就被舍成零；`of_f32` 收到的已经是
精确零，`inexact` 为 false，所以修复前它输出 `0000`、exit 0、**stderr 空** ——
与 `bits bfloat16 0` 逐字节相同：

```
$ bitnum bits bfloat16 1e-46
0000
bitnum: note: '1e-46' is too small for binary32; rounded to zero (inexact)
```

判据同样落在「第一次窄化实际产生了什么」上（非零字面量 + 窄化结果为 ±0），
符号照旧保真（`-1e-46` → `8000`）。已经在 binary64 就舍成零的 `1e-999` 仍走
上一节的 `too small for binary64` —— 两条诊断发生在不同阶段，措辞按越界的那一级写。

修复前这三类输入**一律**输出 `0000`、`exit 0`、无任何 stderr —— 一个拒绝的字面量
伪装成一个合法的 `+0`。这两个状态在 hex 上无法区分，所以回归测试断言的是退出码与
stderr 措辞，不是那 4 个 hex 字符（见 §7 的测试说明）。

## 4. `bitnum check` — 往返自检

```
$ bitnum check binary16 7E00
in    7E00
out   7E00
result: round-trip ok
```

```
$ bitnum check decimal64 A2300000000003D0
in    A2300000000003D0
out   A2300000000003D0
result: round-trip ok
```

非规范 DPD 输入是一个**真实的、必须单独说明**的结果 —— 它解码合法，但没有规范形式，
因为编码器的值域天然排除那 24 个码（PLAN.md §4.4）。`2250016E` 是 `dsEncode.decTest`
里的冗余码：

```
$ bitnum check decimal32 2250016E
in    2250016E
out   (no canonical bytes: 1 non-canonical DPD group(s))
value 888
result: non-canonical input accepted — the encoder never emits redundant DPD codes, so this pattern has no canonical form (PLAN.md §4.4)
exit=1
```

同一份输入在 `value` 下正常解码，并把冗余这一点标出来：

```
$ bitnum value decimal32 2250016E
sign=0  exponent=0  coefficient=888
kind=finite  value=888   (1 non-canonical DPD group(s); the encoder cannot produce these)
```

`888` 正是标准规定的 8/9 序列 —— 不是零、不是报错、不是"修正成最近的合法值"。

**Infinity 族是第二个必须单独说明的结论**（BN-B2，修复自 2026-11-10 审计）。
组合字段为 `11110` 时，其下各位不承载值，所以 `0x78`–`0x7B` 都解成 Infinity；
编码器只写规范的 `0x78`。修复前这里报笼统的 `MISMATCH`，看起来像编解码器的缺陷：

```
$ bitnum check decimal32 79000000
in    79000000
out   78000000
value Infinity
result: infinity family — the bits below the combination field carry no value for Infinity, so the encoder writes only the canonical `11110` plus a zeroed exponent continuation; the value round-trips, those padding bits do not (PLAN.md §1.1, API.md §6)
exit=1
```

退出码**仍是 1**：`check` 的契约是字节恒等，而这几个填充位确实不会回来。
不同之处是输出说清了「丢的是哪些位、为什么这些位不算值」，所以它读起来不再是
一个查不出的 bug。`78000000` 本身照旧 `round-trip ok` / `exit 0`。

## 5. `bitnum table` — 边界值表

下面五块不是手抄的输出，而是 `cmd/bitnum/table_wbtest.mbt` 在测试里逐字比对的对象：
测试读这份 DEMO（以及 README 里 `table decimal32` 那一块），要求 `table` 的报告与文档
**逐字节相同**。所以这里的任何一行漂移都会让 `moon test` 变红 —— 2026-11-17 之前
`table` 是唯一没有任何白盒测试的子命令（连只印散文的 `help` 都有）。

```
$ bitnum table binary16
binary16 boundary values (IEEE 754-2008: s(1) e(5) m(10), bias 15)
  bits  class       value
0000  zero                   0   (zero)
8000  zero                  -0   (negative zero)
0001  subnormal   5.960464477539063e-08   (min subnormal, 2^-24)
03FF  subnormal   0.00006097555160522461   (max subnormal)
0400  normal      0.00006103515625   (min normal, 2^-14)
3C00  normal                 1   (one)
3555  normal      0.333251953125   (one third, rounded)
7BFF  normal             65504   (max finite, 65504)
7C00  infinity        Infinity   (+infinity)
FC00  infinity       -Infinity   (-infinity)
7E00  nan                  NaN   (quiet NaN, zero payload)
```

```
$ bitnum table bfloat16
bfloat16 boundary values (high 16 bits of binary32: s(1) e(8) m(7), bias 127)
  bits  class       value
0000  zero                   0   (zero)
8000  zero                  -0   (negative zero)
0001  subnormal   9.183549615799121e-41   (min subnormal, 2^-133)
007F  subnormal   1.1663108012064884e-38   (max subnormal)
0080  normal      1.1754943508222875e-38   (min normal, 2^-126)
3F80  normal                 1   (one)
4000  normal                 2   (two)
7F7F  normal      3.3895313892515355e+38   (max finite)
7F80  infinity        Infinity   (+infinity)
FF80  infinity       -Infinity   (-infinity)
7FC0  nan                  NaN   (quiet NaN, zero payload)
```

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

```
$ bitnum table decimal64
decimal64 boundary values (DPD: 64 bits, 16 digits, bias 398)
hex               class       value
0000000000000000  finite      0E-398                      (zero at Etiny)
A238000000000000  finite      -0                          (negative zero)
0000000000000001  finite      1E-398                      (smallest subnormal)
003C000000000001  finite      1E-383                      (smallest normal)
2238000000000001  finite      1                           (one)
A238000000000001  finite      -1                          (negative one)
6E38FF3FCFF3FCFF  finite      9999999999999999            (largest coefficient)
77FCFF3FCFF3FCFF  finite      9.999999999999999E+384      (largest finite)
7800000000000000  infinity    Infinity                    (+infinity)
F800000000000000  infinity    -Infinity                   (-infinity)
7C00000000000000  nan         NaN                         (quiet NaN)

Emax=384  Emin=-383  Etiny=-398  Emax_top=369
max exponent: 384 with a 16-digit coefficient, 369 for anything narrower (zero included)
```

```
$ bitnum table decimal128
decimal128 boundary values (DPD: 128 bits, 34 digits, bias 6176)
hex                               class       value
00000000000000000000000000000000  finite      0E-6176                     (zero at Etiny)
A2080000000000000000000000000000  finite      -0                          (negative zero)
00000000000000000000000000000001  finite      1E-6176                     (smallest subnormal)
00084000000000000000000000000001  finite      1E-6143                     (smallest normal)
22080000000000000000000000000001  finite      1                           (one)
A2080000000000000000000000000001  finite      -1                          (negative one)
6E080FF3FCFF3FCFF3FCFF3FCFF3FCFF  finite      9999999999999999999999999999999999  (largest coefficient)
77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF  finite      9.999999999999999999999999999999999E+6144  (largest finite)
78000000000000000000000000000000  infinity    Infinity                    (+infinity)
F8000000000000000000000000000000  infinity    -Infinity                   (-infinity)
7C000000000000000000000000000000  nan         NaN                         (quiet NaN)

Emax=6144  Emin=-6143  Etiny=-6176  Emax_top=6111
max exponent: 6144 with a 34-digit coefficient, 6111 for anything narrower (zero included)
```

**为什么最大有限值是 `9.999999E+96` 而不是 `9.999999E+102`**：两个上限同时生效，取小者。
调整指数必须 `<= Emax`（即 `指数 + 位数 - 1 <= 96`，七位数系数 → 指数 ≤ 90）；
组合字段要求 `exp_top <= 2`（→ 指数 ≤ Emax_top = 90）。两者在满精度处重合，
这正是该格式自洽的地方。第二行 `max exponent` 把两个数都写出来，因为只写一个会误导。

## 6. 错误分支

每条错误都带定位信息，不是一句「invalid input」：

```
$ bitnum value binary16 ZZZZ
bitnum: non-hex character in 'ZZZZ'
exit=1
```

（校验顺序：先格式、再长度、最后字符。所以 `value decimal32 ZZZZ` 报的是
`decimal32 is 8 hex digits, got 4`，`value nosuch ZZZZ` 报的是 `unknown format`
——同一份输入在不同格式下拒在不同的一道门上，这本身是有意的：先拒绝你不知道在问
哪种格式，再拒绝长度对不上，最后才逐字符挑错。）

十进制 `bits` 的词法拒绝是**另一句话**：它不经过「不能精确表示」的外壳，因为
根本没有值被舍入（BN-B9，修复自 2026-11-10 审计）。修复前这些全是
`cannot represent no digits in nan exactly` 这类病句：

```
$ bitnum bits decimal64 nan
bitnum: cannot parse 'nan': no digits
exit=1
```

```
$ bitnum bits decimal64 1.2.3
bitnum: cannot parse '1.2.3': more than one decimal point
exit=1
```

```
$ bitnum bits decimal64 +
bitnum: cannot parse '+': sign with no digits
exit=1
```

裸指数标记与实际写了符号是两种定位，不会给 `1e` 虚构一个符号：

```
$ bitnum bits decimal64 1e
bitnum: cannot parse '1e': exponent with no digits
exit=1
```

```
$ bitnum bits decimal64 1e+
bitnum: cannot parse '1e+': exponent sign with no digits
exit=1
```

`from_hex` 的非 hex 字符走同一个变体：

```
$ bitnum value decimal32 78ZZ0000
bitnum: cannot parse '78ZZ0000': non-hex character
exit=1
```

```
$ bitnum value nosuch 0000
bitnum: unknown format 'nosuch' (expected binary16, bfloat16, decimal32, decimal64, decimal128)
exit=2
```

```
$ bitnum value binary16 000100
bitnum: binary16 is 2 bytes, got 3
exit=1
```

```
$ bitnum bits decimal32 12345678
bitnum: coefficient has 8 decimal digits, this format holds 7
exit=1
```

系数比容器宽得多时（199 位以上）报的仍然是**系数**，不是指数（D4，修复自
2026-11-13 审计）。修复前这一档会把按位数收紧的指数上限
（`Emax - (位数 - 1)`，199 位时是 `-102`）当作越界原因，给出下界大于上界的
倒挂区间 `exponent 0 out of range [-101, -102]`：

```
$ bitnum bits decimal32 111…1        # 199 个 1
bitnum: coefficient has 199 decimal digits, this format holds 7
exit=1
```

```
$ bitnum bits decimal32 9999999E+96
bitnum: exponent 96 out of range [-101, 90]
exit=1
```

这里的 `96` 是**真指数**（`9.999999E+102` 超过 `Emax=96`），上下界也是真指数，
所以说 `exponent`。另一条检查守的是**偏置值装不装得进字段**，措辞不同：

```
$ bitnum bits decimal32 1e155
bitnum: biased exponent 256 out of range [0, 255]
exit=1
```

`255` 是字段容量（`2^(6+2)-1`）：偏置值 256 连位都放不下。字段放得下的偏置值由
下一道门按位数收紧 —— `1e97` 偏置 198 装得下，于是印的是
`exponent 97 out of range [-101, 90]`。两条分支原先共用一句 `biased exponent …`，
于是把真指数 96 印成 `biased exponent 96 out of range [-101, 90]` —— 一个不是偏置
指数的数配一组真指数的界（BN-B5，修复自 2026-11-10 审计）。现在各自说清在检查哪个量。

```
$ bitnum bits binary16 xyz
bitnum: not a number: 'xyz'
exit=1
```

```
$ bitnum value decimal64 A2300000000003D
bitnum: decimal64 is 16 hex digits, got 15
exit=1
```

漏掉末位的 `A2300000000003D` 以前被右对齐成 `0A2300000000003D`，解成一个完全不同的数
（`2.600000000000831E-247`）并退出 0。现在按 `from_hex` 的精确宽度要求拒绝
（2026-11-04 审计 BN-2，P2）。注意措辞用的是 **hex 位数**，不是字节数：库的
`TruncatedInput` 按字节计（`decode_bytes` 需要字节），CLI 在边界翻译成调用方看得懂的单位。

```
$ bitnum value binary16 3c0
bitnum: hex input must have an even number of digits, got 3
exit=1
```

二进制格式这条报错一直是对的 —— 审计就是拿它作对照，发现十进制侧宽松。

```
$ bitnum bits binary16 1e999
7C00
bitnum: note: '1e999' is too large for binary64; rounded to infinity (inexact)
```

退出码：0 成功 / 1 数据错误 / 2 用法错误。

## 7. 全量测试

```
$ moon test
Total tests: 201, passed: 201, failed: 0.
```

201 条测试的覆盖规模（不是"201 个断言"，是 201 条测试里有几条是穷举）：

| 测试 | 规模 |
|---|---|
| binary16 decode→encode | 全部 **65536** 个位模式 |
| binary16 f64 往返 | 全部 65536（NaN payload 单独说明） |
| binary16 类分布 | 2 / 2046 / 61440 / 2 / 2046 |
| 二进制中点穷举 | binary16 0x7BFF + bfloat16 0x7F7F 个间隔 × 5 模式 × 双符号 |
| binary16 溢出带 | 阈值两侧 12 个量级 × 5 模式 × 双符号（含 65505 / 65520 / 1e18） |
| NaN payload 渲染 | 组独立性穷举 0..1023、组回读一致、宽度无关、dectest 五个锚点 |
| bfloat16 同上 | 全部 **65536** |
| DPD 三元组往返 | 全部 **1000** |
| DPD 码空间 | 全部 **1024**（含 24 冗余） |
| 十进制向量 | **568**（496 精确 + 72 冗余），全部有限值；另断言「表里没有 `11110`/`11111` 行」 |
| 十进制向量原文渲染 | **568** 行的 `original_text` 列逐字符 |
| 组合字段 × 指数续域全空间 | **565248** 个模式（3 宽度 × 32 组合 × 全部指数续域 × 4 种系数续域）的 decode→encode |
| 位窗与 Unicode 边界 | 空窗 / 有效宽度截断 / 零被移数的 INT32_MAX 宽度；BMP 大写展开、astral 与混合 ASCII |
| `parse_decimal` 词法全空间 | 孤立代理项 4 个端点 × 8 个槽位 × 3 个格式；BMP 每个标量（63 488 个）在首槽与次槽的归属 |
| 错误回显 | 4 个孤立代理项端点的消息「无解不出字符的码元」+ astral 字符原样 + 字段保真 |
| `table` 报告 | **5** 个格式的报告逐字节对齐 DEMO / README 引用的围栏块 |
| `docs/DEMO.md` 的全部 `bitnum` 块 | **48** 条命令逐行回放，含退出码与 stdout/stderr 分配（`cmd/bitnum/demo_replay_wbtest.mbt`） |
| 拒绝语的行形态 | CRLF / C0 / C1 / 格式字符 / 孤立代理项共 9 个码元在 `printable_text` 下的转义，加 3 条端到端 `describe` 断行 |
| 渲染口径矩阵 | **5** 格式 × 6 个 datum 的 `value` token（`0` / `-0` / `±Infinity` / `NaN` / `-NaN`） |
| 最大有限值之上的中点 | 2 格式 × 5 模式 × 双符号（B4 补的那一格） |
| 舍入模式 | 5 种 × 向量表 |
| `bits` 非法字面量 | 9 条（语法错 6 + 溢出 4 + 分类 9 + 符号 2 + hex/note 8 + 措辞 2 + specials 3） |

`bits` 那 9 条断言的是退出码、stdout/stderr 的分配、以及拒绝措辞里含原输入文本 ——
不是 `0000` 这 4 个字符。修复前后 hex 可能相同（例如本来就该是 `+0` 的输入），
只比 hex 的测试抓不到 BN-1。

