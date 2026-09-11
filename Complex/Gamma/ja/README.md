# LUX.C2.Gamma

[English](../README.md) | [日本語](README.md)

Delphi 用の複素ガンマ関数。Lanczos 近似と大浦拓哉氏の `cdgamma` による実装を備える。各方式には、双対数で微分を伝播する `.Diff` ユニットがある。

## 1. 関数と型

各ユニットは独立した関数を公開し、クラスの定義やオブジェクトの生成を必要としない。通常版は `TSingleC` と `TDoubleC`、`.Diff` 版は `TdSingleC` と `TdDoubleC` に対応する。双対複素数の `o` プロパティは値、`d` プロパティは微分成分を表す。

| ユニット | 公開関数 |
|---|---|
| `LUX.C2.Gamma.Lanczos` | `Gamma7`・`Gamma9`・`Gamma11`・`Gamma15`、`LnGamma7`・`LnGamma9`・`LnGamma11`・`LnGamma15` |
| `LUX.C2.Gamma.Lanczos.Diff` | 同名の関数を双対複素数型に多重定義 |
| `LUX.C2.Gamma.Ooura` | `Gamma` |
| `LUX.C2.Gamma.Ooura.Diff` | 双対複素数型の `Gamma` |

Lanczos の関数名の数字は、定数項を含む係数の個数を表す。有効桁数の保証ではない。各係数列には、対応するパラメーター `g` が設定されている。

| 関数 | 係数の個数 `N` | `g` |
|---|---:|---:|
| `Gamma7` / `LnGamma7` | 7 | 5 |
| `Gamma9` / `LnGamma9` | 9 | 7 |
| `Gamma11` / `LnGamma11` | 11 | 9 |
| `Gamma15` / `LnGamma15` | 15 | 607/128 |

Lanczos の通常版と双対数版は、それぞれのソースファイル内で実装を読み通せるよう、各ユニット内に係数を定義している。大浦版は固定の近似式を用い、次数指定や複素対数ガンマ関数は公開しない。

## 2. 使い方

Delphi のユニット検索パスに、LUX のルート、`Complex`、`Complex/Gamma` を追加する。ガンマ関数ユニットは LUX の数値型に依存するが、FireMonkey には依存しない。

次のコンソールプログラムは、同じ複素引数における値と導関数を評価する。通常版と双対数版の選択を明確にするため、関数名をユニット名で修飾している。

```pascal
program GammaExample;

{$APPTYPE CONSOLE}

uses
  LUX.Complex,
  LUX.Complex.Diff,
  LUX.C2.Gamma.Lanczos,
  LUX.C2.Gamma.Lanczos.Diff;

var
  Z, G :TDoubleC;
  D, F :TdDoubleC;
begin
  Z := TDoubleC.Create( 2.5, 1 );
  G := LUX.C2.Gamma.Lanczos.Gamma15( Z );

  D.o := Z;
  D.d := TDoubleC.Create( 1, 0 );
  F := LUX.C2.Gamma.Lanczos.Diff.Gamma15( D );

  Writeln( 'Gamma: ', G.R, ', ', G.I );
  Writeln( 'Value: ', F.o.R, ', ', F.o.I );
  Writeln( 'Derivative: ', F.d.R, ', ', F.d.I );
end.
```

`D.d` に `1 + 0i` を設定すると、実方向の微分を計算する。近似式が正則な場所では、`F.d` は `Z` におけるガンマ関数の複素導関数の近似値となる。通常の入力で中間値が有限なら、微分成分の初期値がゼロの場合、出力の微分成分もゼロになる。自動微分は実装された近似式を微分するものであり、近似誤差や浮動小数点演算の誤差は残る。

大浦版を使う場合は、`LUX.C2.Gamma.Ooura` または `LUX.C2.Gamma.Ooura.Diff` を追加し、対応する型で `Gamma` を呼び出す。同じ入力に対して両方式を比較できるが、結果の一致だけで精度が保証されるわけではない。

## 3. 数式と実装

### 3.1. Lanczos 近似

`Re(z) >= 1/2` では、有限項の Lanczos 近似を評価する [1, 2]。

```math
A(z)=c_0+\sum_{k=1}^{N-1}\frac{c_k}{z-1+k},
\qquad B=z+g-\frac12,
\qquad \Gamma(z)\approx\sqrt{2\pi}\,A(z)B^{z-1/2}e^{-B}.
```

内部関数 `LnGammaP` が対数形の各項を計算する。`GammaP` は `Exp(LnGammaP(...))` を返し、対数ガンマの計算と係数和・近似式を共有する。`N` ごとに係数列と `g` の組が決まっており、`N` を増やすだけで浮動小数点演算の誤差が必ず小さくなるとは限らない [2]。

### 3.2. 反射公式

Lanczos 版は `Re(z) < 1/2` の場合、反射公式を用いる [3]。

