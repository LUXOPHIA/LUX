unit LUX.Windows.Install;

// 実行ファイル 1 つで入れる・入れ替える・消す手順の部品
//
//【構成】
// ・TWinInstaller … アプリの名前・一緒に入れるファイルの一覧・中に持っている zip のリソース名から作り、手順の 1 つずつを行う。
//
//【入れる先】
// ・既定は Program Files\LUXOPHIA\<アプリの名前>（Root の下）。Dest に書けば替えられる。実行ファイルの名前は <アプリの名前>.exe。
//
//【入れるもの】
// ・動いている実行ファイル自身（Target の名前で置く）。
// ・Files：動いている実行ファイルの隣にある、ファイル・フォルダー（隣からの相対の場所）。フォルダーは、中身を全部。
// ・Payload：実行ファイルの中に持つ zip のリソース（RCDATA）の中身。名前が空なら、持たない。
//
//【入れる手順】（呼ぶ順は、使う側が決める。管理者が要るものは、Elevate で起動し直した方で行う）
// ・Place    … 入れるものを、入れた先に書く（使用中のものも置き換える）。管理者。
// ・Register … Windows の「アプリ」の一覧に載せる。管理者。
// ・Grant    … 入れた先を、その利用者が書き換えられるようにする（以後の入れ替えで UAC が要らないように）。管理者。
//              利用者の名前が空なら、その場で例外（権限を付けずに黙って終わると、以後の入れ替えが、後になって断られる）。
//              権限を付ける icacls の終了コードが 0 でなければ、例外（動かせなかったときも）。
// ・Sweep    … 置き換えで残った古いファイルを消す。
// ・Enroll   … スタートメニューに、ショートカットを置く（今の利用者の分）。
// ・自動起動の登録は Startup（LUX.Windows.Startup。値の名前はアプリの名前、起動するのは Target）。
//
//【「アプリ」の一覧の登録を HKEY_LOCAL_MACHINE に置く理由】
// ・入れる先（Program Files）は PC 全体のもので、書くのは管理者として起動し直した方。HKEY_CURRENT_USER は、そのとき
//   管理者の資格を出した人のものになる（別の管理者の名前で許可したら、その人の一覧に載る）。PC 全体の場所に入れたものは、
//   PC 全体の一覧に載せる。消すときも、管理者として起動し直して消す。
//
//【消す手順】（UninstallString は "<Target>" /uninstall。使う側は、ARG_UNINSTALL なら Uninstall、ARG_REMOVE なら Remove を呼ぶ）
// ・Uninstall（1 回目。利用者の権限で、一覧から呼ばれる）：消すか・利用者のデータ（Datas_）も消すかを聞き（既定は残す）、
//   Stop_ で動いている本体を終わらせ、自分を一時の場所へ写して、それを起動して終わる。
//   動いている実行ファイルは、消せない。入れた先から動いているプロセスを全部終わらせてから消すために、一時の写しへ移る。
// ・Uninstall（2 回目。一時の写しで）：1 回目のプロセスの終わりを、受け継いだハンドルで待つ（時間で待たない）。
//   自分を管理者として起動し直して Remove を行わせ、自動起動の登録・ショートカット・（選ばれたら）利用者のデータを消す。
// ・Remove（管理者）：一覧の登録と、入れた先を消す。使用中で消せないものは、次の再起動で消す（MoveFileEx の
//   MOVEFILE_DELAY_UNTIL_REBOOT。Windows の正規の方法）。一時の写し（自分）も、自分は消せないので、次の再起動で消す。
// ・管理者の許可を断られたら、何も消さない（動いていた本体は、終わったまま）。
//
//【画面】
// ・聞く・知らせるのは Windows 標準の窓（MessageBox）。画面の部品を使わない。

interface //#################################################################### ■

