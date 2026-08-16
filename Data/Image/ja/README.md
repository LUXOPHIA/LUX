# LUX.Data.Image
[English](../README.md) | [日本語](README.md)

Delphi / FireMonkey 向けの超高解像度画像ライブラリ。`TLuxImage` は画素をすべて CPU メモリ上のタイル化された縮小ピラミッドとして保持するので、扱える大きさは GPU のテクスチャ制限に縛られず、RAM の許す限り無制限である。付属のビューアは、画像の大きさではなく窓の大きさで決まるコストでリアルタイムに表示する。タイルは自身の変更を追跡するので、多数のスレッドが同時に描き込みながら、その進行をブロック単位で画面に映し出せる。

## 1. 概要

FireMonkey の `TBitmap` は GPU とデータを共有するため GPU のテクスチャサイズ制限をそのまま受け、実際には 8,192 × 8,192 画素程度が上限となる。`TLuxImage` はそうではない。画素はふつうのヒープ領域に 256 × 256 のタイルに分けて置かれ、画像のどの部分も同時に GPU 上に常駐する必要がない。

### 1.1 特徴

- **GPU のサイズ制限を受けない。** 画素は CPU メモリ上に 256 × 256 のタイルで保持する。
- **メモリは前もって全て確保する。** `SetSize` が全段の全タイルを確保する。載らなければその場で `EOutOfMemory` になり、後から失敗することはない。
- **4 つの画素形式**。いずれも Skia のネイティブなカラータイプに 1 対 1 で対応する。8bit ・ 16bit の符号無整数、16bit ・ 32bit の浮動小数、すべて RGBA。
- **縮小ピラミッドを内蔵**し、全景表示も拡大表示も同じコストで描ける。加えて**タイル単位の変更追跡**により、1 タイルの変更は画像の 3 分の 1 ではなくタイルの 3 分の 1 の費用でピラミッドへ反映される。
- **ロック無しの並行書き込み。** 任意の数のスレッドが互いに素な領域へ同時に書き、終えたタイルを `TileChanged` で報せる。ビューアはそれをリアルタイムに拾う。
- **`TLuxImageWorker`**。任意のブロック処理を画像全体にわたって全コアで実行するスケジューラ。ブロックを 1 個ずつ配るので、レイトレーシングやフラクタルのように画素ごとの計算量が桁で違っても均される。
- **リアルタイムビューア**。滑らかなホイールズームとドラッグスクロール、GPU によるトーンマッピングとガンマ補正。描画途中の画像をブロック単位で映し出す。
- **色管理。** 画像は `ColorSpace` ── sRGB ・ Display P3 ・ Adobe RGB ・ Rec.2020 ・ ProPhoto ・ ACEScg とそれらの線形版、あるいは自作の空間 ── を持てる。保存時に PNG（`sRGB` / `iCCP` ＋ `gAMA` ＋ `cHRM`）と JPEG（APP2 `ICC_PROFILE`）へ埋め込まれ、読み込み時に復元され、ビューアはモニター自身のプロファイルへ GPU で変換して表示する。`nil` なら色管理なし。画素値はどの段階でも変えない。
- **非同期のファイル入出力**。進捗の通知と完了イベントを備える。
- 依存は RTL ・ FireMonkey ・ Skia のみ。いずれも RAD Studio に標準搭載。

### 1.2 動作要件

- RAD Studio 12 以降（RAD Studio 13 / Delphi 37.0 で開発・確認）
- Windows 64bit
- Skia（RAD Studio 同梱）。`sk4d.dll` を実行ファイルと同じ場所に配置すること

## 2. 技術的背景

### 2.1 タイル保持と縮小ピラミッド

画素は一辺 `LUXIMAGE_TILE`（256）のタイルに分けて、タイルごとに別々のヒープ領域へ保持する。これにより巨大な連続確保を避けられ、読み書きやバイリニア補間はふつう同一タイル内に収まる。タイルに余白は無い。1 枚のタイルは `256 × 256 × PixelSize` バイトの素の領域で、行ピッチは 256 画素である。

全段の全タイルは `SetSize` が確保する。遅延確保は一切しないので、`TileData` が返すポインタは常に有効であり、互いに素な領域へ書き込む 2 つのスレッドが確保で競合することもなく、メモリに載らない画像は読み込みや描画の途中ではなく `SetSize` の時点で拒否される。`SetSize` は確保に先立って必要量を物理メモリの空きと比べ、超えていれば確保を試みずに拒否する ── 上限は RAM であってページファイルではない、というのがこのライブラリの前提である。

各画像は半分ずつの縮小段を持つ。段 0 が原寸で、以降は縦横とも半分（切り上げ）になり 1 × 1 まで続く。

```math
W_{\ell+1} = \max\!\left( 1, \left\lceil \frac{W_\ell}{2} \right\rceil \right), \qquad H_{\ell+1} = \max\!\left( 1, \left\lceil \frac{H_\ell}{2} \right\rceil \right) \qquad \text{(2.1)}
```

