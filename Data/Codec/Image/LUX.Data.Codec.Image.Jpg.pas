unit LUX.Data.Codec.Image.Jpg;

// JPEG のコーデック（製品に同梱の Skia のコーデックを使う）
//
//【大きさと領域】
// ・JPEG は、規格上、一辺が 65,535 画素までである。
// ・Skia は、1 枚ぶんの連続した領域を求める。ゆえに、読み書きの間だけ、幅 × 高さ × 4 バイトを使う。
//
//【画素】
// ・JPEG は 8 ビットの形式であり、α を持たない。復号した画素の α は 1 であり、符号化は α を捨てる。
//
//【色空間】
// ・書き：色空間があれば、ICC プロファイルを、APP2 の ICC_PROFILE として埋め込む。
// ・読み：APP2 の ICC_PROFILE をつなげて解く。無ければ nil。

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.SysUtils, System.Classes,
     LUX.Data.Codec.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecJpg

     TImageCodecJpg = class( TImageCodec )
     private
       _Quality :Integer;
     protected
       ///// M E T H O D
       procedure DoDecode( const Stream_:TStream; const Raster_:TImageRaster ); override;
       procedure DoEncode( const Stream_:TStream; const Raster_:TImageRaster; const Header_:TImageHeader ); override;
       ///// A C C E S S O R
       function GetQuality :Integer; virtual;
       procedure SetQuality( const Quality_:Integer ); virtual;
     public
       constructor Create; override;
       ///// C L A S S
       class function Extensions :TArray<String>; override;
       class function Caption :String; override;
       class function Matches( const Bytes_:TBytes ) :Boolean; override;
       ///// P R O P E R T Y
       property Quality :Integer read GetQuality write SetQuality;  // 品質。1〜100 に丸める（既定は 90）
       ///// M E T H O D
       procedure Assign( const Codec_:TImageCodec ); override;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.Math, System.Skia,
     LUX.Color, LUX.Color.Space;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      JPG_SIZE_MAX = 65535;  // 一辺の最大の画素の数

      // マーカー（FF に続く 1 バイト）
      JPG_SOI  = $D8;  // 画像の始まり
      JPG_EOI  = $D9;  // 画像の終わり
      JPG_SOS  = $DA;  // 走査の始まり（これより後に、ヘッダーのセグメントは無い）
      JPG_APP0 = $E0;
      JPG_APP1 = $E1;
      JPG_APP2 = $E2;

      // APP2 の ICC_PROFILE の中身：署名（ICC_PROFILE と 0 の 12 バイト）・通し番号（1 から）・総数・データ
      JPG_ICC_SIGN :array [ 0..12-1 ] of Byte = ( $49, $43, $43, $5F, $50, $52, $4F, $46, $49, $4C, $45, $00 );
      JPG_ICC_HEAD = 12 + 2;                    // 署名と、通し番号・総数
      JPG_ICC_PART = 65535 - 2 - JPG_ICC_HEAD;  // セグメント 1 つに入るデータの最大（長さの欄は、自分の 2 バイトを含めて 65,535 まで）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

procedure Error( const Text_:String );
begin
     raise EImageCodec.Create( 'JPEG: ' + Text_ );
end;

//------------------------------------------------------------------------------

function ReadBytes( const Stream_:TStream ) :TBytes;
begin
     SetLength( Result, Stream_.Size - Stream_.Position );

     if Length( Result ) > 0 then Stream_.ReadBuffer( Result[ 0 ], Length( Result ) );
end;

//------------------------------------------------------------------------------ セグメント

// セグメントは「FF・マーカー・長さ（2 バイト。自分を含み、FF とマーカーを含まない）・中身」である。

// P_ の位置に、長さの欄まで読めるセグメントがあるか。

function IsSegm( const Jpeg_:TBytes; const P_:Integer ) :Boolean;
begin
     Result := ( P_ + 4 <= Length( Jpeg_ ) ) and ( Jpeg_[ P_ ] = $FF );
end;

// P_ の位置のセグメントの、FF から終わりまでのバイト数。

function SegmSize( const Jpeg_:TBytes; const P_:Integer ) :Integer;
begin
     Result := 2 + ( ( Jpeg_[ P_+2 ] shl 8 ) or Jpeg_[ P_+3 ] );
end;

