unit Tests.FMX.Redraw;

// LUX.FMX.Redraw の、次に描かせてよい時刻の決め方（TRedraw.NextDue）の試験
//
//【合成の時機】
// ・合成の時機（垂直帰線の時刻）が分かるときは、それを Origin_ に渡す。次の時刻は、その時刻から周期おきの並びの上の、
//   いまの後の最初の点（合成の直後）にそろう。分からないときは、前の時刻を Origin_ に渡す（前の位相を保つ）。
//
//【窓を出さない】
// ・作った時刻で、知らせの汲み出しと、描かせることを、なぞる。フォームも、窓も、作らない。時刻は、マイクロ秒を刻みにする。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TRedrawTests

     [TestFixture]
     TRedrawTests = class
     private
     public
       [Test] procedure KeepsPhase;
       [Test] procedure RestartsWhenLate;
       [Test] procedure RateFollowsScreen;
       [Test] procedure AlignsToComposition;
       [Test] procedure StaysOnComposition;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils,
     LUX.FMX.Redraw;

const
     PERIOD = 8333;  // 120 Hz の画面の更新の周期（マイクロ秒）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TRedrawTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 描かせてよい時刻を過ぎてから描かせても、次の時刻は、前の時刻に周期を足した所（待ちの分を、次へ持ち越さない）
procedure TRedrawTests.KeepsPhase;
begin
     Assert.AreEqual( Int64( 2 * PERIOD ), TRedraw.NextDue( PERIOD, PERIOD + 700, PERIOD, PERIOD ), '0.7 ミリ秒遅れて描かせた' );
     Assert.AreEqual( Int64( 2 * PERIOD ), TRedraw.NextDue( PERIOD, PERIOD, PERIOD, PERIOD ), 'ちょうどに描かせた' );
     Assert.AreEqual( Int64( 1000 + PERIOD ), TRedraw.NextDue( 1000, 1000, PERIOD, 1000 ), '初めて描かせた（描かせてよかった時刻が、いま）' );
end;

// 前の時刻から 1 周期以上遅れたときは、同じ位相の並びの、いまの後の最初の点（遅れを取り戻すために、続けて描かせない）
procedure TRedrawTests.RestartsWhenLate;
begin
     Assert.AreEqual( Int64( 2 * PERIOD + PERIOD ), TRedraw.NextDue( PERIOD, 2 * PERIOD, PERIOD, PERIOD ), 'ちょうど 1 周期遅れた' );
     Assert.AreEqual( Int64( 3 * PERIOD ), TRedraw.NextDue( 0, 20000, PERIOD, 0 ), '2 周期あまり遅れた：同じ位相の、20000 の後の最初の点' );
     Assert.AreEqual( Int64( 5000 ), TRedraw.NextDue( 0, 5000, 0, 0 ), '周期が分からなければ、下限を置かない' );
end;

// 1 ミリ秒おきに知らせが汲み出され、1 回描くのに 3 ミリ秒かかるとき、描かせる数は、1 秒に、画面の更新の数（120）にそろう
procedure TRedrawTests.RateFollowsScreen;
var
   T, D :Int64;
   N :Integer;
begin
     T := 0;  D := 0;  N := 0;
     while T < 1000000 do
     begin
          if T >= D then
          begin
               D := TRedraw.NextDue( D, T, PERIOD, D );

               Inc( N );

               Inc( T, 3000 );  // 描く手間
          end;

          Inc( T, 1000 );  // 次の知らせ
     end;

     Assert.IsTrue( ( N >= 119 ) and ( N <= 121 ), Format( '1 秒に描かせた数 %d（画面の更新は 120）', [ N ] ) );
end;

// 合成の時機が分かれば、描かせてよい時刻は、それまでの位相から、合成の直後（垂直帰線の時刻から周期おきの点）へ移る。
// 渡された垂直帰線の時刻が、いまより先（次の合成）でも、同じ並びの上の点として扱う
procedure TRedrawTests.AlignsToComposition;
const
     V = 5000;  // 垂直帰線の時刻
begin
     Assert.AreEqual( Int64( V ), TRedraw.NextDue( 1000, 1200, PERIOD, V ), 'いまの後の最初の合成の直後' );
     Assert.AreEqual( Int64( V + PERIOD ), TRedraw.NextDue( V, V + 600, PERIOD, V + 10 * PERIOD ), '先の垂直帰線の時刻を渡されても、次の点' );
     Assert.AreEqual( Int64( V + 3 * PERIOD ), TRedraw.NextDue( V, V + 5 * PERIOD div 2, PERIOD, V ), '遅れても、合成の直後の点' );
     Assert.AreEqual( Int64( V + PERIOD ), TRedraw.NextDue( V, V - 300, PERIOD, V ), '描かせてよい時刻より前に描かせた（窓の大きさの変更）：その次の点' );
end;

// 1 ミリ秒おきに知らせが汲み出され、描く手間が 3 ミリ秒のとき、描かせてよい時刻は、どれも合成の直後の点で、
// 描かせ始めるのは、その点の後の最初の知らせ
procedure TRedrawTests.StaysOnComposition;
const
     V = 3217 + 100 * PERIOD;  // 垂直帰線の時刻（いまより先の合成）
var
   T, D :Int64;
   N :Integer;
begin
     T := 0;  D := 0;  N := 0;
     while T < 1000000 do
     begin
          if T >= D then
          begin
               Assert.IsTrue( ( N = 0 ) or ( T - D < 1000 ), Format( '描かせてよい時刻 %d の後の最初の知らせで、描かせる（%d）', [ D, T ] ) );

               D := TRedraw.NextDue( D, T, PERIOD, V );

               Assert.AreEqual( Int64( 3217 ), D mod PERIOD, Format( '描かせてよい時刻 %d は、合成の直後の点', [ D ] ) );

               Inc( N );

               Inc( T, 3000 );
          end;

          Inc( T, 1000 );
     end;

     Assert.IsTrue( ( N >= 119 ) and ( N <= 121 ), Format( '1 秒に描かせた数 %d（画面の更新は 120）', [ N ] ) );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TRedrawTests );

end. //######################################################################### ■
