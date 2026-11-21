unit Tests.Data.Image.Codec;

// LUX.Data.Image.Codec（TLuxImage と、画像のコーデックをつなぐ橋）の試験
//
// ・画像は、タイル（256 画素）の境をまたぐ大きさで作る。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageRasterTests

     [TestFixture]
     TLuxImageRasterTests = class
     public
       [Test] procedure HeaderOfEachFormat;
       [Test] procedure HeaderResizes;
       [Test] procedure LinesInEveryDirection;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFilerTests

     [TestFixture]
     TLuxImageFilerTests = class
     private
       _Loaded   :Integer;
       _Saved    :Integer;
       _Progress :Integer;
       ///// E V E N T
       procedure OnLoaded( Sender_:TObject );
       procedure OnSaved( Sender_:TObject );
       procedure OnProgress( Sender_:TObject );
     public
       [Setup] procedure Setup;
       [Test] procedure PngLossless8;
       [Test] procedure PngLossless16;
       [Test] procedure HdrFloat;
       [Test] procedure JpgByExtension;
       [Test] procedure LoadBuildsLevels;
       [Test] procedure ProgressReachesEnd;
       [Test] procedure AsyncSaveAndLoad;
       [Test] procedure LoadsByContent;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Classes, System.Math, System.IOUtils,
     LUX.Color, LUX.Color.Space,
     LUX.Data.Codec.Image,
     LUX.Data.Codec.Image.Png,
     LUX.Data.Codec.Image.Jpg,
     LUX.Data.Codec.Image.Hdr,
     LUX.Data.Image,
     LUX.Data.Image.Codec;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      W = 300;  // タイル（256 画素）の境をまたぐ
      H = 270;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

// 画像を、位置から決まる画素で埋める。標本は、Max_ 段階で表せる値にする（Max_ = 0 なら、1 を超える実数）

procedure Fill( const Image_:TLuxImage; const Max_:Integer );
var
   X, Y :Integer;
   Row :TArray<TSingleRGBA>;
begin
     SetLength( Row, Image_.Width );

     for Y := 0 to Image_.Height-1 do
     begin
          for X := 0 to Image_.Width-1 do
          begin
               if Max_ > 0 then Row[ X ] := TSingleRGBA.Create( ( ( X * 7919 + Y * 104729 ) and Max_ ) / Max_,
                                                                ( ( X * 31   + Y * 17     ) and Max_ ) / Max_,
                                                                ( ( X        + Y * 3      ) and Max_ ) / Max_,
                                                                ( ( X * 5    + Y * 11     ) and Max_ ) / Max_ )
                           else Row[ X ] := TSingleRGBA.Create( 0.01 + X * 0.05, 0.01 + Y * 0.03, 0.01 + ( X + Y ) * 0.001, 1 );
          end;

          Image_.SetRow( 0, 0, Y, 1, Image_.Width, @Row[ 0 ] );
     end;

     Image_.Changed;
end;

// 2 つの画像の、同じ位置の画素の、成分の差の最大（最大の成分に対する割合で測るときは、Relative_ を True にする）

function Distance( const A_,B_:TLuxImage; const Relative_:Boolean = False ) :Single;
var
   X, Y :Integer;
   RA, RB :TArray<TSingleRGBA>;
   D :TSingleRGBA;
   E :Single;
begin
     if ( A_.Width <> B_.Width ) or ( A_.Height <> B_.Height ) then Exit( Infinity );

     SetLength( RA, A_.Width );
     SetLength( RB, A_.Width );

     Result := 0;

     for Y := 0 to A_.Height-1 do
     begin
          A_.GetRow( 0, 0, Y, 1, A_.Width, @RA[ 0 ] );
          B_.GetRow( 0, 0, Y, 1, A_.Width, @RB[ 0 ] );

          for X := 0 to A_.Width-1 do
          begin
               D := RA[ X ] - RB[ X ];

               E := Max( Max( Abs( D.R ), Abs( D.G ) ), Max( Abs( D.B ), Abs( D.A ) ) );

               if Relative_ then E := E / Max( RA[ X ].R, Max( RA[ X ].G, RA[ X ].B ) );

               Result := Max( Result, E );
          end;
     end;
end;

// 画像を、コーデックで流れに書き、別の画像に読み戻す

procedure Through( const Codec_:TImageCodec; const From_,To_:TLuxImage );
var
   S :TBytesStream;
