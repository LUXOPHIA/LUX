# LUX.FMX
[English](../README.md) | [日本語](README.md)

Windows の FireMonkey アプリが、その用途によらず必要とする部品群である。メインフォームを通常のトップレベルウィンドウとして振る舞わせる部品、最初の描画の前にウィンドウの表面を地の色で下塗りする部品、明・暗 1 組のカスタムスタイルとその切り替え、メッセージが途切れず届く間も追従する再描画、そして操作に対する画面の滑らかさを測る部品を備える。

## 1. 概要

| ユニット | 主な型 | 役割 |
|---|---|---|
| `LUX.FMX.Window` | `TMainWindow` | メインフォームのウィンドウをアプリケーションウィンドウにする。`Present`／`Conceal`・`OnEnding` |
| `LUX.FMX.Primer` | `TPrimer` | 表示された直後のウィンドウを、FMX が描くまでの間、フォームの `Fill` の色で塗る |
| `LUX.FMX.Style` | `TFmxStyle` | スタイルのリソースを適用し、色・フォント・寸法を役割名で返す |
| `LUX.FMX.Scheme` | `TFmxScheme`・`TSchemeChangedMessage` | 明暗（自動・明・暗）を選び、すべてのフォームを装飾する |
| `LUX.FMX.Redraw` | `TRedraw`・`TRedrawingMessage` | 無効領域のあるフォームを、次のポストメッセージの処理より前に描かせる |
| `LUX.FMX.Motion` | `TMotionProbe`・`TMotionCost`・`TMotionLock` | UI の試験のために、更新間隔・ヒッチ率・途中のフレームを測る |

`LUX.FMX.Light.style` と `LUX.FMX.Dark.style` は、`TFmxStyle` が読み込む 2 つのスタイルファイルである。すべてのユニットは Windows 用であり、FMX の公開面と文書化された Windows API だけを使う（`LUX.FMX.Primer` に明記した例外が 1 つある）。`LUX.FMX.Redraw` と `LUX.FMX.Motion` は [`LUX.Windows`](../../Windows/ja/README.md)（`LUX.Windows.Monitor`・`LUX.Windows.Load`）を使うので、両方のフォルダを検索パスに含める。

## 2. 技術的背景

### 2.1 アプリケーションウィンドウ（`LUX.FMX.Window`）

FMX は、タスクバーのボタンを持つ大きさ 0 の隠れたアプリケーションウィンドウを作り、各フォームのウィンドウをその所有ウィンドウとして作る。その結果、フォームは自分のタスクバーボタンを持たず、最小化はアニメーションなしでフォームを隠し、タスクバーボタンは隠れたウィンドウのあるディスプレイに留まる。最小化の間にウィンドウの表面が破棄されるので、暗い配色のウィンドウは復元時に白く光る。

`TMainWindow` は、メインフォームのウィンドウから所有者を外し、`RegisterApplicationHWNDProc` でそのウィンドウをアプリケーションウィンドウとして登録し、隠れたウィンドウを破棄する。以後、最小化と復元は Windows がフォームのウィンドウそのものに対して行う。FMX が隠れたウィンドウの側で行っていたことは引き継ぐ。`WM_ENDSESSION` ではアプリを終了させる（`OnEnding` が設定されていればそれを呼び、無ければメインフォームを閉じる）。実行中は `TApplication.MainForm` を外しておき、最小化の間に表示した子ウィンドウが縮められないようにし、フォームが実際に閉じるときに戻す。

### 2.2 表面の下塗り（`LUX.FMX.Primer`）

ウィンドウが可視になるとき、Windows は `WM_ERASEBKGND` を送り、通常のアプリはそこで背景を塗る。FMX のウィンドウプロシージャは何も塗らずに「消去済み」と答え、クラスブラシも持たないので、`WM_PAINT` に至るまで新しい表面は白いままである。FMX にはこのメッセージに対する公開の拡張点が無い。そこで `TPrimer` は各フォームのウィンドウプロシージャを差し替え（`GWLP_WNDPROC`）、ウィンドウが表示されてから最初に描かれるまでの間、フォームの `Fill` の色を塗る。対象は、単色で塗る、透明でない、3D でないフォームである。