//------------------------------------------------------------------------------ ICC プロファイル

// APP2 の ICC_PROFILE を、通し番号の順につなげる。無ければ、空を返す。

function ExtractIcc( const Jpeg_:TBytes ) :TBytes;
var
   P, L, N, I :Integer;
   Parts :TArray<TBytes>;
begin
     Result := nil;  Parts := nil;

     P := 2;  // SOI の次
     while IsSegm( Jpeg_, P ) and not ( Jpeg_[ P+1 ] in [ JPG_SOS, JPG_EOI ] ) do
     begin
          L := SegmSize( Jpeg_, P );

          if  ( Jpeg_[ P+1 ] = JPG_APP2 )
          and ( L >= 4 + JPG_ICC_HEAD ) and ( P + L <= Length( Jpeg_ ) )
          and CompareMem( @Jpeg_[ P+4 ], @JPG_ICC_SIGN, 12 ) then
          begin
               N := Jpeg_[ P+4+12 ];

               if Parts = nil then SetLength( Parts, Jpeg_[ P+4+13 ] );

               if ( 1 <= N ) and ( N <= Length( Parts ) ) then Parts[ N-1 ] := Copy( Jpeg_, P + 4 + JPG_ICC_HEAD, L - 4 - JPG_ICC_HEAD );
          end;

          Inc( P, L );
     end;

     for I := 0 to High( Parts ) do Result := Result + Parts[ I ];
end;

// ICC プロファイルを、APP2 の ICC_PROFILE として差し込む。
// 置き場所は、SOI と、それに続く APP0・APP1 の後ろである。1 つに入らない大きさは、分けて入れる。

function InsertIcc( const Jpeg_,Icc_:TBytes ) :TBytes;
var
   P, I, N, O, L :Integer;
   PartsN :Integer;
   Sign :TBytes;
begin
     P := 2;
     while IsSegm( Jpeg_, P ) and ( Jpeg_[ P+1 ] in [ JPG_APP0, JPG_APP1 ] ) do Inc( P, SegmSize( Jpeg_, P ) );

     SetLength( Sign, 12 );

     Move( JPG_ICC_SIGN, Sign[ 0 ], 12 );

     PartsN := ( Length( Icc_ ) + JPG_ICC_PART - 1 ) div JPG_ICC_PART;

     Result := Copy( Jpeg_, 0, P );

     O := 0;
     for I := 1 to PartsN do
     begin
          N := Min( JPG_ICC_PART, Length( Icc_ ) - O );

          L := 2 + JPG_ICC_HEAD + N;  // 長さの欄の値

          Result := Result + [ $FF, JPG_APP2, L shr 8, L and $FF ] + Sign + [ I, PartsN ] + Copy( Icc_, O, N );

          Inc( O, N );
     end;

     Result := Result + Copy( Jpeg_, P, Length( Jpeg_ ) - P );
end;

//------------------------------------------------------------------------------

// 符号のバイトから、Skia のコーデックと、画像の形を得る。
// コーデックは Jpeg_ を写さずに指すので、コーデックを使う間、Jpeg_ を生かしておくこと。

function OpenCodec( const Jpeg_:TBytes; out Header_:TImageHeader ) :ISkCodec;
var
   Icc :TBytes;
   CS :TLuxColorSpace;
begin
     Result := TSkCodec.MakeWithoutCopy( @Jpeg_[ 0 ], Length( Jpeg_ ) );

     if not Assigned( Result ) then Error( 'cannot read the header' );

     Icc := ExtractIcc( Jpeg_ );

     if Length( Icc ) > 0 then CS := TLuxColorSpaces.FromIcc( Icc )
                          else CS := nil;

     Header_ := TImageHeader.Create( Result.Width, Result.Height, CS, 8 );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecJpg

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TImageCodecJpg.GetQuality :Integer;
begin
     Result := _Quality;
end;

procedure TImageCodecJpg.SetQuality( const Quality_:Integer );
begin
     _Quality := EnsureRange( Quality_, 1, 100 );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TImageCodecJpg.Create;
begin
     inherited;

     _Quality := 90;
end;

//////////////////////////////////////////////////////////////////////// C L A S S

class function TImageCodecJpg.Extensions :TArray<String>;
begin
     Result := [ '.jpg', '.jpeg', '.jpe' ];
