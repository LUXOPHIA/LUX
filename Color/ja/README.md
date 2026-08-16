# LUX.Color
[English](../README.md) | [日本語](README.md)

`LUX.Color` は色型を Delphi の値レコードとして定義する。表示に必要な伝達関数を備えた線形浮動小数点の色と、それと暗黙変換で相互変換できる整数ピクセル形式である。`LUX.Color.Half` は GPU テクスチャに一致する配置の `binary16` 版を追加する。`LUX.Color.Space` は RGB 色空間 ── 原色・白色点・伝達関数 ── を定義し、sRGB から ACEScg までのプリセット、空間どうしの変換行列、ICC プロファイルの書き出しと読み込みを備える。

## 1. 概要

すべての色は、コンストラクタ・演算子・暗黙変換を備えた素の `record` であり、スタックに置かれ値としてコピーされる。浮動小数点レコード `TSingleRGB` / `TSingleRGBA` が計算の中心である。線形の放射輝度を保持し、（チャネルごとの乗算を含む）算術演算を備え、`Gamma` と `ToneMap` の各メソッドを公開する。その周囲に記憶形式が並ぶ。

| レコード | チャネル | 用途 |
|---|---|---|
| `TByteRGB` / `TByteRGBA` | `Byte` | 8ビットピクセル。`TAlphaColor` とビット互換 |
| `TWordRGB` / `TWordRGBA` | `Word` | 16ビットピクセル。Skia の `RGBA16161616` に一致する R,G,B(,A) 順 |
| `TUInt32xRGB` / `TUInt32xRGBA` | `UInt32` | 多数の8ビット標本を溢れなく合計する広幅の累算器 |
| `TByteRGBE` | `Byte` ×4 | 共有指数の HDR 符号化 |
| `THalfRGB` / `THalfRGBA` | `THalf` | `binary16`。Skia の `RGBAF16` に一致する R,G,B(,A) 順 |

リトルエンディアン環境では `TByteRGB` はフィールドを B,G,R 順（`TByteRGBA` では A が最上位）で宣言するため、32ビットのビットパターンが FireMonkey の `TAlphaColor` と一致し、双方向に暗黙変換できる。`TSingleRGBA` も同様に `TAlphaColorF` と相互変換する。アルファはストレート（非前乗算）であり、すべてのコンストラクタと変換で既定は不透明である。

## 2. 数学的背景

### 2.1 ディスプレイガンマ

`Gamma` は線形チャネルを指数 $\gamma$（既定 $2.2$）のディスプレイ向けにチャネルごとに符号化する。`TSingleRGBA.Gamma` はアルファに手を付けない。

```math
C' = C^{\,1/\gamma} \qquad \text{(2.1)}
```

### 2.2 トーンマッピング

`ToneMap` は拡張 Reinhard 演算子 [1] をチャネルごとに適用する。$L_w$ は白色点（引数 `W_`、既定 $1$）、すなわち純白に写る輝度である。

```math
C' = \operatorname{clamp}\!\left( \frac{C \left( 1 + C / L_w^{\,2} \right)}{1 + C},\; 0,\; 1 \right) \qquad \text{(2.2)}
```

### 2.3 共有指数符号化

`TByteRGBE` は3つの8ビット仮数 `R`,`G`,`B` と、全チャネルで共有される1つのバイアス付き指数 `E` を、Radiance 画像形式 [2] の流儀で格納する。仮数 $M$ のチャネルの復号は

```math
C = 2^{\,E-128} \, \frac{M}{255} \qquad \text{(2.3)}
```

`TSingleRGB` からの符号化は $E = 128 + \lceil \log_2 \max( R, G, B ) \rceil$ と $M = \mathrm{round}( 2^{-(E-128)} \, 255 \, C )$ を取る。最も明るいチャネルがスケールを決め、ダイナミックレンジは8ビットガンマピクセルの保持できる範囲を大きく超える。

### 2.4 ビット深度の変換

