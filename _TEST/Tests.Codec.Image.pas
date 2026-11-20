unit Tests.Codec.Image;

// LUX.Data.Codec.Image（コーデックの基底）の試験と、コーデックの試験が共に使う、試験用の置き場
//
//【試験用の置き場】
// ・TTestRaster は、画素を 1 次元の配列に持つ、TImageRaster の最小の実装である。
// ・SetLine で書かれた回数を画素ごとに数え、画像の外への読み書きは、その場で失敗させる。
//   これで、コーデックの約束（どの画素も、ちょうど 1 回渡す）を確かめられる。

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.SysUtils, System.Classes,
     DUnitX.TestFramework,
     LUX.Color, LUX.Color.Space,
     LUX.Data.Codec.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTestRaster

     TTestRaster = class( TImageRaster )
     private
       _Header :TImageHeader;
       _Pixels :TArray<TSingleRGBA>;
       _Writes :TArray<Integer>;  // 画素ごとの、SetLine で書かれた回数
       ///// M E T H O D
       function Index( const X_,Y_:Integer ) :Integer;
     protected
       ///// A C C E S S O R
       function GetHeader :TImageHeader; override;
       procedure SetHeader( const Header_:TImageHeader ); override;
       function GetPixels( const X_,Y_:Integer ) :TSingleRGBA;
       procedure SetPixels( const X_,Y_:Integer; const Pixel_:TSingleRGBA );
     public
       constructor Create; overload;
       constructor Create( const Width_,Height_:Integer; const ColorSpace_:TLuxColorSpace; const Depth_:Integer ); overload;
       ///// P R O P E R T Y
       property Pixels[ const X_,Y_:Integer ] :TSingleRGBA read GetPixels write SetPixels; default;
       ///// M E T H O D
       procedure GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); override;
       procedure SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); override;
       function WrittenOnce :Boolean;                           // どの画素も、ちょうど 1 回書かれたか
       function Distance( const Raster_:TTestRaster ) :Single;  // 同じ位置の画素の、成分の差の最大（大きさが違えば無限大）
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecTests

     [TestFixture]
     TImageCodecTests = class
     public
       [Test] procedure ClassOfContent;
       [Test] procedure ClassForExtension;
       [Test] procedure CreateForDefaults;
       [Test] procedure CreateForUnknown;
       [Test] procedure CloneCopiesSettings;
       [Test] procedure DialogFilterItems;
       [Test] procedure EmptyImageRejected;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function StreamOf( const Bytes_:TBytes ) :TBytesStream;  // バイトの並びを読む流れ

implementation //############################################################### ■

uses System.Math,
     LUX.Data.Codec.Image.Png,
     LUX.Data.Codec.Image.Jpg,
     LUX.Data.Codec.Image.Hdr;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function StreamOf( const Bytes_:TBytes ) :TBytesStream;
begin
     Result := TBytesStream.Create( Bytes_ );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTestRaster

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

function TTestRaster.Index( const X_,Y_:Integer ) :Integer;
begin
     if ( X_ < 0 ) or ( X_ >= _Header.Width  )
     or ( Y_ < 0 ) or ( Y_ >= _Header.Height ) then raise ERangeError.CreateFmt( 'pixel (%d, %d) is outside the image', [ X_, Y_ ] );

     Result := Y_ * _Header.Width + X_;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTestRaster.GetHeader :TImageHeader;
begin
     Result := _Header;
end;

procedure TTestRaster.SetHeader( const Header_:TImageHeader );
begin
     _Header := Header_;

     _Pixels := nil;  SetLength( _Pixels, Header_.Width * Header_.Height );
     _Writes := nil;  SetLength( _Writes, Header_.Width * Header_.Height );
end;

//------------------------------------------------------------------------------

function TTestRaster.GetPixels( const X_,Y_:Integer ) :TSingleRGBA;
begin
     Result := _Pixels[ Index( X_, Y_ ) ];
