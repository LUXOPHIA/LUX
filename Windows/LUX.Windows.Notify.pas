unit LUX.Windows.Notify;

// 通知領域（タスクバーの右端）のアイコン・メニュー・通知
//
//【Windows の API を直接使う理由】
// ・FMX には通知領域のアイコンの部品が無い。VCL の TTrayIcon（Vcl.ExtCtrls）は VCL の画面の部品であり、FMX のアプリには
//   持ち込まない。そのため Shell_NotifyIcon と、メニューの API を直接使う。FMX・VCL のどちらの画面にも依存しない。
//
//【窓】
// ・知らせを受けるための見えない窓（AllocateHWnd。Handle）を、作ったスレッドに持つ。作る・使う・壊すのは、
//   メッセージを回している同じスレッド（ふつうは主スレッド）で行う。
// ・アイコンの絵は、実行ファイルのアイコンのリソース（MAINICON）。
//
//【操作】
// ・左のクリックとダブルクリックは、どちらも OnOpen を 1 度呼ぶ。
//   Windows は、ダブルクリックを「押す・離す・2 度目の押し（WM_LBUTTONDBLCLK）・離す」で知らせる。最初に離したときに呼び、
//   2 度目の押しに続く「離す」では呼ばない。1 度目で、すぐ開く（ダブルクリックかを、時間で待って見分けない）。
// ・右クリックで、AddItem で作ったメニューを出す。
// ・Primary は太字にする項目の番号（OnOpen と同じ働きの項目）、Enableds[ 番号 ] は項目を押せるか。番号は AddItem の戻り値（1 から）。
//   無い番号は EArgumentOutOfRangeException。
// ・Balloon で Windows の通知を出す。通知は、送る写しにだけ載せる（登録の控えは、付け直しにも使うので、最後の通知を
//   付け直しのたびに、もう一度出さない）。
// ・エクスプローラーが立ち上がり直したら（TaskbarCreated）、アイコンを付け直す。
//   起動の直後にまだタスクバーが無くて付けられなかったときも、これで付く。
//
//【失敗】
// ・窓・メニューを作れない・項目を足せないのは、その場で例外。
// ・アイコンの登録（Shell_NotifyIcon）が失敗するのは、タスクバーがまだ無いときで、TaskbarCreated で付く。だから例外にしない。

interface //#################################################################### ■

uses System.SysUtils, System.Generics.Collections,
     Winapi.Windows, Winapi.Messages, Winapi.ShellAPI;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TWinNotify = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinNotify

     // 通知領域のアイコン 1 つと、その右クリックのメニュー
     TWinNotify = class
     private
       _Wnd     :HWND;              // 知らせを受ける見えない窓
       _Data    :TNotifyIconDataW;  // アイコンの登録の控え（付け直しにも使う。通知は載せない）
       _Menu    :HMENU;
       _Actions :TList<TProc>;      // メニューの項目の番号 - 1 ごとの処理（区切りは nil）
       _Primary :Integer;
       _OnOpen  :TProc;
       _Restart :UINT;              // TaskbarCreated のメッセージの番号
       _Double  :Boolean;           // ダブルクリックの 2 度目の押しを受けた（続く「離す」では開かない）
     protected
       ///// A C C E S S O R
       function GetTip :String; virtual;
       procedure SetTip( const Tip_:String ); virtual;
       function GetPrimary :Integer; virtual;
       procedure SetPrimary( const Primary_:Integer ); virtual;
       function GetEnableds( const Item_:Integer ) :Boolean; virtual;
       procedure SetEnableds( const Item_:Integer; const Enabled_:Boolean ); virtual;
       function GetOnOpen :TProc; virtual;
       procedure SetOnOpen( const OnOpen_:TProc ); virtual;
       ///// M E T H O D
       procedure Check( const Item_:Integer ); virtual;
       procedure WndProc( var Message_:TMessage ); virtual;
       procedure Open; virtual;
       procedure ShowMenu; virtual;
     public
       constructor Create( const Tip_:String );
       destructor Destroy; override;
       ///// P R O P E R T Y
       property Handle                          :HWND    read _Wnd                         ;  // 知らせを受ける見えない窓
       property Tip                             :String  read GetTip      write SetTip     ;  // マウスを載せたときの文
       property Primary                         :Integer read GetPrimary  write SetPrimary ;  // 太字にする項目の番号（0 は無し）
       property Enableds[ const Item_:Integer ] :Boolean read GetEnableds write SetEnableds;  // 項目を押せるか
       property OnOpen                          :TProc   read GetOnOpen   write SetOnOpen  ;  // 左のクリック・ダブルクリック（どちらも 1 度）
       ///// C O N S T A N T
       const CALLBACK = WM_APP + 1;                                                           // アイコンの操作を、見えない窓に知らせるメッセージの番号
       ///// M E T H O D
       function AddItem( const Caption_:String; const OnClick_:TProc ) :Integer; virtual;     // メニューの項目を足し、その番号を返す
       procedure AddSeparator; virtual;                                                       // メニューの区切りを足す（番号を 1 つ使う）
       procedure Balloon( const Title_,Text_:String ); virtual;                               // Windows の通知を出す
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.Classes;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinNotify

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TWinNotify.GetTip :String;
begin
     Result := _Data.szTip;
