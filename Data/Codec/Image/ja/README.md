# LUX.Data.Codec.Image
[English](../README.md) | [日本語](README.md)

Delphi 向けの画像のコーデック：PNG・JPEG・Radiance HDR。コーデックは、ストリームと画素の並びの間を変換するだけで、画素を入れる入れ物を知らない。ゆえに、同じコーデックで、タイル画像にも、ビットマップにも、素の配列にも、GPU の画像にも読み込める。

## 1. 概要

| ユニット | 主な型 | 役割 |
|---|---|---|
| `LUX.Data.Codec.Image` | `TImageHeader` ・ `TImageRaster` ・ `TImageCodec` ・ `EImageCodec` | 画像の形、入れ物への口、形式の基底クラスと登録簿 |
| `LUX.Data.Codec.Image.Png` | `TImageCodecPng` ・ `TImagePngLevel` | PNG（ `System.ZLib` の上に直接に実装 ） |
| `LUX.Data.Codec.Image.Jpg` | `TImageCodecJpg` | JPEG（ RAD Studio に同梱の Skia のコーデックを使う ） |
| `LUX.Data.Codec.Image.Hdr` | `TImageCodecHdr` | Radiance HDR（ `.hdr` ・ `.pic` ） |

### 1.1 特徴

- **入れ物に依存しない。** コーデックは、入れ物を `TImageRaster` を通してだけ見る。入れ物を足すにはラスターのクラスを 1 つ、形式を足すにはコーデックのクラスを 1 つ書けばよく、互いを直さない。
- **通貨は 1 つ。** 画素は `TSingleRGBA` で受け渡す。32 ビットの実数は、8 ビット・16 ビットの整数の標本も、RGBE の値も、誤差なく表せる。
- **並べ直しのための 1 枚ぶんの領域を持たない。** 画素は、始点と歩みを持つ並びとして渡るので、インターレースのパスも、どの向きの走査線も、復号したそばから渡される。
- **設定はプロパティ。** PNG は `Alpha` と `Level` 、JPEG は `Quality` を持つ。別の形式の指定を運ぶメソッドは無い。
- **状態を持たない。** コーデックが持つのは設定だけなので、 `Clone` した写しを別のスレッドで走らせられる。
- **中身で見分ける。** 読むときは、ストリームの先頭のバイトから形式を見つける。ゆえに、拡張子が何であっても、無くても、ファイルは開ける。書くときは、拡張子で形式を選ぶ。登録簿は、保存のダイアログのフィルター文字列も作る。
- **色空間**を、形式ごとのメタデータから読み、そこへ書く。

### 1.2 動作要件

- RAD Studio 12 以降（開発と試験は RAD Studio 13 / Delphi 37.0 ）
- `LUX.Data.Codec.Image.Jpg` は Skia（ RAD Studio に同梱 ）を使う。 `sk4d.dll` を実行ファイルと同じ場所に配置すること。ほかのユニットは RTL だけに依存する。

## 2. 技術的背景

### 2.1 画素の並び

コーデックと入れ物は、画素を *並び* で受け渡す。並びは、始点 $(x, y)$ ・歩み $(d_x, d_y)$ ・個数 $n$ であり、その $i$ 番目の画素は、

$$( x + i d_x , \quad y + i d_y ) \qquad i = 0, \dots, n-1 \qquad \text{(2.1)}$$

にある。原点は左上で、 $x$ は右向き、 $y$ は下向きである。ふつうの行は、歩みが $(1, 0)$ の並びである。コーデックが出会うほかの場合も、歩みの違う同じものである。

| 元 | 始点 | 歩み |
|---|---|---|
| インターレースの無い画像の行 $y$ | $(0, y)$ | $(1, 0)$ |
| 原点 $(x_0, y_0)$ ・間隔 $(s_x, s_y)$ の Adam7 のパスの行 $j$ | $(x_0, \ y_0 + j s_y)$ | $(s_x, 0)$ |
| 右から左へ入っている Radiance の走査線 | $(w - 1, \ y)$ | $(-1, 0)$ |
| 列である Radiance の走査線 | $(x, 0)$ または $(x, \ h - 1)$ | $(0, 1)$ または $(0, -1)$ |

