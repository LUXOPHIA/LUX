unit LUX.FMX.Primer;

// 窓の表面に、最初の描画の前に、地の色を下塗りする（Windows の FMX。窓が出た瞬間の、白い光りを防ぐ）。
//
//【防ぐ現象】
// ・FMX の窓は、出た瞬間（起動のとき・隠れていた窓が、また出たとき）に、中身が描かれるまでの間、白く映る。
//   暗い配色の窓では、白く光って見える。
//【原因】（RAD Studio 37.0 の FMX.Platform.Win.pas と、Windows の仕組み）
// ・Windows は、窓を見える状態にするとき、その中で、背景を消すメッセージ（WM_ERASEBKGND）を送る。
//   ふつうのアプリは、ここで、窓の地の色を塗る。だから、画面に出る最初の表面は、地の色になっている。
// ・FMX の窓の手続き（WndProc）は、WM_ERASEBKGND に「消した」と答えるだけで、何も塗らない。窓のクラスの地のブラシも、持たない（NULL_BRUSH）。
//   中身を描いて表面へ送るのは、描き直しのメッセージ（WM_PAINT）の番が来てからで、その番は、ほかのメッセージが片付いた後に来る。
//   それまでの間、新しい（白い）ままの表面が、画面に出る。
//【ここで行うこと】
// ・FMX のフォームの窓の手続きを、差し替えて（GWLP_WNDPROC）、窓が出てから最初の描画までの間の WM_ERASEBKGND で、
//   フォームの地の色（Fill）を塗る。ふつうのアプリが行っていることを、FMX の代わりに行う。
// ・塗るのは、窓が出てから、最初に描かれるまでの間だけ。その後の WM_ERASEBKGND は、FMX に任せる
//   （描かれた後にも塗ると、大きさを変えるたびに、中身が地の色に戻って、ちらつく）。
//【フレームワークの迂回】（フレームワークの内側には手を入れない、という決まりの例外）
// ・FMX には、WM_ERASEBKGND に手を入れる、公開の拡張点が無い（WndProc の中で、じかに 1 を返している）。
//   窓のクラスのブラシを替えても、効かない。だから、窓の手続きを、差し替えている。
//   差し替えには、SetWindowLongPtr を使う（SetWindowSubclass は、アプリのマニフェストが、コモンコントロールの版 6 を指定していないと、使えない）。
// ・差し替えた手続きが見るのは、3 つのメッセージだけ：WM_WINDOWPOSCHANGING（窓が出ることを知る）・WM_ERASEBKGND（塗る）・
//   WM_PAINT（描かれたことを知る）。どれも、元の手続き（FMX のもの）へ、そのまま渡す（塗ったときの WM_ERASEBKGND だけ、渡さない）。
// ・FMX の版を上げたら、まだ要るか・まだ正しく動くかを、確かめ直す。
//【対象】
// ・地を単色で塗るフォーム（Fill.Kind が Solid）。透明なフォーム（Transparency）と、3D のフォームは、対象外（何もしない）。
//【使い方】
// ・アプリに 1 つだけ、最初のフォームが出る前に作る（メインのフォームの OnCreate など）。その時点である窓と、その後にできる窓の、すべてに働く。
//   アプリの終わりに、Free する。
//【実行スレッド】
// ・主スレッドでだけ使う。

interface //#################################################################### ■

uses System.Messaging, System.Generics.Collections,
     Winapi.Windows,
     FMX.Forms;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TPrimer = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPrimed

     // 手続きを差し替えてある窓の、控え
     TPrimed = record
       Proc  :TFNWndProc;  // 元の手続き（FMX のもの）
       Fresh :Boolean;     // 窓の表面が、出てから、まだ描かれていないか（そうなら、WM_ERASEBKGND で、地の色を塗る）
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPrimer

     // FMX のフォームの窓の、出た瞬間の表面を、地の色で下塗りする。
     TPrimer = class
     private
       _Wnds  :TDictionary<HWND,TPrimed>;  // 手続きを差し替えてある窓
       _Born  :TMessageSubscriptionId;     // 「フォームの窓ができた」の知らせの、受け取りの番号
       _Dying :TMessageSubscriptionId;     // 「フォームの窓が破棄される」の知らせの、受け取りの番号
       ///// M E T H O D
       procedure Mark( const Wnd_:HWND; const Fresh_:Boolean );
       procedure Cover( const Form_:TCommonCustomForm );
       procedure Bare( const Form_:TCommonCustomForm );
       ///// E V E N T
       procedure BornCome( const Sender_:TObject; const Message_:TMessage );
       procedure DyingCome( const Sender_:TObject; const Message_:TMessage );
     protected
     public
       constructor Create;
       destructor Destroy; override;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.UITypes,
     Winapi.Messages,
     FMX.Types, FMX.Graphics, FMX.Platform.Win;

var
   _Primer :TPrimer = nil;  // いま働いているもの（差し替える手続きが、メソッドではないので、ここに持つ。アプリに 1 つ）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

// 窓 Wnd_ の表面（DC_）を、そのフォームの地の色で塗る。対象外のフォームなら、塗らずに False
function Prime( const Wnd_:HWND; const DC_:HDC ) :Boolean;
var
   F :TCommonCustomForm;
   C :TAlphaColorRec;
   R :TRect;
   B :HBRUSH;