各変換は範囲の両端で正確に対応する。`Byte` → `Word` は $257$ 倍（`$FF` → `$FFFF`）、`Word` → `Byte` は上位バイトを取る。`Byte` → `Single` は $255$ で割り、`Single` → `Byte` / `Word` は $[0,1]$ にクランプしてから丸める。`THalf` チャネルは `Single` を介して `binary16` の精度内でビット正確に変換される [3]。

### 2.5 色空間

RGB 色空間は、3 原色と白色点の CIE 色度座標 $(x, y)$ と、伝達関数で定義される。原色から線形 RGB → CIE XYZ の行列は、$(1,1,1)$ が $Y = 1$ の白色点に写ることを要請して定まる。

```math
\mathbf{M} = \begin{pmatrix} X_r & X_g & X_b \\ 1 & 1 & 1 \\ Z_r & Z_g & Z_b \end{pmatrix} \operatorname{diag}(\mathbf{S}), \qquad \mathbf{S} = \begin{pmatrix} X_r & X_g & X_b \\ 1 & 1 & 1 \\ Z_r & Z_g & Z_b \end{pmatrix}^{-1} \begin{pmatrix} X_w \\ 1 \\ Z_w \end{pmatrix} \qquad \text{(2.4)}
```

ここで各色度座標について $X = x/y$、$Z = (1 - x - y)/y$ である。白色点の異なる空間どうしは Bradford の色順応 [8] で結び、ICC プロファイル [4] も同じ方法で D50 に適応した原色を格納する。

伝達関数 ── 符号化値 $V$ から線形値 $L$ ── は ICC の `parametricCurveType`（関数型 4）と同じ 7 係数の形で保持する。より単純な型はすべてこれに収まる。

```math
L = \begin{cases} (a V + b)^{g} + e & V \ge d \\ c V + f & V < d \end{cases} \qquad \text{(2.5)}
```

sRGB [5] は $g = 2.4,\ a = 1/1.055,\ b = 0.055/1.055,\ c = 1/12.92,\ d = 0.04045$、Rec. 709 / 2020 [6] と ROMM [7] は同じ形で係数が異なる。純ガンマは $a = 1,\ b = c = d = 0$、線形は $g = 1$ である。浮動小数形式の画像が持ち得る負の入力は、符号と絶対値に分けて扱う。

プリセット：

| クラス | 原色 (R, G, B) | 白色点 | 伝達関数 |
|---|---|---|---|
| `TLuxColorSpaceSRGB` / `…LinearSRGB` | (0.64, 0.33) (0.30, 0.60) (0.15, 0.06) | D65 | sRGB / 線形 |
| `TLuxColorSpaceDisplayP3` / `…LinearDisplayP3` | (0.680, 0.320) (0.265, 0.690) (0.150, 0.060) | D65 | sRGB / 線形 |
| `TLuxColorSpaceAdobeRGB` / `…LinearAdobeRGB` | (0.64, 0.33) (0.21, 0.71) (0.15, 0.06) | D65 | γ = 563/256 / 線形 |
| `TLuxColorSpaceRec2020` / `…LinearRec2020` | (0.708, 0.292) (0.170, 0.797) (0.131, 0.046) | D65 | Rec. 709 曲線 / 線形 |
| `TLuxColorSpaceProPhotoRGB` | (0.7347, 0.2653) (0.1596, 0.8404) (0.0366, 0.0001) | D50 | ROMM（γ 1.8、線形の足） |
| `TLuxColorSpaceACEScg` | (0.713, 0.293) (0.165, 0.830) (0.128, 0.044) | ACES (0.32168, 0.33767) | 線形 |

## 3. アーキテクチャ

### 3.1 型