歩みが並びの一部なので、復号は、走査線を復号したそばから渡し、画素を順に並べるための 1 枚ぶんの領域を持たない。

復号は、まず `Raster.Header` を書き（入れ物は、ここで大きさと色空間を決める）、その後、どの画素もちょうど 1 回渡す。符号化は、 `Raster.Header` を読み、要る並びを取る。

### 2.2 PNG

読み込みは、仕様 [1] の定める形式の全体に対応する。圧縮されたデータは DEFLATE [2] である。

| | 対応 |
|---|---|
| ビット深度 | 1 ・ 2 ・ 4 ・ 8 ・ 16 |
| カラータイプ | 0 グレイスケール、2 トゥルーカラー、3 パレット、4 グレイスケール＋α、6 トゥルーカラー＋α |
| 透明度 | `tRNS` の 3 つの形のすべて ―― パレットの α、グレイスケールの透明色、RGB の透明色 |
| インターレース | 無し、および Adam7 |

書き出しは、α つきのトゥルーカラー（ `Alpha` が `False` なら α 無し）で、ラスターの `Depth` が 8 以下なら 8 ビット、それより大きければ 16 ビットである。どの走査線にも Paeth の予測のフィルターを掛ける。標本は 0〜1 に収める。

`Level` は、DEFLATE の手間を選ぶ。PNG は可逆なので、圧縮率が変えるのは大きさと時間であり、画素は決して変わらない。zlib のレベルは 0〜9 あるが、大きさが目立って変わるのは 4 点だけで、それが `TImagePngLevel` の 4 つの値である。

| `Level` | zlib |
| --- | --- |
| `plNone` | 0（ stored ） |
| `plFastest` | 1 |
| `plDefault` | 6 |
| `plMax` | 9 |

`plNone` は、DEFLATE の *stored* ブロックを書く ―― どのデコーダーでも読める、ふつうの PNG であり、大きさより書く速さが大事なときに選ぶ設定である。

### 2.3 JPEG

JPEG は Skia [5] を通す。Skia は、1 枚の画像を連続した 1 つの領域で扱うので、読み書きの間だけ `幅 × 高さ × 4` バイトを使う。規格 [3] は、一辺を 65,535 画素までとしている。JPEG は、α を持たない 8 ビットの形式である。復号した画素の α は 1 であり、符号化は、0〜1 に収め、α を捨てる。

### 2.4 Radiance HDR

形式は Radiance の画像ファイル [6] のものであり、コーデックは、公式の実装 [7] に従う。

1 画素は 4 バイト：3 つの仮数と、共通の指数 $e$ である。仮数 $m$ は、その区間の中点を表す。

$$v = \frac{m + 0.5}{256} \cdot 2^{ e - 128 } \qquad \text{(2.2)}$$

$e = 0$ は黒である。逆向きでは、最大の成分を、 $[ 0.5, 1 )$ の小数と指数に分け、各成分に同じ 2 の冪を掛けて切り捨てる。ゆえに、最大の仮数は 128 以上であり、往復の誤差は、どの成分も、最大の成分の $1 / 256$ 以下である。

走査線は、次の 3 つのどれかで入っている。すべてを読む。

| 入り方 | 並び |
|---|---|
| 無圧縮 | 画素が、4 バイトずつ並ぶ |
| 古い連長 | 画素 `( 1, 1, 1, n )` が、直前の画素を $n$ 回繰り返す。続けて現れると、 $n$ の桁が 8 ビットずつ上がる |
| 新しい連長 | 先頭の `( 2, 2, 上位, 下位 )` が長さを表す。その後、4 つの成分のそれぞれを、1 バイトの繰り返し（ 128 を超える長さのバイト ）か、128 バイトまでのそのままの並びの、まとまりで表す |