begin
     S := TBytesStream.Create;
     try
        TLuxImageFiler.SaveToStream( From_, S, Codec_ );

        S.Position := 0;

        TLuxImageFiler.LoadFromStream( To_, S );
     finally
        S.Free;
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageRasterTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 置き場の形は、画像の大きさ・色空間と、画素形式の標本の精度である
procedure TLuxImageRasterTests.HeaderOfEachFormat;
const
     DEPTHS :array [ TLuxPixel ] of Integer = ( 8, 16, 16, 32 );
var
   K :TLuxPixel;
   I :TLuxImage;
   R :TLuxImageRaster;
begin
     for K := Low( TLuxPixel ) to High( TLuxPixel ) do
     begin
          I := LuxImageClass( K ).Create( 5, 3 );
          R := TLuxImageRaster.Create( I );
          try
             I.ColorSpace := TLuxColorSpaces.AdobeRGB;

             Assert.AreEqual( 5, R.Header.Width  );
             Assert.AreEqual( 3, R.Header.Height );
             Assert.AreEqual( DEPTHS[ K ], R.Header.Depth );
             Assert.IsTrue( R.Header.ColorSpace = TLuxColorSpaces.AdobeRGB );
          finally
             R.Free;
             I.Free;
          end;
     end;
end;

// 形を書くと、画像は、その大きさと色空間になる。画素形式は変わらない
procedure TLuxImageRasterTests.HeaderResizes;
var
   I :TLuxImage;
   R :TLuxImageRaster;
begin
     I := TLuxImageUInt08.Create;
     R := TLuxImageRaster.Create( I );
     try
        R.Header := TImageHeader.Create( 40, 30, TLuxColorSpaces.Rec2020, 16 );

        Assert.AreEqual( 40, I.Width  );
        Assert.AreEqual( 30, I.Height );
        Assert.IsTrue( I.ColorSpace = TLuxColorSpaces.Rec2020 );
        Assert.AreEqual( 8, R.Header.Depth );
     finally
        R.Free;
        I.Free;
     end;
end;

// 並びは、どの歩みでも、始点から歩みずつ進んだ位置の画素である（読みも書きも）
procedure TLuxImageRasterTests.LinesInEveryDirection;
const
     N = 5;
     STEPS :array [ 0..6-1, 0..2-1 ] of Integer = ( ( 1, 0 ), ( -1, 0 ), ( 0, 1 ), ( 0, -1 ), ( 2, 0 ), ( 3, -2 ) );
var
   I :TLuxImageSFlo32;
   R :TLuxImageRaster;
   S, K :Integer;
   X0, Y0 :Integer;
   DX, DY :Integer;
   Ps, Qs :TArray<TSingleRGBA>;
begin
     I := TLuxImageSFlo32.Create( W, H );
     R := TLuxImageRaster.Create( I );
     try
        SetLength( Ps, N );
        SetLength( Qs, N );

        for S := 0 to High( STEPS ) do
        begin
             DX := STEPS[ S, 0 ];
             DY := STEPS[ S, 1 ];

             X0 := 254;  // タイルの境のすぐ手前
             Y0 := 257;  // タイルの境のすぐ先

             for K := 0 to N-1 do Ps[ K ] := TSingleRGBA.Create( S + 1, K + 1, 0.5, 1 );

             R.SetLine( X0, Y0, DX, DY, N, @Ps[ 0 ] );

             for K := 0 to N-1 do Assert.AreEqual( Single( K + 1 ), I.Pixels[ X0 + K * DX, Y0 + K * DY ].G, Format( '歩み (%d, %d) の %d 番目', [ DX, DY, K ] ) );

             R.GetLine( X0, Y0, DX, DY, N, @Qs[ 0 ] );

             for K := 0 to N-1 do Assert.AreEqual( Single( K + 1 ), Qs[ K ].G, Format( '歩み (%d, %d) の %d 番目を読む', [ DX, DY, K ] ) );
        end;
     finally
        R.Free;
        I.Free;
     end;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFilerTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

////////////////////////////////////////////////////////////////////// E V E N T

procedure TLuxImageFilerTests.OnLoaded( Sender_:TObject );
begin
     Inc( _Loaded );
end;

procedure TLuxImageFilerTests.OnSaved( Sender_:TObject );
begin
     Inc( _Saved );
end;

procedure TLuxImageFilerTests.OnProgress( Sender_:TObject );
begin
     Inc( _Progress );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

procedure TLuxImageFilerTests.Setup;
begin
     _Loaded   := 0;
     _Saved    := 0;
     _Progress := 0;
end;

// 8 ビットの画像は、PNG を通すと、画素も色空間も、そのまま戻る
procedure TLuxImageFilerTests.PngLossless8;
var
   C :TImageCodecPng;
   A, B :TLuxImage;