$T$ を `LUXIMAGE_TILE` とすると、段 $\ell$ が保持するタイル数は

```math
\mathrm{TilesX}_\ell = \left\lceil \frac{W_\ell}{T} \right\rceil, \qquad \mathrm{TilesY}_\ell = \left\lceil \frac{H_\ell}{T} \right\rceil \qquad \text{(2.2)}
```

であり、右端と下端のタイルは部分的にしか埋まらない。

各段は一つ下の段の 4 分の 1 の画素しか持たないので、ピラミッドの費用は基底段に対して有界な割合に収まる。

```math
\sum_{\ell=1}^{\infty} \frac{1}{4^{\ell}} = \frac{1}{3} \qquad \text{(2.3)}
```

したがってピラミッドは段 0 のメモリに約 33% を加え、`SetSize` が確保する総量はおよそ $\tfrac{4}{3}\,W H \cdot$ `PixelSize` である。

### 2.2 変更の追跡と縮小段の差分更新

段 0 の各タイルは *Dirty* フラグを、全段の各タイルは内容が変わるたびに進む *Stamp* を持つ。`TileChanged` はフラグを立てて Stamp を進める。不可分操作の 2 回で済むので、どのスレッドからでもロック無しに呼べる。

`UpdateLevels` は Dirty なタイルを集め、その*足跡*だけを上の段に作り直す。段 0 のタイル $(t_x, t_y)$ の段 $\ell$ における足跡は正方形

```math
\left[\, t_x \frac{T}{2^{\ell}},\; (t_x + 1) \frac{T}{2^{\ell}} \right) \times \left[\, t_y \frac{T}{2^{\ell}},\; (t_y + 1) \frac{T}{2^{\ell}} \right) \qquad \text{(2.4)}
```

であり、$\ell \le \log_2 T = 8$ の範囲では 1 画素以上の大きさを持ち、同じタイルの段 $\ell - 1$ における足跡だけから計算できる。したがってタイルごとの連鎖は段 8 まで互いに独立で、Dirty なタイル 1 枚につき 1 連鎖を並列に走らせる。段 8 より上では足跡が 1 画素未満になって隣のタイルと混ざるので、それらの段は丸ごと作り直す ── 画素数は高々 $W H / 4^{9}$ で、無視できる。

1 連鎖の仕事量はタイルの 4 分の 1、16 分の 1、…であるから

```math
\sum_{\ell=1}^{8} \frac{1}{4^{\ell}} \approx \frac{1}{3} \qquad \text{(2.5)}
```

となり、変更の反映には変わったタイルの約 3 分の 1 の費用しかかからない。画像全体の変更（`Changed`、あるいはファイルの読み込み）も全タイルを Dirty にして同じ経路を通り、その費用は従来のピラミッド全構築と同じ画像の 3 分の 1 である。

ビューアはタイルごとの GPU キャッシュを Stamp で検証し（キャッシュ画像はのりしろとして周囲 8 枚の画素も含むので、それらの Stamp も合わせて）、毎フレームの描画前に `UpdateLevels` を呼ぶ。したがって多数のスレッドからタイルを書き込むレンダラの結果は、`TileChanged` と `Notify` 以外に何の結合も無しに、ブロック単位で画面に現れる。

### 2.3 並列ブロックスケジューリング

`TLuxImageWorker` は段 0 をタイルをまたがない正方形のブロックに刻み、ラスタ順に番号を振り、単一の不可分カウンタで $N$ 本のワーカースレッドに 1 個ずつ配る。範囲を静的に割り当てないので、画素ごとの計算量がどう分布していても最後の待ちは高々ブロック 1 個ぶんに収まる ── 隣り合う画素で計算量が桁違いになるレイトレーシングでは、この性質が効く。全タイルが確保済みでブロックは互いに素なので、ワーカーはロックを必要としない。各ワーカーは終えたブロックを `TileChanged` で報せ、約 30 Hz に間引いて画像に `Notify` させ、メインスレッドで `OnProgress` を発火する。

### 2.4 段の選択

画像 1 画素あたりの画面画素数を表示倍率 $s$ とすると、ビューアが描画に用いる段は

```math
\ell = \min\!\left( \max\!\left( 0, \left\lfloor -\log_2 s \right\rfloor \right), \; \mathrm{LevelsN} - 1 \right) \qquad \text{(2.6)}
```

であり、その段における実効倍率は

```math
S = s \cdot 2^{\ell} \in (\,\tfrac{1}{2}, 1\,] \qquad (s < 1) \qquad \text{(2.7)}
```