```
・TByteRGB         ･･･ R,G,B :Byte、記憶順 B,G,R、⇄ TAlphaColor
  ┗・TByteRGBA    ･･･ C :TByteRGB、A :Byte、TAlphaColor とビット互換

・TWordRGB         ･･･ R,G,B :Word、記憶順 R,G,B（ Skia RGBA16161616 ）
  ┗・TWordRGBA    ･･･ C :TWordRGB、A :Word

・TSingleRGB       ･･･ R,G,B :Single、線形。Gamma / ToneMap
  ┗・TSingleRGBA  ･･･ C :TSingleRGB、A :Single、⇄ TAlphaColorF

・TUInt32xRGB      ･･･ R,G,B :UInt32、溢れない累算器
  ┗・TUInt32xRGBA ･･･ C :TUInt32xRGB、A :UInt32

・TByteRGBE        ･･･ C :TByteRGB、E :Byte、共有指数の HDR

・THalfRGB         ･･･ R,G,B :THalf、記憶順 R,G,B（ Skia RGBAF16 ）
  ┗・THalfRGBA    ･･･ C :THalfRGB、A :THalf

・TLuxTransfer     ･･･ g a b c d e f、Decode / Encode、Linear / Gamma / sRGB / Rec709 / ROMM

・TLuxColorSpace   ･･･ Name、RedXY GreenXY BlueXY WhiteXY、Transfer、ToXYZ / FromXYZ / ToXYZD50、ToSpace、IccProfile、FromIcc
  ┣・TLuxColorSpaceSRGB           ┣・TLuxColorSpaceLinearSRGB
  ┣・TLuxColorSpaceDisplayP3      ┣・TLuxColorSpaceLinearDisplayP3
  ┣・TLuxColorSpaceAdobeRGB       ┣・TLuxColorSpaceLinearAdobeRGB
  ┣・TLuxColorSpaceRec2020        ┣・TLuxColorSpaceLinearRec2020
  ┣・TLuxColorSpaceProPhotoRGB    ┗・TLuxColorSpaceACEScg
  ┗・（ 自作の派生クラス、または Create( 名前, xy × 4, 伝達関数 ) ）

・TLuxColorSpaces  ･･･ プリセットの共有インスタンス、Find / Intern / FromIcc / ByName
```

`…RGBA` の各レコードは対応する `…RGB` をフィールド `C` として内包し、`R`,`G`,`B` をプロパティとして再公開する。したがって色とそのアルファ付き形式とのポインタキャストはレイアウト上安全である。

`TLuxColorSpace` は生成後は不変で、所有するものではなく*参照する*ものである。`TLuxColorSpaces` は各プリセットの共有インスタンスをプログラムの終了まで持ち、`Intern` はそれ以外のインスタンスを内容で登録して、同じ空間（原色・白色点・曲線が許容誤差内で一致）が既にあればそれを返す。`FromIcc` は行列＋TRC 型の ICC プロファイル ── 全ての型の `para` 曲線と、`curv` 曲線（最も近い既知の曲線に当てはめる）── を解析し、LUT 型は受け付けない。

### 3.2 ファイル構成

```
・Color/
  ┣・LUX.Color.pas       ･･･ 整数・広幅整数・Single の色レコード
  ┣・LUX.Color.Half.pas  ･･･ THalfRGB / THalfRGBA（ binary16 記憶 ）
  ┗・LUX.Color.Space.pas ･･･ TLuxTransfer、TLuxColorSpace とプリセット、TLuxColorSpaces、ICC
```

`LUX.Color.Half` はスカラ `THalf` のために `LUX.D1.Half` に、`LUX.Color.Space` は色度座標・XYZ・3 × 3 行列のために `LUX.D2` / `LUX.D3` / `LUX.D3x3` に依存する。

## 4. 使い方

```pascal
uses LUX.Color;

var
   C :TSingleRGB;
   E :TByteRGBE;
   B :TByteRGB;
   A :TAlphaColor;
begin
     C := TSingleRGB.Create( 4.0, 2.0, 1.0 );    // 線形。白を超える値
     E := C;                                     // RGBE はレンジを保つ

     C := C.ToneMap( 1 ).Gamma( 2.2 );           // Reinhard の後に表示ガンマ
     B := C;                                     // クランプして8ビットに丸め
     A := B;                                     // UI 用の TAlphaColor
end;
```

