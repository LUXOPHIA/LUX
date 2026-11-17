unit Tests.Windows.Load;

// LUX.Windows.Load の試験：区間の並びの要約と重さの判定（TLoadTrace。作った並び）と、この機械で、本物の TLoad が、
// 演算装置・描画装置・退避の書き出し・ディスクの値を返すこと（値そのものは決め打ちにせず、範囲と、区間の隙間の無さを見る）

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadTraceTests

     [TestFixture]
     TLoadTraceTests = class
     public
       [Test] procedure Stats;
       [Test] procedure Heavy;
       [Test] procedure Lines;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadTests

     [TestFixture]
     TLoadTests = class
     public
       [Test] procedure RealValues;
       [Test] procedure AwaitAfterReach;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Classes, System.Math, System.TypInfo,
     LUX.Windows.Load;

const
     TOL     = 1E-9;
     DONE_MS = 10000;  // 知らせを待つ上限（ミリ秒。来なければ失敗）
     SPAN_MS = 1000;   // 本物の値を取る長さ（ミリ秒）

function Span( const Head_,Tail_,Value_:Double ) :TLoadSpan;
begin
     Result.Head  := Head_;
     Result.Tail  := Tail_;
     Result.Value := Value_;
end;

// Load_ が Time_ までを取り終えるのを待つ（主スレッドの順番待ちを回す）
procedure Reach( const Load_:TLoad; const Time_:Double );
var
   D :Boolean;
   T :Double;
begin
     D := False;

     Load_.Await( Time_, procedure begin D := True end );

     T := TLoad.Now + DONE_MS;
     while not D and ( TLoad.Now < T ) do CheckSynchronize( 10 );

     Assert.IsTrue( D, '取り終えた知らせが来た' );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadTraceTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 平均は、範囲（0〜100）に重なる長さで重みを付け、いちばん悪い値は、範囲に重なる区間の最大。区間が無い種類は、分からない
procedure TLoadTraceTests.Stats;
var
   S :TLoadSeries;
   R :TLoadTrace;
begin
     S := Default( TLoadSeries );
     S[ lkCPU  ] := [ Span( -20, 20, 10 ), Span( 20, 60, 40 ), Span( 60, 140, 70 ), Span( 140, 160, 99 ) ];  // 重なる長さ 20・40・40
     S[ lkDisk ] := [ Span( 50, 50, 30 ) ];                                                                  // 長さ 0 の区間だけ

     R := TLoadTrace.Create( S, 100 );

     Assert.IsTrue( R.Stats[ lkCPU ].Known );
     Assert.AreEqual( ( 20 * 10 + 40 * 40 + 40 * 70 ) / 100, R.Stats[ lkCPU ].Mean, TOL );
     Assert.AreEqual( 70.0, R.Stats[ lkCPU ].Worst, TOL, '範囲の外の 99 は、数えない' );

     Assert.IsTrue( R.Stats[ lkDisk ].Known );
     Assert.AreEqual( 30.0, R.Stats[ lkDisk ].Mean, TOL, '重なりが長さ 0 なら、ただの平均' );

     Assert.IsFalse( R.Stats[ lkPaging ].Known );
     Assert.AreEqual( 0.0, R.Stats[ lkPaging ].Mean, TOL );

     Assert.WillRaise( procedure begin R := TLoadTrace.Create( S, -1 ); end, EArgumentOutOfRangeException, '範囲の長さが負' );
end;

// 範囲（両端を含む）に重なる区間のどれかが、その種類の線を超えれば重い
procedure TLoadTraceTests.Heavy;
var
   S :TLoadSeries;
   R :TLoadTrace;
begin
     S := Default( TLoadSeries );
     S[ lkCPU    ] := [ Span( 0, 16, 20 ), Span( 16, 32, 51 ), Span( 32, 48, 20 ) ];
     S[ lkPaging ] := [ Span( 0, 16, 0 ), Span( 16, 32, 0 ), Span( 32, 48, 0.5 ) ];

     R := TLoadTrace.Create( S, 48 );

     Assert.IsFalse( R.Heavy( 2, 14 ), '20% と、退避 0 ページ／秒（線ちょうど）は、ふだん' );
     Assert.IsTrue ( R.Heavy( 20, 24 ), '演算装置 51%' );
     Assert.IsTrue ( R.Heavy( 0, 16 ), '端の 16 で、隣の 51% の区間に重なる' );
     Assert.IsTrue ( R.Heavy( 40, 44 ), '退避の書き出し 0.5 ページ／秒' );
     Assert.IsFalse( TLoadTrace.Create( Default( TLoadSeries ), 48 ).Heavy( 0, 48 ), '区間が無ければ、重くない' );