### 2.3 スタイルと明暗（`LUX.FMX.Style`・`LUX.FMX.Scheme`）

色の正本はスタイルただ 1 つである。スタイルファイルの中で、色は `color.<役割>` という名前の `TBrushObject`、フォントは `font.<役割>` という名前の `TFontObject`、寸法は `span.<役割>` という名前の `TStyleTag` である。`TFmxStyle` は呼ばれるたびにそれを引くので、値を明暗の切り替えをまたいで保持することがない。`TFmxStyle.Ground` は、スタイルの定義（`StyleLookup` の名前）が描く色を返す。これによりフォームの `Fill`、ひいては下塗りの色が、スタイルの描く背景と一致する。

`TFmxScheme` は `TSystemAppearanceChangedMessage` を受けて `TFmxStyle.Dark` を設定し、各フォームについて、表示の直前と明暗が替わったときに、フォームの背景の定義から `Fill` を決め、`DWMWA_USE_IMMERSIVE_DARK_MODE` でタイトルバーを切り替える。コントロールを作り直す必要はない。

### 2.4 即時の再描画（`LUX.FMX.Redraw`）

FMX は `InvalidateRect` で再描画を依頼し、Windows はポストされたメッセージが 1 つも残っていないときにだけ `WM_PAINT` を生成する。メッセージが切れ目なく届く間、ウィンドウは変化しているのに描かれない。`TRedraw` はスレッドフック（`WH_GETMESSAGE`・`WH_CALLWNDPROCRET`）を設置し、メッセージを 1 つ取り出すたびに、無効領域があり、かつ描画期限を過ぎた FMX のフォームに `UpdateWindow` を呼ぶ。描画期限は、そのウィンドウがあるモニターのリフレッシュ周期おきに並べ、`DwmGetCompositionTimingInfo` が返す垂直帰線の時刻にそろえる。`WM_WINDOWPOSCHANGED` の後は、すぐに描かせる。どの描画の直前にも、そのフォームを送り主として `TRedrawingMessage` を送るので、FMX の外で描かれる内容を同じ 1 回の更新の中で置き直せる。

### 2.5 滑らかさの測定（`LUX.FMX.Motion`）

`TMotionProbe` は、呼び出し側が与えた 1 歩の操作を、1 ミリ秒おきのキューされた呼び出しとして繰り返す。これは連続するマウス入力と同じ、描画が後回しにされる状況である。そのうえで、フォームの `OnPaint` の時刻をすべて記録する。リフレッシュ周期を $T$ とすると、時刻 $t$ に描き終えた内容は刻み $\lceil t / T \rceil$ で表示される（刻みの位相は、測定対象に最も有利なものをとる）。隣り合う描画が $k \ge 2$ 刻み進んだとき、 $(k - 1) T$ をヒッチ時間に加え、

$$\text{ヒッチ率} = \frac{\sum (k - 1) T}{\text{経過時間}} \quad [\text{ms/s}] \qquad \text{(2.1)}$$

が `TMotionPace.HITCH_LIMIT`（5 ms/s）未満であることを求める。測定中のマシンの負荷は `TLoad` が記録し、負荷の高い区間に重なった測定は、判定せずに無効とする。`TMotionCost` は、ウィンドウを表示せずに、1 回の更新（操作・再配置・オフスクリーンのビットマップへの描画）の時間を、最も短いリフレッシュ周期の半分を予算として測る。

## 3. アーキテクチャ

