unit LUX.Windows.Load;

// 機械全体の負荷（演算装置と描画装置の占有率・主記憶の足りなさによる退避・ディスクの使用中の割合）を、専用の実行スレッドで
// 決まった間隔で取り、時刻つきの区間の並びとしてためる（Windows。PDH）
//
//【構成】
// ・TLoad … 取る部品。作ると、取る実行スレッドが動き出し（最初の 1 回を取り終えるまで、作る側が待つ）、壊すと止まる。
//            測る側のスレッドは、何も取らない（取るのも、ためるのも、取る実行スレッド）。測る側は、終わってから Trace で切り出す。
// ・TLoadSpan … 1 つの値の、1 つの区間（始めと終わりの時刻と、その間の平均）。時刻は、ミリ秒（TLoad.Now の時計）。
// ・TLoadTrace … 時刻の範囲を切り出した並び（範囲の始めを 0 にずらす）と、種類ごとの要約（平均・いちばん悪い値）と、
//                 範囲の中の区間が、ふだんの程度を超えているか（Heavy）。OS を知らないので、作った並びで試験できる。
//
//【取る値】（TLoadKind。どれも、PDH の英語の名前で足す。足せなかった値は、区間が無い＝分からない）
// ・lkCPU：演算装置の占有率（%）。\Processor Information(_Total)\% User Time と % Privileged Time の生の値（FirstValue）は、どちらも、
//   全部の論理プロセッサーの、その状態の時間の平均の累計（100 ns 単位）。占有率 ＝（2 つの増えの和 ÷ 経った時間）× 100。
//   経った時間は、QueryPerformanceCounter。1 秒の窓で、PDH の % Processor Time と 0.6 ポイント以内で合う。
//   遊びの時間（% Idle Time）からは出さない：遊んでいたプロセッサーの時間は、起きた時にまとめて数えられ、16 ms の区間では、
//   −200〜90% を跳ねる（使っていた時間の和は、同じ時に 0.7〜26%）。
//   GetSystemTimes は使わない：64 を超える論理プロセッサーの機械では、呼んだスレッドのプロセッサー群の分しか返さない（Microsoft の文書）。
//   PDH の計算（整形した値）も使わない：カウンターの時刻（SecondValue）で割るが、16 ms おきに取ると、時刻が進まずに計算が失敗する
//   （PDH_CALC_NEGATIVE_DENOMINATOR）回がある。
// ・lkGPU3D・lkGPUCopy・lkGPUEtc：描画装置のエンジンの占有率（%）。\GPU Engine(*)\Utilization Percentage は、プロセスごと・エンジンごと
//   （インスタンスの名前 pid_…_luid_…_phys_…_eng_…_engtype_種類）。同じエンジン（_luid_ から後が同じ）のプロセスを足し、エンジンの種類
//   ごとに、いちばん高いエンジンの値をとる。種類は 3D・Copy（転送）・その他（動画・計算など）の 3 つに分ける。このプロセス自身の分は
//   足さない（測る対象の描画は、ほかの負荷ではない）。合成（dwm.exe）の分は、このプロセスが出した姿の合成も含めて、足す。
// ・lkPaging：主記憶の足りなさによる退避（ページ／秒）。\Memory\Pages Output/sec（カウンターの説明：物理メモリの領域を解放するために
//   ディスクに書き込まれたページの数。物理メモリが不足している場合、Windows はメモリ領域を解放するためにページをディスクに書き戻す）。
//   主記憶の量（使っている MB）は、取らない（量が多くても、退避が起きなければ、遅れない）。
//   退避からの読み込み（\Memory\Pages Input/sec。ハード ページ フォールトで読んだページ）は、使わない：ファイルを写像した所や、
//   ファイルの読み込みのキャッシュの外れも数え、退避と区別できない。主記憶が空いていて、書き出しが 0 の間にも、読み込みは、
//   ほかのプログラムのファイルの読み込みで、毎秒 25000 ページ前後が続き、16 ms の区間の 4 割ほどが、1 万ページ／秒を超えることがある。
//   これを退避として線に掛けると、ふだんの機械で、ほとんどの測定が無効になる。ファイルの読み込みの詰まりは、lkDisk で見る。
// ・lkDisk：ディスクの使用中の割合（%）。\PhysicalDisk(*)\% Idle Time（物理ディスクごとの、間隔の中で遊んでいた時間の割合）の、
//   いちばん遊んでいないディスクの 100 − 遊び。どのディスクでも、要求が詰まれば、そのディスクのファイルを待つ処理が遅れる。
//
//【間隔】（GAP。16 ミリ秒を頼み、実際は 17〜19 ミリ秒。1 ミリ秒にしない理由）
// ・演算装置の時間は、OS が、時計の割り込みの刻みごとに数える。刻みは、ふつう 15.625 ms
//   （Microsoft の文書「Acquiring high-resolution time stamps」の表は、PC の RTC を 64 Hz・15.625 ms としている）。
//   刻みより短い区間の占有率は、0% と 100% の間を跳ねる、意味の無い値になる。間隔は、刻みを下回らない 16 ms にする。
// ・描画装置の占有率は、エンジンが走った時間の増えを、取った間隔で割った値（カウンターの説明：The running time of each gpu engine）。
//   数ミリ秒の区間では、1 回の描画の仕事が入ったかどうかで、0% と数十% を跳ねる。
// ・退避の書き出しとディスクは、数は随時に増えるが、1 ms の区間には、0 か 1 つの出来事しか入らず、率としては使えない。
// ・1 回取るのに、約 1.5〜3 ms かかる（描画装置のエンジンのインスタンスが 1700 ほどのとき。その読み出しと集計が大半）。1 ms おきには
//   取れない。16 ms おきでも、取る実行スレッドは、演算装置 1 つの約 16〜18% を使う。
// ・区間は、前に取り終えた時刻から、今回取り終えた時刻まで（16 ms ＋ 取る時間）。取る実行スレッドが遅れれば、区間が長くなるだけで、
//   隙間はできない（PDH が値を出せなかった回は、その種類だけ、その区間が無い）。
// ・作るのに約 350 ms かかる（PDH の問い合わせを開き、描画装置のエンジンのインスタンスを数え、最初の 1 回を取る）。
//
//【ふだんの程度の線】（LOAD_LINES。区間の値が線を超えたら「重い」）
// ・占有率（演算装置・描画装置の各種類・ディスク）：50%（半分を超えたら重い）。待ち行列の見方では、
//   使われている割合 ρ の資源で、後から来た仕事の平均の待ちは、仕事 1 つの時間の ρ ÷（1 − ρ）倍で（M/M/1）、半分を超えると、
//   待ちが、仕事そのものの時間より長くなる。
// ・退避：0 ページ／秒（1 ページでも書き出したら重い）。書き出しは、主記憶が足りずに、使っていたページを追い出している印で、
//   追い出されたページを使う処理は、ディスクからの読み戻しを待つ。主記憶が足りている間は、0 のまま。
//   主記憶が足りない機械で、この値がどう出るか（書き出しが、どの程度の時間の幅で出るか）は、分かっていない。
//
//【知らせ】（Await・Calm）
// ・Await：取り終えた時刻が、指定の時刻を過ぎたら（その時刻までの区間が、そろったら）、知らせる。
// ・Calm：最後に取った区間の値が、どの種類も線以下になったら、知らせる（負荷の値で決める。時間で推し量らない）。
// ・知らせは、主スレッドで、取る実行スレッドに結び付けて積む（TThread.ForceQueue）。TLoad を壊すと、取る実行スレッドの
//   後始末で、まだ動いていない知らせは取り除かれる（壊した後に、知らせが動かない）。条件が既に満たされていれば、後に回して知らせる。
//
//【前提】
// ・Trace・Await・Calm は、主スレッドで使う。区間は、TLoad の寿命の間、ためる（1 秒に約 6 種類 × 62 区間）。
// ・取る実行スレッドが、思わぬ誤りで止まったら、待っている知らせを、すべて知らせ、その後の Trace は、その誤りを例外にする。

