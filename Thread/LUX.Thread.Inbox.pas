unit LUX.Thread.Inbox;

// ほかの実行スレッドから届くものを、主スレッドへ渡す、1 つの受け口。
//
//【使いどころ】
// ・外から来る頼み（ほかのプロセスからの頼みを受ける実行スレッド・裏の仕事）を、受けた場所から、主スレッドへ渡す。
//   渡し方と、片付けの後に届いたものの捨て方を、この 1 か所で決める。
//
//【持ち方】（参照を数える）
// ・受け口は、作った時点から、インターフェース（IInbox）で持つ（オブジェクトの参照で持たない。参照の数で壊れるので、
//   オブジェクトの参照だけで持つと、渡したときに壊れる）。持ち主も、結果を渡す裏の仕事も、それぞれ参照を持つ。
// ・持ち主は、片付けるときに、主スレッドで Close を呼んでから、参照を手放す。持ち主が片付けた後に、裏の仕事が遅れて渡しても、
//   受け口は、裏の仕事の参照で生きていて、届いたものは捨てられ、片付けた持ち主には触れない。
// ・受け口が壊れるのは、最後の参照が手放されたとき（裏の仕事の実行スレッドのこともある）。Close が、受け取り手（持ち主の
//   ものを捕まえていることがある）とためていたものを、主スレッドで手放すので、壊れるときに触れるのは、空の並びだけ。
//
//【振る舞い】
// ・Post は、どの実行スレッドから呼んでもよい。届いたものは、届いた順に、主スレッドで、受け取り手（OnTake）に 1 つずつ渡る。
// ・渡すのは、いつも後（主スレッドが、順番待ちを汲んだとき）。主スレッドから Post しても、その場では渡さない
//   （TThread.Queue は、主スレッドから呼ぶと、その場で実行するので、TThread.ForceQueue で積む）。頼む所（メニュー・ボタン）の
//   イベントの最中に、受け取り手が部品を壊しても、頼んだ側の途中の状態に触れない。
// ・積んだ手続きは、受け口の参照を持つ（汲まれるまで、受け口を生かしておく）。汲まれたときに、開いているかを見る。
// ・受け取り手が、まだ決まっていない間に届いたものは、ためておき、決まったときに、届いた順に渡す
//   （受け取り手を作る前から、受け始められる）。
// ・Close の後に届いたもの・まだ渡していないもの（積んだが、まだ汲まれていないもの）は、捨てる。
//
//【実行スレッド】
// ・作る・OnTake を決める・Close は、主スレッドで行う。Post と、参照を持つ・手放すことは、どの実行スレッドからでもよい。

interface //#################################################################### ■

uses System.SysUtils, System.Classes, System.Generics.Collections;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% IInbox<TItem_>

     // 主スレッドへの受け口
     IInbox<TItem_> = interface
       ///// A C C E S S O R
       function GetOnTake :TProc<TItem_>;
       procedure SetOnTake( const OnTake_:TProc<TItem_> );
       ///// P R O P E R T Y
       property OnTake :TProc<TItem_> read GetOnTake write SetOnTake;  // 受け取り手（主スレッドで呼ばれる）
       ///// M E T H O D
       // 渡す（どの実行スレッドからでも）
       procedure Post( const Item_:TItem_ );
       // 閉じる：以後に届いたもの・まだ渡していないものを、捨てる。受け取り手を手放す
       procedure Close;
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TInbox<TItem_>

     // 主スレッドへの受け口の実体（作ったら、すぐ IInbox で持つ）
     TInbox<TItem_> = class( TInterfacedObject, IInbox<TItem_> )
     private
       _Open   :Boolean;        // 開いている（主スレッドだけが読み書きする）
       _Helds  :TList<TItem_>;  // 受け取り手が決まる前に届いたもの
       _OnTake :TProc<TItem_>;
       ///// M E T H O D
       procedure Take( const Item_:TItem_ );
     protected
       ///// A C C E S S O R
       function GetOnTake :TProc<TItem_>; virtual;
       procedure SetOnTake( const OnTake_:TProc<TItem_> ); virtual;
     public
       constructor Create;
       destructor Destroy; override;
       ///// P R O P E R T Y
       property OnTake :TProc<TItem_> read GetOnTake write SetOnTake;  // 受け取り手（主スレッドで呼ばれる）
       ///// M E T H O D
       // 渡す（どの実行スレッドからでも）
       procedure Post( const Item_:TItem_ ); virtual;
       // 閉じる：以後に届いたもの・まだ渡していないものを、捨てる。受け取り手を手放す
       procedure Close; virtual;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TInbox<TItem_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

// 主スレッドに届いた：開いていれば、受け取り手に渡す。まだ決まっていなければ、ためておく
procedure TInbox<TItem_>.Take( const Item_:TItem_ );
begin
     if not _Open then Exit;

     if Assigned( _OnTake ) then _OnTake( Item_ )
                            else _Helds.Add( Item_ );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TInbox<TItem_>.GetOnTake :TProc<TItem_>;
begin
     Result := _OnTake;
end;

procedure TInbox<TItem_>.SetOnTake( const OnTake_:TProc<TItem_> );
var
   H :TArray<TItem_>;
   I :TItem_;
begin
     if not _Open then Exit;  // 閉じた後は、受け取り手を持たない

     _OnTake := OnTake_;

     if not Assigned( _OnTake ) then Exit;

     // ためてあったものを、届いた順に渡す
     H := _Helds.ToArray;
     _Helds.Clear;

     for I in H do _OnTake( I );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TInbox<TItem_>.Create;
begin
     inherited Create;

     _Open  := True;
     _Helds := TList<TItem_>.Create;
end;

destructor TInbox<TItem_>.Destroy;
begin
     _Helds.Free;

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TInbox<TItem_>.Post( const Item_:TItem_ );
var
   K :IInbox<TItem_>;
   S :TInbox<TItem_>;
   I :TItem_;
begin
     K := Self;  // 積んだ手続きが、汲まれるまで、受け口を生かしておく
     S := Self;
     I := Item_;

     // 主スレッドへ回す（主スレッドから呼んでも、後へ回す）。回した手続きが動くのは、主スレッドなので、開いているかを見るのも、
     // 受け取り手に渡すのも、主スレッド
     TThread.ForceQueue( nil, procedure
                              begin
                                   if K <> nil then S.Take( I );
                              end );
end;

procedure TInbox<TItem_>.Close;
begin
     _Open := False;

     _OnTake := nil;  // 受け取り手が捕まえているものを、主スレッドで手放す

     _Helds.Clear;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
