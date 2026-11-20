unit Tests.Codec.Image.Hdr;

// LUX.Data.Codec.Image.Hdr の試験
//
//【復号の確かめ方】
// ・試験の側で、形式の定義のとおりに、ファイルをバイトから組み立てる（走査線の 3 つの入り方・8 通りの向き）。
// ・復号の結果であるべき画素は、仮数と指数から、定義の式（ ( 仮数 + 0.5 ) / 256 × 2^( 指数 - 128 ) ）で求める。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecHdrTests

     [TestFixture]
     TImageCodecHdrTests = class
     public
       [Test] procedure DecodesFlat;
       [Test] procedure DecodesNewRuns;
       [Test] procedure DecodesOldRuns;
       [Test] procedure OldRunStopsAtScanlineEnd;
       [Test] procedure DecodesEveryOrientation;
       [Test] procedure DecodesXyz;
       [Test] procedure HeaderVariables;
       [Test] procedure RoundTrip;
       [Test] procedure EncodesRunsAndLiterals;
       [Test] procedure EncodesNarrowFlat;
       [Test] procedure EncodesLinearWithPrimaries;
       [Test] procedure RejectsBrokenData;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Classes, System.Math, System.StrUtils,
     LUX.D2, LUX.Color, LUX.Color.Space,
     LUX.Data.Codec.Image,
     LUX.Data.Codec.Image.Hdr,
     Tests.Codec.Image;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      HEAD = '#?RADIANCE'#10'FORMAT=32-bit_rle_rgbe'#10#10;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function Ascii( const Text_:String ) :TBytes;
begin
     Result := TEncoding.ASCII.GetBytes( Text_ );
end;

// 位置 ( X_, Y_ ) の画素の、ファイルの中の 4 バイト。位置ごとに違い、最大の仮数は 128 以上である

function Pixel( const X_,Y_:Integer ) :TBytes;
begin
     Result := [ 128 + X_ * 9 + Y_, ( X_ * 31 + Y_ * 57 ) and $FF, ( X_ * 3 + Y_ * 101 ) and $FF, 126 + ( X_ + Y_ ) mod 5 ];
end;

// 4 バイトの表す実数（形式の定義）

function Value( const Pixel_:TBytes ) :TSingleRGBA;
var
   S :Single;
begin
     if Pixel_[ 3 ] = 0 then Exit( TSingleRGBA.Create( 0, 0, 0, 1 ) );

     S := Power( 2, Pixel_[ 3 ] - 128 ) / 256;

     Result := TSingleRGBA.Create( ( Pixel_[ 0 ] + 0.5 ) * S, ( Pixel_[ 1 ] + 0.5 ) * S, ( Pixel_[ 2 ] + 0.5 ) * S, 1 );
end;

function Same( const A_,B_:TSingleRGBA; const Tol_:Single = 0 ) :Boolean;
begin
     Result := ( Abs( A_.R - B_.R ) <= Tol_ ) and ( Abs( A_.G - B_.G ) <= Tol_ )
           and ( Abs( A_.B - B_.B ) <= Tol_ ) and ( Abs( A_.A - B_.A ) <= Tol_ );
end;

//------------------------------------------------------------------------------

function Decoded( const Hdr_:TBytes ) :TTestRaster;
var
   C :TImageCodecHdr;
   S :TStream;
begin
     Result := TTestRaster.Create;
     try
        C := TImageCodecHdr.Create;
        S := StreamOf( Hdr_ );
        try
           C.Decode( S, Result );
        finally
           S.Free;
           C.Free;
        end;
     except
        Result.Free;

        raise;
     end;
end;

function Encoded( const Raster_:TTestRaster ) :TBytes;
var
   C :TImageCodecHdr;
   S :TBytesStream;
begin
     C := TImageCodecHdr.Create;
     S := TBytesStream.Create;
     try
        C.Encode( S, Raster_ );

        Result := Copy( S.Bytes, 0, S.Size );
     finally
        S.Free;
        C.Free;
     end;
end;

// 画素の始まり（解像度の行の次）の位置

function PixelsAt( const Hdr_:TBytes ) :Integer;
var
   I :Integer;
begin
     I := 1;
     while not ( ( Hdr_[ I-1 ] = 10 ) and ( Hdr_[ I ] = 10 ) ) do Inc( I );  // 空の行

     Inc( I );
     while Hdr_[ I ] <> 10 do Inc( I );                                      // 解像度の行の終わり

     Result := I + 1;
end;

// 復号が、例外で断ること

