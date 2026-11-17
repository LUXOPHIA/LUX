unit Tests.FMX.Motion;

// LUX.FMX.Motion の、引っかかりの割合の計算（TMotionPace.Create）・1 つずつ測る排他（TMotionLock）・画面を使わない
// 1 回の更新の仕事の時間（TMotionCost）・素の窓との比べの判定（TMotionVersus）・負荷の重い区間による無効と測り直し
// （TMotionPace.Valid・TMotionProbe.Settle）の試験
//
//【窓を出さない】
// ・負荷の重い区間は、作った負荷の並び（TLoadTrace）で与える。Settle は、本物の TLoad（窓を出さない）の Calm を待ち、
//   測る手続きの代わりに、作った結果を順に返す。
// ・作った時点の並びと周期から、結果を計算させて、手で数えた値と比べる。
// ・TMotionCost.Measure は、見せないフォームで測る（窓を画面に出さない）。
// ・排他は、試験ごとに GUID の入った名前で作る（本物の試験が握る NAME_DEFAULT には、触れない）。
//   ほかのスレッド・プロセスが握っている間、握れないことは、決めた時間（BLOCK_MS）のうちに握れないことで確かめる。

interface //#################################################################### ■

uses System.Types,
     DUnitX.TestFramework,
     FMX.Graphics;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionPaceTests

     [TestFixture]
     TMotionPaceTests = class
     private
     public
       [Test] procedure EveryPeriod;
       [Test] procedure Jitter;
       [Test] procedure LateUpdates;
       [Test] procedure OneAndHalf;
       [Test] procedure NoUpdate;
       [Test] procedure PassLine;
       [Test] procedure BadInput;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionLockTests

     [TestFixture]
     TMotionLockTests = class
     private
       _Name :String;
     public
       [Setup] procedure Setup;
       [Test] procedure OneThreadAtATime;
       [Test] procedure DeadProcessReleases;
       [Test] procedure OwnerOnly;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionCostTests

     [TestFixture]
     TMotionCostTests = class
     private
       _PaintsN :Integer;
       procedure FormPaint( Sender_:TObject; Canvas_:TCanvas; const ARect_:TRectF );
     public
       [Test] procedure Figures;
       [Test] procedure HiddenForm;
       [Test] procedure Verdicts;
       [Test] procedure HiddenVersus;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionVersusTests

     [TestFixture]
     TMotionVersusTests = class
     public
       [Test] procedure Verdicts;
       [Test] procedure Rounds;
       [Test] procedure ScreenClosed;
       [Test] procedure ShotsFigures;
       [Test] procedure ShotsVerdicts;
       [Test] procedure ApartHidden;
       [Test] procedure ExposedInside;
       [Test] procedure ExposedOutside;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionLoadTests

     [TestFixture]
     TMotionLoadTests = class
     public
       [Test] procedure HeavyGaps;
       [Test] procedure VoidVerdict;
       [Test] procedure SettleRetakes;
       [Test] procedure SettleGivesUp;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Classes, System.Math,
     Winapi.Windows,
     Winapi.DwmApi,
     FMX.Forms, FMX.Platform.Win,
     LUX.Windows.Monitor, LUX.Windows.Load, LUX.FMX.Motion,
     Tests.Peer;

const
     TOL      = 1E-9;   // 比べるときの許し（ミリ秒）
     BLOCK_MS = 300;    // 握れないことを確かめるために待つ時間（ミリ秒）
     DONE_MS  = 10000;  // 握れることを確かめるために待つ、上限の時間（ミリ秒）

// 周期 Period_ の刻みで、1000 ミリ秒の間、毎回描いた時点の並び（始め 0・終わり 1000）から、Skip_ 番目の更新だけを抜いたもの
function Steady( const Period_:Double; const Skip_:Integer ) :TArray<Double>;
var
   I, N :Integer;
begin
     N := Round( 1000 / Period_ );

     Result := [];
     for I := 0 to N do
     begin
          if I <> Skip_ then Result := Result + [ I * Period_ ];
     end;
end;

// 負荷の区間が 1 つも無い並び（どの種類も分からない：重い間は無い）
function Quiet :TLoadTrace;
begin
     Result := TLoadTrace.Create( Default( TLoadSeries ), 0 );
end;

// 演算装置の区間を 1 つだけ持つ並び
function OneSpan( const Head_,Tail_,Value_:Double ) :TLoadTrace;
var
   S :TLoadSeries;
   P :TLoadSpan;
begin
     P.Head  := Head_;
     P.Tail  := Tail_;
     P.Value := Value_;

     S := Default( TLoadSeries );
     S[ lkCPU ] := [ P ];

     Result := TLoadTrace.Create( S, 100 );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionPaceTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 120 Hz の周期ごとに更新が出れば、引っかかりは無い
procedure TMotionPaceTests.EveryPeriod;
var
   P :Double;
   T :TArray<Double>;
   I :Integer;
   R :TMotionPace;