interface //#################################################################### ■

uses System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TLoad = class;

     // 負荷の種類
     TLoadKind = ( lkCPU,       // 演算装置の占有率（%）
                   lkGPU3D,     // 描画装置の 3D のエンジンの占有率（%）
                   lkGPUCopy,   // 描画装置の転送（Copy）のエンジンの占有率（%）
                   lkGPUEtc,    // 描画装置のほかのエンジン（動画・計算など）の占有率（%）
                   lkPaging,    // 主記憶の足りなさによる退避の書き出し（ページ／秒）
                   lkDisk );    // いちばん遊んでいないディスクの、使用中の割合（%）

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadSpan

     // 1 つの値の、1 つの区間
     TLoadSpan = record
       Head  :Double;  // 始めの時刻（ミリ秒）
       Tail  :Double;  // 終わりの時刻（ミリ秒）
       Value :Double;  // その間の平均（単位は、種類ごと）
     end;

     TLoadSpans  = TArray<TLoadSpan>;
     TLoadSeries = array [ TLoadKind ] of TLoadSpans;  // 種類ごとの、時刻の順の区間の並び

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadStat

     // 1 つの種類の、範囲の中の要約
     TLoadStat = record
       Known :Boolean;  // 範囲に重なる区間が、1 つでもあるか（無ければ、分からない。平均もいちばん悪い値も 0）
       Mean  :Double;   // 平均（区間が範囲に重なる長さで重みを付ける）
       Worst :Double;   // 範囲に重なる区間の、いちばん大きい値
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadTrace

     // 時刻の範囲（0 から Elapse まで）の、負荷の並びと要約
     TLoadTrace = record
       Series :TLoadSeries;                       // 範囲に重なる区間（範囲の始めを 0 にずらした時刻）
       Elapse :Double;                            // 範囲の長さ（ミリ秒）
       Stats  :array [ TLoadKind ] of TLoadStat;  // 種類ごとの要約
       // Series_：範囲に重なる区間。Elapse_：範囲の長さ（ミリ秒。0 以上）
       constructor Create( const Series_:TLoadSeries; const Elapse_:Double );
       ///// M E T H O D
       // Head_ から Tail_ まで（両端を含む）に重なる区間のうち、値が線（LOAD_LINES）を超えるものが、1 つでもあるか
       function Heavy( const Head_,Tail_:Double ) :Boolean;
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoad

     // 機械全体の負荷を、専用の実行スレッドで取り、ためる
     TLoad = class
     private
       _Lock    :TCriticalSection;
       _Series  :array [ TLoadKind ] of TList<TLoadSpan>;
       _Reach   :Double;   // 最後に取り終えた時刻（ミリ秒）
       _Fault   :String;   // 取る実行スレッドが止まった誤り（無ければ空）
       _Awaits  :TList<TPair<Double,TProc>>;
       _Calms   :TList<TProc>;
       _Sampler :TThread;  // 取る実行スレッド（所有する）
       ///// M E T H O D
       function IsCalm :Boolean;
       procedure Post( const Time_:Double; const Values_:array of Double; const Heads_:array of Double );
       procedure Fail( const Fault_:String );
     protected
     public
       constructor Create;
       destructor Destroy; override;
       ///// C O N S T A N T
       const GAP = 16;                      // 取る間隔（ミリ秒）
       ///// M E T H O D
       class function Now :Double; static;  // いまの時刻（ミリ秒。QueryPerformanceCounter の時計）
       // Head_ から Tail_ までに重なる区間を切り出す（時刻は Head_ を 0 にずらす）。Tail_ までを取り終えていなくても、あるだけを返す
       function Trace( const Head_,Tail_:Double ) :TLoadTrace; virtual;
       // Time_ までを取り終えたら、Proc_ を呼ぶ
       procedure Await( const Time_:Double; const Proc_:TProc ); virtual;
       // 最後に取った区間の値が、どの種類も線以下になったら、Proc_ を呼ぶ
       procedure Calm( const Proc_:TProc ); virtual;
     end;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

     // ふだんの程度の線（これを超えた区間が「重い」）
     LOAD_LINES :array [ TLoadKind ] of Double = ( 50,      // lkCPU     （%）
                                                   50,      // lkGPU3D   （%）
                                                   50,      // lkGPUCopy （%）
                                                   50,      // lkGPUEtc  （%）
                                                   0,       // lkPaging  （ページ／秒）
                                                   50 );    // lkDisk    （%）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses Winapi.Windows,
     System.Diagnostics, System.Math;

