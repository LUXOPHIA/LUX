unit LUX.Data.Image.Worker;

interface //#################################################################### ■

uses System.SysUtils, System.Classes, System.Diagnostics,
     LUX, LUX.Data.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxBlockProc

     ///// ブロック１個ぶんの処理。ThreadI_ はワーカーの番号（ 0 〜 ThreadsN-1 。スレッド別の作業領域や乱数状態の索引に）
     ///// X_,Y_,W_,H_ は段 0 の画素座標での矩形。ブロックはタイルをまたがない。

     TLuxBlockProc = reference to procedure( const ThreadI_,X_,Y_,W_,H_:Integer );

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageWorker

     ///// 画像を Block 角のブロックに刻み、与えた手続きを全ブロックについて並列に実行する
     /////
     ///// ・何を計算するかは知らない。レンダリング（3D）にも画像処理（2D）にも使える。
     ///// ・ブロックは共有カウンタで１個ずつワーカーに配る（静的分割をしない）ので、
     /////   場所ごとに計算量が桁で違っても、末尾の待ちは最大ブロック１個ぶんで済む。
     ///// ・全タイルが確保済みで、ブロックは互いに素なので、書き込みにロックは要らない。
     ///// ・ブロックを終えるたびに Image.TileChanged を呼び、約 30 Hz に間引いて Image.Notify と
     /////   OnProgress を発火する。表示側はそのタイミングで完了ぶんを反映する。

     TLuxImageWorker = class
     private
       _Image    :TLuxImage;
       _Block    :Integer;
       _ThreadsN :Integer;
       _Writing  :Boolean;
       /////
       _Proc     :TLuxBlockProc;
       _Threads  :TArray<TThread>;   // 専用スレッド（共有プールを占有すると UpdateLevels の TParallel.For が詰まる）
       _Watch    :TStopwatch;
       _BN       :Integer;   // タイル一辺あたりのブロック数
       _NBX      :Integer;   // 画像全体のブロック数（横）
       _Total    :Integer;   // ブロックの総数
       _Next     :Integer;   // 次に配るブロック番号
       _Done     :Integer;   // 完了したブロック数
       _Alive    :Integer;   // 動作中のワーカー数
       _Cancel   :Boolean;
       _Busy     :Boolean;
       _Pending  :Integer;   // 通知がメインスレッドで待機中なら 1
       _Notified :Int64;     // 直前に通知した時刻（ms）
       _Error    :String;    // 手続きが送出した最初の例外
       ///// E V E N T
       _OnProgress :TDelegates;
       _OnFinished :TDelegates;
       ///// A C C E S S O R
       function GetProgress :Single;
       ///// M E T H O D
       procedure Run( const ThreadI_:Integer );
       procedure Fire;
       procedure Finish;
     public
       constructor Create( const Image_:TLuxImage );
       destructor Destroy; override;
       ///// P R O P E R T Y
       property Image     :TLuxImage read _Image                   ;
       property Block     :Integer   read _Block    write _Block   ;  // ブロックの一辺（既定 64 ）
       property ThreadsN  :Integer   read _ThreadsN write _ThreadsN;  // ワーカー数（既定＝全プロセッサグループの論理 CPU 数）
       property Writing   :Boolean   read _Writing  write _Writing ;  // 手続きが画像を書き換える（既定 True 。読むだけなら False ）
       property Busy      :Boolean   read _Busy                    ;
       property Cancelled :Boolean   read _Cancel                  ;
       property Progress  :Single    read GetProgress              ;  // 完了ブロック数／総ブロック数
       ///// M E T H O D
       procedure Start( const Proc_:TLuxBlockProc );  // 全ブロックについて Proc_ を並列に実行し始める
       procedure Cancel;                              // 実行中のブロックを終えた時点で止める
       procedure Wait;                                // 全ワーカーの終了を待つ（メインスレッドなら OnFinished も流し切る）
       ///// E V E N T
       property OnProgress :TDelegates read _OnProgress;  // 約 30 Hz でメインスレッドから
       property OnFinished :TDelegates read _OnFinished;  // 完了・中止のいずれでもメインスレッドから
     end;

implementation //############################################################### ■

