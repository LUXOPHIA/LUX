unit LUX.FMX.Redraw;

// 窓の中身が変わったら、ほかの知らせが続いていても、すぐに描く（Windows の FMX）
//
//【なぜ要るか】
// ・FMX は、描き直しを、Windows に「この範囲が古い」と伝えるだけで頼む（FMX.Platform.Win の
//   TPlatformWin.InvalidateWindowRect が InvalidateRect を呼ぶ）。実際に描くのは、Windows が WM_PAINT を出したとき。
// ・Windows は、WM_PAINT を、届けられた知らせ（PostMessage されたもの）が 1 つも残っていないときにだけ出す。
//   知らせが切れ目なく届く間（報告の速いマウス・重い応答・順番待ちの仕事の連なり）、窓は、変わっているのに、描かれない。
//   利用者には、操作に付いてこない・固まった、と見える。
//
//【すること】
// ・主スレッドが、知らせを 1 つ汲み出すたびに、FMX のフォームの窓に、古い範囲が残っていないかを見る。
//   残っていれば、その知らせを処理する前に、その窓に、その場で描かせる（UpdateWindow）。
//   → 前の知らせの処理で変わったものは、次の知らせの処理の前に、画面に出る。
// ・描かせるのは、その窓の、描かせてよい時刻を過ぎたときだけ。描かせてよい時刻は、その窓がいるモニターの、画面の更新の周期おきに
//   並べる（画面は、それより細かくは変わらない）。知らせが、描くより速く届き続けても、描くことで、知らせの処理が、際限なく遅れない。
// ・描かせてよい時刻は、周期おきに並ぶ点の上に置く（位相を保つ）。次の時刻は、前の時刻と、描かせ始めた時刻の遅いほうより後の、
//   最初の点（TRedraw.NextDue）。描かせた時刻に周期を足すと、描くのは、その時刻を過ぎて最初に汲み出された知らせのときなので、
//   間隔が毎回「周期 ＋ 汲み出しの待ち」になり、画面の更新を何回かに 1 回取り逃す。1 周期以上遅れたら、いまの後の最初の点
//   （取り逃した分を取り戻そうと、続けて描かせない）。
// ・点の並びの位相は、画面の合成（DWM）の時機にそろえる：点は、垂直帰線の時刻（合成の直後）。位相が起動のたびにたまたま決まると、
//   合成の時機が、FMX の外が描く面の反映と、FMX の Present の間に落ちる位相で、多くのコマで片方だけが先に出て、ずれる。
//   待たせる呼び出し（DwmFlush）は使わない（待つ分、描くのが遅れる）。
// ・周期は、窓に描かせるたびに、その時の窓のモニターから取り（LUX.Windows.Monitor）、次に描かせてよい時刻を、窓ごとに覚える。
//   窓がモニターをまたいで移った・モニターの更新の速さが変わったときも、次に描かせた所から、新しい周期になる。
//   取るのは描かせるときだけ（取り出しは数十マイクロ秒で、描く手間の数百分の一）。知らせ 1 つごとには取らない。
//   周期が分からないモニターでは、下限を置かない（古い範囲があれば、知らせのたびに描かせる）。
//   覚えた時刻は、窓が壊れる（WM_NCDESTROY の処理が終わる）ときに捨てる。
// ・古い範囲が無い窓には、何もしない（変わっていないときは、描かない）。1 つの変化に、描かせるのは 1 度。
// ・窓の位置か大きさが変わったときは、その知らせ（WM_WINDOWPOSCHANGED）の処理が終わった所で、古い範囲が残っていれば、
//   すぐに描かせる（次の知らせを待たない。周期の下限も見ない）。大きさが変わると、Windows は、窓の枠をすぐに広げ、FMX は、
//   描く先（スワップチェーン）を捨てて、次に描くときに作り直す（FMX.Forms の TCustomForm.ResizeHandle →
//   FMX.Canvas.D2D の SetSize）。描き終えるまで、広がった所には、下地が見える。その間を、描く手間だけに縮める。
//   WM_SIZE の戻りでは、早すぎる：FMX は、WM_WINDOWPOSCHANGED の処理の中で、先に Windows の既定の処理（そこから
//   WM_SIZE が送られる）を呼び、その後で、フォームの大きさと並びを直す（FMX.Platform.Win の WndProc →
//   TWinWindowHandle.WMWindowPosChanged → Form.SetBoundsF）。WM_SIZE の戻りで描くと、並びを直す前の姿を描き、
//   直した後に、もう 1 度描くことになる。
// ・知らせが途切れたときの描き直しは、これまでどおり、Windows の WM_PAINT が行う。
//
//【合成の時機の取り方】（Microsoft の文書による）
// ・DwmGetCompositionTimingInfo の DWM_TIMING_INFO の qpcVBlank（垂直帰線の前の QueryPerformanceCounter の値）と、
//   qpcRefreshPeriod（モニターの更新の周期。同じ時計の刻み）。どちらも QPC_TIME で、QueryPerformanceCounter と同じ刻み。
//   1 回の呼び出しは 1 マイクロ秒に満たないので、描かせるたびに読む。
// ・qpcVBlank は、いまより先の時刻が返ることがある（いまより 9〜13 ミリ秒先）。並びの上の 1 点として使うので、
//   過去でも先でも、同じに扱う。
// ・Windows 8.1 から、窓の引数には NULL しか渡せない。どのモニターの時機が返るかは、文書に無い（周期の違うモニターが混ざる
//   機械で、いちばん速いモニターの周期が返る例があるが、そのモニターが主のモニターでもあると、どちらの決まりかは
//   分からない）。そこで、返った周期が、窓のモニターの周期（LUX.Windows.Monitor）と同じとみなせる（差が 3% 以内。モニターの周期は
//   整数の Hz なので、端数の分を許す）ときだけ、その時機に並べ、周期も、返った（端数まで正しい）値を使う。違えば、ほかのモニターの
//   時機なので使わず、窓のモニターの周期で、前の時刻の位相を保つ（合成の時機には、そろわない）。
// ・同じ速さのモニターが 2 つ以上あると、返った時機が、窓のモニターのものか、同じ速さのほかのモニターのものかは、区別できない。
//
//【描く直前に行うこと】（この部品が描かせるときも、Windows の WM_PAINT で描かれるときも）
// ・知らせ TRedrawingMessage を、そのフォームを送り主にして、TMessageManager で送る。FMX の外が描くもの
//   （埋め込みの子の窓）を持つ使う側は、これを受けて、その場で、置き直す。直後に FMX が描くので、両方が、同じ 1 回の
//   更新で画面に出る。使う側は、「置き直した後に描く」ために、自分で描かせなくてよい。
//
//【方法】
// ・知らせを汲み出した所と、窓の手続きが知らせを処理し終えた所を知るのに、Windows の公式の仕組み（そのスレッドのフック。
//   SetWindowsHookEx の WH_GETMESSAGE と WH_CALLWNDPROCRET）を使う。窓の手続きは、差し替えない。FMX の内側にも、触らない。
// ・FMX の公開の面には、「知らせを 1 つ処理するたび」の拡張点が無い（手が空いたときの知らせ TIdleMessage は、
//   知らせが続く間は、来ない）。描き直しの依頼を受けるサービス（IFMXWindowService）を包む方法は、取らない：
//   サービスの手続きをすべて中継する要があり、フォームは、作られるときにサービスを覚えるので、後から入れても効かない。
//
//【使い方】
// ・アプリに 1 つ、主スレッドで作る（メインのフォームの OnCreate など）。終わるときに、壊す。
//   フォームの側には、何も書かない。後から作られたフォームも、FMX が自分で作る窓も、対象になる。
// ・FMX の外が描くものを持つフォームだけ、TRedrawingMessage を受けて、置き直す（送り主が、自分のフォームのとき）。
//
//【前提】
// ・Windows の API を呼ぶ部品（Windows の FMX のアプリで使う）。