begin
     P := 1000 / 120;

     SetLength( T, 121 );
     for I := 0 to 120 do T[ I ] := I * P;

     R := TMotionPace.Create( T, P, Quiet );

     Assert.AreEqual( 119, R.UpdatesN );
     Assert.AreEqual( 1000.0, R.Elapse, 1E-6 );
     Assert.AreEqual( P, R.Period, TOL );
     Assert.AreEqual( 0.0, R.Hitch, 1E-6, '周期どおり' );
     Assert.AreEqual( 0.0, R.Ratio, 1E-6 );
     Assert.AreEqual( 0, R.Over60N );
end;

// 描いた時刻の間隔が、周期の前後に揺れているだけ（9.0・7.6 の繰り返し。平均は周期より短い）なら、どの更新も、
// 次の画面の更新に間に合っているので、引っかかりは無い。最初の更新を、始めから 8.0 ミリ秒の所に置く
// （始めを画面の更新の時刻とみなすと、2 つ目の更新が、刻みを 1 つ飛ばしたように見える置き方）
procedure TMotionPaceTests.Jitter;
var
   T :TArray<Double>;
   X :Double;
   I :Integer;
   R :TMotionPace;
begin
     X := 8.0;
     T := [ 0, X ];
     for I := 1 to 100 do
     begin
          if Odd( I ) then X := X + 9.0
                      else X := X + 7.6;

          T := T + [ X ];
     end;
     T := T + [ X + 1 ];

     R := TMotionPace.Create( T, 1000 / 120, Quiet );

     Assert.AreEqual( 9.0, R.Worst, 1E-6 );
     Assert.AreEqual( 0.0, R.Hitch, 1E-6, '周期の前後の揺れは、引っかかりではない' );
     Assert.AreEqual( 0.0, R.Ratio, 1E-6 );
end;

// 飛ばした画面の更新の数 × 周期が、引っかかり
procedure TMotionPaceTests.LateUpdates;
var
   R :TMotionPace;
begin
     // 周期 10。間隔：10・10・25・10・45 → 25 の所で 1 つ（位相によっては 2 つ）、45 の所で 4 つ（位相によっては 3 つ）飛ばす。
     // どの位相でも、合わせて 5 つ → 50 ミリ秒、全体 100 ミリ秒 → 500 ms/s
     R := TMotionPace.Create( [ 0, 10, 20, 45, 55, 100 ], 10, Quiet );

     Assert.AreEqual( 4, R.UpdatesN );
     Assert.IsTrue( Length( R.Gaps ) = 5, '間隔は、時点の数 − 1' );
     Assert.AreEqual( 25.0, R.Gaps[ 2 ], TOL );
     Assert.AreEqual( 45.0, R.Worst, TOL );
     Assert.AreEqual( 50.0, R.Hitch, TOL );
     Assert.AreEqual( 100.0, R.Elapse, TOL );
     Assert.AreEqual( 500.0, R.Ratio, TOL );
     Assert.AreEqual( 2, R.Over60N, '1/60 秒を超えた：25・45' );
     Assert.AreEqual( 1, R.Over30N, '1/30 秒を超えた：45' );

     // 周期より短い間隔（同じ画面の更新に、2 つ入った）と、周期の 1.4 倍の間隔は、位相が合えば、どれも飛ばさない
     R := TMotionPace.Create( [ 0, 3, 6, 20 ], 10, Quiet );

     Assert.AreEqual( 0.0, R.Hitch, TOL );
end;

// 周期の 1.5 倍おきに描けば、どの位相でも、2 つに 1 つの間隔で、画面の更新を 1 つ飛ばす
procedure TMotionPaceTests.OneAndHalf;
var
   T :TArray<Double>;
   I :Integer;
   R :TMotionPace;
begin
     SetLength( T, 11 );
     for I := 0 to 10 do T[ I ] := I * 15;

     R := TMotionPace.Create( T, 10, Quiet );

     Assert.AreEqual( 50.0, R.Hitch, TOL, '10 の間隔のうち 5 つで、1 つずつ飛ばす' );
     Assert.AreEqual( 50 / 0.150, R.Ratio, 1E-6 );
end;

// 更新が 1 度も無ければ、始めから終わりまでの画面の更新を、ほぼ全部飛ばした
procedure TMotionPaceTests.NoUpdate;
var
   P :Double;
   R :TMotionPace;
begin
     P := 1000 / 60;

     // 995 ミリ秒は 59.7 周期。いちばん間に合う位相で、始めの後の 1 つと、終わりの 1 つの間の 58 を飛ばした
     R := TMotionPace.Create( [ 0, 995 ], P, Quiet );

     Assert.AreEqual( 0, R.UpdatesN );
     Assert.AreEqual( 58 * P, R.Hitch, 1E-6 );
     Assert.IsFalse( R.Ratio < TMotionPace.HITCH_LIMIT );
end;

// 合格の線：1 秒に、画面の更新を 1 つだけ飛ばしたとき、周期 4 ミリ秒（4 ms/s）は合格、周期 5 ミリ秒（5 ms/s）は不合格（5 未満が合格）
procedure TMotionPaceTests.PassLine;
var
   R :TMotionPace;
