unit Tests.Windows.Install;

// LUX.Windows.Install の試験
//
//【本物に触れない】
// ・アプリの名前は、試験ごとに GUID の入った試験用の名前。入れる先（Dest）は、一時のフォルダーの下に替える。
//   一緒に入れるものは、試験の実行ファイルの隣に作り、終わりに消す。
// ・「アプリ」の一覧（HKEY_LOCAL_MACHINE）は、管理者のときだけ、試験用の名前で登録して、必ず消す。
//   管理者でないときは、登録が断られ、何もできていないことを確かめる。
//
//【確かめないこと】
// ・Uninstall（利用者に聞く窓・管理者の許可・一時の写しへ移ること）と Enroll（スタートメニュー）は、
//   本物の窓と、利用者の環境に触れるので、ここでは動かさない。
// ・Grant は、一時のフォルダーの下の、試験が作ったフォルダーにだけ行う（本物の入れた先には触れない）。

interface //#################################################################### ■

uses DUnitX.TestFramework,
     LUX.Windows.Install;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TInstallTests

     [TestFixture]
     TInstallTests = class
     private
       _App  :String;  // 試験用のアプリの名前
       _Temp :String;  // 入れる先を置く一時のフォルダー
       _Side :String;  // 試験の実行ファイルの隣に作る、一緒に入れるフォルダー（名前）
     public
       [Setup]    procedure Setup;
       [TearDown] procedure TearDown;
       [Test] procedure Defaults;
       [Test] procedure PlaceAndRemove;
       [Test] procedure PlaceReplacesInUse;
       [Test] procedure MissingFileRaises;
       [Test] procedure RegisterEntry;
       [Test] procedure GrantChecks;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.IOUtils, System.Win.Registry, System.Win.ComObj,
     Winapi.Windows, Winapi.KnownFolders, Winapi.ShlObj, Winapi.ActiveX;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

// 管理者として動いているか
function Elevated :Boolean;
var
   T :THandle;
   E :TOKEN_ELEVATION;
   N :DWORD;
begin
     if not OpenProcessToken( GetCurrentProcess, TOKEN_QUERY, T ) then RaiseLastOSError;
     try
          if not GetTokenInformation( T, TokenElevation, @E, SizeOf( E ), N ) then RaiseLastOSError;

          Result := E.TokenIsElevated <> 0;
     finally
          CloseHandle( T );
     end;
end;

// 実行ファイルの隣
function Beside( const Name_:String ) :String;
begin
     Result := TPath.Combine( ExtractFileDir( ParamStr( 0 ) ), Name_ );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TInstallTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

procedure TInstallTests.Setup;
var
   G :String;
begin
     G := TGUID.NewGuid.ToString.Trim( [ '{', '}' ] );

     _App  := 'LUX.Test.' + G;
     _Temp := TPath.Combine( TPath.GetTempPath, 'LUX.Test.Install.' + G );
     _Side := 'LUX.Test.Side.' + G;

     TDirectory.CreateDirectory( _Temp );

     // 一緒に入れるもの：中にフォルダーを持つフォルダーと、ファイル 1 つ
     TDirectory.CreateDirectory( TPath.Combine( Beside( _Side ), 'sub' ) );

     TFile.WriteAllText( TPath.Combine( Beside( _Side ), 'a.txt'        ), 'A' );
     TFile.WriteAllText( TPath.Combine( Beside( _Side ), 'sub\b.txt'    ), 'B' );
     TFile.WriteAllText( Beside( _Side + '.txt' )                        , 'C' );
end;

// 作ったものを、必ず消す（試験が途中で失敗しても）
procedure TInstallTests.TearDown;
var
   R :TRegistry;
begin
     if TDirectory.Exists( _Temp            ) then TDirectory.Delete( _Temp, True );
     if TDirectory.Exists( Beside( _Side )  ) then TDirectory.Delete( Beside( _Side ), True );
     if TFile.Exists( Beside( _Side + '.txt' ) ) then TFile.Delete( Beside( _Side + '.txt' ) );

     if Elevated then
     begin
          R := TRegistry.Create( KEY_READ or KEY_WRITE );
          try
               R.RootKey := HKEY_LOCAL_MACHINE;

               if R.KeyExists( TWinInstaller.Create( _App, [], '' ).Entry ) then R.DeleteKey( TWinInstaller.Create( _App, [], '' ).Entry );
          finally
               R.Free;
          end;
     end;