となる。つまり段を拡大することは決してなく、残るのは高々 2 倍の縮小で、それはちょうど GPU のミップマップ標本化が受け持つ範囲である。キャッシュするタイルはすべてミップマップ付きテクスチャとして GPU に置き、トリリニアで描くので、サンプラはタイルの LOD 0（段 $\ell$）と LOD 1（2 × 2 平均。段 $\ell + 1$ と同じもの）の間を LOD $= -\log_2 S \in [0, 1)$ で補間する。結果として隣接 2 段が連続にブレンドされ ── GPU がテクスチャの縮小に使うのと同じトリリニア、画像編集ソフトのズーム表示と同じ品質 ── 粗い段を拡大するボケも、細かい段を縮小するエイリアシングも、どの倍率でも出ない。等倍以上（$s \ge 1$）は段 0 を最近傍で描き、画素が四角として見える。可視タイル数は画像ではなく窓によって上から抑えられる。

```math
N_{\text{tiles}} \le \left( \left\lceil \frac{W_{\text{view}}}{S \cdot T} \right\rceil + 1 \right) \left( \left\lceil \frac{H_{\text{view}}}{S \cdot T} \right\rceil + 1 \right) \qquad \text{(2.8)}
```

1920 × 1080 の窓なら、$S \to \tfrac{1}{2}$ で最大およそ 17 × 10 = 170 枚で、画像の大きさによらない。

### 2.5 表示の伝達関数

ビューアはガンマ補正

```math
C' = C^{\,1/\gamma} \qquad \text{(2.9)}
```

を適用し、任意で白色点 $L_w$（`White` プロパティ。既定 1）による拡張 Reinhard のトーンマッピング演算子 [4] を適用する。

```math
C' = \operatorname{clamp}\!\left( \frac{C \left( 1 + C / L_w^{\,2} \right)}{1 + C}, \; 0, \; 1 \right) \qquad \text{(2.10)}
```

いずれも SkSL のランタイムカラーフィルタ、つまり GPU で評価されるので、`Gamma` ・ `ToneMap` ・ `White` の変更はただ同然で、タイルキャッシュも無効化しない。

## 3. アーキテクチャ

### 3.1 モジュールとクラスの構成

```
[ units and what they declare ]

・LUX.Data.Image                      ･･･ RTL only
  ┣・TLuxPixel                       ･･･ ( bpUInt08 … bpSFlo32 )
  ┣・TLuxTile                        ･･･ ( Data, Stamp, Dirty )
  ┣・TLuxLevel                       ･･･ ( Width, Height, Tiles* )
  ┣・TLuxImage                       ･･･ ( see the class hierarchy below )
  ┣・LUX.Data.Image.Files            ･･･ [ Skia ]
  ┃  ┣・TLuxImageFiler
  ┃  ┃  ┣・LoadFromPng / SaveToPng ･･･ System.ZLib, streaming
  ┃  ┃  ┗・LoadFromJpg / SaveToJpg ･･･ Skia codec
  ┃  ┣・LuxSkColorType
  ┃  ┗・LuxImageSize
  ┣・LUX.Data.Image.Worker           ･･･ RTL only
  ┃  ┣・TLuxBlockProc                ･･･ procedure( ThreadI_, X_,Y_,W_,H_ )
  ┃  ┗・TLuxImageWorker              ･･･ block scheduler on N threads
  ┗・LUX.Data.Image.Viewer           ･･･ [ FireMonkey + Skia ]
     ┗・TLuxImageViewer              ･･･ ( TFrame )
        ┣・TTileKey  TTileImg
        ┣・ISkImage cache + apron    ･･･ validated by tile stamps
        ┣・SkSL colour filter
        ┗・wheel zoom / drag scroll

[ class hierarchy ]

・TLuxImage
  ┣・TLuxImageUInt08                 ･･･ TByteRGBA
  ┣・TLuxImageUInt16                 ･･･ TWordRGBA
  ┣・TLuxImageSFlo16                 ･･･ THalfRGBA
  ┗・TLuxImageSFlo32                 ･･･ TSingleRGBA

[ pixel path ]  tiles → mip pyramid → Skia

・TLuxImage
  ┗・level 0                         ･･･ original pixels, 256 × 256 tiles, Dirty + Stamp
     ┗・mip pyramid                  ･･･ level ℓ+1 = half of ℓ ( UpdateLevels, footprints of dirty tiles )
        ┗・level chosen by (2.6)     ･･･ effective scale S ∈ ( ½, 1 ], trilinear on the GPU
           ┗・visible tiles of it    ･･･ bounded by (2.8), not by the image
              ┗・ISkImage + apron    ･･･ cached as TTileImg under TTileKey, rebuilt when a stamp moves
                 ┗・DrawImageRect    ･･･ SkSL colour filter: tone map + gamma

[ writer path ]  any thread → tiles → viewer

・TLuxImageWorker ( or your own threads )
  ┗・block                           ･･･ SetRow / SetRaws / TileData, disjoint per block
     ┗・TileChanged                  ･･･ Dirty := 1, Stamp++  ( atomic, no lock )
        ┗・Notify  ( ≤ 30 Hz )       ･･･ OnChange on the main thread
           ┗・viewer frame           ･･･ UpdateLevels, then draw

[ supporting units of the LUX standard library ]

・LUX                                 ･･･ base declarations, TDelegates
  ┣・LUX.Color                       ･･･ TByteRGBA  TWordRGBA  TSingleRGBA
  ┃  ┣・LUX.Color.Half              ･･･ THalfRGB  THalfRGBA
  ┃  ┗・LUX.Color.Space             ･･･ TLuxColorSpace, presets, TLuxColorSpaces, ICC read / write
  ┣・LUX.D2  LUX.D3  LUX.D3x3        ･･･ chromaticities, XYZ, 3 × 3 matrices
  ┗・LUX.D1.Half                     ･･･ THalf, the half-precision scalar
     ┗・LUX.D1.Half.DIff             ･･･ TdHalf, automatic differentiation
```

