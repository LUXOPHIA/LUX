unit LUX.Windows.Single;

// 二重起動の制御と、2 つ目から 1 つ目への頼み（同じ Windows のセッションの中）
//
//【構成】
// ・TWinSingle  … 同じ名前のプロセスを 1 つに保ち、2 つ目から 1 つ目へ、起動の引数を渡す。
// ・TWinRequest … 頼んだ結果（4 つの値）。
//
//【見分け方】
// ・同じ Windows のセッションで、同じ名前の TWinSingle を最初に作ったプロセスが「1 つ目」（First が真）。
//   2 つ目以降は First が偽で、1 つ目に頼める。
// ・名前は、アプリごとに決める（例 'LUXOPHIA.〜'）。OS の物の名前は、この名前から ObjectName の 1 か所で決める。
//
//【頼みの形：起動の引数】
// ・頼みは、起動の引数（文字列の並び）そのもの。窓を出す・設定を開く・終わる、の区別は、アプリが引数で決める。
//   引数が空なら、アプリは窓を出すだけにする（もう一度起動されたときの、ふつうの振る舞い）。
//   この部品は、引数の意味を知らない。
// ・Request は、渡した後、1 つ目のプロセスが終わるのを、最大 Timeout_ ミリ秒待つ。0 なら待たない。
//   終わらせる頼み（例 '/quit'）は、上限を付けて待ち、窓を出す頼みは、0 で待たない。
//   結果は、相手がいなかった（trAbsent）・終わった（trEnded）・まだ動いている（trAlive）・終わりを待てなかった（trFailed）。
//
//【受け渡しの方式：名前付きの管（メッセージ型）】
// ・頼み 1 つを、管の 1 つのメッセージで送る。OS が、メッセージを丸ごと届けるので、途中まで書かれた頼みを読まない。
//   同時に頼んだ 2 つ目どうしは、OS が順に並べる（管の口は 1 つで、使用中なら、空くまで待つ）。頼む側が途中で落ちても、
//   その接続が切れるだけで、次の頼みに混ざらない。引数の長さに上限を作らない。
// ・管の口は、1 つ目が作るとき（Listen の前）に作る。Listen の前に来た頼みは、口に入ったまま、Listen の後に受ける。
// ・頼む側は、接続した管から、1 つ目のプロセスの番号を OS に聞く（GetNamedPipeServerProcessId）。接続している間は、
//   1 つ目が動いているので、その番号のプロセスを開けば、確かに 1 つ目のもの（番号の使い回しを開かない）。
//   その番号に、前に出す権利を渡す（AllowSetForegroundWindow。1 つ目が窓を前に出せるように）。
// ・管の名前は、PC 全体で 1 つの名前空間なので、セッションの番号を入れる。ほかの者が先に同じ名前の管を作っていたら、
//   1 つ目を作るときに例外（FILE_FLAG_FIRST_PIPE_INSTANCE）。ほかの PC からの接続は断る（PIPE_REJECT_REMOTE_CLIENTS）。
//
//【1 つ目】
// ・作るときに、1 つ目を見分ける排他（mutex）を持ったまま、管の口を用意してから、排他を放す。2 つ目は、排他を一度取ってから
//   頼むので、用意の途中を見ない（時間で待たない）。
// ・Listen で頼みを受け始める。頼みは、このクラスが持つ待ちのスレッドが受け、OnRequest_ を、そのスレッドから、頼み 1 つに
//   1 度呼ぶ。主スレッドへ渡すのは、呼ばれた側（使う側の窓口）。OnRequest_ の中で、主スレッドを待つ呼び出しをしない
//   （壊すときに、主スレッドが、待ちのスレッドの終わりを待つので、互いに待って止まる）。
// ・形の合わないメッセージ（この部品の外の者が書いたもの）は、受けずに捨てる。
// ・待ちのスレッドは、壊すときに止めて、終わりを待つ（投げたままにしない）。待ちのスレッドが、OS の思わない失敗で止まったら、
//   その例外は、スレッドの FatalException に残る。
//
//【2 つ目】
// ・1 つ目が頼むのは、プログラムの誤りなので、EInvalidOpException。2 つ目の Listen も同じ。
//
//【終わり方】
// ・1 つ目は、壊すまで管の口と排他を持つ。窓と部品を止め終えてから壊す（代わりに起動した 1 つ目と、資源がぶつからないように）。