begin
     Assert.AreEqual( 5, TMotionPace.HITCH_LIMIT );

     R := TMotionPace.Create( Steady( 4, 125 ), 4, Quiet );

     Assert.AreEqual( 4.0, R.Hitch, 1E-6 );
     Assert.IsTrue( R.Ratio < TMotionPace.HITCH_LIMIT, Format( '%.3f ms/s は合格', [ R.Ratio ] ) );

     R := TMotionPace.Create( Steady( 5, 100 ), 5, Quiet );

     Assert.AreEqual( 5.0, R.Hitch, 1E-6 );
     Assert.AreEqual( 5.0, R.Ratio, 1E-6 );
     Assert.IsFalse( R.Ratio < TMotionPace.HITCH_LIMIT, Format( '%.3f ms/s は不合格', [ R.Ratio ] ) );
end;

// 計算できない入力は、その場で止める
procedure TMotionPaceTests.BadInput;
var
   R :TMotionPace;
begin
     Assert.WillRaise( procedure begin R := TMotionPace.Create( [ 0 ], 10, Quiet ); end, EArgumentException, '時点が 1 つ' );
     Assert.WillRaise( procedure begin R := TMotionPace.Create( [ 0, 10 ], 0, Quiet ); end, EArgumentOutOfRangeException, '周期が 0' );
     Assert.WillRaise( procedure begin R := TMotionPace.Create( [ 0, 10, 5 ], 10, Quiet ); end, EArgumentException, '時刻の順でない' );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionLockTests

// 名前 Name_ の排他を、別のスレッドで握り、握ったら Got_ を立て、Free_ が立つまで握ってから放す
function Holder( const Name_:String; const Got_,Free_:THandle ) :TThread;
begin
     Result := TThread.CreateAnonymousThread( procedure
     var
        L :TMotionLock;
     begin
          L := TMotionLock.Create( Name_ );
          try
               L.Acquire;

               SetEvent( Got_ );

               WaitForSingleObject( Free_, INFINITE );

               L.Release;
          finally
               L.Free;
          end;
     end );

     Result.FreeOnTerminate := False;
     Result.Start;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

procedure TMotionLockTests.Setup;
begin
     _Name := 'Local\LUX.Test.MotionLock.' + TGUID.NewGuid.ToString.Trim( [ '{', '}' ] );
end;

// 2 つのスレッドが同時に握ろうとしても、後のものは、先のものが放すまで握れない
procedure TMotionLockTests.OneThreadAtATime;
var
   GA, FA, GB, FB :THandle;
   A, B :TThread;
begin
     GA := CreateEvent( nil, True, False, nil );  FA := CreateEvent( nil, True, False, nil );
     GB := CreateEvent( nil, True, False, nil );  FB := CreateEvent( nil, True, False, nil );
     try
          A := Holder( _Name, GA, FA );
          try
               Assert.AreEqual( WAIT_OBJECT_0, WaitForSingleObject( GA, DONE_MS ), '先のスレッドが握った' );

               B := Holder( _Name, GB, FB );
               try
                    Assert.AreEqual( WAIT_TIMEOUT, WaitForSingleObject( GB, BLOCK_MS ), '先のものが握っている間、後のものは握れない' );

                    SetEvent( FA );

                    Assert.AreEqual( WAIT_OBJECT_0, WaitForSingleObject( GB, DONE_MS ), '先のものが放したら、後のものが握る' );
               finally
                    SetEvent( FB );  B.WaitFor;  B.Free;
               end;
          finally
               SetEvent( FA );  A.WaitFor;  A.Free;
          end;
     finally
          CloseHandle( GA );  CloseHandle( FA );  CloseHandle( GB );  CloseHandle( FB );
     end;
end;

// 握ったプロセスが、放さずに落ちたら、待っていたものが握る（放棄された mutex）
procedure TMotionLockTests.DeadProcessReleases;
var
   P, G, F :THandle;
   B :TThread;
begin
     P := TTestPeer.Hold( _Name, DONE_MS );
     try
          G := CreateEvent( nil, True, False, nil );  F := CreateEvent( nil, True, False, nil );
          try
               B := Holder( _Name, G, F );
               try
                    Assert.AreEqual( WAIT_TIMEOUT, WaitForSingleObject( G, BLOCK_MS ), 'ほかのプロセスが握っている間は、握れない' );

                    TerminateProcess( P, 1 );

                    Assert.AreEqual( WAIT_OBJECT_0, WaitForSingleObject( G, DONE_MS ), '握ったプロセスが落ちたら、握れる' );
               finally
                    SetEvent( F );  B.WaitFor;  B.Free;
               end;
          finally
               CloseHandle( G );  CloseHandle( F );
          end;
     finally
          TerminateProcess( P, 1 );  WaitForSingleObject( P, DONE_MS );  CloseHandle( P );
     end;
end;

// 握ったスレッドでは、重ねて握っても 1 度で、ほかのスレッドからは放せない
procedure TMotionLockTests.OwnerOnly;
var
   L :TMotionLock;
   E :Boolean;
   T :TThread;