`LUX.Data.Image.pas` と `LUX.Data.Image.Worker.pas` は FireMonkey も Skia も uses していない。それらへの依存はファイル入出力とビューアのユニットに閉じている。

### 3.2 ファイル構成

```
・Data/Image/
  ┣・LUX.Data.Image.pas        ･･･ TLuxImage と 4 つの具象クラス
  ┣・LUX.Data.Image.Files.pas  ･･･ ファイルの読み書き
  ┣・LUX.Data.Image.Worker.pas ･･･ TLuxImageWorker、並列ブロックスケジューラ
  ┗・LUX.Data.Image.Viewer.pas ･･･ TLuxImageViewer（TFrame 継承）
```

## 4. 使い方

### 4.1 プロジェクトの設定

プロジェクトのソースファイルで Skia キャンバスを有効にし、Vulkan バックエンドが自身を登録できるよう `FMX.Skia.Canvas.Vulkan` を uses に入れる。

```pascal
uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  FMX.Skia.Canvas.Vulkan,
  ...

begin
  GlobalUseSkia                    := True;
  GlobalUseSkiaRasterWhenAvailable := False;

  Application.Initialize;
  ...
```

こうするとビューアはウィンドウのサーフェスへ直接描く。中間のラスタ面も、毎フレームの画面全体のテクスチャ転送も発生しない。設定しなくても動作はするが、その場合は中間のラスタへ描いてから転写するので、毎フレーム画面全体ぶんの転送コストがかかる。

### 4.2 読み込みと表示

```pascal
Image  := TLuxImageUInt08.Create;

Viewer        := TLuxImageViewer.Create( Self );
Viewer.Parent := Self;
Viewer.Align  := TAlignLayout.Client;
Viewer.Image  := Image;

Image.OnLoaded.Add( ImageLoaded );

Image.LoadFromFileAsync( 'huge.jpg' );
```

```pascal
procedure TForm1.ImageLoaded( Sender_:TObject );
begin
     Viewer.FitToWindow;
end;
```

### 4.3 全コアで画像へ描き込む

`TLuxImageWorker` は、利用者の手続きを画像の全ブロックについて実行する。手続きにはワーカー番号と段 0 の画素座標でのブロック矩形が渡され、そこで何を計算するか ── レイトレーシングの場面、フラクタル、別の画像に対するフィルタ ── は手続き次第である。ビューアが付いていれば、終わったブロックから順に表示される。

```pascal
Image := TLuxImageSFlo32.Create( 16384, 16384 );  // ここで全メモリを確保。載らなければ EOutOfMemory

Viewer.Image := Image;
Viewer.FitToWindow;

Worker := TLuxImageWorker.Create( Image );

Worker.OnProgress.Add( WorkerProgress );  // 約 30 Hz、メインスレッド
Worker.OnFinished.Add( WorkerFinished );  // メインスレッド。Cancel 後も発火する

Worker.Start( procedure( const ThreadI_,X_,Y_,W_,H_:Integer )
              var
                 Row  :TArray<TSingleRGBA>;
                 I, J :Integer;
              begin
                   SetLength( Row, W_ );

                   for J := Y_ to Y_+H_-1 do
                   begin
                        for I := 0 to W_-1 do Row[ I ] := Shade( X_+I, J );  // 任意の計算

                        Image.SetRow( 0, X_, J, W_, @Row[ 0 ] );
                   end;
              end );
```

`Block`（既定 64）はブロックの一辺、`ThreadsN`（既定は全プロセッサグループの論理 CPU 数）はスレッド数である。画像を読むだけの処理では `Writing := False` にすると、タイルが変更扱いにならない。

自前のスレッドでも同じことができる。互いに素な領域を `SetRow` ・ `SetRaws` ・ `TileData` で書き、書き終えた段 0 のタイルごとに `TileChanged` を呼び、表示を追い付かせたい時に（頻度は自分で抑えて）`Notify` を呼べばよい。

### 4.4 色空間