begin
     C := TImageCodecPng.Create;
     A := TLuxImageUInt08.Create( W, H );
     B := TLuxImageUInt08.Create;
     try
        A.ColorSpace := TLuxColorSpaces.DisplayP3;

        Fill( A, $FF );

        Through( C, A, B );

        Assert.AreEqual( Single( 0 ), Distance( A, B ) );
        Assert.IsTrue( B.ColorSpace = TLuxColorSpaces.DisplayP3 );
     finally
        B.Free;
        A.Free;
        C.Free;
     end;
end;

// 16 ビットの画像は、PNG を通すと、画素が、そのまま戻る
procedure TLuxImageFilerTests.PngLossless16;
var
   C :TImageCodecPng;
   A, B :TLuxImage;
begin
     C := TImageCodecPng.Create;
     A := TLuxImageUInt16.Create( W, H );
     B := TLuxImageUInt16.Create;
     try
        Fill( A, $FFFF );

        Through( C, A, B );

        Assert.AreEqual( Single( 0 ), Distance( A, B ) );
        Assert.IsTrue( B.ColorSpace = nil );
     finally
        B.Free;
        A.Free;
        C.Free;
     end;
end;

// 実数の画像は、Radiance HDR を通すと、仮数の刻みの誤差で戻る（1 を超える値を含む）
procedure TLuxImageFilerTests.HdrFloat;
var
   C :TImageCodecHdr;
   A, B :TLuxImage;
begin
     C := TImageCodecHdr.Create;
     A := TLuxImageSFlo32.Create( W, H );
     B := TLuxImageSFlo32.Create;
     try
        Fill( A, 0 );

        Through( C, A, B );

        Assert.IsTrue( Distance( A, B, True ) <= 1 / 255 );
        Assert.IsTrue( B.ColorSpace.IsLinear );
     finally
        B.Free;
        A.Free;
        C.Free;
     end;
end;

// 拡張子から作ったコーデックで JPEG を通すと、既定の品質（90）で書かれ、なだらかな画像は、ほぼ戻る
procedure TLuxImageFilerTests.JpgByExtension;
var
   C :TImageCodec;
   A, B :TLuxImage;
   X, Y :Integer;
   Row :TArray<TSingleRGBA>;
begin
     C := TImageCodec.CreateFor( 'image.jpg' );
     A := TLuxImageUInt08.Create( W, H );
     B := TLuxImageUInt08.Create;
     try
        SetLength( Row, W );

        for Y := 0 to H-1 do
        begin
             for X := 0 to W-1 do Row[ X ] := TSingleRGBA.Create( X / ( W - 1 ), Y / ( H - 1 ), 0.5, 1 );

             A.SetRow( 0, 0, Y, 1, W, @Row[ 0 ] );
        end;

        Through( C, A, B );

        Assert.IsTrue( Distance( A, B ) < 0.05 );
     finally
        B.Free;
        A.Free;
        C.Free;
     end;
end;

// 読み込みは、縮小段の更新までを済ませる（段 1 の画素は、段 0 の 4 画素の平均）
procedure TLuxImageFilerTests.LoadBuildsLevels;
var
   C :TImageCodecPng;
   A, B :TLuxImageSFlo32;
   P :TSingleRGBA;
   Q :array [ 0..4-1 ] of TSingleRGBA;
   X, Y, K :Integer;
begin
     C := TImageCodecPng.Create;
     A := TLuxImageSFlo32.Create( W, H );
     B := TLuxImageSFlo32.Create;
     try
        Fill( A, $FFFF );

        Through( C, A, B );

        for K := 0 to 3 do
        begin
             X := 100 + K * 40;
             Y :=  90 + K * 50;

             Q[ 0 ] := B.Pixels[ 2 * X    , 2 * Y     ];
             Q[ 1 ] := B.Pixels[ 2 * X + 1, 2 * Y     ];
             Q[ 2 ] := B.Pixels[ 2 * X    , 2 * Y + 1 ];
             Q[ 3 ] := B.Pixels[ 2 * X + 1, 2 * Y + 1 ];

             B.GetRow( 1, X, Y, 1, 1, @P );

             Assert.AreEqual( ( Q[ 0 ].R + Q[ 1 ].R + Q[ 2 ].R + Q[ 3 ].R ) / 4, P.R, 1e-5, Format( '段 1 の (%d, %d)', [ X, Y ] ) );
        end;
     finally
        B.Free;
        A.Free;
        C.Free;
     end;