interface //#################################################################### ■

uses System.SysUtils, System.Classes;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     // 頼んだ結果
     TWinRequest = ( trAbsent,   // 頼む相手がいなかった（頼みは届いていない）
                     trEnded,    // 頼みが届き、1 つ目のプロセスが、時間内に終わった
                     trAlive,    // 頼みが届き、1 つ目のプロセスは、時間内に終わらなかった（待たないときも、これ）
                     trFailed ); // 頼みが届いたが、終わりを待てなかった（1 つ目のプロセスを開けない・待ちの失敗）

     TWinSingle = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinSingle

     // 同じ名前のプロセスを 1 つに保ち、2 つ目から 1 つ目へ、起動の引数を渡す
     TWinSingle = class
     private
       _Name  :String;
       _Mutex :THandle;  // 1 つ目を見分ける排他
       _First :Boolean;
       _Pipe  :THandle;  // 頼みを受ける管の口（1 つ目だけが持つ）
       _Halt  :THandle;  // 待ちのスレッドを止める合図（1 つ目だけが持つ）
       _Watch :TThread;  // 頼みを待つスレッド（Listen で作る）
       ///// M E T H O D
       function ObjectName( const Kind_:String ) :String;
     protected
     public
       constructor Create( const Name_:String );
       destructor Destroy; override;
       ///// P R O P E R T Y
       property Name  :String  read _Name ;                                                            // アプリごとに決めた名前
       property First :Boolean read _First;                                                            // このプロセスが 1 つ目
       ///// M E T H O D
       procedure Listen( const OnRequest_:TProc<TArray<String>> ); virtual;                            // 1 つ目が頼みを受け始める（OnRequest_ は、待ちのスレッドから呼ぶ）
       function Request( const Args_:TArray<String>; const Timeout_:Cardinal ) :TWinRequest; virtual;  // 1 つ目に Args_ を渡し、1 つ目のプロセスが終わるのを、最大 Timeout_ ミリ秒待つ（0 なら待たない）
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses Winapi.Windows;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      PIPE_REJECT_REMOTE_CLIENTS = $00000008;  // ほかの PC からの接続を断る（Winapi.Windows に宣言が無い）
      PIPE_BUFFER                = 65536;      // 管の受け口の大きさの目安（起動の引数は、これに収まる）

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleWatch

     // 1 つ目の、頼みを待つスレッド
     TSingleWatch = class( TThread )
     private
       _Pipe      :THandle;  // 管の口（持ち主は TWinSingle）
       _Halt      :THandle;  // 止める合図（持ち主は TWinSingle）
       _Done      :THandle;  // 管の読み書きの終わりの合図（このスレッドが持つ）
       _OnRequest :TProc<TArray<String>>;
       ///// M E T H O D
       function Await( var Over_:TOverlapped ) :Boolean;
       function Connect :Boolean;
       function Receive( out Bytes_:TBytes ) :Boolean;
     protected
       procedure Execute; override;
     public
       constructor Create( const Pipe_,Halt_:THandle; const OnRequest_:TProc<TArray<String>> );
       destructor Destroy; override;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

// 引数の並びを、管の 1 つのメッセージにする：数（Int32）、続けて、1 つごとに、文字の数（Int32）と、その文字（UTF-16）
function Encode( const Args_:TArray<String> ) :TBytes;
var
   S :TBytesStream;
   A :String;
   N :Int32;
begin
     S := TBytesStream.Create;
     try
          N := Length( Args_ );

          S.WriteBuffer( N, SizeOf( N ) );

          for A in Args_ do
          begin
               N := Length( A );

               S.WriteBuffer( N, SizeOf( N ) );

               if N > 0 then S.WriteBuffer( A[ 1 ], N * SizeOf( Char ) );
          end;

          Result := Copy( S.Bytes, 0, S.Size );
     finally
          S.Free;
     end;