```pascal
Image.ColorSpace := TLuxColorSpaces.LinearRec2020;   // 「この画素は線形 Rec.2020 である」── 画素値そのものは触らない
Image.SaveToFile( 'render.png' );                     // iCCP ＋ cHRM ＋ gAMA が書かれる
Image.SaveToFile( 'render.jpg', 95 );                 // APP2 ICC_PROFILE が書かれる

Image.LoadFromFile( 'photo.jpg' );                    // Adobe RGB のプロファイル入り → Image.ColorSpace = TLuxColorSpaces.AdobeRGB
                                                      // 未知のプロファイル → 新しい TLuxColorSpace（ TLuxColorSpaces に登録される ）
                                                      // プロファイル無し → nil

Viewer.ColorSpace := nil;                             // 既定：モニター自身のプロファイルへ変換
Viewer.ColorSpace := TLuxColorSpaces.sRGB;            // または sRGB に固定
```

`ColorSpace` は参照であり、画像が所有することはない。プリセットは `TLuxColorSpaces` がプログラムの終了まで持ち、ファイルから読んだ空間もそこへ内容で登録されるので、画像にはどれでも自由に割り当てられ、比較はポインタで済む。

## 5. 画素形式

| クラス | 画素レコード | バイト/画素 | Skia のカラータイプ | 表示ガンマの既定値 |
|---|---|---|---|---|
| `TLuxImageUInt08` | `TByteRGBA` | 4 | `BGRA8888` | 1.0 |
| `TLuxImageUInt16` | `TWordRGBA` | 8 | `RGBA16161616` | 1.0 |
| `TLuxImageSFlo16` | `THalfRGBA` | 8 | `RGBAF16` | 2.2 |
| `TLuxImageSFlo32` | `TSingleRGBA` | 16 | `RGBAF32` | 2.2 |

各形式が Skia のネイティブなカラータイプに一致するため、ビューアは画素形式の変換をせずにタイルを GPU へ渡せる。16bit の浮動小数形式は IEEE 754 `binary16` [5] である。

α はストレート（乗算前）で保持する。

整数形式は既に表示用に符号化された値を保持しているとみなす（JPEG は既に sRGB）ので、表示ガンマの既定値は 1.0。浮動小数形式はリニアな値を保持しているとみなすので、既定値は 2.2 で、トーンマッピングも既定で有効になる。

## 6. API

### 6.1 TLuxImage

```pascal
///// 寸法（ SetSize は全段の全タイルを確保する。できなければ EOutOfMemory を送出し、画像は空のまま ）
procedure SetSize( const W_,H_:Integer );
procedure Clear;                        // 全段を 0 で埋める
property  Width  :Integer;
property  Height :Integer;

///// 形式
class function PixelKind :TLuxPixel;    // bpUInt08 / bpUInt16 / bpSFlo16 / bpSFlo32
class function PixelSize :Integer;      // 1 画素のバイト数
class function IsFloat :Boolean;
class function DefaultGamma :Single;

///// 画素アクセス（書式非依存）
property Colors[ const X_,Y_:Integer ] :TSingleRGBA; default;
procedure GetRow( const L_,X_,Y_,N_:Integer; const Dst_:PSingleRGBA );
procedure SetRow( const L_,X_,Y_,N_:Integer; const Src_:PSingleRGBA );

///// 画素アクセス（型付き。各具象クラスが宣言）
property Pixels[ const X_,Y_:Integer ] :TByteRGBA;    // TLuxImageUInt08
property Pixels[ const X_,Y_:Integer ] :TWordRGBA;    // TLuxImageUInt16
property Pixels[ const X_,Y_:Integer ] :THalfRGBA;    // TLuxImageSFlo16
property Pixels[ const X_,Y_:Integer ] :TSingleRGBA;  // TLuxImageSFlo32

///// 生値アクセス（タイル跨ぎを内部で処理する）
procedure GetRaws( const L_,X_,Y_,N_:Integer; const Dst_:Pointer );
procedure SetRaws( const L_,X_,Y_,N_:Integer; const Src_:Pointer );

///// 段とタイル
property LevelsN :Integer;
function LevelWidth ( const L_:Integer ) :Integer;
function LevelHeight( const L_:Integer ) :Integer;
function LevelTilesX( const L_:Integer ) :Integer;
function LevelTilesY( const L_:Integer ) :Integer;
function TileWidth  ( const L_,TX_:Integer ) :Integer;
function TileHeight ( const L_,TY_:Integer ) :Integer;
function TileData ( const L_,TX_,TY_:Integer ) :Pointer;   // 常に有効。行ピッチは LUXIMAGE_TILE 画素
function TileStamp( const L_,TX_,TY_:Integer ) :Cardinal;  // タイルの内容が変わるたびに進む

///// 変更の追跡
procedure TileChanged( const TX_,TY_:Integer );  // 段 0 のタイルを書いた：Dirty にして Stamp を進める（任意スレッド・ロック無し・イベント無し）
procedure Notify;                                // OnChange をメインスレッドで発火する
procedure Changed;                               // 全体が変わった：全タイル Dirty、Version++、Notify
procedure UpdateLevels;                          // Dirty なタイルを段 1 以上へ反映する（呼び出しは直列化される）

///// ファイル（同期）
procedure LoadFromFile( const FileName_:String );
procedure SaveToFile( const FileName_:String; const Quality_:Integer = 90; const Alpha_:Boolean = True );  // PNG：Alpha_=False なら α 無しの RGB。ColorSpace があれば埋め込む

///// ファイル（別スレッド）
procedure LoadFromFileAsync( const FileName_:String );
procedure SaveToFileAsync( const FileName_:String; const Quality_:Integer = 90; const Alpha_:Boolean = True );
procedure WaitFor;
property  Busy     :Boolean;
property  Progress :Single;      // 0 〜 1

///// 色空間（ LUX.Color.Space 。所有しない。nil = 色管理なし ）
property  ColorSpace :TLuxColorSpace;

///// 通知
property  Version    :Cardinal;  // SetSize ・ Clear ・ Changed で増える（ビューアは全キャッシュを捨てる）
property  OnChange   :TDelegates;
property  OnProgress :TDelegates;
property  OnLoaded   :TDelegates;
property  OnSaved    :TDelegates;
```