uses System.SysUtils,
     LUX.Windows.Startup;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinInstaller

     // 実行ファイル 1 つで入れる・入れ替える・消す手順の部品
     TWinInstaller = record
     private
       _App     :String;          // アプリの名前
       _Files   :TArray<String>;  // 一緒に入れる、実行ファイルの隣のファイル・フォルダー（相対の場所）
       _Payload :String;          // 中に持っている zip のリソース名（空なら、持たない）
       _Dest    :String;          // 入れた先のフォルダー
       ///// A C C E S S O R
       procedure SetDest( const Dest_:String );
       function GetTarget :String;
       function GetInstalled :Boolean;
       function GetHasPayload :Boolean;
       function GetStartup :TWinStartup;
       function GetLink :String;
       function GetEntry :String;
       class function GetRoot :String; static;
       class function GetCurrentUser :String; static;
       ///// M E T H O D
       function Elsewhere :Boolean;
     public
       constructor Create( const App_:String; const Files_:TArray<String>; const Payload_:String );
       ///// P R O P E R T Y
       property App               :String      read _App                        ;                // アプリの名前
       property Dest              :String      read _Dest          write SetDest;                // 入れた先のフォルダー（既定は Root\App）
       property Target            :String      read GetTarget                   ;                // 入れた先の実行ファイル
       property Installed         :Boolean     read GetInstalled                ;                // 入れた先の実行ファイルとして動いているか
       property HasPayload        :Boolean     read GetHasPayload               ;                // 中に持っている zip があるか
       property Startup           :TWinStartup read GetStartup                  ;                // 自動起動の登録（名前は App、起動するのは Target）
       property Link              :String      read GetLink                     ;                // スタートメニューのショートカット
       property Entry             :String      read GetEntry                    ;                // 「アプリ」の一覧の登録の場所（HKEY_LOCAL_MACHINE の下）
       class property Root        :String      read GetRoot                     ;                // 入れる先の既定の親（Program Files\LUXOPHIA）
       class property CurrentUser :String      read GetCurrentUser              ;                // 今の利用者（ドメイン\名前）
       ///// C O N S T A N T
       const ARG_UNINSTALL = '/uninstall';                                                       // 消す（一覧の UninstallString の引数）
       const ARG_REMOVE    = '/remove';                                                          // 管理者として、一覧の登録と入れた先を消す
       const PUBLISHER     = 'LUXOPHIA';                                                         // 一覧に出す発行元
       ///// M E T H O D
       procedure Place;                                                                          // 入れるものを、入れた先に書く（使用中のものも置き換える）。できなければ例外
       procedure Register( const Version_:String );                                              // 「アプリ」の一覧に載せる（Version_ は一覧に出す版）。管理者。できなければ例外
       procedure Unregister;                                                                     // 一覧の登録を消す（無ければ何もしない）。管理者。できなければ例外
       procedure Grant( const User_:String );                                                    // 入れた先を、その利用者が書き換えられるようにする。User_ が空・付けられなければ例外
       procedure Sweep;                                                                          // 置き換えで残った古いファイルを消す（使用中のものは、次の機会に）
       procedure Enroll( const Comment_:String );                                                // スタートメニューに、Target へのショートカットを置く（Comment_ はその説明）。できなければ例外
       procedure Unenroll;                                                                       // スタートメニューのショートカットを消す（無ければ何もしない）
       function Uninstall( const Datas_:TArray<String>; const Stop_:TProc ) :Integer;            // /uninstall で呼ぶ（Datas_：消すかを聞く利用者のデータのフォルダー。Stop_：動いている本体を終わらせる）。終了コード（0：済んだ・やめた・1：管理者の許可を断られた・2：消すのに失敗）
       function Remove :Integer;                                                                 // /remove で呼ぶ（管理者）。終了コード（0：全部消えた・1：残りは次の再起動で消える・2：失敗）
       class function Elevate( const Args_:String ) :Integer; static;                            // 自分を管理者として起動し直して、終わるのを待つ。終了コード（断られたら -1）
       class function Ask( const Title_,Text_:String ) :Boolean; static;                         // はい・いいえを聞く
       class procedure Tell( const Title_,Text_:String; const Error_:Boolean = False ); static;  // 知らせる
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.Classes, System.IOUtils, System.Zip, System.Generics.Collections, System.Generics.Defaults, System.Win.Registry, System.Win.ComObj,
     Winapi.Windows, Winapi.ShellAPI, Winapi.ShlObj, Winapi.ActiveX, Winapi.KnownFolders;