解像度の行 `{+-}{XY} n {+-}{YX} m` は、走査線の並ぶ軸、走査線の中の軸の順に書く。ファイルの座標は $y$ が上向きなので、走査線の順が画像の座標と逆になるのは、X の符号が `-` のとき、Y の符号が `+` のときである。8 通りのすべてを読み、走査線を、対応する始点と歩みの並びとして渡す。

`FORMAT=32-bit_rle_rgbe` と `FORMAT=32-bit_rle_xyze` を読む（ `FORMAT` の無いファイルは RGBE と見なす ）。XYZ の画素は、ファイルの色空間の RGB に直す。値は、入っているまま渡す： `EXPOSURE` と `COLORCORR` は当てはめない。

書き出しは、RGBE を、標準の向き `-Y h +X w` で書く。幅が 17〜32,767 なら新しい連長、それ以外は無圧縮である。この形式は α を持たず、負の成分は 0 になる。

### 2.5 色空間

`TImageHeader.ColorSpace` は、 `LUX.Color.Space` の `TLuxColorSpace` であり、分からないときは `nil` である。ファイルから読んだ色空間は、 `TLuxColorSpaces` に内容で登録されるので、プリセットを表すプロファイルはそのプリセットになり、色空間は参照で比べられる。

| 形式 | 書き | 読み |
|---|---|---|
| PNG | sRGB は `sRGB` チャンクと `gAMA` ・ `cHRM` 。ほかの色空間は `iCCP` と `cHRM`（伝達関数が純粋なガンマなら `gAMA` も）。 `nil` なら何も書かない | `iCCP` 、 `sRGB` 、 `gAMA` ＋ `cHRM` の順に採る。どれも無ければ `nil` |
| JPEG | ICC プロファイル [4] を、APP2 の `ICC_PROFILE` セグメントとして。 `nil` なら何も書かない | そのセグメントをつなげて解く。無ければ `nil` |
| Radiance HDR | 画素を線形に直し、原色を `PRIMARIES=` に書く。 `nil` なら、画素をそのまま書き、 `PRIMARIES=` は書かない | `PRIMARIES=` の原色の、無ければ形式の既定の原色の、線形の色空間 |

## 3. アーキテクチャ

```
[ ユニットと、宣言するもの ]

・LUX.Data.Codec.Image                ･･･ RTL のみ
  ┣・TImageHeader                    ･･･ ( Width, Height, ColorSpace, Depth )
  ┣・TImageRaster                    ･･･ 抽象：Header ・ GetLine ・ SetLine
  ┣・TImageCodec                     ･･･ Decode ・ Encode。抽象：DoDecode ・ DoEncode
  ┃  ┣・Extensions / Caption         ･･･ 形式の拡張子と名前
  ┃  ┣・Matches / ClassOf            ･･･ 先頭のバイトから見分けた、ストリームの形式
  ┃  ┣・Regist / Codecs              ･･･ 形式の登録簿
  ┃  ┣・ClassFor / CreateFor         ･･･ ファイル名の形式
  ┃  ┣・DialogFilter                 ･･･ ダイアログの Filter
  ┃  ┗・Assign / Clone               ･･･ 設定の写し
  ┣・EImageCodec                     ･･･ 形式に合わないデータ
  ┣・LUX.Data.Codec.Image.Png        ･･･ System.ZLib のみ
  ┃  ┣・TImagePngLevel               ･･･ ( plNone, plFastest, plDefault, plMax )
  ┃  ┗・TImageCodecPng               ･･･ Alpha ・ Level
  ┣・LUX.Data.Codec.Image.Jpg        ･･･ [ Skia ]
  ┃  ┗・TImageCodecJpg               ･･･ Quality
  ┗・LUX.Data.Codec.Image.Hdr        ･･･ RTL のみ
     ┗・TImageCodecHdr

[ クラス階層 ]

・TImageCodec
  ┣・TImageCodecPng
  ┣・TImageCodecJpg
  ┗・TImageCodecHdr

[ 依存 ]  橋 → コーデック → 色

・橋                                  ･･･ 入れ物 1 つのために TImageRaster を派生
  ┗・LUX.Data.Codec.Image.*          ･･･ TImageRaster だけを知る
     ┗・LUX.Color  LUX.Color.Space   ･･･ TSingleRGBA ・ TByteRGBE ・ TLuxColorSpace
```

