# LUX.Thread
[English](../README.md) | [日本語](README.md)

スレッドの間で仕事を受け渡すための部品群である。`LUX.Thread.Inbox` は、どのスレッドから届いたものも、届いた順に、メインスレッドのハンドラへ渡す、1 つの受け口を提供する。

## 1. 概要

| ユニット | 主な型 | 役割 |
|---|---|---|
| `LUX.Thread.Inbox` | `IInbox<TItem_>`・`TInbox<TItem_>` | 参照カウントされる、メインスレッドへの受け口 |

このユニットは Delphi の RTL だけに依存し、UI フレームワークに依存しない。

## 2. 技術的背景

受け口は、届いたものをメインスレッドへ渡す方法と、受け取り手がいなくなった後に届いたものの扱いを、1 か所で決める。

* **必ず後で渡す。** `Post` はどのスレッドから呼んでもよい。渡すのは常に後、メインスレッドが待ち行列を処理するときである。`TThread.Queue` はメインスレッドから呼ぶとその場で実行するので、受け口は `TThread.ForceQueue` で積む。したがって、コントロールを破棄するハンドラが、それを投函したイベントの最中に動くことはない。
* **ハンドラが決まる前は保持する。** `OnTake` が未設定の間に届いたものは保持し、設定されたときに届いた順に渡す。受け取り手を作る前から受け付けを始められる。
* **参照カウント。** 受け口は、作った時点から `IInbox<TItem_>` で持つ。所有者とバックグラウンドの仕事がそれぞれ参照を持ち、積まれた配達も処理されるまで参照を持つ。
* **閉じる。** 所有者は、参照を手放す前に、メインスレッドで `Close` を呼ぶ。`Close` はその場でハンドラと保持していたものを手放す。以後に投函されたもの、積まれたがまだ渡されていないものは、捨てられる。遅れて投函するバックグラウンドの仕事は、生きている受け口を持ち続け、片付けられた所有者には触れない。

受け口の生成・`OnTake` の設定・`Close` はメインスレッドで行う。`Post` と、参照の取得・解放は、どのスレッドで行ってもよい。

## 3. アーキテクチャ

```
・IInbox<TItem_>
  ┣・OnTake :TProc<TItem_> ･･･ ハンドラ。メインスレッドで呼ばれる
  ┣・Post( Item_ )         ･･･ 渡す。どのスレッドからでも
  ┗・Close                 ･･･ 未配達のものを捨て、ハンドラを手放す
・TInbox<TItem_>            ･･･ TInterfacedObject。IInbox を実装する
```

## 4. 使い方

```pascal
uses LUX.Thread.Inbox;

var
   _Inbox :IInbox<String>;

procedure TForm1.FormCreate(Sender: TObject);
begin
     _Inbox := TInbox<String>.Create;

     _Inbox.OnTake := procedure( Text_:String )
     begin
          Memo1.Lines.Add( Text_ );              // メインスレッドで
     end;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
     _Inbox.Close;                               // 以後の投函は捨てられる

     _Inbox := nil;
end;
```

バックグラウンドの仕事は、インターフェースの参照を捕まえ、それを通して投函する。

```pascal
procedure Start( const Inbox_:IInbox<String> );
begin
     TThread.CreateAnonymousThread( procedure
     begin
          Inbox_.Post( 'done' );
     end ).Start;
end;
```

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [**Delphi**](https://www.embarcadero.com/jp/products/delphi)
ネイティブなクロスプラットフォームアプリを開発するための統合開発環境（ＩＤＥ）。
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/jp/products/delphi/starter)