interface //#################################################################### ■

uses Winapi.Windows, Winapi.Messages,
     System.Messaging, System.Generics.Collections,
     FMX.Forms;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TRedraw = class;

     // フォームの窓が、いまから描かれる（送り主が、そのフォーム）。受けた所は、その場で、FMX の外が描くものをそろえる
     TRedrawingMessage = class( System.Messaging.TMessage );

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TRedraw

     // 変わった窓を、知らせの処理の間に、すぐに描かせる
     TRedraw = class
     private
       class var _Only :TRedraw;         // アプリに 1 つ（フックの手続きが、ここから見つける）
       _Hook  :HHOOK;                    // 知らせの汲み出しのフック（所有する）
       _Echo  :HHOOK;                    // 窓の手続きが知らせを処理し終えた所のフック（所有する）
       _Unit  :Int64;                    // 時計の、1 秒あたりの刻み
       _Nexts :TDictionary<HWND,Int64>;  // 窓ごとの、次に描かせてよい時刻（時計の刻み。描かせたことの無い窓は、無い）
       _Doing :Boolean;                  // 描かせている最中（その間に汲み出された知らせでは、重ねて描かせない）
       ///// M E T H O D
       procedure Ready( const Form_:TCommonCustomForm );
       class function Composed( const Period_:Int64; out VBlank_,Refresh_:Int64 ) :Boolean; static;
       procedure Draw( const Form_:TCommonCustomForm; const Wnd_:HWND; const Time_:Int64 );
       procedure Flush;
       procedure Moved( const Wnd_:HWND );
       procedure Paints( const Wnd_:HWND );
       class function Fetched( Code_:Integer; WParam_:WPARAM; LParam_:LPARAM ) :LRESULT; stdcall; static;
       class function Called( Code_:Integer; WParam_:WPARAM; LParam_:LPARAM ) :LRESULT; stdcall; static;
     protected
     public
       constructor Create;
       destructor Destroy; override;
       ///// M E T H O D
       // 窓に描かせた後の、次に描かせてよい時刻。Due_：いま描かせた窓の、描かせてよかった時刻（初めてなら Time_）。
       // Time_：描かせ始めた時刻。Period_：画面の更新の周期（0 なら、分からない）。Origin_：描かせてよい時刻の並びが通る時刻
       // （合成の時機が分かれば、その垂直帰線の時刻。分からなければ Due_）。どれも時計の刻み
       class function NextDue( const Due_,Time_,Period_,Origin_:Int64 ) :Int64; static;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils,
     Winapi.DwmApi,
     FMX.Platform.Win,
     LUX.Windows.Monitor;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TRedraw

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