色をある空間から別の空間へ変換し、色空間を ICC プロファイル経由で往復させる：

```pascal
uses LUX.Color, LUX.Color.Space, LUX.D3, LUX.D3x3;

var
   P3, S :TLuxColorSpace;
   M     :TDoubleM3;
   L     :TSingleRGB;
   V     :TDouble3D;
   Icc   :TBytes;
begin
     P3 := TLuxColorSpaces.DisplayP3;                        // 共有プリセット

     L := P3.ToLinear( TSingleRGB.Create( 0.5, 0.25, 0 ) );  // P3 の曲線で復号
     M := P3.ToSpace( TLuxColorSpaces.sRGB );                // 線形 P3 → 線形 sRGB（ 白色点が同じなので順応なし ）
     V := M * TDouble3D.Create( L.R, L.G, L.B );
     L := TLuxColorSpaces.sRGB.ToEncoded( TSingleRGB.Create( V.X, V.Y, V.Z ) );

     Icc := P3.IccProfile;                                   // ICC v4 表示プロファイル（行列＋para 曲線）
     S   := TLuxColorSpaces.FromIcc( Icc );                  // = P3（ 同じインスタンスに寄せられる ）

     S := TLuxColorSpace.Create( 'My camera', TDouble2D.Create( 0.70, 0.30 ), TDouble2D.Create( 0.20, 0.75 ),
                                              TDouble2D.Create( 0.13, 0.05 ), LUX_WHITE_D65, TLuxTransfer.Gamma( 2.2 ) );
     S := TLuxColorSpaces.Intern( S );                       // プログラムの終了まで生かす
end;
```

## 5. 参考文献

1. E. Reinhard, M. Stark, P. Shirley and J. Ferwerda, [*Photographic Tone Reproduction for Digital Images*](https://doi.org/10.1145/566570.566575), ACM Transactions on Graphics, vol. 21, no. 3, pp. 267–276, 2002.
2. G. Ward, [*Real Pixels*](https://www.realtimerendering.com/resources/GraphicsGems/), in Graphics Gems II, Academic Press, pp. 80–83, 1991.
3. IEEE, [*IEEE Standard for Floating-Point Arithmetic (IEEE Std 754-2019)*](https://doi.org/10.1109/IEEESTD.2019.8766229), IEEE, 2019.
4. International Color Consortium, [*Specification ICC.1:2022 — Image technology colour management — Architecture, profile format, and data structure*](https://www.color.org/specification/ICC.1-2022-05.pdf), ICC, 2022.
5. IEC, [*IEC 61966-2-1:1999 — Multimedia systems and equipment — Colour measurement and management — Part 2-1: Colour management — Default RGB colour space — sRGB*](https://webstore.iec.ch/publication/6169), IEC, 1999.
6. ITU-R, [*Recommendation BT.2020-2 — Parameter values for ultra-high definition television systems for production and international programme exchange*](https://www.itu.int/rec/R-REC-BT.2020), ITU, 2015.
7. ISO, [*ISO 22028-2:2013 — Photography and graphic technology — Extended colour encodings for digital image storage, manipulation and interchange — Part 2: Reference output medium metric RGB colour image encoding (ROMM RGB)*](https://www.iso.org/standard/56591.html), ISO, 2013.
8. K. M. Lam, *Metamerism and Colour Constancy*, Ph.D. thesis, University of Bradford, 1985 ── Bradford 変換。[4] に採用されている。
9. Academy of Motion Picture Arts and Sciences, [*ACEScg — A Working Space for CGI Render and Compositing (S-2014-004)*](https://docs.acescentral.com/specifications/acescg/), AMPAS, 2014.

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [**Delphi**](https://www.embarcadero.com/jp/products/delphi)
ネイティブなクロスプラットフォームアプリを開発するための統合開発環境（ＩＤＥ）。
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/jp/products/delphi/starter)
