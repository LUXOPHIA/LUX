unit Tests.Codec.Image.Jpg;

// LUX.Data.Codec.Image.Jpg の試験
//
// ・JPEG は非可逆なので、画素は、なだらかな画像で、許す差を決めて比べる。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecJpgTests

     [TestFixture]
     TImageCodecJpgTests = class
     public
       [Test] procedure RoundTrip;
       [Test] procedure QualityRange;
       [Test] procedure QualityChangesSize;
       [Test] procedure ColorSpaceNone;
       [Test] procedure ColorSpaceIcc;
       [Test] procedure RejectsTooLarge;
       [Test] procedure RejectsBrokenData;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Classes,
     LUX.Color, LUX.Color.Space,
     LUX.Data.Codec.Image,
     LUX.Data.Codec.Image.Jpg,
     Tests.Codec.Image;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

// なだらかな画像（α は、0〜1 に散らしてある）

function Smooth( const Width_,Height_:Integer; const ColorSpace_:TLuxColorSpace ) :TTestRaster;
var
   X, Y :Integer;
begin
     Result := TTestRaster.Create( Width_, Height_, ColorSpace_, 8 );

     for Y := 0 to Height_-1 do
     for X := 0 to Width_ -1 do Result[ X, Y ] := TSingleRGBA.Create( X / ( Width_ - 1 ),
                                                                       Y / ( Height_ - 1 ),
                                                                       ( X + Y ) / ( Width_ + Height_ - 2 ),
                                                                       ( X mod 4 ) / 3 );
end;

function Encoded( const Raster_:TTestRaster; const Quality_:Integer ) :TBytes;
var
   C :TImageCodecJpg;
   S :TBytesStream;
begin
     C := TImageCodecJpg.Create;
     S := TBytesStream.Create;
     try
        C.Quality := Quality_;

        C.Encode( S, Raster_ );

        Result := Copy( S.Bytes, 0, S.Size );
     finally
        S.Free;
        C.Free;
     end;
end;

function Decoded( const Jpeg_:TBytes ) :TTestRaster;
var
   C :TImageCodecJpg;
   S :TStream;
begin
     Result := TTestRaster.Create;
     try
        C := TImageCodecJpg.Create;
        S := StreamOf( Jpeg_ );
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

// バイトの並びの中の、ASCII の文字の並び Text_ の位置（無ければ -1）

function Find( const Bytes_:TBytes; const Text_:String ) :Integer;
var
   T :TBytes;
   I :Integer;
begin
     T := TEncoding.ASCII.GetBytes( Text_ );

     for I := 0 to Length( Bytes_ ) - Length( T ) do
     begin
          if CompareMem( @Bytes_[ I ], @T[ 0 ], Length( T ) ) then Exit( I );
     end;

     Result := -1;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecJpgTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 高い品質では、なだらかな画像の色は、ほぼ元に戻る。α は捨てられ、復号した α は 1 になる
procedure TImageCodecJpgTests.RoundTrip;
const
     TOL = 0.04;
var
   A, B :TTestRaster;
   X, Y :Integer;
begin
     A := Smooth( 64, 48, nil );
     B := nil;
     try
        B := Decoded( Encoded( A, 95 ) );

        Assert.AreEqual( 64, B.Header.Width  );
        Assert.AreEqual( 48, B.Header.Height );
        Assert.AreEqual(  8, B.Header.Depth  );

        Assert.IsTrue( B.WrittenOnce );

        for Y := 0 to 48-1 do
        for X := 0 to 64-1 do
        begin
             Assert.AreEqual( Single( 1 ), B[ X, Y ].A );

             if ( Abs( A[ X, Y ].R - B[ X, Y ].R ) > TOL )
             or ( Abs( A[ X, Y ].G - B[ X, Y ].G ) > TOL )
             or ( Abs( A[ X, Y ].B - B[ X, Y ].B ) > TOL ) then Assert.Fail( Format( '画素 (%d, %d)', [ X, Y ] ) );
        end;
     finally
        B.Free;
        A.Free;
     end;
end;

// 品質は、1〜100 に丸められる
procedure TImageCodecJpgTests.QualityRange;
var
   C :TImageCodecJpg;
begin
     C := TImageCodecJpg.Create;
     try
        C.Quality :=    0;  Assert.AreEqual(   1, C.Quality );
        C.Quality := 1000;  Assert.AreEqual( 100, C.Quality );
        C.Quality :=   50;  Assert.AreEqual(  50, C.Quality );
     finally
        C.Free;
     end;
end;

// 品質を下げると、小さくなる
procedure TImageCodecJpgTests.QualityChangesSize;
var
   A :TTestRaster;
begin
     A := Smooth( 128, 128, nil );
     try
        Assert.IsTrue( Length( Encoded( A, 20 ) ) < Length( Encoded( A, 95 ) ) );
     finally
        A.Free;
     end;
end;

// 色空間が無ければ、ICC プロファイルは埋め込まれず、復号した色空間も無い
procedure TImageCodecJpgTests.ColorSpaceNone;
var
   A, B :TTestRaster;
   Z :TBytes;
begin
     A := Smooth( 16, 16, nil );
     B := nil;
     try
        Z := Encoded( A, 90 );

        Assert.IsTrue( Find( Z, 'ICC_PROFILE' ) < 0 );

        B := Decoded( Z );

        Assert.IsTrue( B.Header.ColorSpace = nil );
     finally
        B.Free;
        A.Free;
     end;
end;

// 色空間は、ICC プロファイルとして埋め込まれ、復号すると、どのプリセットも、同じインスタンスに戻る
procedure TImageCodecJpgTests.ColorSpaceIcc;
var
   CS :TLuxColorSpace;
   A, B :TTestRaster;
   Z :TBytes;
begin
     for CS in TLuxColorSpaces.Presets do
     begin
          A := Smooth( 16, 16, CS );
          B := nil;
          try
             Z := Encoded( A, 90 );

             Assert.IsTrue( Find( Z, 'ICC_PROFILE' ) > 0, CS.Name );

             B := Decoded( Z );

             Assert.IsTrue( B.Header.ColorSpace = CS, CS.Name );
          finally
             B.Free;
             A.Free;
          end;
     end;
end;

// 一辺が 65,535 画素を超える画像は、符号化の前に断られる
procedure TImageCodecJpgTests.RejectsTooLarge;
var
   A :TTestRaster;
begin
     A := TTestRaster.Create( 65536, 1, nil, 8 );
     try
        Assert.WillRaise( procedure begin Encoded( A, 90 ); end, EImageCodec );
     finally
        A.Free;
     end;
end;

// JPEG でないデータは、例外になる
procedure TImageCodecJpgTests.RejectsBrokenData;
begin
     Assert.WillRaise( procedure begin Decoded( nil ).Free; end, EImageCodec, '空' );

     Assert.WillRaise( procedure begin Decoded( [ 1, 2, 3, 4, 5, 6, 7, 8 ] ).Free; end, EImageCodec, 'JPEG の始まりでない' );

     Assert.WillRaise( procedure begin Decoded( [ $FF, $D8, $FF, $D9 ] ).Free; end, EImageCodec, '中身が無い' );
end;

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TImageCodecJpgTests );

end. //######################################################################### ■