end;

procedure TTestRaster.SetPixels( const X_,Y_:Integer; const Pixel_:TSingleRGBA );
begin
     _Pixels[ Index( X_, Y_ ) ] := Pixel_;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTestRaster.Create;
begin
     inherited Create;

end;

constructor TTestRaster.Create( const Width_,Height_:Integer; const ColorSpace_:TLuxColorSpace; const Depth_:Integer );
begin
     Create;

     SetHeader( TImageHeader.Create( Width_, Height_, ColorSpace_, Depth_ ) );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TTestRaster.GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );
var
   I :Integer;
begin
     for I := 0 to N_-1 do Pixels_[ I ] := _Pixels[ Index( X_ + I * DX_, Y_ + I * DY_ ) ];
end;

procedure TTestRaster.SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );
var
   I, J :Integer;
begin
     for I := 0 to N_-1 do
     begin
          J := Index( X_ + I * DX_, Y_ + I * DY_ );

          _Pixels[ J ] := Pixels_[ I ];

          Inc( _Writes[ J ] );
     end;
end;

//------------------------------------------------------------------------------

function TTestRaster.WrittenOnce :Boolean;
var
   W :Integer;
begin
     for W in _Writes do if W <> 1 then Exit( False );

     Result := True;
end;

function TTestRaster.Distance( const Raster_:TTestRaster ) :Single;
var
   I :Integer;
   D :TSingleRGBA;
begin
     if ( _Header.Width <> Raster_._Header.Width ) or ( _Header.Height <> Raster_._Header.Height ) then Exit( Infinity );

     Result := 0;

     for I := 0 to High( _Pixels ) do
     begin
          D := _Pixels[ I ] - Raster_._Pixels[ I ];

          Result := Max( Result, Max( Max( Abs( D.R ), Abs( D.G ) ), Max( Abs( D.B ), Abs( D.A ) ) ) );
     end;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 中身から、形式が選ばれる：どの形式で書いた流れも、その形式と見分けられる。流れの位置は変わらない
procedure TImageCodecTests.ClassOfContent;
var
   K :TImageCodecClass;
   C :TImageCodec;
   R :TTestRaster;
   S :TBytesStream;
begin
     for K in TImageCodec.Codecs do
     begin
          C := K.Create;
          R := TTestRaster.Create( 20, 20, nil, 8 );
          S := TBytesStream.Create;
          try
             C.Encode( S, R );

             S.Position := 0;

             Assert.IsTrue( TImageCodec.ClassOf( S ) = K, K.Caption );

             Assert.AreEqual( Int64( 0 ), S.Position, K.Caption );
          finally
             S.Free;
             R.Free;
             C.Free;
          end;
     end;

     ///// どの形式でもない中身と、空の流れ

     S := TBytesStream.Create( [ 1, 2, 3, 4, 5, 6, 7, 8, 9 ] );
     try
        Assert.IsTrue( TImageCodec.ClassOf( S ) = nil );
     finally
        S.Free;
     end;

     S := TBytesStream.Create;
     try
        Assert.IsTrue( TImageCodec.ClassOf( S ) = nil );
     finally
        S.Free;
     end;
end;

// 拡張子から、形式が選ばれる（大文字と小文字を区別しない。知らない拡張子は nil）
procedure TImageCodecTests.ClassForExtension;
begin
     Assert.IsTrue( TImageCodec.ClassFor( 'a.png'       ) = TImageCodecPng );
     Assert.IsTrue( TImageCodec.ClassFor( 'C:\x\A.PNG'  ) = TImageCodecPng );
     Assert.IsTrue( TImageCodec.ClassFor( 'a.jpg'       ) = TImageCodecJpg );
     Assert.IsTrue( TImageCodec.ClassFor( 'a.jpeg'      ) = TImageCodecJpg );
     Assert.IsTrue( TImageCodec.ClassFor( 'a.jpe'       ) = TImageCodecJpg );
     Assert.IsTrue( TImageCodec.ClassFor( 'a.hdr'       ) = TImageCodecHdr );
     Assert.IsTrue( TImageCodec.ClassFor( 'a.pic'       ) = TImageCodecHdr );
     Assert.IsTrue( TImageCodec.ClassFor( 'a.gif'       ) = nil            );
     Assert.IsTrue( TImageCodec.ClassFor( 'png'         ) = nil            );