begin
     L := TMotionLock.Create( _Name );
     try
          Assert.IsFalse( L.Held );

          L.Acquire;
          L.Acquire;

          Assert.IsTrue( L.Held );

          E := False;
          T := TThread.CreateAnonymousThread( procedure
          begin
               try
                    L.Release;
               except
                    on EInvalidOpException do E := True;
               end;
          end );
          T.FreeOnTerminate := False;
          T.Start;
          T.WaitFor;
          T.Free;

          Assert.IsTrue( E, 'ほかのスレッドからは、放せない' );
          Assert.IsTrue( L.Held );

          L.Release;

          Assert.IsFalse( L.Held );
     finally
          L.Free;
     end;

     Assert.AreEqual( 'Local\LUXOPHIA.MotionProbe', TMotionLock.NAME_DEFAULT );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionCostTests

// 周期 Period_ ミリ秒で 1000 ミリ秒の間、毎回描いた時点の並びから、始めの後の Skip_ 個の更新を抜いた結果（引っかかりは、Period_ × Skip_ ms/s）
function Paced( const Period_:Double; const Skip_:Integer ) :TMotionPace;
var
   T :TArray<Double>;
   I, N :Integer;
begin
     N := Round( 1000 / Period_ );

     T := [];
     for I := 0 to N do
     begin
          if ( I = 0 ) or ( I = N ) or ( I > Skip_ ) then T := T + [ I * Period_ ];  // 1..Skip_ 番の更新を抜く
     end;

     Result := TMotionPace.Create( T, Period_, Quiet );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

procedure TMotionCostTests.FormPaint( Sender_:TObject; Canvas_:TCanvas; const ARect_:TRectF );
begin
     Inc( _PaintsN );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 平均・いちばん悪い値・予算（周期の半分）・合否（平均が予算以内。いちばん悪い 1 歩は、割り込みを拾うので、合否に使わない）
procedure TMotionCostTests.Figures;
var
   C :TMotionCost;
begin
     C := TMotionCost.Create( [ 1, 2, 3, 6 ], 8 );

     Assert.AreEqual( 3.0, C.Mean  , TOL );
     Assert.AreEqual( 6.0, C.Worst , TOL );
     Assert.AreEqual( 4.0, C.Budget, TOL );
     Assert.IsTrue( C.Passed, '平均 3 は、予算 4 以内（いちばん悪い 6 は、記録だけ）' );
     Assert.IsTrue( Length( C.Costs ) = 4 );

     C := TMotionCost.Create( [ 3, 4, 5 ], 8 );

     Assert.IsTrue( C.Passed, '平均ちょうど予算は、合格' );

     C := TMotionCost.Create( [ 4, 4, 5 ], 8 );

     Assert.IsFalse( C.Passed, '平均が予算を超えた' );

     Assert.WillRaise( procedure begin C := TMotionCost.Create( [], 8 ); end, EArgumentException, '時間が無い' );
     Assert.WillRaise( procedure begin C := TMotionCost.Create( [ 1 ], 0 ); end, EArgumentOutOfRangeException, '周期が 0' );
end;

// 見せないフォームで、歩ごとに、並べ直しと描画（フォームの OnPaint が 1 回ずつ）が行われ、窓は画面に出ない
procedure TMotionCostTests.HiddenForm;
var
   F :TForm;
   C :TMotionCost;
begin
     F := TForm.CreateNew( nil );
     try
          F.SetBoundsF( 0, 0, 400, 300 );
          F.OnPaint := FormPaint;

          _PaintsN := 0;

          C := TMotionCost.Measure( F, 20, procedure( const I_:Integer ) begin F.SetBoundsF( 0, 0, 400 + 4 * I_, 300 ) end );

          Assert.IsTrue( Length( C.Costs ) = 20, '歩ごとの時間' );
          Assert.AreEqual( 20, _PaintsN, '歩ごとに 1 回描いた' );
          Assert.AreEqual( TWinMonitor.MinPeriod * 1000 / 2, C.Budget, 1E-9, '予算は、いちばん短い周期の半分' );
          Assert.IsTrue( MinValue( C.Costs ) >= 0 );
          Assert.IsFalse( IsWindowVisible( FormToHWND( F ) ), '窓は画面に出ない' );

     finally
          F.Free;
     end;
end;

// 平均が予算以内なら合格。超えても、素の窓の平均 ＋ 予算の 1 割以内なら枠組みの限界。それより悪ければ、自分の側の原因
procedure TMotionCostTests.Verdicts;
var
   V :TMotionCostVersus;
begin
     // 周期 8 → 予算 4、許し 0.4
     V := TMotionCostVersus.Create( TMotionCost.Create( [ 3, 3 ], 8 ), TMotionCost.Create( [ 1, 1 ], 8 ) );
     Assert.IsTrue( V.Verdict = mvPassed, '平均 3 は合格' );

     V := TMotionCostVersus.Create( TMotionCost.Create( [ 5, 5 ], 8 ), TMotionCost.Create( [ 4.8, 4.8 ], 8 ) );
     Assert.IsTrue( V.Verdict = mvLimit, '平均 5・素の窓 4.8：上乗せ 0.2 は、限界' );

     V := TMotionCostVersus.Create( TMotionCost.Create( [ 5, 5 ], 8 ), TMotionCost.Create( [ 4.5, 4.5 ], 8 ) );
     Assert.IsTrue( V.Verdict = mvOwnCause, '平均 5・素の窓 4.5：上乗せ 0.5 は、自分の側の原因' );

     Assert.AreEqual( 0.4, V.Margin, TOL, '許しは、予算の 1 割' );