画素の書き込み ── `SetRow` ・ `SetRaws` ・ `TileData` 経由の直書き ── はそれ自体では何も印を付けない。書き終えた段 0 のタイルごとに `TileChanged` を、あるいは画像全体を触った後に `Changed` を 1 回呼び、表示を追い付かせたい時に `Notify` を呼ぶ。`Changed` は自分で通知する。1 画素ずつのプロパティセッタは、触ったタイルについて `TileChanged` を呼び、通知はしない。

`UpdateLevels` が Dirty なタイルを最新の縮小段に変える。ビューアは毎フレームの前に、ローダはファイルを読み終えた後に 1 回呼ぶ。段を自分で読むプログラムも呼ぶ必要がある。任意のスレッドから呼べて、同時の呼び出しは直列化される。他のスレッドがまだ別のタイルを書いている最中に呼んでも安全で、タイルは Dirty を降ろした後にしか読まれない。

`Colors[]` と `Pixels[]` は手軽だが、1 画素ごとにタイルを引くので一括処理には遅い。ローダやレンダラは行単位の呼び出しを使う。

保持しているタイルは余白を持たない。ビューアは描画キャッシュを作る際に、必要な 1 画素ののりしろを自分で集める。

### 6.2 TLuxImageWorker

```pascal
constructor Create( const Image_:TLuxImage );

property Image     :TLuxImage;
property Block     :Integer;    // ブロックの一辺。既定 64（ 1 〜 LUXIMAGE_TILE ）
property ThreadsN  :Integer;    // 既定：全プロセッサグループの論理 CPU 数
property Writing   :Boolean;    // 既定 True：ブロックごとに TileChanged。読むだけなら False
property Busy      :Boolean;
property Cancelled :Boolean;
property Progress  :Single;     // 完了ブロック数 ／ 総ブロック数

procedure Start( const Proc_:TLuxBlockProc );   // TLuxBlockProc = reference to procedure( const ThreadI_,X_,Y_,W_,H_:Integer )
procedure Cancel;                               // 実行中のブロックを終えた時点で止まる
procedure Wait;                                 // 全スレッドを待つ。メインスレッドからなら OnFinished も流し切る

property OnProgress :TDelegates;  // メインスレッド。約 30 Hz が上限
property OnFinished :TDelegates;  // メインスレッド。完了でも中止でも 1 回
```

ブロックはタイル内に収まり、ラスタ順に、共有カウンタの不可分加算 1 回につき 1 個ずつ配られる。したがって末尾の待ちは高々ブロック 1 個ぶんである。`ThreadI_` は 0 〜 `ThreadsN` − 1 で、乱数生成器や作業バッファなどのスレッド別状態を引くためのものである。ワーカーは RTL の共有プールではなく専用のスレッドで走る。`TParallel.For` で並列化している `UpdateLevels` が、描画中に飢えないためである。

手続きが例外を送出すると実行は中止され、`OnFinished` の後にメインスレッドで再送出される。デストラクタは中止して待つので、実行中のワーカーを破棄してもよい。

### 6.3 非同期のファイル入出力

`LoadFromFileAsync` と `SaveToFileAsync` は、同じ入出力処理を `TTask` で実行し、通知はすべて `TThread.Queue` でメインスレッドへ戻す。したがってハンドラから直接 UI を触ってよい。

`Busy` はタスクの開始前に立ち、`OnLoaded` / `OnSaved` の直前に降りる。ビューアは `Busy` の間まったく描画しない。読み込みは `SetSize` から始まり、タイルの構造そのものが入れ替わるためである。デストラクタはタスクの終了を待ち、保留中の通知も流し切るので、読み込み中に画像を破棄しても問題ない。

読み込みでは縮小ピラミッドの構築までタスクのスレッドで、全タイルを Dirty にした `UpdateLevels` により、利用可能なコアを使って行う。最初の再描画時に構築すると、その分だけ UI が止まってしまうためである。

`Progress` はピラミッドの構築も含めた全体を 0 から 1 で表す。行単位で報告するため PNG は滑らかに進むが、JPEG は Skia の復号がコールバックを持たない単一の呼び出しであるため、復号が終わるまで進まない。

