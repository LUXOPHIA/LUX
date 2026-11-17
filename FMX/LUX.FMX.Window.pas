unit LUX.FMX.Window;

// メインのフォームの窓を、Windows のふつうのアプリの窓と同じに振る舞わせる（Windows の FMX）。
//
//【FMX の作りと、その結果】（RAD Studio 37.0 の FMX.Platform.Win.pas）
// ・FMX は、タスクバーのボタンを持つ窓として、大きさ 0 の隠れた「アプリの窓」を作り（CreateAppHandle）、
//   フォームの窓を、その持ち物として作る（CreateWindow の DefineParentWnd）。
// ・だから、フォームの窓は、タスクバーのボタンを持たない。最小化すると、フォームの窓は、アニメーションなしで隠れ、
//   代わりに、隠れたアプリの窓が最小化される（MinimizeApp。そこでは、最小化のアニメーションの設定も、一時的に切っている）。
// ・戻すときは、隠れていたフォームの窓が、見える状態に戻る。隠れていた間に、窓の表面（画面に合成される絵）は捨てられているので、
//   FMX が描き直すまでの数十ミリ秒、新しい（白い）表面が画面に出る。暗い配色の窓では、白く光って見える。
// ・タスクバーのボタンは、隠れたアプリの窓のいるディスプレイに出る（フォームの窓を別のディスプレイへ動かしても、付いて来ない）。
//【ここで行うこと】
// ・フォームの窓そのものを、アプリの窓にする。使うのは、FMX が公開している拡張点
//   RegisterApplicationHWNDProc（アプリの窓のハンドルを、外から与える）と、Windows の公式の API だけ。
//   FMX の中には、手を入れない。窓の手続きも、差し替えない。
//     1. フォームの窓から、持ち主を外す（持ち主の無い、いちばん上の階層の窓は、自分のタスクバーのボタンを持つ）。
//     2. アプリの窓として、フォームの窓を返す手続きを、FMX に登録する。
//     3. FMX が作った、隠れたアプリの窓を、破棄する（タスクバーのボタンが 2 つにならないように）。
// ・こうすると、最小化・復元は、Windows が、フォームの窓そのものに対して行う：アニメーションが出て、タスクバーのボタンは
//   窓のいるディスプレイに従い、窓の表面は、最小化の間も保たれる（戻したときに、白く光らない）。
//【FMX が、隠れたアプリの窓の側で行っていたこと】（フォームの窓をアプリの窓にすると、FMX の中では、働かなくなる）
// ・Windows の終了・サインアウトのとき：FMX は、アプリの窓への WM_ENDSESSION で、メインのフォームを Close して、アプリを終わらせていた
//   （WndProc の WM_ENDSESSION）。フォームの窓への WM_ENDSESSION は、FMX が扱わない。
//   → ここで、知らせを受けるだけの隠れた窓（AllocateHWnd）を持ち、同じことを、同じ順に行う。
//     違いは 2 つ：
//       1. FMX は、終了が取りやめになったとき（WParam が 0）にも Close していたが、ここでは、本当に終わるときだけ行う。
//       2. アプリが、終わりの入口（OnEnding）を登録していれば、Close の代わりに、それを呼ぶ。
//          閉じるボタンを「隠して断る」アプリ（通知領域に常駐するアプリなど）では、Close は OnCloseQuery で断られ、
//          アプリの終わりの手順（子の窓を閉じる・止まる期限を仕掛けるなど）を通らない。入口は、その手順を行い、
//          最後にメインのフォームを Close する（このとき、OnCloseQuery が閉じることを認める）。
//          登録が無ければ、今までどおり、メインのフォームを Close する。
//     終わってよいかの問い（WM_QUERYENDSESSION）には、DefWindowProc が「よい」と答える（FMX も、いつも「よい」と答える）。
//     この後の Halt で、FMX の終わりの片付け（DoneApplication。AddExitProc で登録されている）が、フォームと部品を破棄する。
// ・最小化のとき：FMX は、メインフォームが最小化されている間、その窓に位置の知らせ（WM_WINDOWPOSCHANGED）が届くたびに、
//   MinimizeApp を呼び、出ているフォームを全部、1 つずつ最小化する（MinimiseAllForms）。最小化した瞬間は、子の窓を、もう Windows が
//   隠しているので、効き目は無い。しかし、最小化の間に出した子の窓（裏の出来事で出る確認の窓など）は、その後に位置の知らせが届くと、
//   巻き込まれて、縮んだ姿になる（位置の知らせが届くかどうかは、窓の重なりの順が変わるかどうかで決まるので、
//   毎回ではない）。縮んだ子の窓は、メインの窓が最小化の間は、ShowWindow では、元の大きさに戻せない。
//   → メインフォームの指定（TApplication.MainForm。公開の、書き込めるプロパティ）を、外しておく。MinimizeApp は、
//     「メインフォームが最小化されたとき」にだけ呼ばれるので、通らなくなる。
//     外すのは、アプリの手が空いたとき（TIdleMessage）：FMX は、フォームを作り終えた後に、メインフォームを決める
//     （TApplication.RealCreateForms）ので、作っている間には、外せない。
// ・閉じたとき：FMX は、メインフォームを閉じたときにだけ、アプリを終える（FMX.Forms の TCommonCustomForm.Close）。
//   → フォームの OnClose を受けて、本当に閉じるとき（Action が caNone でない）に、メインフォームの指定を戻す。
//     Close は、OnClose を呼んだ後に、メインフォームかを見るので、FMX が、今までどおり、アプリを終える。
//     フォームの元の OnClose は、先に呼ぶ。TMainWindow を作った後で、フォームの OnClose を付け替えないこと。
//【子の窓】（メインのフォームに付いて出る窓：確認・設定の窓など）
// ・子の窓の持ち主は、アプリの窓、つまり、メインのフォームの窓になる。だから、Windows のふつうの決まりどおり、
//   メインの窓を最小化すると、一緒に隠れ、戻すと、元の位置と大きさで、メインの窓の手前に戻る。
//   （FMX のもとの作りでは、MinimizeApp が、子の窓を 1 つずつ最小化し、戻すときに元に戻さないので、縮んだ姿で画面の隅に残った）
//【出す・隠す】（通知領域に常駐するアプリなど、メインの窓を隠して動くアプリ用）
// ・Present：メインの窓を、出して、前に出す。隠れていても、最小化されていても、その前の大きさで出る。
//   FMX の Show・BringToFront は、最小化を戻さず、ほかのアプリの前にも出さないので、Windows の口で行う。
// ・Conceal：メインの窓を、隠す（タスクバーのボタンも消える）。
//   最小化したままのメインのフォームを、そのまま Hide すると、子の窓が、縮んだ姿で画面の隅に残る：
//   FMX は、前に出ているフォームを Hide するとき、次に前に出すフォームを選んで、出し直す
//   （FMX.Forms の TCommonCustomForm.Hide → TScreen.NextActiveForm → Activate → ShowWindow）。
//   メインの窓が最小化の間、子の窓は、Windows が隠している。そこで出し直された窓を、Windows は、最小化の姿で出す。
//   → 最小化の間に隠すときは、先に、前に出ているフォームの指定（公開のプロパティ TScreen.ActiveForm）を外して、FMX に選ばせない。
//     子の窓は、隠れたままになり、次に Present したときに、メインの窓と一緒に、元の位置と大きさで戻る。
//【前提】
// ・受け持つのは、窓の振る舞いだけ。通知領域のアイコン・二重起動・自動起動は、知らない。
// ・アプリに 1 つだけ作る（アプリの窓は、1 つ）。相手は、メインのフォーム。ほかに RegisterApplicationHWNDProc を使っていないこと。
// ・メインのフォームを作ったら、ほかの窓を作る前に、すぐに作る（破棄する隠れた窓の持ち物は、一緒に破棄される）。
//   メインのフォームを破棄する前（OnDestroy）に、Free する。
//【フォームが、窓を作り直すとき】（枠の種類を変えたときなど。FMX は、古い窓を破棄して、新しい窓を作る）
// ・FMX は、アプリの窓が破棄されると、アプリを終わらせる（WndProc の WM_DESTROY）。
//   だから、フォームの窓が破棄される前（TBeforeDestroyFormHandle）に、アプリの窓を、FMX の隠れた窓へ、いったん戻す。
//   新しい窓ができたら（TAfterCreateFormHandle）、もう一度、それをアプリの窓にする。
//【実行スレッド】
// ・主スレッドでだけ使う。