```math
\Gamma(z)\Gamma(1-z)=\frac{\pi}{\sin(\pi z)},\qquad z\notin\mathbb Z.
```

`Gamma*` はこの公式を直接適用する。`LnGamma*` は `Ln(pi / Sin(pi*z)) - LnGammaP(1-z)` を計算し、補助関数が反射後の半平面で近似式を評価する。

### 3.3. 大浦氏のアルゴリズム

大浦版は、作者の `gamerf` パッケージに含まれる `cdgamma.c` の Delphi 移植である [4]。固定の有理式と指数関数を組み合わせた近似式を評価する。反射公式への切り替えは `Re(z) < 0` で行い、Lanczos 版の境界 `1/2` とは異なる。

複素数の除算と反射公式は、`/` と `Sin` を使って直接記述する。双対数版も同じ式を評価し、実部・虚部の演算を通じて微分を伝播する。

## 4. 定義域・分岐・精度

### 4.1. 極

非正整数 `0, -1, -2, ...` はガンマ関数の極であり、計算対象外である [3]。本実装は極を明示的に検出しない。極を入力した場合、演算内容や例外マスクに応じて、有限値・`INF`・`NaN` が返る場合や、浮動小数点例外が発生する場合がある。戻り値が `INF` / `NaN` かどうかで極を確実に判定することはできない。

例えば、浮動小数点例外をマスクした Delphi Win64 の倍精度検証では、5方式すべてが `z = -1` に対して実部約 `-2.5653e16` の有限値を返し、`z = 0` では `NaN` を返した。通常版と双対数版で値の傾向は同じだった。これは制約を示す例であり、環境を問わず同じビット列を返すという仕様ではない。反射公式の計算では、浮動小数点の `Sin(pi*z)` が負の整数で厳密にゼロになるとは限らない。

### 4.2. 対数の分岐

`LnGamma*` は複素対数の主値を組み合わせて計算する。その指数は浮動小数点演算の影響を受けつつ、対応するガンマ関数の近似を表すが、解析的な対数ガンマ関数の主枝に沿うことは保証しない。数値誤差に加え、`2*pi*i` の整数倍だけ異なる場合がある。`Gamma(z)` の対数の主値と、対数ガンマ関数の主枝は異なる分岐規約である。この区別は mpmath の説明を参照 [5]。複素平面上の経路に沿って使う場合、分岐の連続性を仮定しないこと。

### 4.3. 数値計算上の制約

誤差許容値の指定や、全定義域に対する誤差上限の保証はない。精度は係数列、入力、数値型、初等関数の実装、丸めに依存する。大きな引数や中間値によるオーバーフロー・アンダーフロー、桁落ちは、極以外でも発生し得る。対数形を使っても、中間値の範囲の問題がすべてなくなるわけではない。

4種類の Lanczos 係数列と大浦版について、常に成り立つ精度順位や保証桁数を示す再現可能なベンチマークは、本ユニット群には付属しない。そのような保証が必要な用途では、利用する入力範囲と導関数を、独立した高精度計算で検証すること。

## 5. ファイル構成

```text
Gamma/
├─ LUX.C2.Gamma.Lanczos.pas
├─ LUX.C2.Gamma.Lanczos.Diff.pas
├─ LUX.C2.Gamma.Ooura.pas
├─ LUX.C2.Gamma.Ooura.Diff.pas
├─ README.md
└─ ja/README.md
```

複素数型は `LUX.Complex` と `LUX.Complex.Diff` に定義されている。別系統の[実引数のガンマ関数ユニット](../../../D1/Gamma/ja/README.md)は `D1/Gamma` にあり、API や定義域の扱いは各ユニットの説明に従う。

## 6. 参考文献・出典表示

1. C. Lanczos, [*A Precision Approximation of the Gamma Function*](https://doi.org/10.1137/0701008), 1964, pp. 86–96.
2. Boost.Math, [*The Lanczos Approximation*](https://www.boost.org/doc/libs/latest/libs/math/doc/html/math_toolkit/lanczos.html)。係数の個数、パラメーターの選定、桁落ちに関する解説。本 Delphi 実装の精度測定結果ではない。
3. NIST DLMF, [*Gamma Function: Definitions*](https://dlmf.nist.gov/5.2)、[*Functional Relations*](https://dlmf.nist.gov/5.5)。
4. 大浦拓哉, [*Gamma / Error Functions*](https://www.kurims.kyoto-u.ac.jp/~ooura/gamerf.html)。`gamerf` に `cdgamma.c` を収録。
5. mpmath, [*Factorials and gamma functions*](https://mpmath.org/doc/current/functions/gamma.html)。特に `loggamma` の説明。

大浦版には原著者の表示 Copyright(C) 1996 Takuya OOURA を保持している。各ソースの冒頭と元パッケージの表示を参照。

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [Delphi](https://www.embarcadero.com/jp/products/delphi)

ネイティブなクロスプラットフォームアプリを開発するための統合開発環境。