begin
     F := FindWindow( Wnd_ );

     Result := ( F is TCustomForm ) and not F.Transparency and ( TCustomForm( F ).Fill.Kind = TBrushKind.Solid );
     if not Result then Exit;

     C := TAlphaColorRec( TCustomForm( F ).Fill.Color );

     GetClientRect( Wnd_, R );

     B := CreateSolidBrush( RGB( C.R, C.G, C.B ) );
     try
          FillRect( DC_, R, B );
     finally
          DeleteObject( B );
     end;
end;

// FMX のフォームの窓の手続きと、差し替える手続き
function PrimeProc( Wnd_:HWND; Msg_:UINT; WParam_:WPARAM; LParam_:LPARAM ) :LRESULT; stdcall;
var
   P :TPrimed;
begin
     P := _Primer._Wnds[ Wnd_ ];  // 差し替えてある間は、必ず、控えがある

     case Msg_ of
       WM_WINDOWPOSCHANGING:
          // 窓が、見える状態になる：表面は、新しくなる
          if PWindowPos( LParam_ ).flags and SWP_SHOWWINDOW <> 0 then _Primer.Mark( Wnd_, True );
       WM_ERASEBKGND:
          if P.Fresh and Prime( Wnd_, HDC( WParam_ ) ) then Exit( 1 );
       WM_PAINT:
          begin
               Result := CallWindowProc( P.Proc, Wnd_, Msg_, WParam_, LParam_ );  // FMX が、中身を描いて、表面へ送る

               _Primer.Mark( Wnd_, False );

               Exit;
          end;
     end;

     Result := CallWindowProc( P.Proc, Wnd_, Msg_, WParam_, LParam_ );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPrimer

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

// 窓の控えに、表面が、まだ描かれていないかを、書く。
// 控えが無ければ、何もしない（元の手続きを呼んでいる間に、窓が破棄されて、控えが消えていることがある）
procedure TPrimer.Mark( const Wnd_:HWND; const Fresh_:Boolean );
var
   P :TPrimed;
begin
     if not _Wnds.TryGetValue( Wnd_, P ) then Exit;

     P.Fresh := Fresh_;

     _Wnds[ Wnd_ ] := P;
end;

// フォームの窓の手続きを、差し替える
procedure TPrimer.Cover( const Form_:TCommonCustomForm );
var
   W :HWND;
   P :TPrimed;
begin
     W := FormToHWND( Form_ );
     if W = 0 then Exit;                   // フォームが、まだ窓を持っていない（できたときに、知らせが来る）

     P.Proc  := TFNWndProc( GetWindowLongPtr( W, GWLP_WNDPROC ) );
     P.Fresh := not IsWindowVisible( W );  // もう見えている窓は、描かれているものとして扱う

     _Wnds.Add( W, P );                    // 先に控える（差し替えた直後から、メッセージが来る）

     SetWindowLongPtr( W, GWLP_WNDPROC, NativeInt( @PrimeProc ) );
end;

// フォームの窓の手続きを、元に戻す
procedure TPrimer.Bare( const Form_:TCommonCustomForm );
var
   W :HWND;
   P :TPrimed;
begin
     W := FormToHWND( Form_ );
     if not _Wnds.TryGetValue( W, P ) then Exit;  // 差し替えていない窓（窓を持つ前に、破棄されるフォームもある）

     SetWindowLongPtr( W, GWLP_WNDPROC, NativeInt( P.Proc ) );

     _Wnds.Remove( W );
end;

////////////////////////////////////////////////////////////////////// E V E N T

procedure TPrimer.BornCome( const Sender_:TObject; const Message_:System.Messaging.TMessage );
begin
     Cover( TCommonCustomForm( Sender_ ) );
end;

procedure TPrimer.DyingCome( const Sender_:TObject; const Message_:System.Messaging.TMessage );
begin
     Bare( TCommonCustomForm( Sender_ ) );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TPrimer.Create;
var
   I :Integer;
begin
     inherited;

     if Assigned( _Primer ) then raise EInvalidOpException.Create( 'TPrimer は、アプリに 1 つだけ作れる' );

     _Primer := Self;

     _Wnds := TDictionary<HWND,TPrimed>.Create;

     for I := 0 to Screen.FormCount - 1 do Cover( Screen.Forms[ I ] );

     _Born  := TMessageManager.DefaultManager.SubscribeToMessage( TAfterCreateFormHandle  , BornCome  );
     _Dying := TMessageManager.DefaultManager.SubscribeToMessage( TBeforeDestroyFormHandle, DyingCome );
end;

destructor TPrimer.Destroy;
var
   I :Integer;
begin
     // 作るのに失敗したもの（2 つ目）は、何も差し替えていない
     if _Primer = Self then
     begin
          TMessageManager.DefaultManager.Unsubscribe( TAfterCreateFormHandle  , _Born  );
          TMessageManager.DefaultManager.Unsubscribe( TBeforeDestroyFormHandle, _Dying );

          for I := 0 to Screen.FormCount - 1 do Bare( Screen.Forms[ I ] );

          _Wnds.Free;

          _Primer := nil;
     end;

     inherited;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
