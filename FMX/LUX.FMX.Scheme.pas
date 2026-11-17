unit LUX.FMX.Scheme;

// 共通のカスタムスタイル（LUX.FMX.Style）の明・暗を、利用者の選び（自動・明・暗）と Windows の明暗の設定に従って替え、
// どのフォームの地と題名の帯も、その明暗に合わせる（Windows の FMX）
//
//【構成】
// ・TFmxScheme … 選び（Mode）に合う明暗を TFmxStyle.Dark に入れる（当てるのは TFmxStyle）。自動のときは、Windows の明暗の
//                  設定が変わったら替える。替えたら、いまあるすべてのフォーム（Screen.Forms）を飾り直す。
// ・このスタイルでは、実行中に明暗を替えても、部品を作り直さなくてよい。
// ・TSchemeChangedMessage … 明暗が替わった、の知らせ。スタイルの外にあるもの（埋め込みのページなど、スタイルを読めないもの）へ
//                  色を渡し直す所が、TMessageManager で受ける。届くのは、スタイルを当て、フォームを飾り直した後
//                  （受けた側は、替わった後の色を、TFmxStyle から引ける）。明暗が変わらなかったときは、送らない。
//
//【Windows の明暗の知らせ】（RAD Studio 37.0 の FMX.Platform.Win.pas）
// ・FMX の TWinSystemAppearanceService は、自分の隠れた窓で WM_SETTINGCHANGE（ImmersiveColorSet）を受け、レジストリの
//   AppsUseLightTheme を読み直して ThemeKind を新しくし、変わっていれば TSystemAppearanceChangedMessage を送る。
//   ここは、その公開の知らせを受けて、公開のサービス（IFMXSystemAppearanceService）の ThemeKind を読む。見回りをしない。
//
//【フォームの飾り】
// ・どのフォームも、出す直前（FMX の公開の知らせ TFormBeforeShownMessage。TCommonCustomForm.Show が ShowWindow の前に送る）と、
//   明暗を替えたときに、地（Fill）を、そのフォームの地の定義（StyleLookup。既定は backgroundstyle）が描く色にし、題名の帯を明暗に合わせる
//   （DWMWA_USE_IMMERSIVE_DARK_MODE。FMX は窓の枠の明暗を扱わない）。フォームの側は、何もしなくてよい。
// ・地の色は、定義から読む（TFmxStyle.Ground）。ここは、定義の名前も、色の役も知らない：どの定義がどの色を描くかは、スタイルが決めている。
//   スタイルが描く地と、下塗りの色が、同じになる（違うと、窓が出た瞬間に、別の色が見える）。地の定義が増えても、ここは変わらない。
// ・地の定義を外したフォーム（StyleLookup が空）は、スタイルが地を描かないので、地（Fill）に触らない（題名の帯だけ合わせる）。
// ・窓が出る前に地の色が決まるので、出た瞬間の下塗り（LUX.FMX.Primer）も、その色で塗る。
// ・作ったときに付けるだけでは、子の窓の題名の帯が明るいまま残るので、出すたびに付ける。
// ・色の正はスタイルで、ここは色の値を持たない。
//
//【前提】
// ・主スレッドでだけ使う。アプリに 1 つ。

interface //#################################################################### ■

uses System.Classes, System.Messaging,
     FMX.Forms;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TFmxScheme            = class;
     TSchemeChangedMessage = class;

     // 明暗の選び
     TSchemeMode = ( smAuto,    // Windows の設定に従う
                     smLight,   // 明
                     smDark );  // 暗

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TFmxScheme

     // 明暗の選びと Windows の設定に、スタイルとフォームを従わせる
     TFmxScheme = class
     private
       _Mode   :TSchemeMode;
       _Appear :TMessageSubscriptionId;  // 「Windows の明暗が変わった」の知らせの、受け取りの番号
       _Shown  :TMessageSubscriptionId;  // 「フォームを出す」の知らせの、受け取りの番号
       ///// M E T H O D
       function WantDark :Boolean;
       procedure Follow;
       procedure Decorate( const Form_:TCustomForm );
       ///// E V E N T
       procedure AppearCome( const Sender_:TObject; const Message_:TMessage );
       procedure ShownCome( const Sender_:TObject; const Message_:TMessage );
     protected
       ///// A C C E S S O R
       function GetMode :TSchemeMode; virtual;
       procedure SetMode( const Mode_:TSchemeMode ); virtual;
     public
       constructor Create( const Mode_:TSchemeMode );          // 作ったときに当てる
       destructor Destroy; override;
       ///// P R O P E R T Y
       property Mode :TSchemeMode read GetMode write SetMode;  // 替えて明暗が変われば、当て直す
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSchemeChangedMessage

     // 明暗が替わった、の知らせ（送り主は TFmxScheme）
     TSchemeChangedMessage = class( TMessage )
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils,
     Winapi.Windows, Winapi.Dwmapi,
     FMX.Types, FMX.Graphics, FMX.Platform, FMX.Platform.Win,
     LUX.FMX.Style;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TFmxScheme

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