resourcestring //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T E X T 】

     STitle = '%s のアンインストール';
     SAsk   = '%s をアンインストールします。よろしいですか？';
     SAskD  = '%s をアンインストールします。'#13#10#13#10'設定や記録などの利用者のデータも削除しますか？'#13#10'%s'#13#10#13#10'はい：データも削除する'#13#10'いいえ：データは残す'#13#10'キャンセル：アンインストールしない';
     SAbort = 'アンインストールを中止しました（管理者の許可が得られませんでした）。何も削除していません。';
     SFail  = 'アンインストールできませんでした（終了コード %d）。';
     SDone  = '%s をアンインストールしました。';
     SLater = '使用中だったファイルは、次に Windows を再起動したときに削除されます。';
     SLeft  = '次のものは削除できませんでした：'#13#10'%s';
     SNoDel = '削除できないファイルがあります：%s（%s）';

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      UNINSTALL_KEY = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\';  // 「アプリ」の一覧の登録の親
      TEMP_MARK     = '.uninstall.';                                            // 一時の写しのフォルダーの名前の印（<アプリ>.uninstall.<GUID>）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

// 決まったフォルダーの場所（FOLDERID_…）。読めなければ例外
function KnownFolder( const Id_:TGUID ) :String;
var
   P :PWideChar;
begin
     OleCheck( SHGetKnownFolderPath( Id_, 0, 0, P ) );
     try
          Result := P;
     finally
          CoTaskMemFree( P );
     end;
end;

// フォルダーを、途中の階層ごと、在る状態にする（確かめてから作る間に、ほかが作っても、成功）
procedure MakeDir( const Dir_:String );
var
   D, P :String;
   E :DWORD;
begin
     D := ExcludeTrailingPathDelimiter( TPath.GetFullPath( Dir_ ) );

     if TDirectory.Exists( D ) then Exit;

     P := ExtractFileDir( D );

     if ( P <> '' ) and ( P <> D ) then MakeDir( P );

     if CreateDirectory( PChar( D ), nil ) then Exit;

     E := GetLastError;

     if ( E = ERROR_ALREADY_EXISTS ) and TDirectory.Exists( D ) then Exit;

     raise EInOutError.Create( SysErrorMessage( E ) + '：' + D );
end;

// 書く：別の名前に書いて、ディスクまで書き切ってから差し替える（途中で止まっても、古い中身か新しい中身のどちらかが残る）
procedure WriteNew( const Path_:String; const Bytes_:TBytes );
var
   T :String;
   S :TFileStream;
begin
     T := Path_ + '.' + TGUID.NewGuid.ToString + '.tmp';

     try
          S := TFileStream.Create( T, fmCreate );
          try
               if Length( Bytes_ ) > 0 then S.WriteBuffer( Bytes_[ 0 ], Length( Bytes_ ) );

               FlushFileBuffers( S.Handle );
          finally
               S.Free;
          end;

          if not MoveFileEx( PChar( T ), PChar( Path_ ), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH ) then RaiseLastOSError;
     except
          DeleteFile( PChar( T ) );

          raise;
     end;
end;

// 動いている実行ファイルでも置き換える：書けなければ、今のものを別の名前（<名前>.old-<時刻>）に移してから書く
// （動いている実行ファイルは、消せず、上書きもできないが、名前は変えられる）
procedure ReplaceInUse( const Path_:String; const Bytes_:TBytes );
var
   O :String;
begin
     try
          WriteNew( Path_, Bytes_ );
     except
          O := Path_ + '.old-' + FormatDateTime( 'yyyymmddhhnnsszzz', Now );

          if not MoveFileEx( PChar( Path_ ), PChar( O ), MOVEFILE_WRITE_THROUGH ) then raise;

          try
               WriteNew( Path_, Bytes_ );
          except
               MoveFileEx( PChar( O ), PChar( Path_ ), MOVEFILE_WRITE_THROUGH );  // 書けなければ、前のものに戻す

               raise;
          end;
     end;
end;

// 消す。使用中で消せなければ、次の再起動で消す（管理者だけができる）。今消えたら True、再起動を待つなら False
function Discard( const Path_:String; const Dir_:Boolean ) :Boolean;
var
   E :DWORD;
begin
     if Dir_ then Result := RemoveDirectory( PChar( Path_ ) )
             else Result := DeleteFile     ( PChar( Path_ ) );

     if Result then Exit;

     E := GetLastError;

     if ( E = ERROR_FILE_NOT_FOUND ) or ( E = ERROR_PATH_NOT_FOUND ) then Exit( True );

     if not MoveFileEx( PChar( Path_ ), nil, MOVEFILE_DELAY_UNTIL_REBOOT ) then
          raise EInOutError.CreateFmt( SNoDel, [ Path_, SysErrorMessage( GetLastError ) ] );
