unit Tests.Windows.Startup;

// LUX.Windows.Startup の試験
//
//【本物に触れない】
// ・試験ごとに、GUID の入った試験用の名前で、存在しない実行ファイルを登録し、終わりに必ず消す。
//   ほかの値（本物のアプリの自動起動）は、読みも書きもしない。

interface //#################################################################### ■

uses DUnitX.TestFramework,
     LUX.Windows.Startup;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TStartupTests

     [TestFixture]
     TStartupTests = class
     private
       _Name :String;
       function Value( out Text_:String ) :Boolean;
     public
       [Setup]    procedure Setup;
       [TearDown] procedure TearDown;
       [Test] procedure CommandForm;
       [Test] procedure OnAndOff;
       [Test] procedure OtherExeIsNotOn;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Win.Registry,
     Winapi.Windows;

const
     EXE = 'C:\LUX.Test\Missing App.exe';  // 存在しない実行ファイル（登録だけを見る。起動されることはない）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TStartupTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

// 試験用の名前の値を、部品を通さずに読む
function TStartupTests.Value( out Text_:String ) :Boolean;
var
   R :TRegistry;
begin
     R := TRegistry.Create( KEY_READ );
     try
          R.RootKey := HKEY_CURRENT_USER;

          Result := R.OpenKeyReadOnly( TWinStartup.RUN_KEY ) and R.ValueExists( _Name );

          if Result then Text_ := R.ReadString( _Name )
                    else Text_ := '';
     finally
          R.Free;
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

procedure TStartupTests.Setup;
begin
     _Name := 'LUX.Test.Startup.' + TGUID.NewGuid.ToString.Trim( [ '{', '}' ] );
end;

// 試験用の値を、必ず消す（試験が途中で失敗しても）
procedure TStartupTests.TearDown;
var
   R :TRegistry;
begin
     R := TRegistry.Create( KEY_READ or KEY_WRITE );
     try
          R.RootKey := HKEY_CURRENT_USER;

          if R.OpenKey( TWinStartup.RUN_KEY, False ) and R.ValueExists( _Name ) then R.DeleteValue( _Name );
     finally
          R.Free;
     end;
end;

procedure TStartupTests.CommandForm;
var
   S :TWinStartup;
begin
     S := TWinStartup.Create( _Name, EXE );

     Assert.AreEqual( '"' + EXE + '" /tray', S.Command );
     Assert.AreEqual( _Name, S.Name );
     Assert.AreEqual( EXE  , S.Exe  );

     Assert.WillRaise( procedure begin TWinStartup.Create( '', EXE ); end, EArgumentException, '名前が空なら、ほかの値に触れないように止める' );
end;

procedure TStartupTests.OnAndOff;
var
   S :TWinStartup;
   T :String;
begin
     S := TWinStartup.Create( _Name, EXE );

     Assert.IsFalse( S.Enabled, '初めは無い' );

     S.Enabled := True;

     Assert.IsTrue( S.Enabled );
     Assert.IsTrue( Value( T ), '値ができた' );
     Assert.AreEqual( S.Command, T );

     S.Enabled := True;   // 2 度書いても同じ

     Assert.IsTrue( S.Enabled );

     S.Enabled := False;

     Assert.IsFalse( S.Enabled );
     Assert.IsFalse( Value( T ), '値が消えた' );

     S.Enabled := False;  // 無いものを消しても、例外にならない

     Assert.IsFalse( S.Enabled );
end;

// 別の場所の実行ファイルを指す登録は、入っていないと答え、入れると、この実行ファイルを指すように書き直す
procedure TStartupTests.OtherExeIsNotOn;
var
   A, B :TWinStartup;
   T :String;
begin
     A := TWinStartup.Create( _Name, 'C:\LUX.Test\Old\Missing App.exe' );
     B := TWinStartup.Create( _Name, EXE );

     A.Enabled := True;

     Assert.IsTrue ( A.Enabled );
     Assert.IsFalse( B.Enabled, '同じ名前でも、別の実行ファイルを指していれば、入っていない' );

     B.Enabled := True;

     Assert.IsTrue( B.Enabled );
     Assert.IsTrue( Value( T ) );
     Assert.AreEqual( B.Command, T, '書き直した' );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TStartupTests );

end. //######################################################################### ■