function TFmxScheme.WantDark :Boolean;
var
   S :IFMXSystemAppearanceService;
begin
     if _Mode = smAuto then Result := TPlatformServices.Current.SupportsPlatformService( IFMXSystemAppearanceService, S )
                                  and ( S.ThemeKind = TSystemThemeKind.Dark )
                       else Result := _Mode = smDark;
end;

// 選びと Windows の設定から明暗を決めて当て、すべてのフォームを飾り直す（TFmxStyle.Dark は、同じ明暗なら当て直さない）。
// 明暗が替わったら、最後に、知らせる
procedure TFmxScheme.Follow;
var
   I :Integer;
   D :Boolean;
begin
     D := TFmxStyle.Dark;

     TFmxStyle.Dark := WantDark;

     for I := 0 to Screen.FormCount - 1 do
     begin
          if Screen.Forms[ I ] is TCustomForm then Decorate( TCustomForm( Screen.Forms[ I ] ) );
     end;

     if TFmxStyle.Dark <> D then TMessageManager.DefaultManager.SendMessage( Self, TSchemeChangedMessage.Create );
end;

// フォームの地と題名の帯を、いまの明暗に合わせる
procedure TFmxScheme.Decorate( const Form_:TCustomForm );
var
   D :BOOL;
begin
     // 地（Fill）は、このフォームの地の定義が描く色（定義を外したフォームは、スタイルが地を描かないので、触らない）
     if Form_.StyleLookup <> '' then
     begin
          Form_.Fill.Kind  := TBrushKind.Solid;
          Form_.Fill.Color := TFmxStyle.Ground( Form_.StyleLookup );
     end;

     D := TFmxStyle.Dark;

     DwmSetWindowAttribute( FormToHWND( Form_ ), DWMWA_USE_IMMERSIVE_DARK_MODE, @D, SizeOf( D ) );
end;

//////////////////////////////////////////////////////////////////////// E V E N T

procedure TFmxScheme.AppearCome( const Sender_:TObject; const Message_:TMessage );
begin
     Follow;
end;

procedure TFmxScheme.ShownCome( const Sender_:TObject; const Message_:TMessage );
var
   F :TCommonCustomForm;
begin
     F := TFormBeforeShownMessage( Message_ ).Value;

     if F is TCustomForm then Decorate( TCustomForm( F ) );  // 3D のフォーム（TCustomForm3D）は、地の塗りを持たない
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TFmxScheme.GetMode :TSchemeMode;
begin
     Result := _Mode;
end;

procedure TFmxScheme.SetMode( const Mode_:TSchemeMode );
begin
     _Mode := Mode_;

     Follow;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TFmxScheme.Create( const Mode_:TSchemeMode );
begin
     inherited Create;

     _Mode := Mode_;

     TFmxStyle.Dark := WantDark;  // まだ当てていなければ、明暗にかかわらず当てる（TFmxStyle.SetDark）

     _Appear := TMessageManager.DefaultManager.SubscribeToMessage( TSystemAppearanceChangedMessage, AppearCome );
     _Shown  := TMessageManager.DefaultManager.SubscribeToMessage( TFormBeforeShownMessage        , ShownCome  );
end;

destructor TFmxScheme.Destroy;
begin
     TMessageManager.DefaultManager.Unsubscribe( TSystemAppearanceChangedMessage, _Appear );
     TMessageManager.DefaultManager.Unsubscribe( TFormBeforeShownMessage        , _Shown  );

     inherited;
end;

end. //######################################################################### ■
