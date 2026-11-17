unit Tests.Windows.Monitor;

// LUX.Windows.Monitor の試験
//
//【この機械の実物を読む】
// ・この機械の、すべてのモニターについて、そのモニターの上に置いた、出さない窓から、周期を取る。
//   値は、機械ごとに違うので、決まった値とは比べない。どのモニターでも、周期が分かり、その逆数が整数の Hz（24〜1000）であること、
//   窓を別のモニターへ移すと、移った先のモニターと周期になることを確かめる。外れたときは、読んだ値を、失敗の知らせに書く。
// ・窓は、出さない（WS_VISIBLE を付けない）。終わりに、必ず壊す。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMonitorTests

     [TestFixture]
     TMonitorTests = class
     private
     public
       [Test] procedure EachMonitor;
       [Test] procedure MinOfAll;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Types, System.Generics.Collections,
     Winapi.Windows, Winapi.MultiMon,
     LUX.Windows.Monitor;

type
     TMonitorRect = record
       Handle :HMONITOR;
       Rect   :TRect;
     end;

// EnumDisplayMonitors の 1 つのモニター：並びに足す
function Listed( Monitor_:HMONITOR; DC_:HDC; Rect_:PRect; Data_:LPARAM ) :BOOL; stdcall;
var
   S :TMonitorRect;
begin
     S.Handle := Monitor_;
     S.Rect   := Rect_^;

     TList<TMonitorRect>( Data_ ).Add( S );

     Result := True;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMonitorTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// どのモニターでも、周期が分かり、整数の Hz の逆数である。窓を移すと、移った先のモニターの周期になる
procedure TMonitorTests.EachMonitor;
var
   L :TList<TMonitorRect>;
   S :TMonitorRect;
   W :HWND;
   M :TWinMonitor;
   H :Double;
begin
     L := TList<TMonitorRect>.Create;
     try
          Assert.IsTrue( EnumDisplayMonitors( 0, nil, @Listed, LPARAM( L ) ), 'モニターを数えられた' );
          Assert.IsTrue( L.Count > 0, 'モニターが、1 つ以上ある' );

          W := CreateWindowEx( WS_EX_TOOLWINDOW, 'STATIC', '', WS_POPUP, 0, 0, 100, 100, 0, 0, HInstance, nil );
          if W = 0 then RaiseLastOSError;
          try
               for S in L do
               begin
                    // 窓を、そのモニターの中へ移す（出さない）
                    Assert.IsTrue( SetWindowPos( W, 0, S.Rect.Left + 10, S.Rect.Top + 10, 100, 100, SWP_NOZORDER or SWP_NOACTIVATE ), '窓を移せた' );

                    M := TWinMonitor.Create( W );

                    Assert.AreEqual( UInt64( S.Handle ), UInt64( M.Handle ), '窓が移った先のモニター' );
                    Assert.IsTrue( M.Period > 0, '周期が分かる' );

                    H := 1 / M.Period;

                    Assert.IsTrue( Abs( H - Round( H ) ) < 1E-6, Format( '整数の Hz の逆数（モニター (%d, %d)：%.3f Hz）', [ S.Rect.Left, S.Rect.Top, H ] ) );
                    Assert.IsTrue( ( Round( H ) >= 24 ) and ( Round( H ) <= 1000 ), Format( '画面の更新の速さとして、ありうる値（モニター (%d, %d)：%.3f Hz）', [ S.Rect.Left, S.Rect.Top, H ] ) );
               end;
          finally
               DestroyWindow( W );
          end;
     finally
          L.Free;
     end;
end;

// いちばん短い周期は、どのモニターの上に置いた窓の周期とも、同じか短く、どれか 1 つと等しい
procedure TMonitorTests.MinOfAll;
var
   L :TList<TMonitorRect>;
   S :TMonitorRect;
   W :HWND;
   P, Q :Double;
   E :Boolean;
begin
     P := TWinMonitor.MinPeriod;

     Assert.IsTrue( P > 0, 'いちばん短い周期が分かる' );

     L := TList<TMonitorRect>.Create;
     try
          Assert.IsTrue( EnumDisplayMonitors( 0, nil, @Listed, LPARAM( L ) ), 'モニターを数えられた' );

          E := False;

          W := CreateWindowEx( WS_EX_TOOLWINDOW, 'STATIC', '', WS_POPUP, 0, 0, 100, 100, 0, 0, HInstance, nil );
          if W = 0 then RaiseLastOSError;
          try
               for S in L do
               begin
                    Assert.IsTrue( SetWindowPos( W, 0, S.Rect.Left + 10, S.Rect.Top + 10, 100, 100, SWP_NOZORDER or SWP_NOACTIVATE ), '窓を移せた' );

                    Q := TWinMonitor.Create( W ).Period;

                    Assert.IsTrue( P <= Q, Format( 'モニター (%d, %d) の %.3f Hz より、速いか同じ（いちばん短い周期は %.3f Hz）', [ S.Rect.Left, S.Rect.Top, 1 / Q, 1 / P ] ) );

                    if P = Q then E := True;
               end;
          finally
               DestroyWindow( W );
          end;

          Assert.IsTrue( E, Format( 'どれかのモニターの周期と等しい（%.3f Hz）', [ 1 / P ] ) );
     finally
          L.Free;
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TMonitorTests );

end. //######################################################################### ■