end;

// 見せないアプリの窓と素の窓で、同じ歩を続けて測る（どちらも、画面に出さない）
procedure TMotionCostTests.HiddenVersus;
var
   A, B :TForm;
   V :TMotionCostVersus;
begin
     A := TForm.CreateNew( nil );
     B := TForm.CreateNew( nil );
     try
          A.SetBoundsF( 0, 0, 400, 300 );
          B.SetBoundsF( 0, 0, 400, 300 );

          V := TMotionCostVersus.Measure( A, B, 10, procedure( const F_:TCustomForm; const I_:Integer ) begin F_.SetBoundsF( 0, 0, 400 + 4 * I_, 300 ) end );

          Assert.IsTrue( Length( V.App .Costs ) = 10 );
          Assert.IsTrue( Length( V.Base.Costs ) = 10 );
          Assert.AreEqual( 400.0 + 4 * 9, Double( B.Width ), 1E-6, '素の窓にも、同じ歩を与えた' );
          Assert.IsFalse( IsWindowVisible( FormToHWND( A ) ) or IsWindowVisible( FormToHWND( B ) ), '窓は画面に出ない' );
     finally
          B.Free;
          A.Free;
     end;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionVersusTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 組になった回の並び（周期 4 ミリ秒で、刻みを n 個飛ばすと 4n ms/s）
function Paces( const Skips_:array of Integer ) :TArray<TMotionPace>;
var
   I :Integer;
begin
     SetLength( Result, Length( Skips_ ) );
     for I := 0 to High( Skips_ ) do Result[ I ] := Paced( 4, Skips_[ I ] );
end;

// アプリの中央の値が基準未満なら合格。そうでなく、素の窓の回のいちばん大きい値以下なら枠組みの限界。それより悪ければ、自分の側の原因
procedure TMotionVersusTests.Verdicts;
var
   V :TMotionVersus;
begin
     V := TMotionVersus.Create( Paces( [ 1, 2, 1 ] ), Paces( [ 0, 0, 0 ] ) );
     Assert.AreEqual( 4.0, V.AppMid, 1E-6 );
     Assert.IsTrue( V.Verdict = mvPassed, '中央 4 ms/s は合格（8 の回があっても）' );

     V := TMotionVersus.Create( Paces( [ 3, 3, 4 ] ), Paces( [ 1, 4, 2 ] ) );
     Assert.AreEqual( 3, V.PairsN );
     Assert.AreEqual( 12.0, V.AppMid , 1E-6 );
     Assert.AreEqual(  8.0, V.BaseMid, 1E-6 );
     Assert.AreEqual(  4.0, V.BaseMin, 1E-6 );
     Assert.AreEqual( 16.0, V.BaseMax, 1E-6 );
     Assert.AreEqual( 16.0, V.Apps[ 2 ].Ratio, 1E-6, '回ごとの値' );
     Assert.IsTrue( V.Verdict = mvLimit, '中央 12・素の窓 4〜16：素の窓の揺れの内は、限界' );

     V := TMotionVersus.Create( Paces( [ 4, 4, 4 ] ), Paces( [ 1, 4, 2 ] ) );
     Assert.IsTrue( V.Verdict = mvLimit, '中央 16・素の窓の最大 16：ちょうどは、限界' );

     V := TMotionVersus.Create( Paces( [ 5, 5, 5 ] ), Paces( [ 1, 4, 2 ] ) );
     Assert.IsTrue( V.Verdict = mvOwnCause, '中央 20・素の窓の最大 16：自分の側の原因' );

     Assert.WillRaise( procedure begin V := TMotionVersus.Create( Paces( [ 1, 2 ] ), Paces( [ 0 ] ) ); end, EArgumentException, '組の数がそろわない' );
end;

// 交互に 3 組、1 回 1 秒（全体で 6 秒）
procedure TMotionVersusTests.Rounds;
begin
     Assert.AreEqual( 3, TMotionVersus.ROUNDS );
     Assert.AreEqual( 1, TMotionVersus.ROUND_SECONDS );
     Assert.AreEqual( 6, 2 * TMotionVersus.ROUNDS * TMotionVersus.ROUND_SECONDS, '全体の長さ（秒）' );
end;
// 画面が使えなかった測定は、更新の間隔が整っていても無効で、比べは判定しない
procedure TMotionVersusTests.ScreenClosed;
var
   R :TMotionPace;
begin
     R := TMotionPace.Create( [ 0, 10, 20, 30 ], 10, Quiet, False );

     Assert.AreEqual( 0.0, R.Ratio, TOL );
     Assert.IsFalse( R.Shown );
     Assert.IsFalse( R.Valid, '画面が使えなかった' );
     Assert.IsTrue( TMotionVersus.Create( [ R, R, Paced( 4, 0 ) ], Paces( [ 0, 0, 0 ] ) ).Verdict = mvVoid, '有効な組が 1 つ：判定しない' );
     Assert.IsTrue( TMotionVersus.Create( [ R, Paced( 4, 0 ), Paced( 4, 0 ) ], Paces( [ 0, 0, 0 ] ) ).PairsN = 2, '無効な回の組は、除く' );

     Assert.IsTrue( TMotionPace.Create( [ 0, 10, 20, 30 ], 10, Quiet ).Shown, '渡さなければ、画面は使えた' );
