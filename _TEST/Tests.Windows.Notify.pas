unit Tests.Windows.Notify;

// LUX.Windows.Notify の試験
//
//【確かめ方】
// ・クリックは、アイコンの操作の知らせ（TWinNotify.CALLBACK）を、見えない窓（Handle）へ送って確かめる。
// ・付け直しは、アイコンを消してから、エクスプローラーが立ち上がり直した知らせ（TaskbarCreated）を、見えない窓だけへ送って
//   確かめる（ほかの窓へは送らない）。アイコンがあるかは、Shell_NotifyIconGetRect が答えるかで見る。
//
//【確かめないこと】
// ・右クリックのメニューと、通知（Balloon）の見た目は、人の手の操作と目でしか確かめられない（出すと、利用者の画面に出る）。
//   作っている間、通知領域にアイコンが一瞬出る。

interface //#################################################################### ■

uses DUnitX.TestFramework,
     LUX.Windows.Notify;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TNotifyTests

     [TestFixture]
     TNotifyTests = class
     public
       [Test] procedure MenuItemsAndStates;
       [Test] procedure TipIsKept;
       [Test] procedure UnknownItemRaises;
       [Test] procedure OpenOncePerClick;
       [Test] procedure ReaddOnTaskbarCreated;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Types,
     Winapi.Windows, Winapi.Messages, Winapi.ShellAPI;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

// アイコンが、通知領域に登録されているか
function Present( const N_:TWinNotify ) :Boolean;
var
   I :NOTIFYICONIDENTIFIER;
   R :TRect;
begin
     I := Default( NOTIFYICONIDENTIFIER );

     I.cbSize := SizeOf( I );
     I.hWnd   := N_.Handle;
     I.uID    := 1;

     Result := Succeeded( Shell_NotifyIconGetRect( I, R ) );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TNotifyTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

procedure TNotifyTests.MenuItemsAndStates;
var
   N :TWinNotify;
   A, B, C :Integer;
begin
     N := TWinNotify.Create( '試験' );
     try
          A := N.AddItem( '開く', procedure begin end );
          N.AddSeparator;
          B := N.AddItem( '止める', procedure begin end );
          C := N.AddItem( '終わる', procedure begin end );

          Assert.AreEqual( 1, A );
          Assert.AreEqual( 3, B, '区切りも番号を 1 つ使う' );
          Assert.AreEqual( 4, C );

          Assert.AreEqual( 0, N.Primary );

          N.Primary := A;

          Assert.AreEqual( A, N.Primary );

          N.Primary := 0;

          Assert.AreEqual( 0, N.Primary );

          Assert.IsTrue( N.Enableds[ B ] );

          N.Enableds[ B ] := False;

          Assert.IsFalse( N.Enableds[ B ] );
          Assert.IsTrue ( N.Enableds[ C ], 'ほかの項目は変わらない' );

          N.Enableds[ B ] := True;

          Assert.IsTrue( N.Enableds[ B ] );
     finally
          N.Free;
     end;
end;

procedure TNotifyTests.TipIsKept;
var
   N :TWinNotify;
begin
     N := TWinNotify.Create( '最初' );
     try
          Assert.AreEqual( '最初', N.Tip );

          N.Tip := '処理中 3 本';

          Assert.AreEqual( '処理中 3 本', N.Tip );

          N.Tip := StringOfChar( 'あ', 500 );

          Assert.AreEqual( 127, Length( N.Tip ), '入りきらない分は切る（szTip は 128 文字）' );
     finally
          N.Free;
     end;
end;

procedure TNotifyTests.UnknownItemRaises;
var
   N :TWinNotify;
begin
     N := TWinNotify.Create( '試験' );
     try
          N.AddItem( '開く', procedure begin end );

          Assert.WillRaise( procedure begin N.Enableds[ 9 ] := False; end, EArgumentOutOfRangeException );
          Assert.WillRaise( procedure begin if N.Enableds[ 9 ] then Exit; end, EArgumentOutOfRangeException );
          Assert.WillRaise( procedure begin N.Primary := 9; end, EArgumentOutOfRangeException );

          Assert.AreEqual( 0, N.Primary, '無い番号を太字にしようとしても、変わらない' );
     finally
          N.Free;
     end;
end;

// 1 回のクリックも、ダブルクリックも、開くのは 1 度
procedure TNotifyTests.OpenOncePerClick;
var
   N :TWinNotify;
   K :Integer;

//······································
     procedure Mouse( const Messages_:TArray<Integer> );
     var
        M :Integer;
     begin
          for M in Messages_ do SendMessage( N.Handle, TWinNotify.CALLBACK, 1, M );
     end;
//······································

begin
     K := 0;

     N := TWinNotify.Create( '試験' );
     try
          N.OnOpen := procedure begin Inc( K ); end;

          Mouse( [ WM_LBUTTONDOWN, WM_LBUTTONUP ] );

          Assert.AreEqual( 1, K, '1 回のクリック' );

          Mouse( [ WM_LBUTTONDOWN, WM_LBUTTONUP, WM_LBUTTONDBLCLK, WM_LBUTTONUP ] );

          Assert.AreEqual( 2, K, 'ダブルクリックは、1 度目で開き、2 度目では開かない' );

          Mouse( [ WM_LBUTTONDOWN, WM_LBUTTONUP ] );

          Assert.AreEqual( 3, K, 'ダブルクリックの後の 1 回のクリックは、また開く' );

          Mouse( [ WM_RBUTTONDOWN ] );

          Assert.AreEqual( 3, K, '右のボタンを押しただけでは、開かない' );
     finally
          N.Free;
     end;
end;

// アイコンが消えても、エクスプローラーが立ち上がり直した知らせで、付け直す
procedure TNotifyTests.ReaddOnTaskbarCreated;
var
   N :TWinNotify;
   D :TNotifyIconDataW;
begin
     N := TWinNotify.Create( '試験' );
     try
          Assert.IsTrue( Present( N ), '作ると、通知領域に付く（タスクバーがあること）' );

          // エクスプローラーが立ち上がり直したときと同じに、アイコンを無くす（自分のアイコンだけ）
          D := Default( TNotifyIconDataW );

          D.cbSize := SizeOf( D );
          D.Wnd    := N.Handle;
          D.uID    := 1;

          Assert.IsTrue( Shell_NotifyIconW( NIM_DELETE, @D ) );

          Assert.IsFalse( Present( N ), '消えた' );

          SendMessage( N.Handle, RegisterWindowMessage( 'TaskbarCreated' ), 0, 0 );

          Assert.IsTrue( Present( N ), '付け直した' );

          Assert.AreEqual( '試験', N.Tip, '控えの文のまま' );
     finally
          N.Free;
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TNotifyTests );

end. //######################################################################### ■