//////////////////////////////////////////////////////////////////////// P D H

// pdh.h・pdhmsg.h の宣言（RTL に無い）
type
     PDH_HQUERY   = THandle;
     PDH_HCOUNTER = THandle;

     TPdhRawCounter = record
       CStatus     :DWORD;
       TimeStamp   :TFileTime;
       FirstValue  :Int64;
       SecondValue :Int64;
       MultiCount  :DWORD;
     end;

     // PDH_FMT_COUNTERVALUE（共用体のうち doubleValue だけを使う）
     TPdhFmtValue = record
       CStatus :DWORD;
       Value   :Double;
     end;

     PPdhFmtItem = ^TPdhFmtItem;
     TPdhFmtItem = record
       Name  :PWideChar;
       Value :TPdhFmtValue;
     end;

const
     PDH_FMT_DOUBLE         = $00000200;
     PDH_FMT_NOCAP100       = $00008000;
     PDH_CSTATUS_VALID_DATA = $00000000;
     PDH_CSTATUS_NEW_DATA   = $00000001;
     PDH_MORE_DATA          = $800007D2;

     // synchapi.h・winnt.h（Winapi.Windows に無い）
     CREATE_WAITABLE_TIMER_HIGH_RESOLUTION = $00000002;
     TIMER_MODIFY_STATE                    = $0002;