interface //#################################################################### ■

uses System.SysUtils, System.Messaging, System.UITypes,
     Winapi.Windows, Winapi.Messages,
     FMX.Forms;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TMainWindow = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMainWindow

     // メインのフォームの窓を、アプリの窓（タスクバーのボタンを持つ、ふつうの窓）にする。
     TMainWindow = class
     private
       _Form     :TCommonCustomForm;       // 相手のフォーム（所有しない）
       _Born     :TMessageSubscriptionId;  // 「フォームの窓ができた」の知らせの、受け取りの番号
       _Dying    :TMessageSubscriptionId;  // 「フォームの窓が破棄される」の知らせの、受け取りの番号
       _Idle     :TMessageSubscriptionId;  // 「手が空いた」の知らせの、受け取りの番号
       _Guard    :HWND;                    // Windows の終了の知らせを受ける、隠れた窓（所有する）
       _Close    :TCloseEvent;             // フォームの、元の OnClose（閉じるときに、先に呼ぶ）
       _OnEnding :TProc;                   // アプリの終わりの入口（無ければ、Windows の終了で、フォームを Close する）
       ///// A C C E S S O R
       function GetOnEnding :TProc;
       procedure SetOnEnding( const OnEnding_:TProc );
       ///// M E T H O D
       procedure Adopt;
       procedure Leave;
       ///// E V E N T
       procedure BornCome( const Sender_:TObject; const Message_:System.Messaging.TMessage );
       procedure DyingCome( const Sender_:TObject; const Message_:System.Messaging.TMessage );
       procedure IdleCome( const Sender_:TObject; const Message_:System.Messaging.TMessage );
       procedure FormClose( Sender_:TObject; var Action_:TCloseAction );
       procedure GuardProc( var Message_:Winapi.Messages.TMessage );
     protected
     public
       constructor Create( const Form_:TCommonCustomForm );
       destructor Destroy; override;
       ///// P R O P E R T Y
       property OnEnding :TProc read GetOnEnding write SetOnEnding;  // アプリの終わりの入口（Windows の終了・サインアウトで、主スレッドから 1 度呼ぶ。最後にメインのフォームを Close すること）
       ///// M E T H O D
       procedure Present;
       procedure Conceal;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.Classes,
     FMX.Types, FMX.Platform.Win;