end;

// フォルダーを中身ごと消す（深いものから）。全部が今消えたら True
function Purge( const Dir_:String ) :Boolean;
var
   F :String;
   Ds :TArray<String>;
begin
     Result := True;

     if not TDirectory.Exists( Dir_ ) then Exit;

     for F in TDirectory.GetFiles( Dir_, '*', TSearchOption.soAllDirectories ) do
     begin
          SetFileAttributes( PChar( F ), FILE_ATTRIBUTE_NORMAL );  // 読み取り専用でも消す

          if not Discard( F, False ) then Result := False;
     end;

     // フォルダーは、中のフォルダーより後に消す。中のフォルダーの名前は、親の名前を頭に含んで長いので、長いものから消す
     Ds := TDirectory.GetDirectories( Dir_, '*', TSearchOption.soAllDirectories );

     TArray.Sort<String>( Ds, TComparer<String>.Construct( function( const A_,B_:String ) :Integer
                                                           begin
                                                                Result := Length( B_ ) - Length( A_ );
                                                           end ) );

     for F in Ds do if not Discard( F, True ) then Result := False;

     if not Discard( Dir_, True ) then Result := False;
end;

// ファイルを、終わるまで待って動かす（窓は出さない）。Elevate_ なら管理者として（利用者に確かめが出る）。
// 終了コード（動かせない・断られたなら -1）
function RunWait( const File_,Params_:String; const Elevate_:Boolean ) :Integer;
var
   I :TShellExecuteInfo;
   C :DWORD;
begin
     I := Default( TShellExecuteInfo );

     I.cbSize       := SizeOf( I );
     I.fMask        := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_NOASYNC;
     I.lpFile       := PChar( File_ );
     I.lpParameters := PChar( Params_ );
     I.nShow        := SW_HIDE;

     if Elevate_ then I.lpVerb := 'runas';

     if not ShellExecuteEx( @I ) or ( I.hProcess = 0 ) then Exit( -1 );
     try
          WaitForSingleObject( I.hProcess, INFINITE );

          if GetExitCodeProcess( I.hProcess, C ) then Result := Integer( C )
                                                 else Result := -1;
     finally
          CloseHandle( I.hProcess );
     end;
end;

// ショートカット（.lnk）を作る（作業フォルダーは Target_ のフォルダー、アイコンは Target_ の 0 番）
procedure MakeLink( const Lnk_,Target_,Comment_:String );
var
   O :IUnknown;
   L :IShellLink;
begin
     O := CreateComObject( CLSID_ShellLink );
     L := O as IShellLink;

     OleCheck( L.SetPath( PChar( Target_ ) ) );
     OleCheck( L.SetWorkingDirectory( PChar( ExtractFileDir( Target_ ) ) ) );
     OleCheck( L.SetIconLocation( PChar( Target_ ), 0 ) );
     OleCheck( L.SetDescription( PChar( Comment_ ) ) );

     OleCheck( ( O as IPersistFile ).Save( PChar( Lnk_ ), True ) );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinInstaller

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

procedure TWinInstaller.SetDest( const Dest_:String );
begin
     _Dest := ExcludeTrailingPathDelimiter( Dest_ );
end;

function TWinInstaller.GetTarget :String;
begin
     Result := TPath.Combine( _Dest, _App + '.exe' );
end;

function TWinInstaller.GetInstalled :Boolean;
begin
     Result := SameText( ParamStr( 0 ), Target );
end;

function TWinInstaller.GetHasPayload :Boolean;
begin
     Result := ( _Payload <> '' ) and ( FindResource( HInstance, PChar( _Payload ), RT_RCDATA ) <> 0 );
end;

function TWinInstaller.GetStartup :TWinStartup;
begin
     Result := TWinStartup.Create( _App, Target );
end;

function TWinInstaller.GetLink :String;
begin
     Result := TPath.Combine( KnownFolder( FOLDERID_Programs ), _App + '.lnk' );
end;

function TWinInstaller.GetEntry :String;
begin
     Result := UNINSTALL_KEY + _App;
end;

//------------------------------------------------------------------------------

class function TWinInstaller.GetRoot :String;
begin
     Result := TPath.Combine( KnownFolder( FOLDERID_ProgramFiles ), PUBLISHER );