```
・LUX.FMX.Window
  ┗・TMainWindow              ･･･ アプリに 1 つ。メインフォームが相手
     ┣・OnEnding :TProc       ･･･ セッション終了時に呼ばれる入口
     ┣・Present               ･･･ 表示・復元して前面に出す
     ┗・Conceal               ･･･ 隠す（タスクバーボタンも消える）
・LUX.FMX.Primer
  ┗・TPrimer                  ･･･ アプリに 1 つ。全フォームに働く
・LUX.FMX.Style
  ┗・TFmxStyle                ･･･ クラスメンバーのみ
     ┣・Dark :Boolean         ･･･ 設定するとスタイルを適用し直す
     ┣・Apply                 ･･･ 現在の明暗のスタイルを適用する
     ┣・Color( Role_ )        ･･･ color.<役割>
     ┣・Font( Role_ )         ･･･ font.<役割>
     ┣・Span( Role_ )         ･･･ span.<役割>
     ┗・Ground( Lookup_ )     ･･･ 定義が描く色
・LUX.FMX.Scheme
  ┣・TSchemeMode              ･･･ smAuto / smLight / smDark
  ┣・TFmxScheme               ･･･ アプリに 1 つ
  ┃  ┗・Mode :TSchemeMode    ･･･ 変更すると適用と装飾をやり直す
  ┗・TSchemeChangedMessage    ･･･ 明暗が替わった後に送られる
・LUX.FMX.Redraw
  ┣・TRedraw                  ･･･ アプリに 1 つ。メインスレッド
  ┗・TRedrawingMessage        ･･･ フォームを描く直前に送られる
・LUX.FMX.Motion
  ┣・TMotionProbe             ･･･ 表示中のフォームを測る
  ┃  ┣・Pace / PaceFor       ･･･ 更新間隔 → TMotionPace
  ┃  ┣・Drift                ･･･ 同上。タイマーで歩を進める
  ┃  ┣・Shots / ShotsFor     ･･･ 画面から写したフレーム → TMotionShots
  ┃  ┣・Versus / ShotsVersus ･･･ アプリのフォームと素のフォームの比較
  ┃  ┗・Settle               ･･･ 負荷が静まるのを待って測り、測り直す
  ┣・TMotionCost              ･･･ 1 回の更新の時間。ウィンドウは出さない
  ┣・TMotionCostVersus        ･･･ 同上。素のフォームとの比較
  ┗・TMotionLock              ･･･ 名前付き mutex。窓の試験を 1 つずつに
```

ライブラリ内のユニットの依存：

```
・LUX.FMX.Scheme
  ┗・LUX.FMX.Style
・LUX.FMX.Redraw
  ┗・LUX.Windows.Monitor
・LUX.FMX.Motion
  ┣・LUX.Windows.Load
  ┗・LUX.Windows.Monitor
```

## 4. 使い方

2 つのスタイルファイルを、`TFmxStyle` が期待する名前の `RCDATA` リソースとして実行ファイルに入れる。

```
LUX_FMX_LIGHT RCDATA "LUX.FMX.Light.style"
LUX_FMX_DARK  RCDATA "LUX.FMX.Dark.style"
```

スタイルは、プロジェクトファイルで、フォームを作る前に適用する。

```pascal
uses FMX.Forms, LUX.FMX.Scheme;

var
   S :TFmxScheme;
begin
     Application.Initialize;

     S := TFmxScheme.Create( smAuto );           // スタイルを適用し、Windows の設定に従う
     try
          Application.CreateForm( TForm1, Form1 );
          Application.Run;
     finally
          S.Free;
     end;
end.
```

残りの部品はメインフォームの `OnCreate` で作り、`OnDestroy` で解放する。

```pascal
uses LUX.FMX.Primer, LUX.FMX.Window, LUX.FMX.Redraw;

procedure TForm1.FormCreate(Sender: TObject);
begin
     _Primer := TPrimer.Create;                  // 最初のフォームが出る前に
     _Window := TMainWindow.Create( Self );      // ほかのウィンドウを作る前に
     _Redraw := TRedraw.Create;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
     _Redraw.Free;
     _Window.Free;
     _Primer.Free;
end;
```

自分で描くコントロールは、描くたびにスタイルから引く。

```pascal
Canvas.Fill.Color := TFmxStyle.Color( 'accent' );
Canvas.Font.Assign( TFmxStyle.Font( 'body' ) );
```

変更のたびに回せる、1 回の更新の速い確認：

```pascal
uses LUX.FMX.Motion;

var
   C :TMotionCost;
begin
     C := TMotionCost.Measure( F, 100, procedure( const Step_:Integer )   // F：表示していないフォーム
     begin
          F.Width := 640 + Step_;
     end );

     Assert( C.Passed );                         // C.Mean <= C.Budget
end;
```

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [**Delphi**](https://www.embarcadero.com/jp/products/delphi)
ネイティブなクロスプラットフォームアプリを開発するための統合開発環境（ＩＤＥ）。
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/jp/products/delphi/starter)