procedure Rejects( const Hdr_:TBytes; const Name_:String );
begin
     Assert.WillRaise( procedure begin Decoded( Hdr_ ).Free; end, EImageCodec, Name_ );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecHdrTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 無圧縮の走査線
procedure TImageCodecHdrTests.DecodesFlat;
var
   Z :TBytes;
   R :TTestRaster;
   X, Y :Integer;
begin
     Z := Ascii( HEAD + '-Y 2 +X 3'#10 );

     for Y := 0 to 2-1 do
     for X := 0 to 3-1 do Z := Z + Pixel( X, Y );

     R := Decoded( Z );
     try
        Assert.AreEqual(  3, R.Header.Width  );
        Assert.AreEqual(  2, R.Header.Height );
        Assert.AreEqual( 32, R.Header.Depth  );

        Assert.IsTrue( R.WrittenOnce );

        for Y := 0 to 2-1 do
        for X := 0 to 3-1 do Assert.IsTrue( Same( R[ X, Y ], Value( Pixel( X, Y ) ) ), Format( '(%d, %d)', [ X, Y ] ) );
     finally
        R.Free;
     end;

     ///// 指数 0 の画素は、黒

     R := Decoded( Ascii( HEAD + '-Y 1 +X 2'#10 ) + [ 200, 100, 50, 0,  128, 128, 128, 129 ] );
     try
        Assert.IsTrue( Same( R[ 0, 0 ], TSingleRGBA.Create( 0, 0, 0, 1 ) ) );
        Assert.IsTrue( Same( R[ 1, 0 ], TSingleRGBA.Create( 1.00390625, 1.00390625, 1.00390625, 1 ) ) );
     finally
        R.Free;
     end;
end;

// 新しい連長：成分ごとに、繰り返し（128 を超える長さ）と、そのままの並びが混ざる
procedure TImageCodecHdrTests.DecodesNewRuns;
var
   Z :TBytes;
   R :TTestRaster;
   X :Integer;
begin
     Z := Ascii( HEAD + '-Y 1 +X 20'#10 )
        + [ 2, 2, 0, 20 ]
        + [ 128 + 20, 200 ]                   // 1 つ目の成分：200 が 20 個
        + [ 5, 1, 2, 3, 4, 5,  128 + 15, 9 ]  // 2 つ目：そのまま 5 個、9 が 15 個
        + [ 128 + 7, 77,  0,  128 + 13, 33 ]  // 3 つ目：77 が 7 個、長さ 0（何もしない）、33 が 13 個
        + [ 128 + 20, 130 ];                  // 指数

     R := Decoded( Z );
     try
        Assert.IsTrue( R.WrittenOnce );

        for X := 0 to 20-1 do
        begin
             Assert.IsTrue( Same( R[ X, 0 ], Value( [ 200, IfThen( X < 5, X + 1, 9 ), IfThen( X < 7, 77, 33 ), 130 ] ) ), Format( 'X = %d', [ X ] ) );
        end;
     finally
        R.Free;
     end;
end;

// 古い連長：( 1, 1, 1, 回数 ) は、直前の画素の繰り返し。続くと、回数の桁が 8 ビットずつ上がる
procedure TImageCodecHdrTests.DecodesOldRuns;
var
   A, B :TBytes;
   R :TTestRaster;
   X :Integer;
begin
     A := [ 200, 10, 20, 128 ];
     B := [ 130, 40, 50, 131 ];

     ///// A、3 回の繰り返し、B、( 2 + 1 × 256 ) 回の繰り返し：全部で 1 + 3 + 1 + 258 = 263 画素

     R := Decoded( Ascii( HEAD + '-Y 1 +X 263'#10 ) + A + [ 1, 1, 1, 3 ] + B + [ 1, 1, 1, 2 ] + [ 1, 1, 1, 1 ] );
     try
        Assert.IsTrue( R.WrittenOnce );

        for X := 0 to 263-1 do
        begin
             if X < 4 then Assert.IsTrue( Same( R[ X, 0 ], Value( A ) ), Format( 'X = %d', [ X ] ) )
                      else Assert.IsTrue( Same( R[ X, 0 ], Value( B ) ), Format( 'X = %d', [ X ] ) );
        end;
     finally
        R.Free;
     end;
end;

// 古い連長の繰り返しが、走査線の終わりを越える分は、無いものとされる（形式の定義）
procedure TImageCodecHdrTests.OldRunStopsAtScanlineEnd;
var
   A, B :TBytes;
   R :TTestRaster;
begin
     A := [ 200, 10, 20, 128 ];
     B := [ 130, 40, 50, 131 ];

     R := Decoded( Ascii( HEAD + '-Y 2 +X 4'#10 ) + A + [ 1, 1, 1, 200 ] + B + B + B + B );
     try
        Assert.IsTrue( R.WrittenOnce );

        Assert.IsTrue( Same( R[ 3, 0 ], Value( A ) ) );
        Assert.IsTrue( Same( R[ 0, 1 ], Value( B ) ) );
        Assert.IsTrue( Same( R[ 3, 1 ], Value( B ) ) );
     finally
        R.Free;
     end;
end;

// 解像度の行の 8 通りの向き。
// ファイルの座標は Y が上向きなので、走査線が上から下へ並ぶのは -Y、左から右へ進むのは +X である。
procedure TImageCodecHdrTests.DecodesEveryOrientation;
const
     W = 3;
     H = 2;
var
   YMajor, MinusX, MinusY :Boolean;
   SX, SY :String;
   Z :TBytes;
   I, J, X, Y :Integer;
   R :TTestRaster;
   Name :String;
begin
     for YMajor in [ False, True ] do
     for MinusX in [ False, True ] do
     for MinusY in [ False, True ] do
     begin
          SX := IfThen( MinusX, '-X ', '+X ' ) + W.ToString;
          SY := IfThen( MinusY, '-Y ', '+Y ' ) + H.ToString;

          if YMajor then Name := SY + ' ' + SX
                    else Name := SX + ' ' + SY;

          Z := Ascii( HEAD + Name + #10 );

          ///// ファイルの順に、画素を並べる（I：走査線の番号　J：走査線の中の番号）

          if YMajor then
          begin
               for I := 0 to H-1 do
               for J := 0 to W-1 do
               begin
                    if MinusY then Y := I else Y := H-1 - I;
                    if MinusX then X := W-1 - J else X := J;

                    Z := Z + Pixel( X, Y );
               end;
          end
          else
          begin
               for I := 0 to W-1 do
               for J := 0 to H-1 do
               begin
                    if MinusX then X := W-1 - I else X := I;
                    if MinusY then Y := J else Y := H-1 - J;

                    Z := Z + Pixel( X, Y );
               end;
          end;

          R := Decoded( Z );
          try
             Assert.AreEqual( W, R.Header.Width , Name );
             Assert.AreEqual( H, R.Header.Height, Name );

             Assert.IsTrue( R.WrittenOnce, Name );

             for Y := 0 to H-1 do
             for X := 0 to W-1 do Assert.IsTrue( Same( R[ X, Y ], Value( Pixel( X, Y ) ) ), Format( '%s：(%d, %d)', [ Name, X, Y ] ) );
          finally
             R.Free;
          end;
     end;
end;

// XYZ の画素は、色空間の RGB に直されて渡る。
// 既定の色空間の白は、等エネルギー（ X = Y = Z ）なので、X = Y = Z の画素は、R = G = B になる
procedure TImageCodecHdrTests.DecodesXyz;
var
   R :TTestRaster;
   P :TSingleRGBA;
begin
     R := Decoded( Ascii( '#?RADIANCE'#10'FORMAT=32-bit_rle_xyze'#10#10'-Y 1 +X 1'#10 ) + [ 128, 128, 128, 129 ] );
     try
        P := R[ 0, 0 ];

        Assert.IsTrue( Same( P, TSingleRGBA.Create( 1.00390625, 1.00390625, 1.00390625, 1 ), 1e-4 ), Format( '%g %g %g', [ P.R, P.G, P.B ] ) );
     finally
        R.Free;
     end;
end;

// ヘッダーの変数：FORMAT が無ければ RGB。PRIMARIES があれば、その原色の線形の色空間。
// 無ければ、Radiance の既定の原色。知らない変数と、行の終わりの CR は、読み飛ばす
procedure TImageCodecHdrTests.HeaderVariables;
var
   R :TTestRaster;
begin
     R := Decoded( Ascii( '#?RGBE'#10'SOFTWARE=test'#10'EXPOSURE=2.5'#13#10#10'-Y 1 +X 1'#10 ) + [ 128, 128, 128, 129 ] );
     try
        Assert.IsTrue( Same( R[ 0, 0 ], TSingleRGBA.Create( 1.00390625, 1.00390625, 1.00390625, 1 ) ), '値は、そのまま渡る' );

        Assert.IsTrue( R.Header.ColorSpace.IsLinear );
        Assert.AreEqual( 0.640, R.Header.ColorSpace.RedXY  .X, 1e-9 );
        Assert.AreEqual( 0.290, R.Header.ColorSpace.GreenXY.X, 1e-9 );
        Assert.AreEqual( 1 / 3, R.Header.ColorSpace.WhiteXY.X, 1e-9 );
        Assert.AreEqual( 1 / 3, R.Header.ColorSpace.WhiteXY.Y, 1e-9 );
     finally
        R.Free;
     end;

     ///// sRGB の原色と D65 の白は、登録済みの「線形の sRGB」になる

     R := Decoded( Ascii( '#?RADIANCE'#10'PRIMARIES= 0.6400 0.3300 0.3000 0.6000 0.1500 0.0600 0.3127 0.3290'#10'FORMAT=32-bit_rle_rgbe'#10#10'-Y 1 +X 1'#10 ) + [ 128, 128, 128, 129 ] );
     try
        Assert.IsTrue( R.Header.ColorSpace = TLuxColorSpaces.LinearSRGB );
     finally
        R.Free;
     end;
end;

// 符号化して復号すると、仮数の刻みの誤差（最大の成分の 1 / 256 以下）で、元に戻る。α は 1 になる
procedure TImageCodecHdrTests.RoundTrip;
const
     W = 40;
     H = 9;
var
   A, B :TTestRaster;
   X, Y :Integer;
   P, Q :TSingleRGBA;
   V :Single;
begin
     A := TTestRaster.Create( W, H, nil, 32 );
     B := nil;
     try
        for Y := 0 to H-1 do
        for X := 0 to W-1 do
        begin
             V := Power( 10, ( X - W / 2 ) / 4 );  // 10^-5 〜 10^5

             A[ X, Y ] := TSingleRGBA.Create( V, V * ( Y + 1 ) / H, V * 0.01 * X, 0.5 );
        end;

        B := Decoded( Encoded( A ) );

        Assert.IsTrue( B.WrittenOnce );

        for Y := 0 to H-1 do
        for X := 0 to W-1 do
        begin
             P := A[ X, Y ];  P.A := 1;
             Q := B[ X, Y ];

             Assert.IsTrue( Same( P, Q, Max( P.R, Max( P.G, P.B ) ) / 255 ), Format( '(%d, %d)', [ X, Y ] ) );
        end;
     finally
        B.Free;
        A.Free;
     end;
end;

// 新しい連長の書き出し：127 を超える繰り返しと、128 を超えるそのままの並びが、分けて書かれ、正しく戻る
procedure TImageCodecHdrTests.EncodesRunsAndLiterals;
const
     W = 700;
var
   A, B :TTestRaster;
   X :Integer;
   Z :TBytes;
   P :Integer;
begin
     A := TTestRaster.Create( W, 1, nil, 32 );
     B := nil;
     try
        ///// 前半は同じ色（長い繰り返し）、後半は 1 画素ごとに違う色（長い、そのままの並び）

        for X := 0 to W-1 do
        begin
             if X < 300 then A[ X, 0 ] := TSingleRGBA.Create( 0.75, 0.5, 0.25, 1 )
                        else A[ X, 0 ] := TSingleRGBA.Create( ( 128 + X * 37 mod 128 ) / 256, ( X * 91 mod 256 ) / 256, ( X * 53 mod 256 ) / 256, 1 );
        end;

        Z := Encoded( A );
        P := PixelsAt( Z );

        Assert.IsTrue( ( Z[ P ] = 2 ) and ( Z[ P+1 ] = 2 ) and ( ( Z[ P+2 ] shl 8 ) or Z[ P+3 ] = W ), '新しい連長の先頭' );

        Assert.IsTrue( Length( Z ) - P < 4 * W, '無圧縮より小さい' );

        B := Decoded( Z );

        Assert.IsTrue( A.Distance( B ) <= 1 / 256 );
     finally
        B.Free;
        A.Free;
     end;
end;

// 新しい連長で表せない幅（17 未満）は、無圧縮で書かれる
procedure TImageCodecHdrTests.EncodesNarrowFlat;
var
   A, B :TTestRaster;
   Z :TBytes;
   X, Y :Integer;
begin
     A := TTestRaster.Create( 16, 3, nil, 32 );
     B := nil;
     try
        for Y := 0 to 3-1 do
        for X := 0 to 16-1 do A[ X, Y ] := TSingleRGBA.Create( 1, 1, 1, 1 );

        Z := Encoded( A );

        Assert.AreEqual( 4 * 16 * 3, Integer( Length( Z ) ) - PixelsAt( Z ) );

        B := Decoded( Z );

        Assert.IsTrue( Same( B[ 15, 2 ], TSingleRGBA.Create( 1.00390625, 1.00390625, 1.00390625, 1 ) ) );
     finally
        B.Free;
        A.Free;
     end;
end;

// 色空間があれば、画素は線形に直して書かれ、原色が PRIMARIES に書かれる。色空間が無ければ、PRIMARIES は書かれない
procedure TImageCodecHdrTests.EncodesLinearWithPrimaries;
var
   A, B :TTestRaster;
   Z :TBytes;
   T :String;
begin
     A := TTestRaster.Create( 1, 1, TLuxColorSpaces.sRGB, 8 );
     B := nil;
     try
        A[ 0, 0 ] := TSingleRGBA.Create( 0.5, 0.5, 0.5, 1 );

        Z := Encoded( A );
        T := TEncoding.ASCII.GetString( Z, 0, PixelsAt( Z ) );

        Assert.IsTrue( T.Contains( 'PRIMARIES= 0.6400 0.3300 0.3000 0.6000 0.1500 0.0600 0.3127 0.3290'#10 ), T );
        Assert.IsTrue( T.EndsWith( #10#10'-Y 1 +X 1'#10 ), T );

        B := Decoded( Z );

        Assert.IsTrue( B.Header.ColorSpace = TLuxColorSpaces.LinearSRGB );

        Assert.AreEqual( 0.21404, Double( B[ 0, 0 ].R ), 0.002, 'sRGB の 0.5 は、線形の 0.214' );
     finally
        B.Free;
        A.Free;
     end;

     A := TTestRaster.Create( 1, 1, nil, 32 );
     try
        A[ 0, 0 ] := TSingleRGBA.Create( 0.5, 0.5, 0.5, 1 );

        Z := Encoded( A );

        Assert.AreEqual( '#?RADIANCE'#10'FORMAT=32-bit_rle_rgbe'#10#10'-Y 1 +X 1'#10, TEncoding.ASCII.GetString( Z, 0, PixelsAt( Z ) ) );
     finally
        A.Free;
     end;
end;

// 形式に合わないデータは、例外になる
procedure TImageCodecHdrTests.RejectsBrokenData;
var
   P :TBytes;
begin
     P := [ 128, 128, 128, 129 ];

     Rejects( nil                                                               , '空' );
     Rejects( Ascii( 'RADIANCE'#10#10'-Y 1 +X 1'#10 ) + P                         , '「#?」で始まらない' );
     Rejects( Ascii( '#?RADIANCE'#10'FORMAT=32-bit_rle_rgbe'#10 )                 , 'ヘッダーの途中で終わる' );
     Rejects( Ascii( '#?RADIANCE'#10'FORMAT=24-bit_rgb'#10#10'-Y 1 +X 1'#10 ) + P , '知らない FORMAT' );
     Rejects( Ascii( '#?RADIANCE'#10'PRIMARIES= 1 2 3'#10#10'-Y 1 +X 1'#10 ) + P  , 'PRIMARIES の数が足りない' );
     Rejects( Ascii( '#?' + StringOfChar( 'a', 3000 ) + #10#10'-Y 1 +X 1'#10 ) + P, '行が長すぎる' );
     Rejects( Ascii( HEAD + '-Y 1 +Y 1'#10 ) + P                                  , '同じ軸が 2 つ' );
     Rejects( Ascii( HEAD + '-Y 0 +X 1'#10 ) + P                                  , '個数が 0' );
     Rejects( Ascii( HEAD + 'Y 1 X 1'#10 ) + P                                    , '符号が無い' );
     Rejects( Ascii( HEAD + '-Y 1 +X'#10 ) + P                                    , '個数が無い' );
     Rejects( Ascii( HEAD + '-Y 1 +X 2'#10 ) + P                                  , '画素の途中で終わる' );
     Rejects( Ascii( HEAD + '-Y 1 +X 2'#10 ) + [ 1, 1, 1, 1 ] + P                 , '走査線が繰り返しで始まる' );
     Rejects( Ascii( HEAD + '-Y 1 +X 20'#10 ) + [ 2, 2, 0, 21, 128 + 21, 0 ]      , '新しい連長の長さが、幅と違う' );
     Rejects( Ascii( HEAD + '-Y 1 +X 20'#10 ) + [ 2, 2, 0, 20, 128 + 21, 0 ]      , '繰り返しが、走査線を越える' );
     Rejects( Ascii( HEAD + '-Y 1 +X 20'#10 ) + [ 2, 2, 0, 20, 128 + 19, 0, 2, 1, 2 ], 'そのままの並びが、走査線を越える' );
end;

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TImageCodecHdrTests );

end. //######################################################################### ■