end;

// 割合と、有効か（画面が使えて、写し取りの失敗が無く、コマがある）
procedure TMotionVersusTests.ShotsFigures;
var
   S :TMotionShots;
begin
     S := TMotionShots.Create( 200, 5, 0, 0, 1500, True );
     Assert.AreEqual( 0.025, S.Rate, TOL );
     Assert.IsTrue( S.Valid );

     Assert.IsFalse( TMotionShots.Create( 70000, 0, 1, 0, 1500, True ).Valid, '写し取りに 1 度でも失敗' );
     Assert.IsFalse( TMotionShots.Create( 200, 0, 0, 1, 1500, True ).Valid, 'ほかの窓が 1 度でもかぶさった' );
     Assert.IsFalse( TMotionShots.Create( 200, 0, 0, 0, 1500, False ).Valid, '画面が使えなかった' );
     Assert.IsFalse( TMotionShots.Create( 0, 0, 0, 0, 0, True ).Valid, 'コマが無い' );
     Assert.AreEqual( 0.0, TMotionShots.Create( 0, 0, 0, 0, 0, True ).Rate, TOL );
end;

// 組になった回の並び（1000 コマのうち、当てはまったコマの数）
function Shots( const Bads_:array of Integer ) :TArray<TMotionShots>;
var
   I :Integer;
begin
     SetLength( Result, Length( Bads_ ) );
     for I := 0 to High( Bads_ ) do Result[ I ] := TMotionShots.Create( 1000, Bads_[ I ], 0, 0, 1000, True );
end;

// 中央の値が 0 なら合格。素の窓の回のいちばん大きい値以下なら限界。それより悪ければ自分の側の原因。測れていない回・
// 全部のコマが当てはまった回（窓が見えていないのと区別できない）の組は除き、有効な組が 2 つ未満なら判定しない
procedure TMotionVersusTests.ShotsVerdicts;
var
   V :TMotionShotsVersus;
begin
     Assert.IsTrue( TMotionShotsVersus.Create( Shots( [ 0, 0, 10 ] ), Shots( [ 30, 30, 30 ] ) ).Verdict = mvPassed, '中央 0%' );

     V := TMotionShotsVersus.Create( Shots( [ 40, 45, 50 ] ), Shots( [ 30, 60, 43 ] ) );
     Assert.AreEqual( 0.045, V.AppMid , TOL );
     Assert.AreEqual( 0.060, V.BaseMax, TOL );
     Assert.IsTrue( V.Verdict = mvLimit, '中央 4.5%・素の窓 3〜6%：限界' );

     Assert.IsTrue( TMotionShotsVersus.Create( Shots( [ 80, 80, 80 ] ), Shots( [ 30, 60, 43 ] ) ).Verdict = mvOwnCause, '中央 8%・素の窓の最大 6%：自分の側の原因' );
     Assert.IsTrue( TMotionShotsVersus.Create( Shots( [ 1000, 1000, 1000 ] ), Shots( [ 1000, 1000, 1000 ] ) ).Verdict = mvVoid, 'どちらも 100%：同じ程度と取り違えない' );
     Assert.IsTrue( TMotionShotsVersus.Create( Shots( [ 50, 50, 50 ] ), Shots( [ 1000, 1000, 30 ] ) ).Verdict = mvVoid, '素の窓が 2 回 100%：有効な組が 1 つ' );

     V := TMotionShotsVersus.Create( [ TMotionShots.Create( 1000, 0, 1, 0, 1000, True ), TMotionShots.Create( 1000, 0, 0, 1, 1000, True ), TMotionShots.Create( 1000, 0, 0, 0, 1000, True ) ], Shots( [ 0, 0, 0 ] ) );
     Assert.AreEqual( 1, V.PairsN, '写し取りの失敗・かぶさりの回の組は、除く' );
     Assert.IsTrue( V.Verdict = mvVoid );
end;
// 窓の見える枠（DWMWA_EXTENDED_FRAME_BOUNDS）
function FrameOf( const F_:TCustomForm ) :TRect;
begin
     Assert.IsTrue( Succeeded( DwmGetWindowAttribute( FormToHWND( F_ ), DWMWA_EXTENDED_FRAME_BOUNDS, @Result, SizeOf( Result ) ) ), '見える枠を読めた' );
end;

// 見せない 2 つの窓で：重なっていれば、素の窓を、同じモニターの重ならない所へ移す。見える枠が接しているだけなら、動かさない
procedure TMotionVersusTests.ApartHidden;
var
   A, B :TForm;
   VA, VB, V :TRect;
