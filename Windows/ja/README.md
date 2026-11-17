# LUX.Windows
[English](../README.md) | [日本語](README.md)

デスクトップアプリの起動・常駐・インストールと、マシンの状態の取得のための、Windows 固有の部品群である。Windows API を直接呼び、UI フレームワークに依存しないので、FireMonkey のアプリにも VCL のアプリにも使える。

## 1. 概要

| ユニット | 主な型 | 役割 |
|---|---|---|
| `LUX.Windows.Single` | `TWinSingle`・`TWinRequest` | 名前ごとにプロセスを 1 つに保ち、2 つ目の起動引数を 1 つ目へ渡す |
| `LUX.Windows.Notify` | `TWinNotify` | 通知領域のアイコンと、そのコンテキストメニュー・バルーン通知 |
| `LUX.Windows.Startup` | `TWinStartup` | サインイン時の自動起動（現在のユーザーの `Run` キーへの登録） |
| `LUX.Windows.Install` | `TWinInstaller` | 実行ファイル自身によるインストール・更新・アンインストール |
| `LUX.Windows.Monitor` | `TWinMonitor` | ウィンドウがあるモニターと、そのリフレッシュ周期 |
| `LUX.Windows.Load` | `TLoad`・`TLoadTrace`・`TLoadSpan` | 専用スレッドで採取する、マシン全体の負荷 |

`LUX.Windows.Install` は `LUX.Windows.Startup` を使う。ほかのユニットは互いに独立である。

## 2. 技術的背景

### 2.1 単一インスタンス（`LUX.Windows.Single`）

1 つの Windows セッションの中で、ある名前の `TWinSingle` を最初に作ったプロセスが 1 つ目のインスタンスである（`First` が真）。依頼は起動引数の並びそのものであり、メッセージ型の名前付きパイプの 1 メッセージとして送る。したがって書きかけの依頼が読まれることはなく、同時に依頼したプロセスは OS が順に並べる。1 つ目のインスタンスは、自分を識別する mutex を保持したままパイプを用意するので、2 つ目が用意の途中の状態を見ることはなく、時間による待ちを使わない。依頼側は、接続したパイプからサーバーのプロセス ID を得て（`GetNamedPipeServerProcessId`）、前面に出る権利を与え、必要ならその終了を待つ。結果は `trAbsent`・`trEnded`・`trAlive`・`trFailed` のいずれかである。

### 2.2 通知領域（`LUX.Windows.Notify`）

`TWinNotify` は隠しウィンドウ（`AllocateHWnd`）を持ち、実行ファイルの `MAINICON` を `Shell_NotifyIcon` で登録する。左クリックとダブルクリックは、どちらも最初のボタンの解放で `OnOpen` をちょうど 1 度呼び、両者を見分けるための待ちを置かない。エクスプローラーが再起動したとき（`TaskbarCreated`）にはアイコンを登録し直す。これは、タスクバーがまだ無いうちに起動した場合も兼ねる。

### 2.3 サインイン時の起動（`LUX.Windows.Startup`）

`TWinStartup` は、`HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` に、値 `"<実行ファイル>" /tray` を書く。`/tray` は、アプリがウィンドウを出さずに常駐を始めるための引数である。`Enabled` は、登録がこの実行ファイルをこの形で指しているときだけ真を返す。

### 2.4 インストール（`LUX.Windows.Install`）

`TWinInstaller` は、実行中の実行ファイル・その隣のファイル・任意で埋め込みの zip リソースを、既定では `Program Files\LUXOPHIA\<アプリ>` にインストールする。手順は別々のメソッドであり、呼ぶ順と、どれを昇格して行うかは呼び出し側が決める。`Place`、`Register`（Windows のインストール済みアプリの一覧。`HKEY_LOCAL_MACHINE` の下）、`Grant`（以後の更新を昇格なしで行えるようにする）、`Sweep`、`Enroll`（スタートメニューのショートカット）である。実行中の実行ファイルは自分を削除できないので、アンインストールは実行ファイルを一時的な場所へ複製し、そこから続行する。使用中のファイルは、`MoveFileEx` により次の再起動時に削除される。

### 2.5 モニターのリフレッシュ周期（`LUX.Windows.Monitor`）

Windows 8.1 以降、`DwmGetCompositionTimingInfo` はウィンドウを受け取らないので、モニターごとの周期を得られない。`TWinMonitor` は、`MonitorFromWindow` でモニターを、`GetMonitorInfo` でそのデバイス名を、`EnumDisplaySettings`（`dmDisplayFrequency`）でリフレッシュレートを得る。レートが分からないとき、周期は 0 である。レートは整数の Hz なので、端数のあるレートでは周期に 2 % 未満の誤差が出うる。

### 2.6 マシンの負荷（`LUX.Windows.Load`）

`TLoad` は、専用のスレッドで PDH から 16 ms おきに採取し、各値を時間の区間として蓄える。16 ms は時計の割り込みの間隔を下回らない値であり、それより短い区間の占有率は意味を持たない。