end;

// Encode の逆。形が合わなければ False（読める分だけ読まず、全部を捨てる）
function Decode( const Bytes_:TBytes; out Args_:TArray<String> ) :Boolean;
var
   P, I :Integer;
   N, K :Int32;
begin
     Args_ := nil;

     P := 0;

     if Length( Bytes_ ) - P < SizeOf( N ) then Exit( False );

     Move( Bytes_[ P ], N, SizeOf( N ) );  Inc( P, SizeOf( N ) );

     if ( N < 0 ) or ( N > ( Length( Bytes_ ) - P ) div SizeOf( K ) ) then Exit( False );  // 1 つに、少なくとも長さの分が要る

     SetLength( Args_, N );
     for I := 0 to N - 1 do
     begin
          if Length( Bytes_ ) - P < SizeOf( K ) then Exit( False );

          Move( Bytes_[ P ], K, SizeOf( K ) );  Inc( P, SizeOf( K ) );

          if ( K < 0 ) or ( K > ( Length( Bytes_ ) - P ) div SizeOf( Char ) ) then Exit( False );

          SetLength( Args_[ I ], K );

          if K > 0 then Move( Bytes_[ P ], Args_[ I ][ 1 ], K * SizeOf( Char ) );

          Inc( P, K * SizeOf( Char ) );
     end;

     Result := P = Length( Bytes_ );                                                       // 余りがあれば、形が違う
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleWatch

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

// 管の読み書きの終わりを待つ。止める合図が先に立ったら、読み書きを取り消し、取り消しが済むのを待って False
function TSingleWatch.Await( var Over_:TOverlapped ) :Boolean;
var
   W :array [ 0..1 ] of THandle;
   N :DWORD;
begin
     W[ 0 ] := _Halt;  W[ 1 ] := _Done;

     case WaitForMultipleObjects( 2, @W[ 0 ], False, INFINITE ) of
       WAIT_OBJECT_0 + 0 : begin
                                CancelIoEx( _Pipe, @Over_ );

                                GetOverlappedResult( _Pipe, Over_, N, True );  // 取り消しが済むまで待つ（Over_ は、この後に捨てる）

                                Result := False;
                           end;
       WAIT_OBJECT_0 + 1 : Result := True;
     else
          RaiseLastOSError;  // 待ちの失敗（ハンドルが壊れた）

          Result := False;
     end;
end;

// 頼む側が、管につなぐのを待つ。止める合図なら False
function TSingleWatch.Connect :Boolean;
var
   O :TOverlapped;
   N :DWORD;
begin
     O := Default( TOverlapped );  O.hEvent := _Done;

     if ConnectNamedPipe( _Pipe, @O ) then Exit( True );

     case GetLastError of
       ERROR_PIPE_CONNECTED : Result := True;  // Listen の前、または前の頼みの後に、もうつないでいた
       ERROR_NO_DATA        : Result := True;  // つないで、書いて、もう閉じた（書いたものは、まだ読める）
       ERROR_IO_PENDING     : begin
                                   Result := Await( O );

                                   if Result and not GetOverlappedResult( _Pipe, O, N, False ) then RaiseLastOSError;
                              end;
     else
          RaiseLastOSError;

          Result := False;
     end;
end;

// 1 つのメッセージを、全部読む。止める合図なら False。頼む側が何も書かずに閉じたら、空のまま True
function TSingleWatch.Receive( out Bytes_:TBytes ) :Boolean;
var
   O :TOverlapped;
   B :array [ 0..4095 ] of Byte;
   N :DWORD;
   E :DWORD;