橋は、入れ物の側に置く。 `TLuxImage` の隣にある `LUX.Data.Image.Codec` がその 1 つである： `TLuxImageRaster` が画像をラスターとして見せ、 `TLuxImageFiler` が進捗・ミップピラミッド・非同期の動作を足す。

新しい形式は、新しいユニット 1 つである： `TImageCodec` から派生し、 `Extensions` ・ `Caption` ・ `Matches` ・ `DoDecode` ・ `DoEncode` を実装し、形式の設定をプロパティとして公開して `Assign` で写し、ユニットの `initialization` でクラスを `Regist` する。

## 4. 使い方

### 4.1 自前のラスター

```pascal
uses LUX.Color, LUX.Data.Codec.Image;

type
  TArrayRaster = class( TImageRaster )
  private
    _Header :TImageHeader;
    _Pixels :TArray<TSingleRGBA>;
  protected
    function GetHeader :TImageHeader; override;
    procedure SetHeader( const Header_:TImageHeader ); override;
  public
    procedure GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); override;
    procedure SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); override;
  end;

function TArrayRaster.GetHeader :TImageHeader;
begin
     Result := _Header;
end;

procedure TArrayRaster.SetHeader( const Header_:TImageHeader );
begin
     _Header := Header_;

     SetLength( _Pixels, Header_.Width * Header_.Height );
end;

procedure TArrayRaster.GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );
var
   I :Integer;
begin
     for I := 0 to N_-1 do Pixels_[ I ] := _Pixels[ ( Y_ + I * DY_ ) * _Header.Width + ( X_ + I * DX_ ) ];
end;

procedure TArrayRaster.SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );
var
   I :Integer;
begin
     for I := 0 to N_-1 do _Pixels[ ( Y_ + I * DY_ ) * _Header.Width + ( X_ + I * DX_ ) ] := Pixels_[ I ];
end;
```

### 4.2 読み書き

```pascal
uses System.Classes, LUX.Data.Codec.Image, LUX.Data.Codec.Image.Png, LUX.Data.Codec.Image.Jpg, LUX.Data.Codec.Image.Hdr;

Raster := TArrayRaster.Create;

Stream := TFileStream.Create( 'sky.hdr', fmOpenRead );
Codec  := TImageCodec.ClassOf( Stream ).Create;          // 中身から TImageCodecHdr が選ばれる
try
   Codec.Decode( Stream, Raster );                       // Raster.Header が、大きさと色空間になる
finally
   Stream.Free;
   Codec .Free;
end;

Png    := TImageCodecPng.Create;
Stream := TFileStream.Create( 'sky.png', fmCreate );
try
   Png.Level := plFastest;

   Png.Encode( Stream, Raster );
finally
   Stream.Free;
   Png   .Free;
end;
```

### 4.3 ダイアログ

```pascal
OpenDialog1.Filter := TImageCodec.DialogFilter( '画像' );     // '画像 (*.png;*.jpg;…)|…|PNG (*.png)|*.png|…'
SaveDialog1.Filter := TImageCodec.DialogFilter;               // 形式ごとに 1 項目
```

## 5. API リファレンス

### 5.1 TImageHeader

```pascal
Width      :Integer;         // 横の画素の数（ 1 以上 ）
Height     :Integer;         // 縦の画素の数（ 1 以上 ）
ColorSpace :TLuxColorSpace;  // 画素の値の色空間。分からなければ nil 。所有しない
Depth      :Integer;         // 標本 1 つのビット数。実数は 32
```

### 5.2 TImageRaster

```pascal
property Header :TImageHeader;   // 読む：いまの形　　書く：この大きさと色空間になる
procedure GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );  // 並びを読む
procedure SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );  // 並びを書く
```

