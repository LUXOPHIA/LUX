unit Tests.Process.Deadline;

// LUX.Process.Deadline の試験
//
//【やり方】
// ・期限は、自分のプロセスを終わらせるので、相手役のプロセス（Tests.Peer の --deadline）に仕掛けさせる。
//   相手役は、期限を仕掛けた後、主スレッドを止めたままにする。期限で終わり、その終了コードが返ることを見る。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDeadlineTests

     [TestFixture]
     TDeadlineTests = class
     public
       [Test] procedure EndsStuckProcess;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils,
     Winapi.Windows,
     Tests.Peer;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDeadlineTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 主スレッドが止まったままのプロセスが、期限で終わり、決めた終了コードを返す
procedure TDeadlineTests.EndsStuckProcess;
var
   H :THandle;
   C :Cardinal;
begin
     H := TTestPeer.Stuck( 300, 7 );
     try
          Assert.AreEqual( WAIT_OBJECT_0, WaitForSingleObject( H, 10000 ), '期限を過ぎても、終わらない' );

          Assert.IsTrue( GetExitCodeProcess( H, C ) );
          Assert.AreEqual( Cardinal( 7 ), C );
     finally
          TerminateProcess( H, 1 );  // 終わっていれば、何も起きない
          CloseHandle( H );
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TDeadlineTests );

end. //######################################################################### ■