end;

class function TImageCodecJpg.Caption :String;
begin
     Result := 'JPEG';
end;

class function TImageCodecJpg.Matches( const Bytes_:TBytes ) :Boolean;
begin
     Result := ( Length( Bytes_ ) >= 3 ) and ( Bytes_[ 0 ] = $FF ) and ( Bytes_[ 1 ] = JPG_SOI ) and ( Bytes_[ 2 ] = $FF );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TImageCodecJpg.Assign( const Codec_:TImageCodec );
begin
     inherited;

     _Quality := ( Codec_ as TImageCodecJpg ).Quality;
end;

//------------------------------------------------------------------------------

// Skia のコーデックが確実に展開できる先は、8 ビット（BGRA8888）だけである。
// JPEG は 8 ビットなので、それで失うものは無い。

procedure TImageCodecJpg.DoDecode( const Stream_:TStream; const Raster_:TImageRaster );
var
   Jpeg :TBytes;
   Codec :ISkCodec;
   H :TImageHeader;
   Buf :TArray<TByteRGBA>;
   Row :TArray<TSingleRGBA>;
   P :PByteRGBA;
   X, Y :Integer;
begin
     Jpeg := ReadBytes( Stream_ );

     Codec := OpenCodec( Jpeg, H );

     Raster_.Header := H;

     SetLength( Buf, NativeInt( H.Width ) * H.Height );

     if not Codec.GetPixels( @Buf[ 0 ], NativeUInt( H.Width ) * SizeOf( TByteRGBA ),
                             TSkColorType.BGRA8888, TSkAlphaType.Unpremul ) then Error( 'cannot decode the pixels' );

     SetLength( Row, H.Width );

     P := @Buf[ 0 ];
     for Y := 0 to H.Height-1 do
     begin
          for X := 0 to H.Width-1 do
          begin
               Row[ X ] := P^;  Inc( P );
          end;

          Raster_.SetLine( 0, Y, 1, 0, H.Width, @Row[ 0 ] );
     end;
end;

//------------------------------------------------------------------------------

procedure TImageCodecJpg.DoEncode( const Stream_:TStream; const Raster_:TImageRaster; const Header_:TImageHeader );
var
   Buf :TArray<TByteRGBA>;
   Row :TArray<TSingleRGBA>;
   P :PByteRGBA;
   X, Y :Integer;
   Pixmap :ISkPixmap;
   Image :ISkImage;
   Jpeg :TBytes;
begin
     if ( Header_.Width > JPG_SIZE_MAX ) or ( Header_.Height > JPG_SIZE_MAX ) then Error( Format( 'the image (%d x %d) exceeds %d pixels on a side',
                                                                                       [ Header_.Width, Header_.Height, JPG_SIZE_MAX ] ) );

     SetLength( Buf, NativeInt( Header_.Width ) * Header_.Height );
     SetLength( Row, Header_.Width );

     P := @Buf[ 0 ];
     for Y := 0 to Header_.Height-1 do
     begin
          Raster_.GetLine( 0, Y, 1, 0, Header_.Width, @Row[ 0 ] );

          for X := 0 to Header_.Width-1 do
          begin
               P^ := TByteRGBA( Row[ X ] );  P^.A := $FF;  Inc( P );
          end;
     end;

     Pixmap := TSkPixmap.Create( TSkImageInfo.Create( Header_.Width, Header_.Height, TSkColorType.BGRA8888, TSkAlphaType.Opaque ),
                                 @Buf[ 0 ], NativeUInt( Header_.Width ) * SizeOf( TByteRGBA ) );

     Image := TSkImage.MakeFromRaster( Pixmap );

     if not Assigned( Image ) then Error( 'cannot wrap the pixels' );

     Jpeg := Image.Encode( TSkEncodedImageFormat.JPEG, _Quality );

     if Length( Jpeg ) = 0 then Error( 'cannot encode the pixels' );

     if Assigned( Header_.ColorSpace ) then Jpeg := InsertIcc( Jpeg, Header_.ColorSpace.IccProfile );

     Stream_.WriteBuffer( Jpeg[ 0 ], Length( Jpeg ) );
end;

initialization //############################################################### ■

     TImageCodec.Regist( TImageCodecJpg );

end. //######################################################################### ■