begin
     A := TForm.CreateNew( nil );
     B := TForm.CreateNew( nil );
     try
          A.SetBoundsF( 100, 100, 400, 300 );
          B.SetBoundsF( 150, 150, 400, 300 );

          TMotionProbe.Apart( A, B );

          VA := FrameOf( A );
          VB := FrameOf( B );

          Assert.IsFalse( VA.IntersectsWith( VB ), Format( '重ならない：(%d,%d,%d,%d)・(%d,%d,%d,%d)', [ VA.Left, VA.Top, VA.Right, VA.Bottom, VB.Left, VB.Top, VB.Right, VB.Bottom ] ) );
          Assert.AreEqual( UInt64( TWinMonitor.Create( FormToHWND( A ) ).Handle ), UInt64( TWinMonitor.Create( FormToHWND( B ) ).Handle ), '同じモニター' );
          Assert.AreEqual( VA.Right, VB.Left, '右に、接して置いた' );

          // 見える枠が接しているだけの 2 つは、動かさない
          V := VB;

          TMotionProbe.Apart( A, B );

          Assert.IsTrue( FrameOf( B ) = V, '動かさない' );
          Assert.IsFalse( IsWindowVisible( FormToHWND( A ) ) or IsWindowVisible( FormToHWND( B ) ), '窓は画面に出ない' );
     finally
          B.Free;
          A.Free;
     end;
end;

// 作った窓の配置：測る窓の見える枠は (100,100)-(300,300)。枠の内は測る窓。枠の外は Outer_。Hide_ の点だけは Hider_
function Layout( const Outer_:TMotionSpot; const Hide_:TPoint; const Hider_:TMotionSpot ) :TMotionTop;
begin
     Result := function( const P_:TPoint ) :TMotionSpot
     begin
          if P_ = Hide_ then Exit( Hider_ );

          if TRect.Create( 100, 100, 300, 300 ).Contains( P_ ) then Result := msOwn
                                                                else Result := Outer_;
     end;
end;

const
     FRAME :TRect = ( Left:100; Top:100; Right:300; Bottom:300 );
     AWAY  :TPoint = ( X:-1; Y:-1 );  // どの点にも当たらない

// 範囲が窓の枠の内なら、どの点も測る窓でなければならない
procedure TMotionVersusTests.ExposedInside;
begin
     Assert.IsTrue ( TMotionProbe.Exposed( TRect.Create( 120, 120, 280, 280 ), FRAME, Layout( msOther, AWAY, msOwn ) ), 'かぶさりが無い' );
     Assert.IsFalse( TMotionProbe.Exposed( TRect.Create( 120, 120, 280, 280 ), FRAME, Layout( msOther, TPoint.Create( 200, 200 ), msOther   ) ), '真ん中に、ほかのプロセスの窓' );
     Assert.IsFalse( TMotionProbe.Exposed( TRect.Create( 120, 120, 280, 280 ), FRAME, Layout( msOther, TPoint.Create( 120, 120 ), msSibling ) ), '枠の内に、同じプロセスのほかの窓（測る窓の手前）' );
end;

// 範囲が窓の外まで伸びる（窓の端を、後ろの板の色で見つける）とき、枠の外の点は、同じプロセスの窓（後ろの板）ならよい
procedure TMotionVersusTests.ExposedOutside;
begin
     Assert.IsTrue ( TMotionProbe.Exposed( TRect.Create( 200, 150, 400, 250 ), FRAME, Layout( msSibling, AWAY, msOwn ) ), '外は、試験の後ろの板' );
     Assert.IsFalse( TMotionProbe.Exposed( TRect.Create( 200, 150, 400, 250 ), FRAME, Layout( msOther  , AWAY, msOwn ) ), '外に、ほかのプロセスの窓' );
     Assert.IsFalse( TMotionProbe.Exposed( TRect.Create( 200, 150, 400, 250 ), FRAME, Layout( msSibling, TPoint.Create( 250, 200 ), msOther ) ), '範囲と枠が交わる所の真ん中が、隠れている' );
     Assert.IsFalse( TMotionProbe.Exposed( TRect.Create( 400, 150, 500, 250 ), FRAME, Layout( msSibling, AWAY, msOwn ) ), '範囲と枠が交わらない（測る窓が写らない）' );
end;
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionLoadTests

// Results_ を、呼ばれるたびに 1 つずつ返す測る手続き。呼ばれた回数を Count_ に数える
function Replay( const Results_:TArray<TMotionPace>; const Count_:PInteger ) :TMotionMeasure;
begin
     Result := procedure( const Done_:TProc<TMotionPace> )
     begin
          Inc( Count_^ );

          Done_( Results_[ Count_^ - 1 ] );
     end;
end;

// Settle を、本物の TLoad で動かし、知らせが来るまで、主スレッドの順番待ちを回す（来なければ、DONE_MS で失敗）
function Settled( const Results_:TArray<TMotionPace>; out Count_:Integer ) :TMotionPace;
var
   L :TLoad;
   D :Boolean;
   R :TMotionPace;
   N :Integer;
   T :Double;
begin
     N := 0;
     D := False;

     L := TLoad.Create;
     try
          TMotionProbe.Settle( L, Replay( Results_, @N ), procedure( R_:TMotionPace ) begin R := R_;  D := True; end );

          T := TLoad.Now + DONE_MS;
          while not D and ( TLoad.Now < T ) do CheckSynchronize( 10 );
     finally
          L.Free;
     end;

     Assert.IsTrue( D, 'Settle が、知らせを返した（機械の負荷が、線以下になった）' );

     Count_ := N;
     Result := R;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 隣り合う時点の間ごとに、線を超えた負荷の区間に重なるかを数え、1 つでも重なれば無効