`Header` を書くと、入れ物がそれまで持っていた画素は失われる。標本の精度が決まっている入れ物は、 `Depth` に従わなくてよい。

### 5.3 TImageCodec

```pascal
constructor Create; virtual;

///// 形式
class function Extensions :TArray<String>;     // 小文字・点つき。先頭が既定
class function Caption :String;
class function Handles( const FileName_:String ) :Boolean;
class function Matches( const Bytes_:TBytes ) :Boolean;              // この形式の、先頭のバイトか

///// 登録簿
class procedure Regist( const Codec_:TImageCodecClass );             // ユニットの initialization から
class function Codecs :TArray<TImageCodecClass>;                     // 登録の順
class function ClassOf( const Stream_:TStream ) :TImageCodecClass;   // 中身から。どの形式でもなければ nil 。位置は変えない
class function ClassFor( const FileName_:String ) :TImageCodecClass; // 拡張子から。知らない拡張子なら nil
class function CreateFor( const FileName_:String ) :TImageCodec;     // 知らない拡張子なら nil
class function DialogFilter( const Caption_:String = '' ) :String;

///// 設定
procedure Assign( const Codec_:TImageCodec );
function Clone :TImageCodec;

///// 変換
procedure Decode( const Stream_:TStream; const Raster_:TImageRaster );   // 先頭のバイトを確かめてから DoDecode
procedure Encode( const Stream_:TStream; const Raster_:TImageRaster );   // 大きさを確かめてから DoEncode
```

```pascal
TImageCodecPng    property Alpha :Boolean;      // α を書くか              （既定 True ）
                  property Level :TImagePngLevel;    // plNone 〜 plMax         （既定 plDefault ）

TImageCodecJpg    property Quality :Integer;    // 1 〜 100 に収める       （既定 90 ）
```

形式に合わないデータは `EImageCodec` を送出する。途中で終わるストリームは、代わりに、ストリーム自身の `EReadError` を送出することがある。 `Encode` は、大きさの無い画像を、何も書かないうちに断る。

## 6. 制限

- JPEG は、1 枚の画像を 1 つの領域に置く必要があり、一辺は 65,535 画素までである。
- PNG の書き出しは、パレット・グレイスケール・インターレースのファイルを作らない。
- Radiance HDR： `EXPOSURE` ・ `COLORCORR` ・ `PIXASPECT` ・ `VIEW` は、当てはめず、保ちもしない。スペクトルの画像（ `Radiance_spectra` ）は読まない。XYZE は書かない。

## 7. 参考文献

1. W3C, [*Portable Network Graphics (PNG) Specification (Third Edition)*](https://www.w3.org/TR/png-3/), W3C Recommendation, 2025.
2. P. Deutsch, [*DEFLATE Compressed Data Format Specification version 1.3*](https://www.rfc-editor.org/rfc/rfc1951), RFC 1951, IETF, 1996.
3. ITU-T, [*Recommendation T.81: Digital compression and coding of continuous-tone still images — Requirements and guidelines*](https://www.itu.int/rec/T-REC-T.81), ITU-T, 1992.
4. International Color Consortium, [*Specification ICC.1:2022 — Image technology colour management — Architecture, profile format, and data structure*](https://www.color.org/specification/ICC.1-2022-05.pdf), ICC, 2022.
5. [*Skia Graphics Library*](https://skia.org/), Google.
6. G. Ward, [*Radiance File Formats*](https://radsite.lbl.gov/radiance/refer/filefmts.pdf), Lawrence Berkeley National Laboratory.
7. Lawrence Berkeley National Laboratory, [*Radiance*](https://github.com/LBNL-ETA/Radiance), ソースコード（ `src/common/color.c` ・ `color.h` ・ `resolu.c` ・ `header.c` ）.

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [**Delphi**](https://www.embarcadero.com/jp/products/delphi)
ネイティブなクロスプラットフォームアプリを開発するための統合開発環境（ＩＤＥ）。
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/jp/products/delphi/starter)