end;

procedure TWinNotify.SetTip( const Tip_:String );
begin
     StrPLCopy( _Data.szTip, Tip_, Length( _Data.szTip ) - 1 );

     Shell_NotifyIconW( NIM_MODIFY, @_Data );  // タスクバーがまだ無ければ失敗するが、付け直すときに、控えの文で付く
end;

//------------------------------------------------------------------------------

function TWinNotify.GetPrimary :Integer;
begin
     Result := _Primary;
end;

procedure TWinNotify.SetPrimary( const Primary_:Integer );
var
   I :UINT;
begin
     if Primary_ = 0 then I := UINT( -1 )  // -1 は「太字の項目なし」
     else
     begin
          Check( Primary_ );

          I := Primary_;
     end;

     if not SetMenuDefaultItem( _Menu, I, 0 ) then RaiseLastOSError;

     _Primary := Primary_;
end;

//------------------------------------------------------------------------------

function TWinNotify.GetEnableds( const Item_:Integer ) :Boolean;
begin
     Check( Item_ );

     Result := GetMenuState( _Menu, Item_, MF_BYCOMMAND ) and ( MF_GRAYED or MF_DISABLED ) = 0;
end;

procedure TWinNotify.SetEnableds( const Item_:Integer; const Enabled_:Boolean );
begin
     Check( Item_ );

     if Enabled_ then EnableMenuItem( _Menu, Item_, MF_BYCOMMAND or MF_ENABLED )  // 戻り値は前の状態（項目があることは上で確かめた）
                 else EnableMenuItem( _Menu, Item_, MF_BYCOMMAND or MF_GRAYED  );
end;

//------------------------------------------------------------------------------

function TWinNotify.GetOnOpen :TProc;
begin
     Result := _OnOpen;
end;

procedure TWinNotify.SetOnOpen( const OnOpen_:TProc );
begin
     _OnOpen := OnOpen_;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

// その番号の項目が無ければ、例外
procedure TWinNotify.Check( const Item_:Integer );
begin
     if GetMenuState( _Menu, Item_, MF_BYCOMMAND ) = UINT( -1 ) then raise EArgumentOutOfRangeException.CreateFmt( 'TWinNotify: 番号 %d の項目はありません', [ Item_ ] );
end;

//------------------------------------------------------------------------------

procedure TWinNotify.WndProc( var Message_:TMessage );
begin
     if Message_.Msg = CALLBACK then
     begin
          case Message_.LParam of
            WM_LBUTTONUP     : if _Double then _Double := False  // ダブルクリックの 2 度目の「離す」（1 度目で開いた）
                                          else Open;
            WM_LBUTTONDBLCLK : _Double := True;
            WM_RBUTTONUP     : ShowMenu;
          end;
     end
     else
     if Message_.Msg = _Restart then Shell_NotifyIconW( NIM_ADD, @_Data )  // エクスプローラーが立ち上がり直した
                                else Message_.Result := DefWindowProc( _Wnd, Message_.Msg, Message_.WParam, Message_.LParam );
