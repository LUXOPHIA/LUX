unit Tests.Windows.Single;

// LUX.Windows.Single の試験
//
//【名前】
// ・試験ごとに、GUID の入った別の名前を使う（ほかの試験・本物のアプリと混ざらない）。
//
//【別のプロセス】
// ・終わりを待つ結果（終わった・まだ動いている・相手がいない）は、別のプロセス（Tests.Peer の --single の役）を 1 つ目にして確かめる。
//
//【確かめないこと】
// ・trFailed（1 つ目のプロセスを開けない・待ちの失敗）は、試験の中では起こせない。

interface //#################################################################### ■

uses DUnitX.TestFramework,
     LUX.Windows.Single;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleTests

     [TestFixture]
     TSingleTests = class
     private
       function NewName :String;
     public
       [Test] procedure FirstAndSecond;
       [Test] procedure ArgsReachFirst;
       [Test] procedure RequestBeforeListen;
       [Test] procedure ManySenders;
       [Test] procedure Misuse;
       [Test] procedure WaitForEnd;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
     Winapi.Windows,
     Tests.Peer;

const
     FAIL_MS = 60000;  // 試験の失敗を見つけるための上限

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TCatch

     // 待ちのスレッドが受けた頼みを、順に控える。Want 個そろったら、合図を立てる
     TCatch = class
     private
       _Lock :TCriticalSection;
       _List :TList<TArray<String>>;
       _Full :TEvent;
       _Want :Integer;
     public
       constructor Create( const Want_:Integer );
       destructor Destroy; override;
       procedure Take( const Args_:TArray<String> );
       function Wait :Boolean;
       function Items :TArray<TArray<String>>;
     end;

constructor TCatch.Create( const Want_:Integer );
begin
     inherited Create;

     _Lock := TCriticalSection.Create;
     _List := TList<TArray<String>>.Create;
     _Full := TEvent.Create( nil, True, False, '' );
     _Want := Want_;
end;

destructor TCatch.Destroy;
begin
     _Full.Free;
     _List.Free;
     _Lock.Free;

     inherited;
end;

procedure TCatch.Take( const Args_:TArray<String> );
begin
     _Lock.Enter;
     try
          _List.Add( Args_ );

          if _List.Count >= _Want then _Full.SetEvent;
     finally
          _Lock.Leave;
     end;
end;

function TCatch.Wait :Boolean;
begin
     Result := _Full.WaitFor( FAIL_MS ) = wrSignaled;
end;

function TCatch.Items :TArray<TArray<String>>;
begin
     _Lock.Enter;
     try
          Result := _List.ToArray;
     finally
          _Lock.Leave;
     end;
end;

//------------------------------------------------------------------------------

// 何もしない受け手（試験の手続きの中で作ると、それを捕まえた無名メソッドと互いに参照して、解放されない）
function Nop :TProc<TArray<String>>;
begin
     Result := procedure( A_:TArray<String> ) begin end;
end;

// 2 つの並びが同じか
function Same( const A_,B_:TArray<String> ) :Boolean;
var
   I :Integer;
begin
     Result := Length( A_ ) = Length( B_ );

     if Result then for I := 0 to High( A_ ) do if A_[ I ] <> B_[ I ] then Exit( False );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

function TSingleTests.NewName :String;
begin
     Result := 'LUX.Test.' + TGUID.NewGuid.ToString.Trim( [ '{', '}' ] );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

procedure TSingleTests.FirstAndSecond;
var
   N :String;
   A, B :TWinSingle;
begin
     N := NewName;

     A := TWinSingle.Create( N );
     try
          B := TWinSingle.Create( N );
          try
               Assert.IsTrue ( A.First );
               Assert.IsFalse( B.First );
          finally
               B.Free;
          end;
     finally
          A.Free;
     end;

     A := TWinSingle.Create( N );
     try
          Assert.IsTrue( A.First, '1 つ目を壊したら、次に作ったものが 1 つ目' );
     finally
          A.Free;
     end;
end;

// 引数が、そのまま 1 つ目に届く（空・空の文字列・日本語・空白と引用符・長いもの）
procedure TSingleTests.ArgsReachFirst;
var
   N :String;
   A, B :TWinSingle;
   C :TCatch;
   Q :TArray<TArray<String>>;
   I :Integer;
   L :TArray<TArray<String>>;
begin
     N := NewName;

     Q := [ [],
            [ '/settings' ],
            [ '', 'あいう', 'with space "q"', '' ],
            [ StringOfChar( '長', 40000 ), 'x' ] ];  // 読む区切り（4096 バイト）を越えるもの

     C := TCatch.Create( Length( Q ) );
     A := TWinSingle.Create( N );
     try
          A.Listen( procedure( A_:TArray<String> ) begin C.Take( A_ ); end );

          B := TWinSingle.Create( N );
          try
               for I := 0 to High( Q ) do Assert.IsTrue( B.Request( Q[ I ], 0 ) = trAlive, '届いて、待たずに戻る（1 つ目は動いている）' );
          finally
               B.Free;
          end;

          Assert.IsTrue( C.Wait, '待ちのスレッドが、全部受ける' );

          L := C.Items;

          Assert.AreEqual( Integer( Length( Q ) ), Integer( Length( L ) ) );

          for I := 0 to High( Q ) do Assert.IsTrue( Same( Q[ I ], L[ I ] ), Format( '%d 番目の頼みが、そのまま、順に届く', [ I ] ) );
     finally
          A.Free;  // 待ちのスレッドを止めて、終わりを待つ
          C.Free;
     end;