| `TLoadKind` | 値 |
|---|---|
| `lkCPU` | プロセッサーの占有率（%）。ユーザー時間と特権時間の生のカウンターから求める |
| `lkGPU3D`・`lkGPUCopy`・`lkGPUEtc` | 種類ごとの、最も使われている GPU エンジン（%）。このプロセスの分は除く |
| `lkPaging` | 物理メモリを空けるために書き出されたページ（ページ／秒） |
| `lkDisk` | 最も使われている物理ディスク（%） |

`LOAD_LINES` は、区間を「重い」とみなす線を与える。占有率は 50 %、ページングは 0 である。

## 3. アーキテクチャ

```
・LUX.Windows.Single
  ┣・TWinRequest                   ･･･ trAbsent / trEnded / trAlive / trFailed
  ┗・TWinSingle
     ┣・First :Boolean             ･･･ このプロセスが 1 つ目のインスタンス
     ┣・Listen( OnRequest_ )       ･･･ 1 つ目：依頼の受け付けを始める
     ┗・Request( Args_, Timeout_ ) ･･･ 2 つ目以降：自分の引数を送る
・LUX.Windows.Notify
  ┗・TWinNotify
     ┣・Tip :String                ･･･ マウスを載せたときの文
     ┣・OnOpen :TProc              ･･･ 左クリック・ダブルクリック
     ┣・AddItem / AddSeparator     ･･･ コンテキストメニューを組み立てる
     ┣・Primary :Integer           ･･･ 太字で示す項目
     ┣・Enableds[ Item_ ] :Boolean ･･･ 項目を選べるか
     ┗・Balloon( Title_, Text_ )   ･･･ 通知を出す
・LUX.Windows.Startup
  ┗・TWinStartup                   ･･･ レコード
     ┣・Command :String            ･･･ "<Exe>" /tray
     ┗・Enabled :Boolean           ･･･ 読む：登録済みか。書く：登録・削除
・LUX.Windows.Install
  ┗・TWinInstaller                 ･･･ レコード
     ┣・Dest, Target :String       ･･･ インストール先のフォルダと実行ファイル
     ┣・Installed :Boolean         ･･･ インストール先から動いているか
     ┣・Startup :TWinStartup       ･･･ サインイン時の起動の登録
     ┣・Place / Register / Grant   ･･･ 昇格が要るインストールの手順
     ┣・Sweep / Enroll             ･･･ ユーザーの権限で行う手順
     ┣・Uninstall / Remove         ･･･ /uninstall と /remove の処理
     ┗・Elevate( Args_ )           ･･･ 自分を管理者として起動し直す
・LUX.Windows.Monitor
  ┗・TWinMonitor                   ･･･ レコード
     ┣・Period :Double             ･･･ リフレッシュ周期（秒）。不明なら 0
     ┗・MinPeriod :Double          ･･･ 全モニターのうち最も短い周期
・LUX.Windows.Load
  ┣・TLoadSpan                     ･･･ 1 つの値の、1 つの区間
  ┣・TLoadTrace                    ･･･ 時刻の範囲の中の区間の並びと要約
  ┃  ┗・Heavy( Head_, Tail_ )     ･･･ 範囲の中に、線を超える区間があるか
  ┗・TLoad                         ･･･ 採取するスレッドを所有する
     ┣・Now :Double                ･･･ 現在の時刻（ミリ秒）
     ┣・Trace( Head_, Tail_ )      ･･･ 範囲を切り出す → TLoadTrace
     ┣・Await( Time_, Proc_ )      ･･･ Time_ まで採取し終えたら呼ぶ
     ┗・Calm( Proc_ )              ･･･ どの種類も線以下になったら呼ぶ
```

## 4. 使い方

インスタンスを 1 つに限り、再び起動されたらウィンドウを出す常駐アプリ：

```pascal
uses LUX.Windows.Single, LUX.Windows.Notify;

var
   S :TWinSingle;
begin
     S := TWinSingle.Create( 'Example.App' );

     if not S.First then
     begin
          S.Request( [], 0 );                    // 1 つ目に、ウィンドウを出すよう頼む

          Exit;
     end;

     S.Listen( procedure( Args_:TArray<String> )
     begin
          // 待ちのスレッドから呼ばれる。Args_ をメインスレッドへ渡す
     end );
end;
```

```pascal
     N := TWinNotify.Create( 'Example' );
     N.OnOpen  := ShowMain;
     N.Primary := N.AddItem( 'Open', ShowMain );
     N.AddSeparator;
     N.AddItem( 'Quit', Quit );
     N.Balloon( 'Example', 'Finished.' );
```

ウィンドウがあるモニターのリフレッシュ周期と、測った区間の負荷の並び：

```pascal
uses LUX.Windows.Monitor, LUX.Windows.Load;

var
   L :TLoad;
   H :Double;
   T :TLoadTrace;
begin
     Writeln( TWinMonitor.Create( Wnd ).Period * 1000:0:2, ' ms' );

     L := TLoad.Create;
     try
          H := TLoad.Now;
          // ... 測る対象の処理 ...
          T := L.Trace( H, TLoad.Now );

          if T.Heavy( 0, T.Elapse ) then Writeln( 'measured under heavy load' );
     finally
          L.Free;
     end;
end;
```

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [**Delphi**](https://www.embarcadero.com/jp/products/delphi)
ネイティブなクロスプラットフォームアプリを開発するための統合開発環境（ＩＤＥ）。
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/jp/products/delphi/starter)