function PdhOpenQueryW( DataSource_:PWideChar; UserData_:DWORD_PTR; out Query_:PDH_HQUERY ) :DWORD; stdcall; external 'pdh.dll';
function PdhAddEnglishCounterW( Query_:PDH_HQUERY; Path_:PWideChar; UserData_:DWORD_PTR; out Counter_:PDH_HCOUNTER ) :DWORD; stdcall; external 'pdh.dll';
function PdhCollectQueryData( Query_:PDH_HQUERY ) :DWORD; stdcall; external 'pdh.dll';
function PdhGetRawCounterValue( Counter_:PDH_HCOUNTER; Type_:PDWORD; out Value_:TPdhRawCounter ) :DWORD; stdcall; external 'pdh.dll';
function PdhGetFormattedCounterValue( Counter_:PDH_HCOUNTER; Format_:DWORD; Type_:PDWORD; out Value_:TPdhFmtValue ) :DWORD; stdcall; external 'pdh.dll';
function PdhGetFormattedCounterArrayW( Counter_:PDH_HCOUNTER; Format_:DWORD; var Size_:DWORD; out Count_:DWORD; Items_:Pointer ) :DWORD; stdcall; external 'pdh.dll';
function PdhCloseQuery( Query_:PDH_HQUERY ) :DWORD; stdcall; external 'pdh.dll';

const
     PDH_FORMAT = PDH_FMT_DOUBLE or PDH_FMT_NOCAP100;  // 整形した値は、倍精度で、100 で頭打ちにしない

     PATH_USER   = '\Processor Information(_Total)\% User Time';
     PATH_KERNEL = '\Processor Information(_Total)\% Privileged Time';
     PATH_GPU    = '\GPU Engine(*)\Utilization Percentage';
     PATH_PAGING = '\Memory\Pages Output/sec';
     PATH_DISK   = '\PhysicalDisk(*)\% Idle Time';

// Proc_ を、主スレッドで、Thread_ に結び付けて、後に回して呼ぶ（Thread_ の後始末で、まだ動いていなければ取り除かれる）。
// どのスレッドから呼んでも、その場では呼ばない（TThread.ForceQueue）。TProc を、積める型（TThreadProcedure）に包む
procedure Later( const Thread_:TThread; const Proc_:TProc );
begin
     TThread.ForceQueue( Thread_, procedure begin Proc_() end );
end;

function IsValid( const Status_:DWORD ) :Boolean;
begin
     Result := ( Status_ = PDH_CSTATUS_VALID_DATA ) or ( Status_ = PDH_CSTATUS_NEW_DATA );
end;

type
     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadSampler

     // 取る実行スレッド。PDH の問い合わせを、開くのも、取るのも、閉じるのも、このスレッド（問い合わせの持ち主は、このスレッドだけ）
     TLoadSampler = class( TThread )
     private
       _Owner  :TLoad;
       _Stop   :TEvent;                      // 止める合図（待ちを、すぐに抜ける）
       _Opened :TEvent;                      // 最初の 1 回を取り終えた（作る側が、これを待つ）
       _Query  :PDH_HQUERY;
       _User   :PDH_HCOUNTER;                // 足せなかったものは 0
       _Kernel :PDH_HCOUNTER;
       _GPU    :PDH_HCOUNTER;
       _Paging :PDH_HCOUNTER;
       _Disk   :PDH_HCOUNTER;
       _Prior  :Double;                      // 前に取り終えた時刻（ミリ秒）
       _Busy   :Int64;                       // 演算装置を使っていた時間の累計（100 ns）。_BusyAt に取ったもの
       _BusyAt :Double;                      // _Busy を取った時刻（ミリ秒。取れていなければ NaN）
       _Self   :String;                      // このプロセスの、描画装置のエンジンのインスタンスの名前の頭（pid_番号_）
       _Buffer :TBytes;                      // 整形した値の並びの置き場（使い回す）
       _Engine :TDictionary<String,Double>;  // エンジンごとの占有率（使い回す）
       ///// M E T H O D
       function Counter( const Path_:String ) :PDH_HCOUNTER;
       function Items( const Counter_:PDH_HCOUNTER ) :Integer;
       function Item( const I_:Integer ) :PPdhFmtItem;
       function BusyOf( out Busy_:Int64 ) :Boolean;
       procedure Open;
       procedure Sample( const Time_:Double );
     protected
       procedure Execute; override;
       procedure TerminatedSet; override;
     public
       constructor Create( const Owner_:TLoad );
       destructor Destroy; override;
       ///// P R O P E R T Y
       property Opened :TEvent read _Opened;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadTrace

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 平均の重みは、区間が範囲（0〜Elapse）に重なる長さ。範囲が長さ 0、または重なりがどれも長さ 0 なら、重なる区間の値の、ただの平均
constructor TLoadTrace.Create( const Series_:TLoadSeries; const Elapse_:Double );
var
   K :TLoadKind;
   S :TLoadSpan;
   W, WS, VS, PS :Double;
   N :Integer;
