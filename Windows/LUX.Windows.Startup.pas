unit LUX.Windows.Startup;

// サインインのときに、アプリを常駐から始める登録（今の利用者の分）
//
//【登録の形】
// ・HKEY_CURRENT_USER の Software\Microsoft\Windows\CurrentVersion\Run に、値の名前 Name、値 Command（"<実行ファイル>" /tray）を書く。
//   /tray は、窓を出さずに常駐を始める引数（アプリが、そう読む）。
// ・Enabled を読むと、登録が、この実行ファイルを、この形で指しているかを答える。別の場所の実行ファイルを指す古い登録は、
//   入っていないと答え、True を書くと、この実行ファイルを指すように書き直す。False を書くと、値を消す（無ければ何もしない）。
//
//【書いてよいとき】
// ・Enabled に書くのは、入れた先の実行ファイルから動いているときだけ（判定は、使う側が持つ。入れる部品の Installed）。
//   開発の途中の実行ファイルの書き込みが、利用者の機械の自動起動を、その実行ファイルへ向けないように。
//   この部品は、どこから動いているかを知らない（入れる先の決まりを、ここに持たない）。
//
//【失敗】
// ・登録を開けない・書けない・消せないのは、その場で例外。

interface //#################################################################### ■

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinStartup

     // サインインのときに、実行ファイルを /tray で起動する登録
     TWinStartup = record
     private
       _Name :String;  // 登録の値の名前（アプリの名前）
       _Exe  :String;  // 起動する実行ファイル
       ///// A C C E S S O R
       function GetCommand :String;
       function GetEnabled :Boolean;
       procedure SetEnabled( const Enabled_:Boolean );
     public
       constructor Create( const Name_,Exe_:String );
       ///// P R O P E R T Y
       property Name    :String  read _Name                      ;       // 登録の値の名前
       property Exe     :String  read _Exe                       ;       // 起動する実行ファイル
       property Command :String  read GetCommand                 ;       // 登録する値（"<Exe>" /tray）
       property Enabled :Boolean read GetEnabled write SetEnabled;       // 登録が、この実行ファイルを指しているか（書くと、登録・消す）
       ///// C O N S T A N T
       const RUN_KEY = 'Software\Microsoft\Windows\CurrentVersion\Run';  // HKEY_CURRENT_USER の下の、登録の場所
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Win.Registry,
     Winapi.Windows;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinStartup

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TWinStartup.GetCommand :String;
begin
     Result := '"' + _Exe + '" /tray';
end;

//------------------------------------------------------------------------------

function TWinStartup.GetEnabled :Boolean;
var
   R :TRegistry;
begin
     R := TRegistry.Create( KEY_READ );
     try
          R.RootKey := HKEY_CURRENT_USER;

          if not R.OpenKeyReadOnly( RUN_KEY ) then Exit( False );  // 登録の場所が無い：何も登録されていない

          Result := R.ValueExists( _Name ) and ( R.GetDataType( _Name ) in [ rdString, rdExpandString ] ) and SameText( R.ReadString( _Name ), Command );
     finally
          R.Free;
     end;
end;

procedure TWinStartup.SetEnabled( const Enabled_:Boolean );
var
   R :TRegistry;
begin
     R := TRegistry.Create( KEY_READ or KEY_WRITE );
     try
          R.RootKey := HKEY_CURRENT_USER;

          if not R.OpenKey( RUN_KEY, Enabled_ ) then        // 消すときは、場所を作らない
          begin
               if Enabled_ then raise ERegistryException.CreateFmt( '自動起動の登録の場所を開けません：%s', [ SysErrorMessage( R.LastError ) ] );

               Exit;  // 場所が無い：消す物が無い
          end;

          if Enabled_ then R.WriteString( _Name, Command )  // 書けなければ、TRegistry が例外
          else
          if R.ValueExists( _Name ) and not R.DeleteValue( _Name ) then raise ERegistryException.CreateFmt( '自動起動の登録を消せません：%s', [ SysErrorMessage( R.LastError ) ] );
     finally
          R.Free;
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TWinStartup.Create( const Name_,Exe_:String );
begin
     if Name_ = '' then raise EArgumentException.Create( 'TWinStartup: 名前が空です' );

     _Name := Name_;
     _Exe  := Exe_ ;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