end;

// 読みも書きも、進捗が知らされ、終わると 1 になる
procedure TLuxImageFilerTests.ProgressReachesEnd;
var
   C :TImageCodecPng;
   A, B :TLuxImage;
   S :TBytesStream;
begin
     C := TImageCodecPng.Create;
     A := TLuxImageUInt08.Create( W, H );
     B := TLuxImageUInt08.Create;
     S := TBytesStream.Create;
     try
        Fill( A, $FF );

        A.OnProgress.Add( OnProgress );
        B.OnProgress.Add( OnProgress );

        TLuxImageFiler.SaveToStream( A, S, C );

        Assert.AreEqual( Single( 1 ), A.Progress );
        Assert.IsTrue( _Progress > 10, '書く間の知らせ' );

        _Progress := 0;

        S.Position := 0;

        TLuxImageFiler.LoadFromStream( B, S );

        Assert.AreEqual( Single( 1 ), B.Progress );
        Assert.IsTrue( _Progress > 10, '読む間の知らせ' );
     finally
        S.Free;
        B.Free;
        A.Free;
        C.Free;
     end;
end;

// 非同期の読み書き：呼んだ直後にコーデックを解放してよく、設定は写しに引き継がれ、終わりが 1 回ずつ知らされる
procedure TLuxImageFilerTests.AsyncSaveAndLoad;
var
   F :String;
   C :TImageCodecPng;
   A, B :TLuxImage;
   Z :TBytes;
begin
     F := TPath.Combine( TPath.GetTempPath, TPath.GetGUIDFileName + '.png' );

     A := TLuxImageUInt08.Create( W, H );
     B := TLuxImageUInt08.Create;
     try
        Fill( A, $FF );

        A.OnSaved .Add( OnSaved  );
        B.OnLoaded.Add( OnLoaded );

        ///// 書く

        C := TImageCodecPng.Create;
        try
           C.Alpha := False;

           TLuxImageFiler.SaveToFileAsync( A, F, C );
        finally
           C.Free;
        end;

        A.WaitFor;

        Assert.IsFalse( A.Busy );
        Assert.AreEqual( 1, _Saved );

        Z := TFile.ReadAllBytes( F );

        Assert.AreEqual( 2, Integer( Z[ 8 + 8 + 9 ] ), '写しに引き継がれた設定（α 無しのカラータイプ）' );

        ///// 読む

        TLuxImageFiler.LoadFromFileAsync( B, F );

        B.WaitFor;

        Assert.IsFalse( B.Busy );
        Assert.AreEqual( 1, _Loaded );

        Assert.AreEqual( W, B.Width  );
        Assert.AreEqual( H, B.Height );
        Assert.AreEqual( Single( 1 ), B[ 10, 10 ].A, 'α 無しで書いたので、α は 1' );
        Assert.AreEqual( A[ 257, 3 ].R, B[ 257, 3 ].R );
     finally
        B.Free;
        A.Free;

        if TFile.Exists( F ) then TFile.Delete( F );
     end;
end;

// 読み込みは、形式を中身で選ぶ：拡張子が違っていても読め、どの形式でもない中身は断られる
procedure TLuxImageFilerTests.LoadsByContent;
var
   F :String;
   C :TImageCodecPng;
   A, B :TLuxImage;
begin
     F := TPath.Combine( TPath.GetTempPath, TPath.GetGUIDFileName + '.jpg' );  // 中身は PNG、拡張子は JPEG

     C := TImageCodecPng.Create;
     A := TLuxImageUInt08.Create( W, H );
     B := TLuxImageUInt08.Create;
     try
        Fill( A, $FF );

        TLuxImageFiler.SaveToFile( A, F, C );

        Assert.IsTrue( TLuxImageFiler.CodecOf( F ) = TImageCodecPng );

        TLuxImageFiler.LoadFromFile( B, F );

        Assert.AreEqual( Single( 0 ), Distance( A, B ) );

        TFile.WriteAllBytes( F, [ 1, 2, 3, 4, 5, 6, 7, 8, 9 ] );

        Assert.IsTrue( TLuxImageFiler.CodecOf( F ) = nil );

        Assert.WillRaise( procedure begin TLuxImageFiler.LoadFromFile( B, F ); end, EImageCodec );
     finally
        B.Free;
        A.Free;
        C.Free;

        if TFile.Exists( F ) then TFile.Delete( F );
     end;
end;

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TLuxImageRasterTests );
     TDUnitX.RegisterTestFixture( TLuxImageFilerTests  );

end. //######################################################################### ■