end;

//------------------------------------------------------------------------------

procedure TWinNotify.Open;
begin
     if not Assigned( _OnOpen ) then Exit;

     SetForegroundWindow( _Wnd );  // 前に出す権利をもらう（無いと、開いた画面がほかの窓の後ろに隠れる）

     _OnOpen();
end;

procedure TWinNotify.ShowMenu;
var
   P :TPoint;
   C :Integer;
begin
     GetCursorPos( P );

     SetForegroundWindow( _Wnd );                                                                           // 前に出しておかないと、メニューの外をクリックしてもメニューが閉じない

     C := Integer( TrackPopupMenu( _Menu, TPM_RIGHTBUTTON or TPM_RETURNCMD or TPM_NONOTIFY, P.X, P.Y, 0, _Wnd, nil ) );

     PostMessage( _Wnd, WM_NULL, 0, 0 );                                                                    // メニューを閉じた後の操作を正しく受けるための、文書にある作法

     if ( C >= 1 ) and ( C <= _Actions.Count ) and Assigned( _Actions[ C - 1 ] ) then _Actions[ C - 1 ]();  // 0 は何も選ばなかった
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TWinNotify.Create( const Tip_:String );
begin
     inherited Create;

     _Actions := TList<TProc>.Create;
     _Wnd     := AllocateHWnd( WndProc );                                                                                                            // 作れなければ、AllocateHWnd が例外
     _Menu    := CreatePopupMenu;

     if _Menu = 0 then RaiseLastOSError;

     _Restart := RegisterWindowMessage( 'TaskbarCreated' );

     if _Restart = 0 then RaiseLastOSError;

     _Data := Default( TNotifyIconDataW );

     _Data.cbSize           := SizeOf( _Data );
     _Data.Wnd              := _Wnd;
     _Data.uID              := 1;
     _Data.uFlags           := NIF_MESSAGE or NIF_ICON or NIF_TIP;
     _Data.uCallbackMessage := CALLBACK;
     _Data.hIcon            := LoadImage( HInstance, 'MAINICON', IMAGE_ICON, GetSystemMetrics( SM_CXSMICON ), GetSystemMetrics( SM_CYSMICON ), 0 );  // 無ければ 0（絵の無いアイコン）

     StrPLCopy( _Data.szTip, Tip_, Length( _Data.szTip ) - 1 );

     Shell_NotifyIconW( NIM_ADD, @_Data );                                                                                                           // 起動の直後でタスクバーがまだ無ければ失敗するが、TaskbarCreated で付け直す
end;

destructor TWinNotify.Destroy;
begin
     Shell_NotifyIconW( NIM_DELETE, @_Data );  // 付いていなければ失敗するが、消す物が無いだけ

     if _Data.hIcon <> 0 then DestroyIcon( _Data.hIcon );

     if _Menu <> 0 then DestroyMenu( _Menu );

     if _Wnd <> 0 then DeallocateHWnd( _Wnd );

     _Actions.Free;

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

function TWinNotify.AddItem( const Caption_:String; const OnClick_:TProc ) :Integer;
begin
     _Actions.Add( OnClick_ );

     Result := _Actions.Count;

     if not AppendMenu( _Menu, MF_STRING, Result, PChar( Caption_ ) ) then RaiseLastOSError;
end;

procedure TWinNotify.AddSeparator;
begin
     _Actions.Add( nil );

     if not AppendMenu( _Menu, MF_SEPARATOR, _Actions.Count, nil ) then RaiseLastOSError;
end;

//------------------------------------------------------------------------------

procedure TWinNotify.Balloon( const Title_,Text_:String );
var
   D :TNotifyIconDataW;
begin
     D := _Data;

     D.uFlags      := _Data.uFlags or NIF_INFO;
     D.dwInfoFlags := NIIF_INFO;

     StrPLCopy( D.szInfoTitle, Title_, Length( D.szInfoTitle ) - 1 );
     StrPLCopy( D.szInfo     , Text_ , Length( D.szInfo      ) - 1 );

     Shell_NotifyIconW( NIM_MODIFY, @D );  // タスクバーが無いときは出せない（通知を待たせる先が無い）
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