// フォームの窓が描かれる直前に行うこと：使う側に知らせる
procedure TRedraw.Ready( const Form_:TCommonCustomForm );
begin
     TMessageManager.DefaultManager.SendMessage( Form_, TRedrawingMessage.Create );
end;

// 合成の時機（垂直帰線の時刻と、その周期。時計の刻み）を読む。読めて、その周期が、窓のモニターの周期 Period_ と同じと
// みなせる（差が 3% 以内）ときだけ真。違えば、ほかのモニターの時機なので、使わない
class function TRedraw.Composed( const Period_:Int64; out VBlank_,Refresh_:Int64 ) :Boolean;
var
   I :TDwmTimingInfo;
begin
     VBlank_  := 0;
     Refresh_ := 0;

     if Period_ <= 0 then Exit( False );                                   // 窓のモニターの周期が分からなければ、比べられない

     I := Default( TDwmTimingInfo );
     I.cbSize := SizeOf( I );

     if Failed( DwmGetCompositionTimingInfo( 0, I ) ) then Exit( False );  // Windows 8.1 から、窓の引数は NULL だけ

     Refresh_ := Int64( I.qpcRefreshPeriod );
     VBlank_  := Int64( I.qpcVBlank );

     Result := ( Refresh_ > 0 ) and ( Abs( Refresh_ - Period_ ) * 100 <= Period_ * 3 );
end;

// フォームの窓 Wnd_ に、古い範囲が残っていれば、その場で描かせ、次に描かせてよい時刻を覚える。Time_：いまの時刻（時計の刻み）
procedure TRedraw.Draw( const Form_:TCommonCustomForm; const Wnd_:HWND; const Time_:Int64 );
var
   N, P, O, R :Int64;
begin
     if ( Wnd_ = 0 ) or not IsWindowVisible( Wnd_ ) or not GetUpdateRect( Wnd_, nil, False ) then Exit;  // 窓がまだ無いフォームは 0

     if not _Nexts.TryGetValue( Wnd_, N ) then N := Time_;

     // 周期は、描かせる時の窓のモニターから取る（窓が移っていれば、移った先の周期）。分からなければ 0：下限を置かない
     P := Round( TWinMonitor.Create( Wnd_ ).Period * _Unit );

     // 合成の時機が、窓のモニターのものと読めれば、その垂直帰線と周期に並べる。読めなければ、前の時刻の位相を保つ
     if Composed( P, O, R ) then P := R
                            else O := N;

     _Nexts.AddOrSetValue( Wnd_, NextDue( N, Time_, P, O ) );

     Ready( Form_ );

     UpdateWindow( Wnd_ );                                                                               // FMX が、その場で描く（WM_PAINT を、じかに受ける）
end;

// 知らせを 1 つ汲み出した：古い範囲が残っていて、描かせてよい時刻を過ぎたフォームの窓に、その場で描かせる
procedure TRedraw.Flush;
var
   T, N :Int64;
   I :Integer;
   F :TCommonCustomForm;
   W :HWND;
begin
     if _Doing then Exit;

     QueryPerformanceCounter( T );

     _Doing := True;
     try
          for I := 0 to Screen.FormCount - 1 do
          begin
               F := Screen.Forms[ I ];
               W := FormToHWND( F );

               if _Nexts.TryGetValue( W, N ) and ( T < N ) then Continue;  // 描かせてよい時刻に、まだなっていない

               Draw( F, W, T );
          end;
     finally
          _Doing := False;
     end;
end;

// 窓の位置か大きさが変わった知らせの処理が、終わった：フォームの窓なら、すぐに描かせる（周期の下限は見ない）
procedure TRedraw.Moved( const Wnd_:HWND );
var
   F :TCommonCustomForm;
   T :Int64;