begin
     Bytes_ := nil;

     while True do
     begin
          O := Default( TOverlapped );  O.hEvent := _Done;

          if ReadFile( _Pipe, B[ 0 ], SizeOf( B ), N, @O ) then E := ERROR_SUCCESS
                                                          else E := GetLastError;

          // 読み始められたもの（すぐ終わった・続きがある・待ちになった）は、終わった後の結果と、読めた数を、OS に聞き直す
          if ( E = ERROR_SUCCESS ) or ( E = ERROR_MORE_DATA ) or ( E = ERROR_IO_PENDING ) then
          begin
               if ( E = ERROR_IO_PENDING ) and not Await( O ) then Exit( False );

               if GetOverlappedResult( _Pipe, O, N, False ) then E := ERROR_SUCCESS
                                                            else E := GetLastError;
          end;

          case E of
            ERROR_SUCCESS     : begin
                                     Bytes_ := Bytes_ + BytesOf( @B[ 0 ], N );

                                     Exit( True );  // メッセージの終わり
                                end;
            ERROR_MORE_DATA   : Bytes_ := Bytes_ + BytesOf( @B[ 0 ], N );  // メッセージの続きがある
            ERROR_BROKEN_PIPE : Exit( True );                              // 頼む側が、書き終える前に閉じた（読めた分は、形が合わずに捨てられる）
          else
               RaiseLastOSError( E );
          end;
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

procedure TSingleWatch.Execute;
var
   B :TBytes;
   A :TArray<String>;
   R :Boolean;
begin
     while Connect do
     begin
          R := Receive( B );

          DisconnectNamedPipe( _Pipe );  // 次の頼みのために、口を空ける（読み終えたので、頼む側の接続は要らない）

          if not R then Exit;

          if Decode( B, A ) then _OnRequest( A );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TSingleWatch.Create( const Pipe_,Halt_:THandle; const OnRequest_:TProc<TArray<String>> );
begin
     _Pipe      := Pipe_;
     _Halt      := Halt_;
     _OnRequest := OnRequest_;
     _Done      := CreateEvent( nil, True, False, nil );

     if _Done = 0 then RaiseLastOSError;

     inherited Create( False );  // スレッドは AfterConstruction で動き出すので、欄は先に入れておいてよい
end;

destructor TSingleWatch.Destroy;
begin
     inherited;  // スレッドの終わりを待つ（止める合図は、持ち主が先に立てる）

     if _Done <> 0 then CloseHandle( _Done );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinSingle

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

// OS の物の名前（決まりは、ここだけ）。
// 排他は、セッションの中だけの名前空間（Local\）に置く。管は、PC 全体で 1 つの名前空間なので、セッションの番号を入れる
function TWinSingle.ObjectName( const Kind_:String ) :String;
var
   S :DWORD;