var
   // FMX に登録する手続きは、メソッドではないので、返す値を、ここに持つ（アプリに 1 つ）
   _Main :TMainWindow = nil;  // いま働いているもの
   _Wnd  :HWND        = 0;    // FMX に、アプリの窓として答える窓：フォームの窓か、まだそうしていない間は、FMX が作った隠れた窓

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

// FMX に登録する手続き。
// 0 を返すと、FMX は、そのたびに、新しい隠れたアプリの窓を作る（UpdateApplicationHwnd は、前の窓を覚えていない）。
// だから、フォームの窓をアプリの窓にしていない間も、FMX が作った隠れた窓を、覚えておいて答える
function AppWnd :HWND;
begin
     Result := _Wnd;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMainWindow

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TMainWindow.GetOnEnding :TProc;
begin
     Result := _OnEnding;
end;

procedure TMainWindow.SetOnEnding( const OnEnding_:TProc );
begin
     _OnEnding := OnEnding_;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

// フォームの窓を、アプリの窓にする：持ち主を外し、FMX が作った隠れたアプリの窓を、破棄する
procedure TMainWindow.Adopt;
var
   W, O :HWND;
begin
     W := FormToHWND( _Form );
     if W = 0 then Exit;             // フォームが、まだ窓を持っていない（できたときに、知らせが来る）

     O := GetWindow( W, GW_OWNER );  // FMX が作った、隠れたアプリの窓

     SetWindowLongPtr( W, GWLP_HWNDPARENT, 0 );

     _Wnd := W;

     // ApplicationHWND を読むと、FMX は、登録した手続きに聞いて、アプリの窓を、フォームの窓に替える（UpdateApplicationHwnd）。
     // 隠れた窓を破棄するのは、替わった後だけ：FMX は、アプリの窓が破棄されると、アプリを終わらせる（WndProc の WM_DESTROY）
     if ( ApplicationHWND = W ) and ( O <> 0 ) then DestroyWindow( O );
end;

// フォームの窓を、アプリの窓でなくする：FMX に、隠れたアプリの窓を、作り直させる
procedure TMainWindow.Leave;
begin
     _Wnd := 0;                // 0 を答えると、FMX は、隠れたアプリの窓を、新しく作る
     _Wnd := ApplicationHWND;  // その窓を、覚えておいて、次からは、それを答える
end;

////////////////////////////////////////////////////////////////////// E V E N T

procedure TMainWindow.BornCome( const Sender_:TObject; const Message_:System.Messaging.TMessage );
begin
     if Sender_ = _Form then Adopt;
end;

procedure TMainWindow.DyingCome( const Sender_:TObject; const Message_:System.Messaging.TMessage );
begin
     if Sender_ = _Form then Leave;
end;

// アプリの手が空いた：メインフォームの指定を、外す（FMX の MinimizeApp を、通らなくする）
procedure TMainWindow.IdleCome( const Sender_:TObject; const Message_:System.Messaging.TMessage );
begin
     if Application.MainForm = _Form then Application.MainForm := nil;