end;

// 線：占有率は半分、退避の書き出しは 0 ページ／秒（起きたら重い）
procedure TLoadTraceTests.Lines;
begin
     Assert.AreEqual( 50.0   , LOAD_LINES[ lkCPU     ], TOL );
     Assert.AreEqual( 50.0   , LOAD_LINES[ lkGPU3D   ], TOL );
     Assert.AreEqual( 50.0   , LOAD_LINES[ lkGPUCopy ], TOL );
     Assert.AreEqual( 50.0   , LOAD_LINES[ lkGPUEtc  ], TOL );
     Assert.AreEqual( 0.0    , LOAD_LINES[ lkPaging  ], TOL );
     Assert.AreEqual( 50.0   , LOAD_LINES[ lkDisk    ], TOL );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLoadTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// この機械で、演算装置・描画装置（3D）・退避の書き出し・ディスクの値が、1 秒の間、隙間なく取れる。区間の長さは、GAP 以上
procedure TLoadTests.RealValues;
const
     KINDS :array of TLoadKind = [ lkCPU, lkGPU3D, lkPaging, lkDisk ];
var
   L :TLoad;
   H :Double;
   R :TLoadTrace;
   K :TLoadKind;
   I :Integer;
begin
     L := TLoad.Create;
     try
          H := TLoad.Now;

          Reach( L, H + SPAN_MS );

          R := L.Trace( H, H + SPAN_MS );
     finally
          L.Free;
     end;

     for K in KINDS do Assert.IsTrue( R.Stats[ K ].Known, GetEnumName( TypeInfo( TLoadKind ), Ord( K ) ) + ' が取れた' );

     // 演算装置は、生の値から出すので、PDH が整形できない回にも区間が途切れない：区間の端が、前の区間の終わりに続き、
     // 範囲の始めから終わりまでを覆う。区間の長さは、取る間隔を下回らない（ほかの種類は、PDH が値を出せない回に、区間が欠けうる）
     for I := 1 to High( R.Series[ lkCPU ] ) do
     begin
          Assert.AreEqual( R.Series[ lkCPU ][ I - 1 ].Tail, R.Series[ lkCPU ][ I ].Head, TOL, '区間が続く' );
          Assert.IsTrue( R.Series[ lkCPU ][ I ].Tail - R.Series[ lkCPU ][ I ].Head >= TLoad.GAP - 1, '区間は、取る間隔ほど' );
     end;

     Assert.IsTrue( R.Series[ lkCPU ][ 0 ].Head <= 0, '範囲の始めから覆う' );
     Assert.IsTrue( R.Series[ lkCPU ][ High( R.Series[ lkCPU ] ) ].Tail >= SPAN_MS, '範囲の終わりまで覆う' );

     Assert.IsTrue( InRange( R.Stats[ lkCPU   ].Mean, -1, 101 ), '演算装置の占有率は、0〜100%' );
     Assert.IsTrue( InRange( R.Stats[ lkGPU3D ].Mean,  0, 101 ), '描画装置の占有率は、0〜100%' );
     Assert.IsTrue( R.Stats[ lkPaging ].Worst >= 0, '退避の書き出しは、0 以上' );
     Assert.IsTrue( InRange( R.Stats[ lkDisk  ].Mean, -1, 101 ), 'ディスクの使用中の割合は、0〜100%' );
end;

// Await の知らせが来た時には、その時刻までの演算装置の区間がそろっている
procedure TLoadTests.AwaitAfterReach;
var
   L :TLoad;
   T :Double;
   R :TLoadTrace;
begin
     L := TLoad.Create;
     try
          T := TLoad.Now + 50;

          Reach( L, T );

          R := L.Trace( T - 50, T );

          Assert.IsTrue( Length( R.Series[ lkCPU ] ) > 0 );
          Assert.IsTrue( R.Series[ lkCPU ][ High( R.Series[ lkCPU ] ) ].Tail >= 50, '知らせの時には、その時刻まで取り終えている' );

          Assert.WillRaise( procedure begin R := L.Trace( 10, 5 ); end, EArgumentException, '範囲が逆' );
     finally
          L.Free;
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TLoadTraceTests );
     TDUnitX.RegisterTestFixture( TLoadTests );

end. //######################################################################### ■