begin
     if not ( Elapse_ >= 0 ) then raise EArgumentOutOfRangeException.Create( '範囲の長さは、0 以上' );

     Elapse := Elapse_;

     for K := Low( TLoadKind ) to High( TLoadKind ) do
     begin
          Series[ K ] := Copy( Series_[ K ] );

          Stats[ K ] := Default( TLoadStat );

          WS := 0;  VS := 0;  PS := 0;  N := 0;
          for S in Series[ K ] do
          begin
               if ( S.Tail < 0 ) or ( S.Head > Elapse_ ) then Continue;

               W := Min( S.Tail, Elapse_ ) - Max( S.Head, 0 );

               WS := WS + W;
               VS := VS + W * S.Value;
               PS := PS + S.Value;

               if ( N = 0 ) or ( S.Value > Stats[ K ].Worst ) then Stats[ K ].Worst := S.Value;

               Inc( N );
          end;

          if N = 0 then Continue;

          Stats[ K ].Known := True;

          if WS > 0 then Stats[ K ].Mean := VS / WS
                    else Stats[ K ].Mean := PS / N;
     end;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

function TLoadTrace.Heavy( const Head_,Tail_:Double ) :Boolean;
var
   K :TLoadKind;
   S :TLoadSpan;
begin
     for K := Low( TLoadKind ) to High( TLoadKind ) do
     begin
          for S in Series[ K ] do
          begin
               if ( S.Tail >= Head_ ) and ( S.Head <= Tail_ ) and ( S.Value > LOAD_LINES[ K ] ) then Exit( True );
          end;
     end;

     Result := False;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadSampler

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

// 問い合わせに、英語の名前の値を足す。足せなければ 0（その値は、分からない）
function TLoadSampler.Counter( const Path_:String ) :PDH_HCOUNTER;
begin
     if PdhAddEnglishCounterW( _Query, PChar( Path_ ), 0, Result ) <> ERROR_SUCCESS then Result := 0;
end;

// 名前の * の値を、整形して _Buffer に並べ、その数を返す。値を出せなければ 0。
// 要る大きさは、毎回、大きさ 0 で問い合わせて知る（足りない大きさを渡したときに返る大きさは、当てにしない：PdhGetFormattedCounterArray の文書）。
// その間にインスタンスが増えれば、もう一度、問い合わせる
function TLoadSampler.Items( const Counter_:PDH_HCOUNTER ) :Integer;
var
   S, N, R :DWORD;
begin
     repeat
          S := 0;
          R := PdhGetFormattedCounterArrayW( Counter_, PDH_FORMAT, S, N, nil );

          if R <> PDH_MORE_DATA then Exit( 0 );  // 値を出せない（前の回と同じ時刻など）か、インスタンスが無い

          if Integer( S ) > Length( _Buffer ) then SetLength( _Buffer, S );

          S := Length( _Buffer );
          R := PdhGetFormattedCounterArrayW( Counter_, PDH_FORMAT, S, N, @_Buffer[ 0 ] );
     until R <> PDH_MORE_DATA;

     if R = ERROR_SUCCESS then Result := N
                          else Result := 0;
end;

function TLoadSampler.Item( const I_:Integer ) :PPdhFmtItem;
begin
     Result := PPdhFmtItem( @_Buffer[ I_ * SizeOf( TPdhFmtItem ) ] );
end;

// 演算装置を使っていた時間の累計（ユーザー モードと特権モードの和。100 ns）。どちらかを取れなければ偽
function TLoadSampler.BusyOf( out Busy_:Int64 ) :Boolean;
var
   U, K :TPdhRawCounter;
begin
     Result := ( _User <> 0 ) and ( _Kernel <> 0 )
           and ( PdhGetRawCounterValue( _User  , nil, U ) = ERROR_SUCCESS ) and IsValid( U.CStatus )
           and ( PdhGetRawCounterValue( _Kernel, nil, K ) = ERROR_SUCCESS ) and IsValid( K.CStatus );

     if Result then Busy_ := U.FirstValue + K.FirstValue;