end;

// フォームが、閉じられる（FMX.Forms の TCommonCustomForm.Close → DoClose）。
// 本当に閉じるなら、メインフォームの指定を戻す：FMX は、この後、メインフォームかを見て、アプリを終える
procedure TMainWindow.FormClose( Sender_:TObject; var Action_:TCloseAction );
begin
     if Assigned( _Close ) then _Close( Sender_, Action_ );

     if Action_ <> TCloseAction.caNone then Application.MainForm := _Form;
end;

// 隠れた窓に届いたメッセージ。Windows が、本当に終わるとき（WM_ENDSESSION で、WParam が 0 でない）に、
// FMX が、隠れたアプリの窓で行っていたこと（FMX.Platform.Win の WndProc の WM_ENDSESSION）を、同じ順に行う：
// アプリの終わりの入口を呼び（無ければ、メインのフォームを Close し）、保存の知らせを出して、アプリを終わらせる。
// WM_QUERYENDSESSION は、DefWindowProc が真（終わってよい）を返す
procedure TMainWindow.GuardProc( var Message_:Winapi.Messages.TMessage );
begin
     if ( Message_.Msg = WM_ENDSESSION ) and ( Message_.WParam <> 0 ) then
     begin
          try
               Screen.ActiveForm := nil;

               if Assigned( _OnEnding ) then _OnEnding()
                                        else _Form.Close;
          except
               on E :Exception do Application.HandleException( E );  // Close の中の失敗で、終わるのを止めない（FMX と同じ）
          end;

          TMessageManager.DefaultManager.SendMessage( nil, TSaveStateMessage.Create );

          Application.Terminate;

          Halt;
     end;

     Message_.Result := DefWindowProc( _Guard, Message_.Msg, Message_.WParam, Message_.LParam );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TMainWindow.Create( const Form_:TCommonCustomForm );
begin
     inherited Create;

     if Assigned( _Main ) then raise EInvalidOpException.Create( 'TMainWindow は、アプリに 1 つだけ作れる' );

     _Main := Self;
     _Form := Form_;

     _Wnd := ApplicationHWND;  // FMX が、もう作っている、隠れたアプリの窓

     RegisterApplicationHWNDProc( AppWnd );

     Adopt;

     _Born  := TMessageManager.DefaultManager.SubscribeToMessage( TAfterCreateFormHandle  , BornCome  );
     _Dying := TMessageManager.DefaultManager.SubscribeToMessage( TBeforeDestroyFormHandle, DyingCome );
     _Idle  := TMessageManager.DefaultManager.SubscribeToMessage( TIdleMessage            , IdleCome  );

     _Close        := _Form.OnClose;
     _Form.OnClose := FormClose;

     _Guard := AllocateHWnd( GuardProc );
end;

destructor TMainWindow.Destroy;
begin
     // 作るのに失敗したもの（2 つ目）は、何も登録していない
     if _Main = Self then
     begin
          DeallocateHWnd( _Guard );

          _Form.OnClose := _Close;

          TMessageManager.DefaultManager.Unsubscribe( TAfterCreateFormHandle  , _Born  );
          TMessageManager.DefaultManager.Unsubscribe( TBeforeDestroyFormHandle, _Dying );
          TMessageManager.DefaultManager.Unsubscribe( TIdleMessage            , _Idle  );

          // フォームの窓は、アプリの窓のままにしておく（この後、フォームの破棄で、アプリが終わる。
          // ここで FMX の隠れた窓に戻すと、終わりぎわに、タスクバーのボタンが、もう 1 つ出る）
          RegisterApplicationHWNDProc( nil );

          _Wnd  := 0;
          _Main := nil;
     end;

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

// メインの窓を、出して、前に出す（隠れている・最小化されているときも）
procedure TMainWindow.Present;
var
   W :HWND;
begin
     _Form.Show;

     W := FormToHWND( _Form );

     // 最小化されていたら、その前の大きさに戻す（最大化していたなら、最大化に。FMX の WindowState := wsNormal は、最大化を忘れる）
     if IsIconic( W ) then ShowWindow( W, SW_RESTORE );

     SetForegroundWindow( W );
end;

// メインの窓を、隠す
procedure TMainWindow.Conceal;
begin
     // 最小化の間は、FMX に、次に前に出すフォームを選ばせない（選ばれた子の窓が、縮んだ姿で画面の隅に出る）
     if IsIconic( FormToHWND( _Form ) ) then Screen.ActiveForm := nil;

     _Form.Hide;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