procedure TMotionLoadTests.HeavyGaps;
var
   R :TMotionPace;
begin
     // 時点 0・10・20・30・40。区間 12〜18 が 80%：間 1（10〜20）だけが重い
     R := TMotionPace.Create( [ 0, 10, 20, 30, 40 ], 10, OneSpan( 12, 18, 80 ) );

     Assert.IsTrue( Length( R.Heavys ) = 4, '間の数と同じ' );
     Assert.IsFalse( R.Heavys[ 0 ] );
     Assert.IsTrue ( R.Heavys[ 1 ] );
     Assert.IsFalse( R.Heavys[ 2 ] );
     Assert.AreEqual( 1, R.HeavysN );
     Assert.IsFalse( R.Valid, '重い間が 1 つでもあれば、無効' );
     Assert.IsTrue( R.Trace.Stats[ lkCPU ].Known, '負荷の並びを持つ' );
     Assert.AreEqual( 80.0, R.Trace.Stats[ lkCPU ].Worst, TOL );

     // 区間の端が時点に載れば、両側の間に重なる（両端を含む）
     R := TMotionPace.Create( [ 0, 10, 20, 30, 40 ], 10, OneSpan( 20, 25, 80 ) );

     Assert.IsTrue( R.Heavys[ 1 ] and R.Heavys[ 2 ] );
     Assert.AreEqual( 2, R.HeavysN );

     // 線ちょうど（50%）は、ふだんの程度
     R := TMotionPace.Create( [ 0, 10, 20, 30, 40 ], 10, OneSpan( 0, 40, 50 ) );

     Assert.AreEqual( 0, R.HeavysN );
     Assert.IsTrue( R.Valid );

     // 負荷が分からなければ（区間が無ければ）、重い間は無い
     Assert.IsTrue( TMotionPace.Create( [ 0, 10 ], 10, Quiet ).Valid );
end;

// どちらかが無効なら、割合によらず、判定しない
procedure TMotionLoadTests.VoidVerdict;
var
   H :TMotionPace;
   V :TMotionVersus;
begin
     H := TMotionPace.Create( Steady( 4, -1 ), 4, OneSpan( 500, 510, 90 ) );

     Assert.AreEqual( 0.0, H.Ratio, 1E-6, '割合は合格の値' );
     Assert.IsFalse( H.Valid );

     V := TMotionVersus.Create( [ H, H, Paced( 4, 0 ) ], Paces( [ 0, 0, 0 ] ) );
     Assert.IsTrue( V.Verdict = mvVoid, 'アプリの窓の測定が 2 回無効（有効な組が 1 つ）' );

     V := TMotionVersus.Create( Paces( [ 0, 0, 0 ] ), [ H, Paced( 4, 0 ), H ] );
     Assert.IsTrue( V.Verdict = mvVoid, '素の窓の測定が 2 回無効（有効な組が 1 つ）' );

     V := TMotionVersus.Create( Paces( [ 0, 0, 0 ] ), Paces( [ 0, 0, 0 ] ) );
     Assert.IsTrue( V.Verdict = mvPassed, 'どちらも有効なら、割合で判定する' );
end;

// 無効な結果のあいだは測り直し、最初の有効な結果を知らせる
procedure TMotionLoadTests.SettleRetakes;
var
   B, G, R :TMotionPace;
   N :Integer;
begin
     B := TMotionPace.Create( [ 0, 10, 20 ], 10, OneSpan( 5, 6, 99 ) );
     G := TMotionPace.Create( [ 0, 10, 20 ], 10, OneSpan( 5, 6, 10 ) );

     R := Settled( [ B, B, G, B ], N );

     Assert.AreEqual( 3, N, '有効な結果が出た 3 回目で止まる' );
     Assert.IsTrue( R.Valid );
end;

// SETTLE_N 回続けて無効なら、最後の無効な結果を知らせる
procedure TMotionLoadTests.SettleGivesUp;
var
   B, R :TMotionPace;
   S :TArray<TMotionPace>;
   I, N :Integer;
begin
     B := TMotionPace.Create( [ 0, 10, 20 ], 10, OneSpan( 5, 6, 99 ) );

     SetLength( S, TMotionProbe.SETTLE_N + 1 );
     for I := 0 to High( S ) do S[ I ] := B;

     R := Settled( S, N );

     Assert.AreEqual( TMotionProbe.SETTLE_N, N, 'SETTLE_N 回で止まる' );
     Assert.IsFalse( R.Valid, '無効のまま知らせる' );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TMotionPaceTests );
     TDUnitX.RegisterTestFixture( TMotionLockTests );
     TDUnitX.RegisterTestFixture( TMotionCostTests );
     TDUnitX.RegisterTestFixture( TMotionVersusTests );
     TDUnitX.RegisterTestFixture( TMotionLoadTests );

end. //######################################################################### ■