end;

// 問い合わせを開き、最初の 1 回を取る（率の値は、2 回の差から出すので、最初の 1 回は、区間を作らない）
procedure TLoadSampler.Open;
var
   R :DWORD;
begin
     _Self := Format( 'pid_%d_', [ GetCurrentProcessId ] );

     R := PdhOpenQueryW( nil, 0, _Query );

     if R <> ERROR_SUCCESS then raise EOSError.CreateFmt( 'PdhOpenQuery が失敗した：$%.8x', [ R ] );

     _User   := Counter( PATH_USER   );
     _Kernel := Counter( PATH_KERNEL );
     _GPU    := Counter( PATH_GPU    );
     _Paging := Counter( PATH_PAGING );
     _Disk   := Counter( PATH_DISK   );

     R := PdhCollectQueryData( _Query );

     if R <> ERROR_SUCCESS then raise EOSError.CreateFmt( 'PdhCollectQueryData が失敗した：$%.8x', [ R ] );

     _Prior  := TLoad.Now;
     _BusyAt := NaN;

     if BusyOf( _Busy ) then _BusyAt := _Prior;
end;

// 1 回取り、前に取り終えた時刻から Time_ までの区間を、持ち主に渡す（値を出せなかった種類は NaN で渡し、区間を作らない）
procedure TLoadSampler.Sample( const Time_:Double );
var
   V :array [ TLoadKind ] of Double;
   H :array [ TLoadKind ] of Double;
   K :TLoadKind;
   B :Int64;
   F :TPdhFmtValue;
   Q :PPdhFmtItem;
   I, N, P :Integer;
   M :Double;
   E :String;
   T :TLoadKind;
   A :TPair<String,Double>;
begin
     for K := Low( TLoadKind ) to High( TLoadKind ) do
     begin
          V[ K ] := NaN;
          H[ K ] := _Prior;
     end;

     // 演算装置：使っていた時間の増え ÷ 経った時間（100 ns の単位を、ミリ秒に直す：1 ms ＝ 10000 × 100 ns）
     if BusyOf( B ) then
     begin
          if not IsNan( _BusyAt ) and ( Time_ > _BusyAt ) then
          begin
               V[ lkCPU ] := 100 * ( ( B - _Busy ) / 10000 ) / ( Time_ - _BusyAt );
               H[ lkCPU ] := _BusyAt;
          end;

          _Busy   := B;
          _BusyAt := Time_;
     end;

     // 描画装置：エンジンごとにプロセスを足し、種類ごとに、いちばん高いエンジン
     if _GPU <> 0 then
     begin
          _Engine.Clear;

          N := Items( _GPU );
          for I := 0 to N - 1 do
          begin
               Q := Item( I );

               if not IsValid( Q.Value.CStatus ) then Continue;

               E := Q.Name;

               if E.StartsWith( _Self ) then Continue;  // このプロセス自身の描画

               P := Pos( '_luid_', E );

               if P = 0 then Continue;

               E := Copy( E, P, MaxInt );

               if not _Engine.TryGetValue( E, M ) then M := 0;

               _Engine.AddOrSetValue( E, M + Q.Value.Value );
          end;

          for A in _Engine do
          begin
               E := Copy( A.Key, Pos( '_engtype_', A.Key ) + Length( '_engtype_' ), MaxInt );

               if E = '3D'   then T := lkGPU3D
               else
               if E = 'Copy' then T := lkGPUCopy
                             else T := lkGPUEtc;

               if IsNan( V[ T ] ) or ( A.Value > V[ T ] ) then V[ T ] := A.Value;
          end;
     end;

     // 退避の書き出し
     if ( _Paging <> 0 ) and ( PdhGetFormattedCounterValue( _Paging, PDH_FORMAT, nil, F ) = ERROR_SUCCESS ) and IsValid( F.CStatus ) then V[ lkPaging ] := F.Value;

     // ディスク：いちばん遊んでいない物理ディスク（_Total は、全部の平均なので、除く）
     if _Disk <> 0 then
     begin
          M := NaN;

          N := Items( _Disk );
          for I := 0 to N - 1 do
          begin
               Q := Item( I );

               if not IsValid( Q.Value.CStatus ) or ( String( Q.Name ) = '_Total' ) then Continue;

               if IsNan( M ) or ( Q.Value.Value < M ) then M := Q.Value.Value;
          end;

          if not IsNan( M ) then V[ lkDisk ] := 100 - M;
     end;

     _Owner.Post( Time_, V, H );

     _Prior := Time_;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