begin
     if Kind_ = 'Mutex' then Exit( 'Local\' + _Name + '.Mutex' );

     if not ProcessIdToSessionId( GetCurrentProcessId, S ) then RaiseLastOSError;

     Result := '\\.\pipe\' + _Name + '.' + UIntToStr( S ) + '.' + Kind_;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TWinSingle.Create( const Name_:String );
begin
     inherited Create;

     _Name := Name_;

     _Mutex := CreateMutex( nil, True, PChar( ObjectName( 'Mutex' ) ) );  // 新しく作ったときだけ、作ったスレッドが持ち主になる

     if _Mutex = 0 then RaiseLastOSError;                                 // 作れない（同じ名前の別の種類の物がある・権限が無い）：二重起動を防げないので、続けない

     _First := GetLastError <> ERROR_ALREADY_EXISTS;

     if _First then
     begin
          try
               _Halt := CreateEvent( nil, True, False, nil );

               if _Halt = 0 then RaiseLastOSError;

               _Pipe := CreateNamedPipe( PChar( ObjectName( 'Request' ) ),
                                         PIPE_ACCESS_INBOUND or FILE_FLAG_OVERLAPPED or FILE_FLAG_FIRST_PIPE_INSTANCE,
                                         PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT or PIPE_REJECT_REMOTE_CLIENTS,
                                         1, 0, PIPE_BUFFER, 0, nil );

               if _Pipe = INVALID_HANDLE_VALUE then
               begin
                    _Pipe := 0;

                    RaiseLastOSError;  // ほかの者が、先に同じ名前の管を作っている（頼みを、そちらへ渡さない）
               end;
          finally
               ReleaseMutex( _Mutex );  // 用意ができた（2 つ目は、これを取ってから頼む）
          end;
     end
     else
     begin
          // 1 つ目の用意が済むのを待つ（WAIT_ABANDONED は、1 つ目が用意の途中で落ちたことで、取れてはいる）
          if WaitForSingleObject( _Mutex, INFINITE ) = WAIT_FAILED then RaiseLastOSError;

          ReleaseMutex( _Mutex );
     end;
end;

destructor TWinSingle.Destroy;
begin
     if Assigned( _Watch ) then
     begin
          SetEvent( _Halt );

          _Watch.Free;  // 止まるのを待ってから壊す
     end;

     if _Pipe  <> 0 then CloseHandle( _Pipe  );
     if _Halt  <> 0 then CloseHandle( _Halt  );
     if _Mutex <> 0 then CloseHandle( _Mutex );

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TWinSingle.Listen( const OnRequest_:TProc<TArray<String>> );
begin
     if not _First         then raise EInvalidOpException.Create( 'TWinSingle.Listen: 頼みを受けるのは 1 つ目だけです' );
     if Assigned( _Watch ) then raise EInvalidOpException.Create( 'TWinSingle.Listen: 既に受けています' );

     _Watch := TSingleWatch.Create( _Pipe, _Halt, OnRequest_ );
end;

//------------------------------------------------------------------------------

function TWinSingle.Request( const Args_:TArray<String>; const Timeout_:Cardinal ) :TWinRequest;
var
   N :String;
   H, P :THandle;
   I :ULONG;
   B :TBytes;
   W :DWORD;
begin
     if _First then raise EInvalidOpException.Create( 'TWinSingle.Request: 1 つ目は自分に頼めません' );

     N := ObjectName( 'Request' );

     // 管につなぐ。口が使用中（ほかの頼みを受けている・1 つ目が前の頼みを片付けている）なら、空くまで待つ
     while True do
     begin
          H := CreateFile( PChar( N ), GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0 );

          if H <> INVALID_HANDLE_VALUE then Break;

          case GetLastError of
            ERROR_FILE_NOT_FOUND : Exit( trAbsent );                                   // 1 つ目が終わって、口が消えた
            ERROR_PIPE_BUSY      : WaitNamedPipe( PChar( N ), NMPWAIT_WAIT_FOREVER );  // 戻ったら、つなぎ直す（口が消えていれば、上で trAbsent）
          else
               RaiseLastOSError;
          end;
     end;

     try
          // つないでいる間は 1 つ目が動いているので、この番号のプロセスは、確かに 1 つ目
          if not GetNamedPipeServerProcessId( H, I ) then RaiseLastOSError;

          P := OpenProcess( SYNCHRONIZE, False, I );  // 開けなければ 0（終わりを待てない：trFailed）

          AllowSetForegroundWindow( I );              // 1 つ目が窓を前に出せるように、前に出す権利を渡す（渡せなくても、頼みは届く）

          B := Encode( Args_ );

          if not WriteFile( H, B[ 0 ], Length( B ), W, nil ) then
          begin
               case GetLastError of
                 ERROR_NO_DATA,
                 ERROR_BROKEN_PIPE : begin
                                          if P <> 0 then CloseHandle( P );

                                          Exit( trAbsent );  // 書く前に、1 つ目が終わった
                                     end;
               else
                    RaiseLastOSError;
               end;
          end;
     finally
          CloseHandle( H );
     end;

     if P = 0 then Exit( trFailed );

     try
          case WaitForSingleObject( P, Timeout_ ) of
            WAIT_OBJECT_0 : Result := trEnded;
            WAIT_TIMEOUT  : Result := trAlive;
          else
               Result := trFailed;
          end;
     finally
          CloseHandle( P );
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
