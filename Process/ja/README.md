# LUX.Process
[English](../README.md) | [日本語](README.md)

プロセス全体に関わる部品群である。`LUX.Process.Deadline` は、現在のプロセスの終了に期限を設け、終了の手順が詰まってもプロセスが残らないようにする。

## 1. 概要

| ユニット | 主な型 | 役割 |
|---|---|---|
| `LUX.Process.Deadline` | `TProcessDeadline` | 指定の時間が過ぎてもプロセスが動いていたら、終了させる |

このユニットは Windows 用であり、UI フレームワークに依存しない。

## 2. 技術的背景

終了の手順は、メインスレッドでも、止まりきらない部品の中でも、どこででも詰まりうる。終わらないプロセスは、次に起動されたプロセスと同じ資源を奪い合う。`TProcessDeadline.Arm` は、終了の手順を始めるときに呼ぶ。

* 期限は専用のスレッドで待つので、メインスレッドが詰まっていても働く。
* 期限の前にプロセスが通常どおり終われば、待っているスレッドはプロセスとともに消える。このスレッドは生成元より長く生きることが役目なので、その終了を待つものは無い。
* 期限が来たら、後片付けをせずに、その場で `TerminateProcess` により、指定の終了コードでプロセスを終わらせる。詰まっているのは、その後片付けだからである。

## 3. アーキテクチャ

```
・TProcessDeadline      ･･･ 状態を持たないクラスメソッドのレコード
  ┗・Arm( Ms_, Code_ ) ･･･ Ms_ ミリ秒後にプロセスを終わらせる
```

## 4. 使い方

```pascal
uses LUX.Process.Deadline;

procedure TForm1.Quit;
begin
     TProcessDeadline.Arm( 5000, 1 );            // あと最大 5 秒

     // ... ワーカーを止め、ウィンドウを閉じる ...

     Close;
end;
```

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [**Delphi**](https://www.embarcadero.com/jp/products/delphi)
ネイティブなクロスプラットフォームアプリを開発するための統合開発環境（ＩＤＥ）。
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/jp/products/delphi/starter)