// 次に取る時刻は、前に取り終えた時刻の GAP 後（区間が、時計の割り込みの刻みより短くならない。待ちが延びれば、区間が延びるだけ）。
// 待ちは、高い分解能の待てるタイマー（CREATE_WAITABLE_TIMER_HIGH_RESOLUTION。Windows 10 1803 から）で行う：ふつうの待ち
// （WaitForSingleObject の待ち時間）は、時計の割り込みの刻みに丸められ、16 ms を頼むと、31 ms ほど待つことがある。
// このタイマーは、OS 全体の時計の設定（timeBeginPeriod）を変えない。待ちは、止める合図で、すぐに抜ける
procedure TLoadSampler.Execute;
var
   N, T :Double;
   W :THandle;
   D :TLargeInteger;
   H :array [ 0..1 ] of THandle;
begin
     try
          Open;
     except
          on X:Exception do
          begin
               if _Query <> 0 then PdhCloseQuery( _Query );

               _Owner.Fail( X.ClassName + '：' + X.Message );

               _Opened.SetEvent;

               Exit;
          end;
     end;

     _Opened.SetEvent;

     W := 0;
     try
          try
               W := CreateWaitableTimerExW( nil, nil, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_MODIFY_STATE or Winapi.Windows.SYNCHRONIZE );  // 名前だけでは TThread.Synchronize を指す

               if W = 0 then RaiseLastOSError;

               H[ 0 ] := _Stop.Handle;
               H[ 1 ] := W;

               N := _Prior + TLoad.GAP;

               while not Terminated do
               begin
                    T := TLoad.Now;

                    if T < N then
                    begin
                         D := -Ceil( ( N - T ) * 10000 );  // 負は、いまからの相対の時間（100 ns 単位）

                         if not SetWaitableTimer( W, D, 0, nil, nil, False ) then RaiseLastOSError;

                         if WaitForMultipleObjects( 2, @H, False, INFINITE ) = WAIT_FAILED then RaiseLastOSError;

                         Continue;
                    end;

                    if PdhCollectQueryData( _Query ) <> ERROR_SUCCESS then raise EOSError.Create( 'PdhCollectQueryData が失敗した' );

                    T := TLoad.Now;

                    Sample( T );

                    N := T + TLoad.GAP;
               end;
          except
               on X:Exception do _Owner.Fail( X.ClassName + '：' + X.Message );
          end;
     finally
          if W <> 0 then CloseHandle( W );

          PdhCloseQuery( _Query );
     end;
end;

procedure TLoadSampler.TerminatedSet;
begin
     inherited;

     _Stop.SetEvent;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TLoadSampler.Create( const Owner_:TLoad );
begin
     _Owner  := Owner_;
     _Stop   := TEvent.Create( nil, True, False, '' );
     _Opened := TEvent.Create( nil, True, False, '' );
     _Engine := TDictionary<String,Double>.Create;

     inherited Create( False );
end;

destructor TLoadSampler.Destroy;
begin
     inherited;  // スレッドを止めて待ち、このスレッドに結び付けて積んだ知らせを取り除く（TThread.ShutdownThread）

     _Engine.Free;
     _Opened.Free;
     _Stop.Free;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoad

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

// 最後に取った区間の値が、どの種類も線以下か（区間がまだ無い種類は、見ない）。_Lock の中で呼ぶ
function TLoad.IsCalm :Boolean;
var
   K :TLoadKind;
   L :TList<TLoadSpan>;
begin
     for K := Low( TLoadKind ) to High( TLoadKind ) do
     begin
          L := _Series[ K ];

          if ( L.Count > 0 ) and ( L.Last.Value > LOAD_LINES[ K ] ) then Exit( False );
     end;

     Result := True;
end;

// 取る実行スレッドから：区間を足し、条件の満たされた知らせを、主スレッドへ積む。Values_ の NaN は、その種類の区間を作らない
procedure TLoad.Post( const Time_:Double; const Values_:array of Double; const Heads_:array of Double );
var
   K :TLoadKind;
   S :TLoadSpan;
   F :TList<TProc>;
   I :Integer;
   P :TProc;
