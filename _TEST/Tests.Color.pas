unit Tests.Color;

// LUX.Color の試験（TByteRGBE と実数の間の変換）
//
// ・変換の定義は、Radiance のもの（仮数 M は、( M + 0.5 ) / 256 × 2^( E - 128 ) を表す。E = 0 は黒）。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TByteRGBETests

     [TestFixture]
     TByteRGBETests = class
     public
       [Test] procedure ToReal;
       [Test] procedure FromReal;
       [Test] procedure FromUnrepresentable;
       [Test] procedure RoundTripError;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Math,
     LUX.Color;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

procedure CheckBytes( const R_,G_,B_,E_:Byte; const C_:TByteRGBE; const Name_:String );
begin
     Assert.AreEqual( Format( '%d %d %d %d', [ R_, G_, B_, E_ ] ), Format( '%d %d %d %d', [ C_.R, C_.G, C_.B, C_.E ] ), Name_ );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TByteRGBETests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 仮数と指数から、実数へ（値は、2 進で正確に表せるものを選んである）
procedure TByteRGBETests.ToReal;
var
   C :TSingleRGB;
begin
     C := TByteRGBE.Create( 128, 128, 128, 129 );  // 128.5 / 256 × 2

     Assert.AreEqual( Single( 1.00390625 ), C.R );
     Assert.AreEqual( Single( 1.00390625 ), C.G );
     Assert.AreEqual( Single( 1.00390625 ), C.B );

     C := TByteRGBE.Create( 255, 0, 64, 128 );     // ( 255.5, 0.5, 64.5 ) / 256

     Assert.AreEqual( Single( 0.998046875 ), C.R );
     Assert.AreEqual( Single( 0.001953125 ), C.G );
     Assert.AreEqual( Single( 0.251953125 ), C.B );

     C := TByteRGBE.Create( 128, 0, 0, 120 );      // 128.5 / 256 × 2^-8

     Assert.AreEqual( Single( 128.5 / 65536 ), C.R );

     C := TByteRGBE.Create( 200, 100, 50, 0 );     // 指数 0 は、仮数によらず黒

     Assert.AreEqual( Single( 0 ), C.R );
     Assert.AreEqual( Single( 0 ), C.G );
     Assert.AreEqual( Single( 0 ), C.B );
end;

// 実数から、仮数と指数へ。最大の成分の仮数は、128〜255 になる
procedure TByteRGBETests.FromReal;
begin
     CheckBytes( 128, 128, 128, 129, TSingleRGB.Create( 1   , 1   , 1    ), '1' );
     CheckBytes( 128,  64,   0, 128, TSingleRGB.Create( 0.5 , 0.25, 0    ), '0.5' );
     CheckBytes( 255, 127,   1, 128, TSingleRGB.Create( 0.999, 0.499, 0.005 ), '1 のすぐ下' );
     CheckBytes( 200, 100,  50, 138, TSingleRGB.Create( 800 , 400 , 200  ), '800' );
     CheckBytes( 128,   0,   0, 121, TSingleRGB.Create( 1/256, 0  , 0    ), '1 / 256' );
end;

// 表せない値：黒（非数・負だけ・小さすぎる値）、負の成分は 0
procedure TByteRGBETests.FromUnrepresentable;
begin
     CheckBytes(   0,   0,   0,   0, TSingleRGB.Create(  0   ,  0  ,  0   ), '0' );
     CheckBytes(   0,   0,   0,   0, TSingleRGB.Create( 1e-33, 0   ,  0   ), '小さすぎる' );
     CheckBytes(   0,   0,   0,   0, TSingleRGB.Create( -1   , -2  , -3   ), '負だけ' );
     CheckBytes(   0,   0,   0,   0, TSingleRGB.Create( NaN  , NaN , NaN  ), '非数' );
     CheckBytes( 128,   0,  64, 129, TSingleRGB.Create(  1   , -5  ,  0.5 ), '負の成分' );
end;

// 往復の誤差：最大の成分は、仮数が 128 以上なので、誤差は、最大の成分の 1 / 256 以下である
procedure TByteRGBETests.RoundTripError;
var
   I :Integer;
   V :Single;
   A, B :TSingleRGB;
begin
     V := 1e-6;
     for I := 0 to 400 do
     begin
          A := TSingleRGB.Create( V, V * 0.37, V * 0.011 );

          B := TByteRGBE( A );

          Assert.IsTrue( Abs( B.R - A.R ) <= A.R / 255, Format( '最大の成分（%g）', [ V ] ) );
          Assert.IsTrue( Abs( B.G - A.G ) <= A.R / 255, Format( '中の成分（%g）'  , [ V ] ) );
          Assert.IsTrue( Abs( B.B - A.B ) <= A.R / 255, Format( '小の成分（%g）'  , [ V ] ) );

          V := V * 1.0717;  // 400 歩で、約 12 桁
     end;
end;

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TByteRGBETests );

end. //######################################################################### ■