uses System.Math
     {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

///// 論理 CPU の総数。Windows では TThread.ProcessorCount が現在のプロセッサグループ（最大 64 ）しか
///// 数えないので、全グループを数える。

function LuxProcessorCount :Integer;
begin
     {$IFDEF MSWINDOWS}
     Result := GetActiveProcessorCount( ALL_PROCESSOR_GROUPS );

     if Result < 1 then Result := TThread.ProcessorCount;
     {$ELSE}
     Result := TThread.ProcessorCount;
     {$ENDIF}
end;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      NOTIFY_MS = 33;  // 通知の最短間隔（約 30 Hz ）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageWorker

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TLuxImageWorker.GetProgress :Single;
begin
     if _Total > 0 then Result := _Done / _Total
                   else Result := 0;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

///// ワーカー本体。ブロックが尽きるか中止されるまで、共有カウンタから１個ずつ取って処理する。

procedure TLuxImageWorker.Run( const ThreadI_:Integer );
var
   I, BX, BY, TX, TY, X, Y, W, H :Integer;
begin
     while not _Cancel do
     begin
          I := AtomicIncrement( _Next ) - 1;

          if I >= _Total then Break;

          BX := I mod _NBX;
          BY := I div _NBX;

          TX := BX div _BN;
          TY := BY div _BN;

          X := ( TX shl LUXIMAGE_TILE_LOG ) + ( BX mod _BN ) * _Block;
          Y := ( TY shl LUXIMAGE_TILE_LOG ) + ( BY mod _BN ) * _Block;

          W := Min( _Block, Min( ( TX + 1 ) shl LUXIMAGE_TILE_LOG, _Image.Width  ) - X );  // タイルと画像の端で切る
          H := Min( _Block, Min( ( TY + 1 ) shl LUXIMAGE_TILE_LOG, _Image.Height ) - Y );

          if ( W > 0 ) and ( H > 0 ) then
          begin
               try
                    _Proc( ThreadI_, X, Y, W, H );
               except
                    on E:Exception do
                    begin
                         if _Error = '' then _Error := E.ClassName + ' ： ' + E.Message;

                         _Cancel := True;
                    end;
               end;

               if _Writing then _Image.TileChanged( TX, TY );
          end;

          AtomicIncrement( _Done );

          Fire;
     end;

     if AtomicDecrement( _Alive ) = 0 then Finish;  // 最後に抜けたワーカーが締める
end;

///// 通知を約 30 Hz に間引いてメインスレッドへ送る。待機中の通知が１つある間は追加しない。

procedure TLuxImageWorker.Fire;
var
   T :Int64;
begin
     T := _Watch.ElapsedMilliseconds;

     if T - _Notified < NOTIFY_MS then Exit;

     if AtomicExchange( _Pending, 1 ) <> 0 then Exit;

     _Notified := T;

     TThread.Queue( nil, procedure
                         begin
                              _Pending := 0;

                              if not _Busy then Exit;  // 既に締めた後なら何もしない

                              if _Writing then _Image.Notify;

                              _OnProgress.Run( Self );
                         end );
end;

///// 完了・中止の締め。メインスレッドで最終の通知を出す。

procedure TLuxImageWorker.Finish;
begin
     TThread.Queue( nil, procedure
                         var
                            M :String;
                         begin
                              M := _Error;

                              _Busy := False;

                              if _Writing then _Image.Notify;

                              _OnProgress.Run( Self );
                              _OnFinished.Run( Self );   // この中で自身が破棄されても良いよう、以後はフィールドに触れない

                              if M <> '' then raise Exception.Create( M );
                         end );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TLuxImageWorker.Create( const Image_:TLuxImage );
begin
     inherited Create;

     _Image    := Image_;
     _Block    := 64;
     _ThreadsN := LuxProcessorCount;
     _Writing  := True;
     _Total    := 0;
     _Next     := 0;
     _Done     := 0;
     _Alive    := 0;
     _Cancel   := False;
     _Busy     := False;
     _Pending  := 0;
     _Notified := 0;
     _Error    := '';
end;

destructor TLuxImageWorker.Destroy;
begin
     Cancel;  Wait;

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageWorker.Start( const Proc_:TLuxBlockProc );
var
   NBY, I, T :Integer;
begin
     if _Busy then raise EInvalidOpException.Create( '前の処理がまだ終わっていない' );

     if not Assigned( _Image ) or ( _Image.Width < 1 ) or ( _Image.Height < 1 ) then raise EInvalidOpException.Create( '画像が空である' );

     if _Image.Busy then raise EInvalidOpException.Create( '画像が読み書きの最中である' );

     _Block    := Max( 1, Min( LUXIMAGE_TILE, _Block ) );
     _ThreadsN := Max( 1, _ThreadsN );

     _BN   := ( LUXIMAGE_TILE + _Block - 1 ) div _Block;
     _NBX  := ( _Image.LevelTilesX( 0 ) - 1 ) * _BN + ( _Image.TileWidth ( 0, _Image.LevelTilesX( 0 ) - 1 ) + _Block - 1 ) div _Block;
     NBY   := ( _Image.LevelTilesY( 0 ) - 1 ) * _BN + ( _Image.TileHeight( 0, _Image.LevelTilesY( 0 ) - 1 ) + _Block - 1 ) div _Block;

     _Total    := _NBX * NBY;
     _Next     := 0;
     _Done     := 0;
     _Alive    := _ThreadsN;
     _Cancel   := False;
     _Busy     := True;
     _Pending  := 0;
     _Notified := 0;
     _Error    := '';
     _Proc     := Proc_;

     _Watch := TStopwatch.StartNew;

     SetLength( _Threads, _ThreadsN );

     for I := 0 to _ThreadsN-1 do
     begin
          T := I;  // 無名メソッドは for の制御変数を捕捉できない

          _Threads[ I ] := TThread.CreateAnonymousThread( procedure
                                                          begin
                                                               Run( T );
                                                          end );

          _Threads[ I ].FreeOnTerminate := False;  // Wait で回収する
     end;

     for I := 0 to _ThreadsN-1 do _Threads[ I ].Start;
end;

procedure TLuxImageWorker.Cancel;
begin
     _Cancel := True;
end;

procedure TLuxImageWorker.Wait;
var
   I :Integer;
begin
     for I := 0 to High( _Threads ) do
     begin
          _Threads[ I ].WaitFor;  // メインスレッドからなら、待つ間も Queue を流す
          _Threads[ I ].Free;
     end;

     _Threads := nil;

     ///// 保留中の通知を、まだ自分が生きているうちに流し切る

     if TThread.CurrentThread.ThreadID = MainThreadID then CheckSynchronize;
end;

end. //######################################################################### ■