### 6.4 対応ファイル形式

| 形式 | 読み | 書き | 備考 |
|---|---|---|---|
| PNG | ✔ | ✔ | `System.ZLib` の上に直接実装。読みは規格の定める全ての形式に対応。書きは RGBA（`Alpha_ = False` なら α 無しの RGB）で、`TLuxImageUInt08` なら 8bit、それ以外は 16bit。`ColorSpace` があれば、sRGB は `sRGB` チャンク（＋規格の勧める `gAMA` と `cHRM`）、それ以外は `iCCP` プロファイル＋ `cHRM`（曲線が純ガンマなら `gAMA` も）として書く。読み込みでは `iCCP`、次に `sRGB`、次に `gAMA` ＋ `cHRM` の順に採用する。 |
| JPEG | ✔ | ✔ | Skia のコーデックを使用。`ColorSpace` があれば ICC プロファイルを APP2 `ICC_PROFILE` セグメントとして JFIF ヘッダの後ろに埋め込み、読み込みではそのセグメントを繋いで解析する。 |

PNG の読み込みは [1] の規格全体を網羅する。その圧縮データ列は DEFLATE [2] である。

| | 対応 |
|---|---|
| ビット深度 | 1 ・ 2 ・ 4 ・ 8 ・ 16 |
| カラータイプ | 0 グレイスケール、2 トゥルーカラー、3 パレット、4 グレイスケール＋α、6 トゥルーカラー＋α |
| 透明度 | `tRNS` の3形態すべて ―― パレットのα、グレイの透明色指定、RGB の透明色指定 |
| インターレース | 無し、および Adam7 |

非インターレースの画像は1行ずつ復号してそのままタイルへ書き込むので、ファイルがどれだけ大きくても画像1枚分の一時領域を確保しない。Adam7 の画像はパス毎に復号して画素を最終位置へ散らす。こちらは遅いが、同じく全画面分のバッファを持たない。

JPEG は Skia [6] を経由する。Skia は画像 1 枚分の連続バッファを要求するため、読み書きの間だけ画像本体とは別に `幅 × 高さ × 4` バイトを必要とする。また JPEG の規格 [3] 上の上限は 65,535 画素。

浮動小数の画像を PNG に保存すると 0〜1 にクランプして 16bit へ、JPEG に保存すると 0〜1 にクランプして 8bit へ量子化する。トーンマッピングは表示側の設定なので保存時には掛けない。

`LUX.Data.Image.Files.pas` は以下も公開する。

```pascal
function LuxSkColorType( const Kind_:TLuxPixel ) :TSkColorType;
function LuxImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;
```

### 6.5 TLuxImageViewer

```pascal
property Image      :TLuxImage;
property Gamma      :Single;       // 表示ガンマ（out = in^(1/Gamma)）
property ToneMap    :Boolean;      // Reinhard のトーンマッピング
property White      :Single;       // トーンマッピングの白色点。既定 1
property Background :TAlphaColor;
property Scale      :Single;       // 画面画素 ／ 画像画素
property Origin     :TPointF;      // 表示領域の左上に対応する画像座標
property MinScale   :Single;       // 既定 1/4096
property MaxScale   :Single;       // 既定 256

property ColorSpace       :TLuxColorSpace;   // 表示側の色空間。nil = モニター自身のプロファイル
property ActiveColorSpace :TLuxColorSpace;   // 実際に使われている表示側の色空間

procedure FitToWindow;
procedure ZoomAt( const P_:TPointF; const Factor_:Single );
procedure ZoomWheel( const WheelDelta_:Integer );
function  ViewToImage( const P_:TPointF ) :TPointF;
function  ImageToView( const P_:TPointF ) :TPointF;
procedure Redraw;
```

`Image` を代入すると、`Gamma` と `ToneMap` はそのクラスの既定値に戻り、画像は窓に合わせられる。画像が `ColorSpace` を持つときの `Gamma` の既定値は 1 で ── 表示の符号化は伝達関数が決めるので ── `Gamma` は追加の調整として働く。画像の色空間が変わると既定値が掛け直される。

`ColorSpace` は変換の*表示側*である。`nil` のままなら、ビューアは窓が乗っているモニターに割り当てられた ICC プロファイル（Photoshop の「モニタ RGB」）を `GetICMProfile` で Windows から取得して解析し、窓がモニターを移れば追従する。解析できないプロファイルや割り当て無しは sRGB になる。空間を代入すれば上書きできる ── `TLuxColorSpaces.sRGB` を入れれば sRGB 固定で、これは Windows の HDR／自動カラー管理の下でも正しい選択である（表示への変換はコンポジタが行うため）。画像に色空間が無ければ、このプロパティに関わらず何も変換しない。

`Scale` を設定すると画像は中央に置き直される（画像の中心が表示の中心へ来る）。`ZoomAt` は逆に表示上の指定した点を固定するもので、ホイールがカーソル下の画素を動かさないのはこちらを使っているため。