end;

// Listen の前の頼みは、口に残り、Listen の後に受ける
procedure TSingleTests.RequestBeforeListen;
var
   N :String;
   A, B :TWinSingle;
   C :TCatch;
begin
     N := NewName;

     C := TCatch.Create( 1 );
     A := TWinSingle.Create( N );
     try
          B := TWinSingle.Create( N );
          try
               Assert.IsTrue( B.Request( [ 'early' ], 0 ) = trAlive );
          finally
               B.Free;
          end;

          A.Listen( procedure( A_:TArray<String> ) begin C.Take( A_ ); end );

          Assert.IsTrue( C.Wait );
          Assert.IsTrue( Same( [ 'early' ], C.Items[ 0 ] ) );
     finally
          A.Free;
          C.Free;
     end;
end;

// 同時に頼んでも、1 つも欠けず、混ざらない
procedure TSingleTests.ManySenders;
const
     THREADS = 8;
     EACH    = 5;
var
   N :String;
   A :TWinSingle;
   C :TCatch;
   Ts :TArray<TThread>;
   I :Integer;
   L :TArray<TArray<String>>;
   S :TStringList;
   R :TArray<String>;

//······································
     function Sender( const K_:Integer ) :TThread;
     begin
          Result := TThread.CreateAnonymousThread( procedure
          var
             B :TWinSingle;
             J :Integer;
          begin
               B := TWinSingle.Create( N );
               try
                    for J := 1 to EACH do B.Request( [ IntToStr( K_ ), IntToStr( J ) ], 0 );
               finally
                    B.Free;
               end;
          end );

          Result.FreeOnTerminate := False;
     end;
//······································

begin
     N := NewName;

     C := TCatch.Create( THREADS * EACH );
     A := TWinSingle.Create( N );
     try
          A.Listen( procedure( A_:TArray<String> ) begin C.Take( A_ ); end );

          SetLength( Ts, THREADS );
          for I := 0 to THREADS - 1 do Ts[ I ] := Sender( I );
          for I := 0 to THREADS - 1 do Ts[ I ].Start;
          for I := 0 to THREADS - 1 do
          begin
               Ts[ I ].WaitFor;
               Ts[ I ].Free;
          end;

          Assert.IsTrue( C.Wait, '全部の頼みが届く' );

          L := C.Items;

          Assert.AreEqual( THREADS * EACH, Integer( Length( L ) ) );

          S := TStringList.Create;
          try
               S.Sorted     := True;
               S.Duplicates := dupError;  // 同じ頼みが 2 度届いたら、例外

               for R in L do
               begin
                    Assert.AreEqual( 2, Integer( Length( R ) ), '頼みの中身が混ざらない' );

                    S.Add( R[ 0 ] + '.' + R[ 1 ] );
               end;
          finally
               S.Free;
          end;
     finally
          A.Free;
          C.Free;
     end;
end;

procedure TSingleTests.Misuse;
var
   N :String;
   A, B :TWinSingle;
begin
     N := NewName;

     A := TWinSingle.Create( N );
     B := TWinSingle.Create( N );
     try
          Assert.WillRaise( procedure begin A.Request( nil, 0 ); end, EInvalidOpException, '1 つ目は自分に頼めない' );
          Assert.WillRaise( procedure begin B.Listen( Nop() ); end, EInvalidOpException, '2 つ目は頼みを受けない' );

          A.Listen( Nop() );

          Assert.WillRaise( procedure begin A.Listen( Nop() ); end, EInvalidOpException, '二度は受け始めない' );
     finally
          B.Free;
          A.Free;
     end;
end;

// 別のプロセスを 1 つ目にして、終わりを待つ結果を確かめる
procedure TSingleTests.WaitForEnd;
var
   N :String;
   P :THandle;
   B :TWinSingle;
   T :UInt64;
begin
     N := NewName;

     P := TTestPeer.Start( N, FAIL_MS );
     try
          B := TWinSingle.Create( N );
          try
               Assert.IsFalse( B.First );

               Assert.IsTrue( B.Request( [ '/stay' ], 0 ) = trAlive, '待たない：まだ動いている' );

               T := GetTickCount64;

               Assert.IsTrue( B.Request( [ '/stay' ], 300 ) = trAlive, '終わらない頼み：上限まで待って、まだ動いている' );
               Assert.IsTrue( GetTickCount64 - T >= 250, '上限まで待った' );

               Assert.IsTrue( B.Request( [ '/quit' ], FAIL_MS ) = trEnded, '終わる頼み：終わった' );

               Assert.IsTrue( WaitForSingleObject( P, 0 ) = WAIT_OBJECT_0, '戻ったときには、1 つ目のプロセスは終わっている' );

               Assert.IsTrue( B.Request( nil, 0 ) = trAbsent, '頼む相手がもういない' );
          finally
               B.Free;
          end;
     finally
          if WaitForSingleObject( P, 0 ) <> WAIT_OBJECT_0 then TerminateProcess( P, 1 );  // 試験が途中で失敗しても、相手役を残さない

          CloseHandle( P );
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TSingleTests );

end. //######################################################################### ■