begin
     if _Doing then Exit;

     F := FindWindow( Wnd_ );  // フォームの窓でなければ nil

     if not Assigned( F ) then Exit;

     QueryPerformanceCounter( T );

     _Doing := True;
     try
          Draw( F, Wnd_, T );
     finally
          _Doing := False;
     end;
end;

// 描き直しの知らせ（WM_PAINT）が、汲み出された：フォームの窓なら、描かれる直前のことを行う
procedure TRedraw.Paints( const Wnd_:HWND );
var
   F :TCommonCustomForm;
begin
     if _Doing then Exit;

     F := FindWindow( Wnd_ );

     if not Assigned( F ) then Exit;

     _Doing := True;
     try
          Ready( F );
     finally
          _Doing := False;
     end;
end;

// 主スレッドが、知らせを 1 つ汲み出した（Windows が、汲み出しの中から呼ぶ）
class function TRedraw.Fetched( Code_:Integer; WParam_:WPARAM; LParam_:LPARAM ) :LRESULT;
begin
     // 取り除かれた知らせだけ（のぞいただけの知らせは、もう一度、汲み出される）
     if ( Code_ = HC_ACTION ) and ( WParam_ = PM_REMOVE ) then
     begin
          if PMsg( LParam_ ).message = WM_PAINT then _Only.Paints( PMsg( LParam_ ).hwnd )  // いまから、Windows の知らせで描かれる
                                                else _Only.Flush;
     end;

     Result := CallNextHookEx( 0, Code_, WParam_, LParam_ );
end;

// 窓の手続きが、送られた知らせを 1 つ処理し終えた（Windows が、窓の手続きの戻りで呼ぶ）
class function TRedraw.Called( Code_:Integer; WParam_:WPARAM; LParam_:LPARAM ) :LRESULT;
begin
     if Code_ = HC_ACTION then
     begin
          case PCWPRetStruct( LParam_ ).message of
            WM_WINDOWPOSCHANGED: _Only.Moved( PCWPRetStruct( LParam_ ).hwnd );
            WM_NCDESTROY       : _Only._Nexts.Remove( PCWPRetStruct( LParam_ ).hwnd );  // 窓が壊れた：覚えた時刻を捨てる
          end;
     end;

     Result := CallNextHookEx( 0, Code_, WParam_, LParam_ );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TRedraw.Create;
begin
     inherited Create;

     if Assigned( _Only ) then raise EInvalidOpException.Create( 'TRedraw は、アプリに 1 つだけ作れる' );

     if not QueryPerformanceFrequency( _Unit ) then RaiseLastOSError;

     _Nexts := TDictionary<HWND,Int64>.Create;

     _Only := Self;

     _Hook := SetWindowsHookEx( WH_GETMESSAGE    , @Fetched, 0, GetCurrentThreadId );
     _Echo := SetWindowsHookEx( WH_CALLWNDPROCRET, @Called , 0, GetCurrentThreadId );

     if ( _Hook = 0 ) or ( _Echo = 0 ) then RaiseLastOSError;  // 掛かった方は、デストラクターが外す（作る途中の例外で、呼ばれる）
end;

destructor TRedraw.Destroy;
begin
     if _Echo <> 0 then UnhookWindowsHookEx( _Echo );
     if _Hook <> 0 then UnhookWindowsHookEx( _Hook );

     if _Only = Self then _Only := nil;

     _Nexts.Free;

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

// 描かせてよい時刻は、Origin_ を通り、周期おきに並ぶ点の上に置く。次の時刻は、前の時刻（Due_）と描かせ始めた時刻（Time_）の
// 遅いほうより後の、最初の点。
// ・遅れていなければ、前の時刻の次の点（描かせた時刻に周期を足すと、間隔が毎回「周期 ＋ 汲み出しの待ち」になり、画面の更新を
//   何回かに 1 回取り逃す）。1 周期以上遅れたら、いまの後の最初の点（取り逃した分を取り戻そうと、続けて描かせない）。
// ・Origin_ が合成の時機（垂直帰線の時刻）なら、どの時刻も合成の直後になる。
class function TRedraw.NextDue( const Due_,Time_,Period_,Origin_:Int64 ) :Int64;
var
   B, Q :Int64;
begin
     if Period_ <= 0 then Exit( Time_ );  // 周期が分からない：下限を置かない

     if Due_ > Time_ then B := Due_
                     else B := Time_;

     // ( B − Origin_ ) ÷ 周期 の、負の側へ丸めた商（Origin_ が、いまより先の垂直帰線でもよい）
     Q := ( B - Origin_ ) div Period_;
     if ( B - Origin_ ) - Q * Period_ < 0 then Dec( Q );

     Result := Origin_ + ( Q + 1 ) * Period_;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