ホイールを手前に回すと拡大する。掛かる倍率は $2^{-\Delta / 480}$ なので、4 ノッチで 2 倍になる。左ドラッグでスクロールする。

### 6.6 1 フレームの描き方

1. `Version` が変わっていればタイルキャッシュを全て捨てる。続いて `UpdateLevels` で、前のフレーム以降に変わったタイルを上の段へ反映する。
2. 段は (2.6) によって選ばれ、½〜1 倍の縮小になり、拡大はしない。残りの縮小は GPU 上のタイルのミップマップのトリリニア標本化に任せ、その段と 1 つ粗い段をブレンドする。
3. その段の可視タイルを列挙する。枚数の上限は (2.8) で与えられる。
4. 各タイルを `ISkImage` 化し ── GPU キャンバスならそのキャンバスの `GrDirectContext` でミップマップ付きテクスチャにして ── `TTileKey`（段とタイル番号）を鍵としてキャッシュし、そのタイルと周囲 8 枚の Stamp の和で検証する。GPU の文脈が変わればキャッシュを捨てる。キャッシュする画像は隣のタイルから集めた 1 画素ののりしろを持つので、タイル境界でも補間が本物の隣接画素を読み、継ぎ目が出ない。隣を検証に含めるのは、隣が変わった時にのりしろを最新に保つためである。
5. `DrawImageRect` で並べる。`Scale` ≧ 1 では最近傍で採取するので、等倍を超えて拡大すると画素が四角として見える。それ未満では線形＋ミップマップ間の線形（トリリニア）、タイルにミップマップを持てないラスタキャンバスでは線形のみ。色管理・トーンマッピング・ガンマ補正は 1 つの SkSL ランタイムカラーフィルタ、つまり GPU で行うので、`Gamma` ・ `ToneMap` ・ `White` やどちらの色空間の変更もただ同然で、キャッシュも無効化しない。

カラーフィルタは画素ごとに、プリマルチプライを解いてから、画像の伝達関数で復号 → トーンマップ（任意。線形光で）→ 画像の原色から表示の原色への 3 × 3 行列（白色点が違えば Bradford 順応込み）→ 表示の伝達関数で符号化 → `pow( 1/Gamma )` → 再びプリマルチプライ、の順に処理する。画像に色空間が無ければトーンマップとガンマだけが残り、従来どおりになる。伝達関数はどちらも ICC の 7 係数（`LUX.Color.Space` §2.5）として渡すので、ライブラリで表せる曲線はそのまま GPU で走る。

CPU 側でのリサンプルは一切行わない。1 フレームあたりの CPU 仕事は、変わったタイルぶんのピラミッド更新と、作り直したり新しく現れたりしたタイルののりしろ集約だけである。

## 7. 制限

- ディスクへの退避機構は持たない。`SetSize` は、タイルが物理メモリの空きに載らない画像を拒否する。
- TIFF ・ OpenEXR ・ Radiance HDR は未実装。
- Skia のコーデックが確実に変換できるのは 8bit までなので、JPEG は常に BGRA8888 で受けて、対象クラスがそれより広い場合は後から変換する。JPEG は 8bit の形式なので損失は無い。
- `TLuxImageWorker` が向くのはブロックごとに独立な処理である。走査順や画像全体への依存を持つアルゴリズム（積分画像、FFT）には別のスケジューリングが要る。

## 8. デモ

リポジトリのルートにある `LuxImage.dproj` は、PNG または JPEG を 4 つの形式のいずれかで開くか、`TLuxImageWorker` で 4,096² 〜 65,536² 画素のマンデルブロ集合を全コアで描き、終わったブロックから順に表示する。結果は PNG または JPEG に保存できる。

## 9. 参考文献

1. W3C, [*Portable Network Graphics (PNG) Specification (Third Edition)*](https://www.w3.org/TR/png-3/), W3C Recommendation, 2025.
2. P. Deutsch, [*DEFLATE Compressed Data Format Specification version 1.3*](https://www.rfc-editor.org/rfc/rfc1951), RFC 1951, IETF, 1996.
3. ITU-T, [*Recommendation T.81: Digital compression and coding of continuous-tone still images — Requirements and guidelines*](https://www.itu.int/rec/T-REC-T.81), ITU-T, 1992.
4. E. Reinhard, M. Stark, P. Shirley and J. Ferwerda, [*Photographic Tone Reproduction for Digital Images*](https://doi.org/10.1145/566570.566575), ACM Transactions on Graphics, vol. 21, no. 3, pp. 267–276, 2002.
5. IEEE, [*IEEE Standard for Floating-Point Arithmetic (IEEE Std 754-2019)*](https://doi.org/10.1109/IEEESTD.2019.8766229), IEEE, 2019.
6. [*Skia Graphics Library*](https://skia.org/), Google.

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [**Delphi**](https://www.embarcadero.com/jp/products/delphi)
ネイティブなクロスプラットフォームアプリを開発するための統合開発環境（ＩＤＥ）。
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/jp/products/delphi/starter)
