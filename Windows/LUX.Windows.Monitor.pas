unit LUX.Windows.Monitor;

// 窓がいるモニターと、その画面の更新の周期
//
//【周期の取り方】
// ・窓のモニター：MonitorFromWindow（MONITOR_DEFAULTTONEAREST：窓と重なりのいちばん大きいモニター。重ならなければ、いちばん近いもの）。
//   取るたびに、窓のいまの位置で決まるので、窓がモニターをまたいで移れば、次に取ったときから、移った先のモニターになる。
// ・モニターの装置名：GetMonitorInfo の MONITORINFOEX.szDevice（\\.\DISPLAY1 の形）。
// ・更新の速さ：EnumDisplaySettings( 装置名, ENUM_CURRENT_SETTINGS ) の dmDisplayFrequency（その装置の、いまのモードの、
//   垂直の更新の速さ。整数の Hz）。周期は、その逆数。
//
//【この取り方を選んだ理由】（Microsoft の公式の文書による）
// ・DWM の合成の周期（DwmGetCompositionTimingInfo）は、Windows 8.1 から、窓の引数に NULL しか渡せない（NULL 以外は E_INVALIDARG）。
//   窓ごと・モニターごとには取れないので、モニターごとに更新の速さが違う機械では、窓のモニターの周期にならない。
// ・EnumDisplaySettings は、装置名を渡すと、その装置の、いまのモードを返す。モニターごとに取れる。
// ・dmDisplayFrequency が 0 か 1 のときは、装置の既定の速さを表し、実際の速さは分からない（DEVMODE の文書）。そのとき、
//   周期は 0（分からない）とする。取り出しに失敗したときも、0。
// ・dmDisplayFrequency は整数の Hz なので、端数のある速さ（59.94 Hz など）では、周期に 2% 未満の誤りが出うる。
//
//【いちばん短い周期】（MinPeriod）
// ・つながっている全部のモニターの周期のうち、いちばん短いもの（いちばん速いモニター）。プロセス全体で 1 つだけ決める値
//   （FMX の GlobalPreferredFramesPerSecond など）を、窓がどのモニターへ移っても足りるように決めるときに使う。
// ・モニターごとの周期は、上と同じ取り方（Period）で取る。周期が分からないモニターは、比べない。どれも分からなければ 0。
// ・モニターを足した・外した・速さを変えた後は、呼び直す（値を覚えておかない）。
//
//【可変の更新の速さ（VRR）】
// ・Microsoft の文書が述べるのは、OS の VRR が、全画面の DirectX 11 のゲームと、「ウィンドウ化されたゲームの最適化」の
//   対象のゲームに効くこと、動的な更新の速さ（DRR）が、ノートの機械の画面だけのもので、ふだんは 60 Hz、ペンの入力と
//   スクロールでは 120 Hz に切り替えること、までである。ふつうの窓のアプリの合成の速さが変わるか、変わっている間に
//   dmDisplayFrequency が何を返すかは、文書に無い（確かめていない）。
// ・ここでは、いまのモードの速さを、その画面が更新できる速さとして、周期にする。実際の更新が、それより間遠になっていれば、
//   この周期は、実際より短い。描かせる下限に使えば、画面より遅くは描かせない。引っかかりを数える物差しに使えば、
//   引っかかりを、少なくは数えない。
//
//【手間】
// ・1 回の取り出し（MonitorFromWindow から EnumDisplaySettings まで）は、数十マイクロ秒かかる。
//   知らせ 1 つごとのような、頻繁な所では呼ばない。

interface //#################################################################### ■

uses Winapi.Windows;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinMonitor

     // 窓がいるモニター
     TWinMonitor = record
     private
       _Handle :HMONITOR;
       ///// A C C E S S O R
       function GetPeriod :Double;
     public
       // Wnd_：その窓がいま、いちばん大きく重なっているモニター（重ならなければ、いちばん近いもの）
       constructor Create( const Wnd_:HWND );
       ///// P R O P E R T Y
       property Handle :HMONITOR read _Handle  ;  // モニター
       property Period :Double   read GetPeriod;  // 画面の更新の周期（秒）。分からなければ 0
       ///// M E T H O D
       class function MinPeriod :Double; static;  // 全部のモニターの周期のうち、いちばん短いもの（秒）。どれも分からなければ 0
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses Winapi.MultiMon;

const
     ENUM_CURRENT_SETTINGS = DWORD( -1 );  // EnumDisplaySettings の、いまのモードを取る指定（winuser.h。Winapi.Windows に宣言が無い）

// EnumDisplayMonitors の 1 つのモニター：その周期が分かり、いままでのものより短ければ、置き換える（Data_ は、Double の置き場）
function Shorter( Monitor_:HMONITOR; DC_:HDC; Rect_:PRect; Data_:LPARAM ) :BOOL; stdcall;
var
   M :TWinMonitor;
   P :Double;
begin
     M._Handle := Monitor_;

     P := M.Period;

     if ( P > 0 ) and ( ( PDouble( Data_ )^ = 0 ) or ( P < PDouble( Data_ )^ ) ) then PDouble( Data_ )^ := P;

     Result := True;  // 全部のモニターを見る
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TWinMonitor

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TWinMonitor.GetPeriod :Double;
var
   I :TMonitorInfoEx;
   M :TDeviceMode;
begin
     I := Default( TMonitorInfoEx );
     I.cbSize := SizeOf( I );

     if not GetMonitorInfo( _Handle, PMonitorInfo( @I ) ) then Exit( 0 );

     M := Default( TDeviceMode );
     M.dmSize := SizeOf( M );

     if not EnumDisplaySettings( I.szDevice, ENUM_CURRENT_SETTINGS, M ) then Exit( 0 );

     // 0 と 1 は、装置の既定の速さ（実際の速さは分からない）
     if M.dmDisplayFrequency <= 1 then Exit( 0 );

     Result := 1 / M.dmDisplayFrequency;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TWinMonitor.Create( const Wnd_:HWND );
begin
     _Handle := MonitorFromWindow( Wnd_, MONITOR_DEFAULTTONEAREST );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

class function TWinMonitor.MinPeriod :Double;
begin
     Result := 0;

     if not EnumDisplayMonitors( 0, nil, @Shorter, LPARAM( @Result ) ) then Result := 0;  // 数えられなければ、分からない
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