begin
     F := TList<TProc>.Create;
     try
          _Lock.Enter;
          try
               for K := Low( TLoadKind ) to High( TLoadKind ) do
               begin
                    if IsNan( Values_[ Ord( K ) ] ) then Continue;

                    S.Head  := Heads_[ Ord( K ) ];
                    S.Tail  := Time_;
                    S.Value := Values_[ Ord( K ) ];

                    _Series[ K ].Add( S );
               end;

               _Reach := Time_;

               for I := _Awaits.Count - 1 downto 0 do
               begin
                    if _Awaits[ I ].Key <= _Reach then
                    begin
                         F.Add( _Awaits[ I ].Value );

                         _Awaits.Delete( I );
                    end;
               end;

               if IsCalm then
               begin
                    F.AddRange( _Calms );

                    _Calms.Clear;
               end;
          finally
               _Lock.Leave;
          end;

          for P in F do Later( _Sampler, P );
     finally
          F.Free;
     end;
end;

// 取る実行スレッドから：誤りを残し、待っている知らせを、すべて積む（知らせを受けた側の Trace が、誤りを例外にする）
procedure TLoad.Fail( const Fault_:String );
var
   F :TList<TProc>;
   A :TPair<Double,TProc>;
   P :TProc;
begin
     F := TList<TProc>.Create;
     try
          _Lock.Enter;
          try
               _Fault := Fault_;
               _Reach := Infinity;

               for A in _Awaits do F.Add( A.Value );

               F.AddRange( _Calms );

               _Awaits.Clear;
               _Calms .Clear;
          finally
               _Lock.Leave;
          end;

          for P in F do Later( _Sampler, P );
     finally
          F.Free;
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TLoad.Create;
var
   K :TLoadKind;
   S :TLoadSampler;
begin
     inherited;

     _Lock   := TCriticalSection.Create;
     _Awaits := TList<TPair<Double,TProc>>.Create;
     _Calms  := TList<TProc>.Create;
     _Reach  := -Infinity;

     for K := Low( TLoadKind ) to High( TLoadKind ) do _Series[ K ] := TList<TLoadSpan>.Create;

     // 最初の 1 回を取り終えるまで待つ：これより後の時刻は、どれも、区間に覆われる
     S := TLoadSampler.Create( Self );

     _Sampler := S;

     S.Opened.WaitFor( INFINITE );

     if _Fault <> '' then raise EOSError.Create( '負荷を取り始められない：' + _Fault );
end;

destructor TLoad.Destroy;
var
   K :TLoadKind;
begin
     _Sampler.Free;  // 止めて待つ。まだ動いていない知らせは、取り除かれる

     for K := Low( TLoadKind ) to High( TLoadKind ) do _Series[ K ].Free;

     _Calms .Free;
     _Awaits.Free;
     _Lock  .Free;

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

class function TLoad.Now :Double;
begin
     Result := TStopwatch.GetTimeStamp / TStopwatch.Frequency * 1000;
end;

function TLoad.Trace( const Head_,Tail_:Double ) :TLoadTrace;
var
   R :TLoadSeries;
   K :TLoadKind;
   S :TLoadSpan;
   I0, I :Integer;
begin
     if Tail_ < Head_ then raise EArgumentException.Create( '範囲の終わりが、始めより前' );

     _Lock.Enter;
     try
          if _Fault <> '' then raise EOSError.Create( '負荷を取る処理が止まった：' + _Fault );

          for K := Low( TLoadKind ) to High( TLoadKind ) do
          begin
               R[ K ] := [];

               // 時刻の順に並んでいるので、後ろから、範囲より前の区間に来るまで見る
               I0 := _Series[ K ].Count;
               while ( I0 > 0 ) and ( _Series[ K ][ I0 - 1 ].Tail >= Head_ ) do Dec( I0 );

               for I := I0 to _Series[ K ].Count - 1 do
               begin
                    S := _Series[ K ][ I ];

                    if S.Head > Tail_ then Break;

                    S.Head := S.Head - Head_;
                    S.Tail := S.Tail - Head_;

                    R[ K ] := R[ K ] + [ S ];
               end;
          end;
     finally
          _Lock.Leave;
     end;

     Result := TLoadTrace.Create( R, Tail_ - Head_ );
end;

procedure TLoad.Await( const Time_:Double; const Proc_:TProc );
var
   D :Boolean;
begin
     _Lock.Enter;
     try
          D := _Reach >= Time_;

          if not D then _Awaits.Add( TPair<Double,TProc>.Create( Time_, Proc_ ) );
     finally
          _Lock.Leave;
     end;

     if D then Later( _Sampler, Proc_ );
end;

procedure TLoad.Calm( const Proc_:TProc );
var
   D :Boolean;
begin
     _Lock.Enter;
     try
          D := ( _Fault <> '' ) or IsCalm;

          if not D then _Calms.Add( Proc_ );
     finally
          _Lock.Leave;
     end;

     if D then Later( _Sampler, Proc_ );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
