# bitnum 实测记录

> 本文件里的每一条输出都是**实际跑出来的**，命令在代码块第一行，输出紧随其后。
> 没有任何一行是手写的。要复核任意一条，复制 `$` 开头的命令在仓库根目录执行即可。
>
> 环境：
> ```
> $env:MOON_HOME="E:\moonbit\home"; $env:Path="E:\moonbit\home\bin;"+$env:Path
> moon 0.1.20261016 (1af328f 2026-10-16)
> moonc v0.10.16+b1a0e846e (2026-10-16)
> ```

## 0. 门禁

```
$ moon check
Finished. moon: ran 4 tasks, now up to date (0 warnings, 0 errors)

$ moon test
Total tests: 63, passed: 63, failed: 0.

$ moon build --target wasm
Finished. moon: ran 2 tasks, now up to date

$ moon fmt
Finished. moon: ran 21 tasks, now up to date

$ moon fmt --check
Finished. moon: ran 21 tasks, now up to date
```

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
24 个冗余 DPD 码（每个格式 24 条），`fail` 为零。这三行是十进制侧唯一的正确性依据。

二进制侧的向量由 `scripts/float_ref.py` 生成，它是精确整数运算，**并与两个独立实现交叉核对**：

```
$ python scripts/float_ref.py
numpy cross-check (nearest_even): compared=19988 mismatch=0
torch cross-check (bf16 nearest_even): compared=4973 mismatch=0
wrote examples\vectors-binary16.tsv (965 rows)
```

- `numpy` 的 `float16` 走的是平台自己的 IEEE 转换，19988 条随机 binary64 输入**逐位一致**。
- `torch` 的 `bfloat16`（Google TPU 格式的原产地）4973 条**逐位一致**。

两点独立实现 + 一个精确整数参考，三者吻合。这不是自证。

## 2. `bitnum value` — 字段分解

PLAN.md §7 给的两条示例输出，逐字符吻合：

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
kind=signaling-nan  value=sNaN
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
exit=0
```

0.1 不是 binary16 可表示的，`2E66` 是最近偶数舍入的结果，并且**显式声明了 inexact**
（写到 stderr，stdout 保持干净可管道）。

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
exit=0
```

```
$ bitnum bits binary16 -1e999
FC00
bitnum: note: '-1e999' is too large for binary64; rounded to infinity (inexact)
exit=0
```

符号跟着原字面量走。bfloat16 的容器更宽（指数域 8 位），同样输入落在 `7F80`：

```
$ bitnum bits bfloat16 1e999
7F80
bitnum: note: '1e999' is too large for binary64; rounded to infinity (inexact)
exit=0
```

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

## 5. `bitnum table` — 边界值表

```
$ bitnum table binary16
binary16 boundary values (IEEE 754-2008: s(1) e(5) m(10), bias 15)
  bits  class       value
0000  zero                   0   (zero)
8000  zero                   0   (negative zero)
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
8000  zero                   0   (negative zero)
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

```
$ bitnum bits decimal32 9999999E+96
bitnum: biased exponent 96 out of range [-101, 90]
exit=1
```

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
exit=0
```

退出码：0 成功 / 1 数据错误 / 2 用法错误。

## 7. 全量测试

```
$ moon test
Total tests: 63, passed: 63, failed: 0.
```

63 条测试的覆盖规模（不是"63 个断言"，是 63 条测试里有几条是穷举）：

| 测试 | 规模 |
|---|---|
| binary16 decode→encode | 全部 **65536** 个位模式 |
| binary16 f64 往返 | 全部 65536（NaN payload 单独说明） |
| binary16 类分布 | 2 / 2046 / 61440 / 2 / 2046 |
| bfloat16 同上 | 全部 **65536** |
| DPD 三元组往返 | 全部 **1000** |
| DPD 码空间 | 全部 **1024**（含 24 冗余） |
| 十进制向量 | **568**（496 精确 + 72 冗余） |
| 舍入模式 | 5 种 × 向量表 |
| `bits` 非法字面量 | 9 条（语法错 6 + 溢出 4 + 分类 9 + 符号 2 + hex/note 8 + 措辞 2 + specials 3） |

`bits` 那 9 条断言的是退出码、stdout/stderr 的分配、以及拒绝措辞里含原输入文本 ——
不是 `0000` 这 4 个字符。修复前后 hex 可能相同（例如本来就该是 `+0` 的输入），
只比 hex 的测试抓不到 BN-1。