end;

// 拡張子から作ったコーデックにも、形式ごとの既定の設定が入っている
procedure TImageCodecTests.CreateForDefaults;
var
   C :TImageCodec;
begin
     C := TImageCodec.CreateFor( 'a.png' );
     try
        Assert.IsTrue( ( C as TImageCodecPng ).Alpha, 'PNG の Alpha' );
        Assert.IsTrue( ( C as TImageCodecPng ).Level = plDefault, 'PNG の Level' );
     finally
        C.Free;
     end;

     C := TImageCodec.CreateFor( 'a.jpg' );
     try
        Assert.AreEqual( 90, ( C as TImageCodecJpg ).Quality, 'JPEG の Quality' );
     finally
        C.Free;
     end;
end;

// 知らない拡張子からは、nil が返る
procedure TImageCodecTests.CreateForUnknown;
begin
     Assert.IsTrue( TImageCodec.CreateFor( 'a.gif' ) = nil );
end;

// 写しは、同じクラスで、同じ設定を持ち、元とは別のものである
procedure TImageCodecTests.CloneCopiesSettings;
var
   P, P1 :TImageCodecPng;
   J, J1 :TImageCodecJpg;
begin
     P  := TImageCodecPng.Create;
     P1 := nil;
     try
        P.Alpha := False;
        P.Level := plNone;

        P1 := P.Clone as TImageCodecPng;

        Assert.IsTrue( P1 <> P );
        Assert.IsFalse( P1.Alpha );
        Assert.IsTrue( P1.Level = plNone );
     finally
        P1.Free;
        P .Free;
     end;

     J  := TImageCodecJpg.Create;
     J1 := nil;
     try
        J.Quality := 37;

        J1 := J.Clone as TImageCodecJpg;

        Assert.AreEqual( 37, J1.Quality );
     finally
        J1.Free;
        J .Free;
     end;
end;

// ダイアログの Filter は、登録の順の形式ごとの項目であり、見出しを渡すと、全形式の項目が先頭に付く
procedure TImageCodecTests.DialogFilterItems;
const
     EACH = 'PNG (*.png)|*.png|JPEG (*.jpg;*.jpeg;*.jpe)|*.jpg;*.jpeg;*.jpe|Radiance HDR (*.hdr;*.pic)|*.hdr;*.pic';
     ALL  = '*.png;*.jpg;*.jpeg;*.jpe;*.hdr;*.pic';
begin
     Assert.AreEqual( EACH, TImageCodec.DialogFilter );

     Assert.AreEqual( 'Images (' + ALL + ')|' + ALL + '|' + EACH, TImageCodec.DialogFilter( 'Images' ) );
end;

// 大きさの無い画像は、どの形式でも、符号化の前に断られ、流れには何も書かれない
procedure TImageCodecTests.EmptyImageRejected;
var
   K :TImageCodecClass;
   C :TImageCodec;
   R :TTestRaster;
   S :TBytesStream;
begin
     for K in TImageCodec.Codecs do
     begin
          C := K.Create;
          R := TTestRaster.Create;
          S := TBytesStream.Create;
          try
             Assert.WillRaise( procedure begin C.Encode( S, R ); end, EImageCodec, K.Caption );

             Assert.AreEqual( Int64( 0 ), S.Size, K.Caption );
          finally
             S.Free;
             R.Free;
             C.Free;
          end;
     end;
end;

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TImageCodecTests );

end. //######################################################################### ■