end;

class function TWinInstaller.GetCurrentUser :String;
begin
     Result := GetEnvironmentVariable( 'USERDOMAIN' ) + '\' + GetEnvironmentVariable( 'USERNAME' );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

// 動いている実行ファイルが、消すために写した一時の写しか
function TWinInstaller.Elsewhere :Boolean;
begin
     Result := ExtractFileName( ExtractFileDir( ParamStr( 0 ) ) ).StartsWith( _App + TEMP_MARK, True );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TWinInstaller.Create( const App_:String; const Files_:TArray<String>; const Payload_:String );
begin
     if App_ = '' then raise EArgumentException.Create( 'TWinInstaller: アプリの名前が空です' );

     _App     := App_    ;
     _Files   := Files_  ;
     _Payload := Payload_;
     _Dest    := TPath.Combine( Root, App_ );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TWinInstaller.Place;
var
   H, F, P, N :String;
   S :TResourceStream;
   Z :TZipFile;
   I :Integer;
   B :TBytes;
begin
     MakeDir( _Dest );

     ReplaceInUse( Target, TFile.ReadAllBytes( ParamStr( 0 ) ) );

     // 実行ファイルの隣のもの
     H := ExtractFileDir( ParamStr( 0 ) );

     for F in _Files do
     begin
          P := TPath.Combine( H, F );

          if TDirectory.Exists( P ) then
          begin
               for N in TDirectory.GetFiles( P, '*', TSearchOption.soAllDirectories ) do
               begin
                    MakeDir( ExtractFileDir( TPath.Combine( _Dest, ExtractRelativePath( IncludeTrailingPathDelimiter( H ), N ) ) ) );

                    ReplaceInUse( TPath.Combine( _Dest, ExtractRelativePath( IncludeTrailingPathDelimiter( H ), N ) ), TFile.ReadAllBytes( N ) );
               end;
          end
          else
          if TFile.Exists( P ) then
          begin
               MakeDir( ExtractFileDir( TPath.Combine( _Dest, F ) ) );

               ReplaceInUse( TPath.Combine( _Dest, F ), TFile.ReadAllBytes( P ) );
          end
          else
               raise EFileNotFoundException.Create( '一緒に入れるものが見つかりません：' + P );
     end;

     // 中に持っている zip の中身
     if _Payload = '' then Exit;

     S := TResourceStream.Create( HInstance, _Payload, RT_RCDATA );
     Z := TZipFile.Create;
     try
          Z.Open( S, zmRead );

          for I := 0 to Z.FileCount - 1 do
          begin
               N := Z.FileNames[ I ].Replace( '/', '\' );

               if N.EndsWith( '\' ) then Continue;  // フォルダーの項目（作り手によって / か \ で終わる）

               P := TPath.Combine( _Dest, N );

               MakeDir( ExtractFileDir( P ) );

               Z.Read( I, B );

               ReplaceInUse( P, B );
          end;
     finally
          Z.Free;
          S.Free;
     end;
end;

//------------------------------------------------------------------------------

procedure TWinInstaller.Register( const Version_:String );
var
   R :TRegistry;
   S :Int64;
   F :String;
begin
     S := 0;
     for F in TDirectory.GetFiles( _Dest, '*', TSearchOption.soAllDirectories ) do Inc( S, TFile.GetSize( F ) );

     R := TRegistry.Create( KEY_READ or KEY_WRITE );
     try
          R.RootKey := HKEY_LOCAL_MACHINE;

          if not R.OpenKey( Entry, True ) then raise ERegistryException.CreateFmt( '「アプリ」の一覧に登録できません：%s', [ SysErrorMessage( R.LastError ) ] );

          R.WriteString ( 'DisplayName'    , _App                                );
          R.WriteString ( 'DisplayVersion' , Version_                            );
          R.WriteString ( 'Publisher'      , PUBLISHER                           );
          R.WriteString ( 'InstallLocation', _Dest                               );
          R.WriteString ( 'DisplayIcon'    , Target + ',0'                       );
          R.WriteString ( 'UninstallString', '"' + Target + '" ' + ARG_UNINSTALL );
          R.WriteInteger( 'NoModify'       , 1                                   );
          R.WriteInteger( 'NoRepair'       , 1                                   );
          R.WriteInteger( 'EstimatedSize'  , Integer( ( S + 1023 ) div 1024 )    );  // KB
     finally
          R.Free;
     end;
end;

procedure TWinInstaller.Unregister;
var
   R :TRegistry;
begin
     R := TRegistry.Create( KEY_READ );
     try
          R.RootKey := HKEY_LOCAL_MACHINE;

          if not R.KeyExists( Entry ) then Exit;  // 読むだけなら、管理者でなくてよい（登録が無ければ、何も求めない）
     finally
          R.Free;
     end;

     R := TRegistry.Create( KEY_READ or KEY_WRITE );
     try
          R.RootKey := HKEY_LOCAL_MACHINE;

          if not R.DeleteKey( Entry ) then raise ERegistryException.CreateFmt( '「アプリ」の一覧の登録を消せません：%s', [ SysErrorMessage( R.LastError ) ] );
     finally
          R.Free;
     end;
end;

//------------------------------------------------------------------------------

procedure TWinInstaller.Grant( const User_:String );
var
   C :Integer;
begin
     if User_ = '' then raise EArgumentException.Create( 'TWinInstaller.Grant: 利用者の名前が空です' );

     C := RunWait( 'icacls.exe', '"' + _Dest + '" /grant "' + User_ + ':(OI)(CI)M"', False );

     if C <> 0 then raise EOSError.CreateFmt( '入れた先に、利用者 %s の書き換えの権限を付けられません（icacls の終了コード %d）：%s', [ User_, C, _Dest ] );
end;

procedure TWinInstaller.Sweep;
var
   F :String;
begin
     if not TDirectory.Exists( _Dest ) then Exit;

     for F in TDirectory.GetFiles( _Dest, '*.old-*', TSearchOption.soAllDirectories ) do DeleteFile( PChar( F ) );  // 使用中のものは、次の機会に
end;

//------------------------------------------------------------------------------

procedure TWinInstaller.Enroll( const Comment_:String );
begin
     OleCheck( CoInitializeEx( nil, COINIT_APARTMENTTHREADED ) );  // 既に同じ形で初期化されていれば S_FALSE（成功）
     try
          MakeLink( Link, Target, Comment_ );
     finally
          CoUninitialize;
     end;
end;

procedure TWinInstaller.Unenroll;
begin
     if not DeleteFile( PChar( Link ) ) and ( GetLastError <> ERROR_FILE_NOT_FOUND ) then RaiseLastOSError;
end;

//------------------------------------------------------------------------------

function TWinInstaller.Uninstall( const Datas_:TArray<String>; const Stop_:TProc ) :Integer;
var
   T, D, C, L :String;
   A :Integer;
   P :Boolean;
   H :THandle;
   S :TStartupInfo;
   I :TProcessInformation;
   Es :TArray<String>;
begin
     if ParamStr( 2 ) = '' then
     begin
          // 1 回目：聞く → 本体を終わらせる → 一時の写しへ移る
          if Length( Datas_ ) = 0 then
          begin
               if not Ask( Format( STitle, [ _App ] ), Format( SAsk, [ _App ] ) ) then Exit( 0 );

               P := False;
          end
          else
          begin
               L := '';
               for D in Datas_ do L := L + #13#10'・' + D;

               A := MessageBox( 0, PChar( Format( SAskD, [ _App, L.Substring( 2 ) ] ) ), PChar( Format( STitle, [ _App ] ) ),
                                MB_YESNOCANCEL or MB_ICONQUESTION or MB_DEFBUTTON2 or MB_SETFOREGROUND );  // 既定の答えは「いいえ」（データは残す）

               if A = IDCANCEL then Exit( 0 );

               P := A = IDYES;
          end;

          if Assigned( Stop_ ) then Stop_();

          T := TPath.Combine( TPath.Combine( TPath.GetTempPath, _App + TEMP_MARK + TGUID.NewGuid.ToString.Trim( [ '{', '}' ] ) ), _App + '.exe' );

          MakeDir( ExtractFileDir( T ) );

          WriteNew( T, TFile.ReadAllBytes( ParamStr( 0 ) ) );

          // 自分のプロセスのハンドルを、受け継がせる形で写して、一時の写しに渡す（写しは、これで自分の終わりを待つ）
          if not DuplicateHandle( GetCurrentProcess, GetCurrentProcess, GetCurrentProcess, @H, SYNCHRONIZE, True, 0 ) then RaiseLastOSError;
          try
               C := '"' + T + '" ' + ARG_UNINSTALL + ' ' + UIntToStr( UInt64( H ) ) + ' ' + IntToStr( Ord( P ) );  UniqueString( C );

               S := Default( TStartupInfo );  S.cb := SizeOf( S );

               if not CreateProcess( nil, PChar( C ), nil, nil, True, 0, nil, PChar( ExtractFileDir( T ) ), S, I ) then RaiseLastOSError;

               CloseHandle( I.hThread  );
               CloseHandle( I.hProcess );
          finally
               CloseHandle( H );
          end;

          Exit( 0 );
     end;

     // 2 回目（一時の写し）：1 回目の終わりを待つ → 管理者として、一覧の登録と入れた先を消す → 利用者の分を消す
     H := THandle( StrToUInt64( ParamStr( 2 ) ) );
     P := ParamStr( 3 ) = '1';

     WaitForSingleObject( H, INFINITE );  // 入れた先から動いていたプロセスが、終わった

     CloseHandle( H );

     A := Elevate( ARG_REMOVE );

     case A of
       -1   : begin
                   Tell( Format( STitle, [ _App ] ), SAbort, True );

                   Exit( 1 );
              end;
       0, 1 : ;
       2    : Exit( 2 );  // 理由は、管理者として動いた方が、もう知らせた
     else
          Tell( Format( STitle, [ _App ] ), Format( SFail, [ A ] ), True );

          Exit( 2 );
     end;

     Es := nil;

     try
          Startup.Enabled := False;
     except
          on E:Exception do Es := Es + [ E.Message ];
     end;

     try
          Unenroll;
     except
          on E:Exception do Es := Es + [ Link + '（' + E.Message + '）' ];
     end;

     if P then
     begin
          for D in Datas_ do
          begin
               try
                    if TDirectory.Exists( D ) then TDirectory.Delete( D, True );
               except
                    on E:Exception do Es := Es + [ D + '（' + E.Message + '）' ];
               end;
          end;
     end;

     L := Format( SDone, [ _App ] );

     if A = 1 then L := L + #13#10#13#10 + SLater;

     if Length( Es ) > 0 then L := L + #13#10#13#10 + Format( SLeft, [ String.Join( #13#10, Es ) ] );

     Tell( Format( STitle, [ _App ] ), L, Length( Es ) > 0 );

     Result := 0;
end;

function TWinInstaller.Remove :Integer;
var
   P, D :String;
begin
     try
          Unregister;

          if Purge( _Dest ) then Result := 0
                            else Result := 1;

          // 既定の親（LUXOPHIA）が空になったら、それも消す（ほかのアプリが入っていれば、空でないので残る）
          P := ExtractFileDir( _Dest );

          if SameText( P, Root ) and TDirectory.Exists( P ) and TDirectory.IsEmpty( P ) then RemoveDirectory( PChar( P ) );

          // 一時の写し（自分）は、動いているので、次の再起動で消す
          if Elsewhere then
          begin
               D := ExtractFileDir( ParamStr( 0 ) );

               Discard( ParamStr( 0 ), False );
               Discard( D            , True  );
          end;
     except
          on E:Exception do
          begin
               Tell( Format( STitle, [ _App ] ), E.Message, True );  // 管理者の別のプロセスなので、ここで知らせる

               Result := 2;
          end;
     end;
end;

//------------------------------------------------------------------------------

class function TWinInstaller.Elevate( const Args_:String ) :Integer;
begin
     Result := RunWait( ParamStr( 0 ), Args_, True );
end;

class function TWinInstaller.Ask( const Title_,Text_:String ) :Boolean;
begin
     Result := MessageBox( 0, PChar( Text_ ), PChar( Title_ ), MB_YESNO or MB_ICONQUESTION or MB_SETFOREGROUND ) = IDYES;
end;

class procedure TWinInstaller.Tell( const Title_,Text_:String; const Error_:Boolean = False );
begin
     if Error_ then MessageBox( 0, PChar( Text_ ), PChar( Title_ ), MB_OK or MB_ICONERROR       or MB_SETFOREGROUND )
               else MessageBox( 0, PChar( Text_ ), PChar( Title_ ), MB_OK or MB_ICONINFORMATION or MB_SETFOREGROUND );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
