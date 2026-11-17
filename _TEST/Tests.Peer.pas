unit Tests.Peer;

// 試験の相手役のプロセス（この試験の実行ファイル自身を、最初の引数で役を決めて、別のプロセスとして動かす）
//
//【役】
// ・--single 名前 合図 … TWinSingle の 1 つ目になって頼みを受け始め、名前付きの合図（合図）を立てる。
//                       引数 '/quit' だけの頼みを受けたら終わる。ほかの頼みは受けて捨てる（終わらない）。
// ・--deadline ミリ秒 終了コード … TProcessDeadline の期限を仕掛けて、主スレッドを止めたままにする（期限で終わる）。
// ・--lock 名前 合図   … 名前の TMotionLock を握って、名前付きの合図（合図）を立て、放さずに、落とされるまで待つ。
//
//【使い方】
// ・試験のプログラムは、DUnitX より先に Serve を呼び、真なら（役として動いたなら）そのまま終わる。
// ・Start（--single）と Hold（--lock）は、役を起動し、役が合図を立てるまで待って、そのプロセスのハンドルを返す（閉じるのは呼んだ側）。

interface //#################################################################### ■

uses Winapi.Windows;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTestPeer

     // 試験の相手役のプロセス
     TTestPeer = record
     private
       class function Launch( const Role_,Name_:String; const Limit_:Cardinal ) :THandle; static;
     public
       ///// M E T H O D
       class function Serve :Boolean; static;                                               // 役として動いたら True
       class function Start( const Name_:String; const Limit_:Cardinal ) :THandle; static;  // --single の役を起動し、受け始めるまで（最大 Limit_ ミリ秒）待つ
       class function Stuck( const Ms_,Code_:Cardinal ) :THandle; static;                   // --deadline の役を起動する（プロセスのハンドルを返す）
       class function Hold( const Name_:String; const Limit_:Cardinal ) :THandle; static;   // --lock の役を起動し、握るまで（最大 Limit_ ミリ秒）待つ
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils,
     LUX.Windows.Single, LUX.Process.Deadline, LUX.FMX.Motion;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTestPeer

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

// 役 Role_ を、名前 Name_ で起動し、役が合図を立てるまで（最大 Limit_ ミリ秒）待つ
class function TTestPeer.Launch( const Role_,Name_:String; const Limit_:Cardinal ) :THandle;
var
   N, C :String;
   R :THandle;
   S :TStartupInfo;
   P :TProcessInformation;
   W :array [ 0..1 ] of THandle;
begin
     N := 'Local\' + ExtractFileName( Name_ ) + '.Ready';  // 名前に Local\ が付いていても、合図の名前は、その後ろから作る

     R := CreateEvent( nil, True, False, PChar( N ) );

     if R = 0 then RaiseLastOSError;
     try
          C := '"' + ParamStr( 0 ) + '" ' + Role_ + ' "' + Name_ + '" "' + N + '"';  UniqueString( C );

          S := Default( TStartupInfo );  S.cb := SizeOf( S );

          if not CreateProcess( nil, PChar( C ), nil, nil, False, CREATE_NO_WINDOW, nil, nil, S, P ) then RaiseLastOSError;

          CloseHandle( P.hThread );

          // 役が支度を終えるか、役が先に終わるか
          W[ 0 ] := R;  W[ 1 ] := P.hProcess;

          if WaitForMultipleObjects( 2, @W[ 0 ], False, Limit_ ) <> WAIT_OBJECT_0 then
          begin
               TerminateProcess( P.hProcess, 1 );
               CloseHandle( P.hProcess );

               raise EAbort.Create( '相手役が、支度を終えなかった' );
          end;

          Result := P.hProcess;
     finally
          CloseHandle( R );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

class function TTestPeer.Serve :Boolean;
var
   G :TWinSingle;
   E, R :THandle;
   L :TMotionLock;
begin
     // 期限を仕掛けて、止まったままでいる役
     if ParamStr( 1 ) = '--deadline' then
     begin
          TProcessDeadline.Arm( StrToUInt( ParamStr( 2 ) ), StrToUInt( ParamStr( 3 ) ) );

          Sleep( INFINITE );
     end;

     // 排他を握って、放さずに、落とされるまで待つ役
     if ParamStr( 1 ) = '--lock' then
     begin
          L := TMotionLock.Create( ParamStr( 2 ) );

          L.Acquire;

          R := OpenEvent( EVENT_MODIFY_STATE, False, PChar( ParamStr( 3 ) ) );

          if R = 0 then RaiseLastOSError;

          SetEvent( R );
          CloseHandle( R );

          Sleep( INFINITE );
     end;

     Result := ParamStr( 1 ) = '--single';

     if not Result then Exit;

     E := CreateEvent( nil, True, False, nil );

     if E = 0 then RaiseLastOSError;
     try
          G := TWinSingle.Create( ParamStr( 2 ) );
          try
               G.Listen( procedure( A_:TArray<String> )
                         begin
                              if ( Length( A_ ) = 1 ) and ( A_[ 0 ] = '/quit' ) then SetEvent( E );
                         end );

               R := OpenEvent( EVENT_MODIFY_STATE, False, PChar( ParamStr( 3 ) ) );

               if R = 0 then RaiseLastOSError;

               SetEvent( R );
               CloseHandle( R );

               WaitForSingleObject( E, INFINITE );
          finally
               G.Free;  // 待ちのスレッドを止めてから、合図を閉じる
          end;
     finally
          CloseHandle( E );
     end;
end;

class function TTestPeer.Start( const Name_:String; const Limit_:Cardinal ) :THandle;
begin
     Result := Launch( '--single', Name_, Limit_ );
end;

class function TTestPeer.Hold( const Name_:String; const Limit_:Cardinal ) :THandle;
begin
     Result := Launch( '--lock', Name_, Limit_ );
end;

class function TTestPeer.Stuck( const Ms_,Code_:Cardinal ) :THandle;
var
   C :String;
   S :TStartupInfo;
   P :TProcessInformation;
begin
     C := Format( '"%s" --deadline %d %d', [ ParamStr( 0 ), Ms_, Code_ ] );  UniqueString( C );

     S := Default( TStartupInfo );  S.cb := SizeOf( S );

     if not CreateProcess( nil, PChar( C ), nil, nil, False, CREATE_NO_WINDOW, nil, nil, S, P ) then RaiseLastOSError;

     CloseHandle( P.hThread );

     Result := P.hProcess;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