end;

//------------------------------------------------------------------------------

procedure TInstallTests.Defaults;
var
   K :TWinInstaller;
   P :PWideChar;
   F :String;
begin
     OleCheck( SHGetKnownFolderPath( FOLDERID_ProgramFiles, 0, 0, P ) );
     try
          F := P;
     finally
          CoTaskMemFree( P );
     end;

     K := TWinInstaller.Create( _App, [], '' );

     Assert.AreEqual( TPath.Combine( F, 'LUXOPHIA' ), TWinInstaller.Root );
     Assert.AreEqual( TPath.Combine( TPath.Combine( F, 'LUXOPHIA' ), _App ), K.Dest, '既定は Program Files\LUXOPHIA\<アプリ>' );
     Assert.AreEqual( TPath.Combine( K.Dest, _App + '.exe' ), K.Target );
     Assert.IsFalse( K.Installed , '試験の実行ファイルは、入れた先から動いていない' );
     Assert.IsFalse( K.HasPayload, 'zip を持たない' );

     Assert.AreEqual( _App    , K.Startup.Name );
     Assert.AreEqual( K.Target, K.Startup.Exe , '自動起動は、入れた先の実行ファイルを指す' );

     Assert.AreEqual( 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + _App, K.Entry );
     Assert.AreEqual( _App + '.lnk', ExtractFileName( K.Link ) );

     K.Dest := TPath.Combine( _Temp, 'Dest\' );

     Assert.AreEqual( TPath.Combine( _Temp, 'Dest' ), K.Dest, '替えた先（末尾の区切りは取る）' );

     Assert.WillRaise( procedure begin TWinInstaller.Create( '', [], '' ); end, EArgumentException );
end;

// 入れる → 消す
procedure TInstallTests.PlaceAndRemove;
var
   K :TWinInstaller;
begin
     K := TWinInstaller.Create( _App, [ _Side, _Side + '.txt' ], '' );

     K.Dest := TPath.Combine( _Temp, 'LUXOPHIA\' + _App );

     K.Place;

     Assert.IsTrue( TFile.Exists( K.Target ) );
     Assert.IsTrue( TFile.GetSize( ParamStr( 0 ) ) = TFile.GetSize( K.Target ), '実行ファイル自身を、Target の名前で置く' );

     Assert.AreEqual( 'A', TFile.ReadAllText( TPath.Combine( K.Dest, _Side + '\a.txt'     ) ) );
     Assert.AreEqual( 'B', TFile.ReadAllText( TPath.Combine( K.Dest, _Side + '\sub\b.txt' ) ), 'フォルダーの中身を、形のまま' );
     Assert.AreEqual( 'C', TFile.ReadAllText( TPath.Combine( K.Dest, _Side + '.txt'       ) ) );

     Assert.AreEqual( 0, K.Remove, '使用中のものが無ければ、全部、今消える' );

     Assert.IsFalse( TDirectory.Exists( K.Dest ), '入れた先が消えた' );
     Assert.IsTrue ( TDirectory.Exists( ExtractFileDir( K.Dest ) ), '既定の親（Root）でない親は、消さない' );
end;

// 使用中（動いている実行ファイルと同じ：消せず上書きできないが、名前は変えられる）でも置き換え、古いものは Sweep で消す
procedure TInstallTests.PlaceReplacesInUse;
var
   K :TWinInstaller;
   H :HMODULE;
begin
     K := TWinInstaller.Create( _App, [], '' );

     K.Dest := TPath.Combine( _Temp, 'Dest' );

     K.Place;

     // 動いている実行ファイルと同じに、実行の形で読み込む（中のコードは動かさない）
     H := LoadLibraryEx( PChar( K.Target ), 0, DONT_RESOLVE_DLL_REFERENCES );

     if H = 0 then RaiseLastOSError;
     try
          K.Place;

          Assert.AreEqual( 1, Integer( Length( TDirectory.GetFiles( K.Dest, '*.old-*' ) ) ), '使用中のものは、別の名前に移した' );

          K.Sweep;

          Assert.AreEqual( 1, Integer( Length( TDirectory.GetFiles( K.Dest, '*.old-*' ) ) ), '使用中の間は、消せずに残す' );
     finally
          FreeLibrary( H );
     end;

     K.Sweep;

     Assert.AreEqual( 0, Integer( Length( TDirectory.GetFiles( K.Dest, '*.old-*' ) ) ), '使われなくなったら、消す' );
     Assert.IsTrue( TFile.Exists( K.Target ) );
end;

procedure TInstallTests.MissingFileRaises;
var
   K :TWinInstaller;
begin
     K := TWinInstaller.Create( _App, [ _Side + '.missing' ], '' );

     K.Dest := TPath.Combine( _Temp, 'Dest' );

     Assert.WillRaise( procedure begin K.Place; end, EFileNotFoundException );
end;

// 「アプリ」の一覧の登録（管理者のときだけ、本当に書いて消す）
procedure TInstallTests.RegisterEntry;
var
   K :TWinInstaller;
   R :TRegistry;
begin
     K := TWinInstaller.Create( _App, [], '' );

     K.Dest := TPath.Combine( _Temp, 'Dest' );

     K.Place;

     if not Elevated then
     begin
          Assert.WillRaise( procedure begin K.Register( '1.2.3' ); end, ERegistryException, '管理者でなければ、断られる' );

          K.Unregister;  // 登録が無ければ、管理者でなくても、何もせずに済む

          Exit;
     end;

     K.Register( '1.2.3' );

     R := TRegistry.Create( KEY_READ );
     try
          R.RootKey := HKEY_LOCAL_MACHINE;

          Assert.IsTrue( R.OpenKeyReadOnly( K.Entry ) );

          Assert.AreEqual( _App                                                         , R.ReadString( 'DisplayName'     ) );
          Assert.AreEqual( '1.2.3'                                                      , R.ReadString( 'DisplayVersion'  ) );
          Assert.AreEqual( 'LUXOPHIA'                                                   , R.ReadString( 'Publisher'       ) );
          Assert.AreEqual( K.Dest                                                       , R.ReadString( 'InstallLocation' ) );
          Assert.AreEqual( '"' + K.Target + '" ' + TWinInstaller.ARG_UNINSTALL          , R.ReadString( 'UninstallString' ) );
     finally
          R.Free;
     end;

     K.Unregister;

     R := TRegistry.Create( KEY_READ );
     try
          R.RootKey := HKEY_LOCAL_MACHINE;

          Assert.IsFalse( R.KeyExists( K.Entry ), '消えた' );
     finally
          R.Free;
     end;
end;

// 利用者の名前が空なら、その場で例外。権限を付ける手段（icacls）が失敗したら、例外。できれば、何も言わずに済む
procedure TInstallTests.GrantChecks;
var
   K :TWinInstaller;
begin
     K := TWinInstaller.Create( _App, [], '' );

     K.Dest := TPath.Combine( _Temp, 'Dest' );

     Assert.WillRaise( procedure begin K.Grant( '' ); end, EArgumentException, '利用者の名前が空' );

     Assert.WillRaise( procedure begin K.Grant( TWinInstaller.CurrentUser ); end, EOSError, '入れた先が無い（icacls が失敗する）' );

     TDirectory.CreateDirectory( K.Dest );

     Assert.WillRaise( procedure begin K.Grant( 'LUX.Test.NoSuchUser.' + TGUID.NewGuid.ToString ); end, EOSError, '無い利用者（icacls が失敗する）' );

     Assert.WillNotRaise( procedure begin K.Grant( TWinInstaller.CurrentUser ); end, Exception, '自分が作ったフォルダーに、自分の権限を付ける' );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TInstallTests );

end. //######################################################################### ■
