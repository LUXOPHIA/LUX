unit LUX.Data.Image.Files.Jpg;

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.Classes, System.SysUtils,
     LUX.Data.Image, LUX.Data.Image.Files;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFilerJpg

     ///// JPEG の読み書き（ Skia のコーデックを使う ）
     /////
     ///// ・規格上 65,535 角までで、Skia は画像１枚分の連続バッファを要求するので、
     /////   読み書きの間だけ画像本体とは別に 幅 × 高さ × 4 バイトを必要とする。
     ///// ・Skia のコーデックは 8bit 以外へ確実に展開できないので、常に BGRA8888 で受けてから
     /////   対象の画素形式へ変換する。JPEG は 8bit の形式なので損失は無い。
     ///// ・復号は途中経過を返さない不可分な呼び出しなので、進捗はそこだけ足踏みする。
     ///// ・色空間：Image.ColorSpace があれば ICC プロファイルを APP2 の ICC_PROFILE として
     /////   埋め込み、読みでは APP2 を繋いで解析する。

     TLuxImageFilerJpg = class( TLuxImageFiler )
     private
       _Quality :Integer;
       ///// A C C E S S O R
       procedure SetQuality( const Quality_:Integer );
     protected
       ///// M E T H O D
       procedure DoLoad( const Image_:TLuxImage; const Stream_:TStream ); override;
       procedure DoSave( const Image_:TLuxImage; const Stream_:TStream ); override;
     public
       constructor Create;
       ///// C L A S S
       class function Extensions :TArray<String>; override;
       class function Caption :String; override;
       ///// P R O P E R T Y
       property Quality :Integer read _Quality write SetQuality;  // 1 〜 100 （既定 90 ）
       ///// M E T H O D
       procedure Assign( const Filer_:TLuxImageFiler ); override;
       function ImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean; override;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function LuxJpegIcc( const Jpeg_:TBytes ) :TBytes;            // APP2 の ICC_PROFILE を繋げて取り出す（無ければ空）
function LuxJpegWithIcc( const Jpeg_,Icc_:TBytes ) :TBytes;   // APP2 の ICC_PROFILE を挿入したものを返す

implementation //############################################################### ■

uses System.Math,
     System.Skia,
     LUX, LUX.Color, LUX.Color.Space;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% APP2 ICC_PROFILE

///// APP2 セグメント（ FFE2 長さ 'ICC_PROFILE'#0 通番 総数 データ ）を通番順に繋げる

function LuxJpegIcc( const Jpeg_:TBytes ) :TBytes;
var
   P, L, N, I, K :Integer;
   Parts :TArray<TBytes>;
   Cnt   :Integer;
begin
     Result := nil;  Parts := nil;  Cnt := 0;

     if ( Length( Jpeg_ ) < 4 ) or ( Jpeg_[ 0 ] <> $FF ) or ( Jpeg_[ 1 ] <> $D8 ) then Exit;

     P := 2;

     while P + 4 <= Length( Jpeg_ ) do
     begin
          if Jpeg_[ P ] <> $FF then Break;

          K := Jpeg_[ P+1 ];

          if K = $D8 then begin Inc( P, 2 );  Continue;  end;    // SOI（念のため）
          if ( K = $DA ) or ( K = $D9 ) then Break;              // SOS / EOI：ここから先にヘッダは無い

          L := ( Jpeg_[ P+2 ] shl 8 ) or Jpeg_[ P+3 ];           // 長さ（この 2 バイトを含む）

          if ( K = $E2 ) and ( L >= 16 ) and ( P + 2 + L <= Length( Jpeg_ ) ) and
             CompareMem( @Jpeg_[ P+4 ], PAnsiChar( 'ICC_PROFILE'#0 ), 12 ) then
          begin
               N := Jpeg_[ P+16 ];  // 通番（ 1 〜 ）
               if Cnt = 0 then begin Cnt := Jpeg_[ P+17 ];  SetLength( Parts, Cnt );  end;

               if ( N >= 1 ) and ( N <= Length( Parts ) ) then
               begin
                    SetLength( Parts[ N-1 ], L - 16 );
                    if L - 16 > 0 then Move( Jpeg_[ P+18 ], Parts[ N-1 ][ 0 ], L - 16 );
               end;
          end;

          Inc( P, 2 + L );
     end;

     for I := 0 to High( Parts ) do Result := Result + Parts[ I ];
end;

///// SOI（と続く APP0 / APP1 ）の直後に APP2 を挿入する。1 セグメントの上限 65,533 バイトを超える ICC は分割する。

function LuxJpegWithIcc( const Jpeg_,Icc_:TBytes ) :TBytes;
const
      PART_MAX = 65533 - 16;   // セグメント長 65,535 − 長さ 2 − 署名 12 − 通番・総数 2
var
   P, L, K, I, N, Cnt, Ofs :Integer;
   S :TMemoryStream;
   //-------
   procedure W8( const V_:Byte );  begin  S.WriteBuffer( V_, 1 );  end;
   procedure W16( const V_:Integer );  var B :array [ 0..1 ] of Byte;  begin  B[0] := V_ shr 8;  B[1] := V_ and $FF;  S.WriteBuffer( B, 2 );  end;
begin
     if ( Length( Icc_ ) = 0 ) or ( Length( Jpeg_ ) < 2 ) then Exit( Jpeg_ );

     ///// 挿入位置：SOI の後、APP0 / APP1 が続く間はその後ろ

     P := 2;

     while P + 4 <= Length( Jpeg_ ) do
     begin
          if Jpeg_[ P ] <> $FF then Break;

          K := Jpeg_[ P+1 ];

          if not ( K in [ $E0, $E1 ] ) then Break;

          L := ( Jpeg_[ P+2 ] shl 8 ) or Jpeg_[ P+3 ];

          Inc( P, 2 + L );
     end;

     Cnt := ( Length( Icc_ ) + PART_MAX - 1 ) div PART_MAX;

     S := TMemoryStream.Create;
     try
        S.WriteBuffer( Jpeg_[ 0 ], P );

        Ofs := 0;

        for I := 1 to Cnt do
        begin
             N := Min( PART_MAX, Length( Icc_ ) - Ofs );

             W8( $FF );  W8( $E2 );
             W16( 2 + 12 + 2 + N );
             S.WriteBuffer( PAnsiChar( 'ICC_PROFILE'#0 )^, 12 );
             W8( I );  W8( Cnt );
             S.WriteBuffer( Icc_[ Ofs ], N );

             Inc( Ofs, N );
        end;

        S.WriteBuffer( Jpeg_[ P ], Length( Jpeg_ ) - P );

        SetLength( Result, S.Size );
        Move( S.Memory^, Result[ 0 ], S.Size );
     finally
        S.Free;
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFilerJpg

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

procedure TLuxImageFilerJpg.SetQuality( const Quality_:Integer );
begin
     _Quality := Min( Max( Quality_, 1 ), 100 );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageFilerJpg.DoLoad( const Image_:TLuxImage; const Stream_:TStream );
var
   Src   :TBytes;
   Codec :ISkCodec;
   W, H  :Integer;
   Buf   :TBytes;
   Row   :TArray<TSingleRGBA>;
   S     :PByteRGBA;
   X, Y  :Integer;
   Icc   :TBytes;
begin
     SetLength( Src, Stream_.Size - Stream_.Position );

     if Length( Src ) > 0 then Stream_.ReadBuffer( Src[ 0 ], Length( Src ) );

     Codec := TSkCodec.MakeWithoutCopy( @Src[ 0 ], Length( Src ) );

     if not Assigned( Codec ) then raise EInOutError.Create( 'JPEG を開けない' );

     W := Codec.Width;
     H := Codec.Height;

     Image_.SetSize( W, H );

     ///// 色空間：APP2 の ICC_PROFILE

     Icc := LuxJpegIcc( Src );

     if Length( Icc ) > 0 then Image_.ColorSpace := TLuxColorSpaces.FromIcc( Icc )
                          else Image_.ColorSpace := nil;

     ///// Skia のコーデックは画像１枚分の連続バッファを要求する。
     ///// また変換先は 8bit（ BGRA8888 ）しか確実に対応していないので、
     ///// JPEG が 8bit であることを踏まえて常に BGRA8888 で受け、必要なら書式変換する。

     SetLength( Buf, NativeInt( W ) * H * SizeOf( TByteRGBA ) );

     if not Codec.GetPixels( @Buf[ 0 ], NativeUInt( W ) * SizeOf( TByteRGBA ),
                             TSkColorType.BGRA8888, TSkAlphaType.Unpremul ) then
       raise EInOutError.Create( 'JPEG を復号できない' );

     ///// Skia の復号は途中経過を返さない不可分な呼び出しなので、
     ///// ここまでで一気に 0.8 まで進む（実際に所要時間の大半を占めるのもここ）

     Image_.DoProgress( 0.8 );

     if Image_.PixelKind = bpUInt08 then
     begin
          for Y := 0 to H-1 do
          begin
               Image_.SetRaws( 0, 0, Y, W, @Buf[ NativeInt( Y ) * W * SizeOf( TByteRGBA ) ] );

               Image_.DoProgress( 0.8 + 0.2 * ( Y + 1 ) / H );
          end;
     end
     else
     begin
          SetLength( Row, W );

          for Y := 0 to H-1 do
          begin
               S := @Buf[ NativeInt( Y ) * W * SizeOf( TByteRGBA ) ];

               for X := 0 to W-1 do
               begin
                    Row[ X ] := S^;  Inc( S );
               end;

               Image_.SetRow( 0, 0, Y, W, @Row[ 0 ] );

               Image_.DoProgress( 0.8 + 0.2 * ( Y + 1 ) / H );
          end;
     end;

     Buf := nil;  Codec := nil;  Src := nil;

     Image_.Changed;
end;

procedure TLuxImageFilerJpg.DoSave( const Image_:TLuxImage; const Stream_:TStream );
var
   W, H    :Integer;
   Buf     :TBytes;
   Row     :TArray<TSingleRGBA>;
   X, Y    :Integer;
   Q       :PByteRGBA;
   Pixmap  :ISkPixmap;
   Image   :ISkImage;
   Jpeg    :TBytes;
begin
     W := Image_.Width;
     H := Image_.Height;

     if ( W < 1 ) or ( H < 1 ) then raise EInOutError.Create( '空の画像は保存できない' );

     if ( W > 65535 ) or ( H > 65535 ) then raise EInOutError.Create( 'JPEG は 65,535 画素を超えられない' );

     SetLength( Buf, NativeInt( W ) * H * SizeOf( TByteRGBA ) );
     SetLength( Row, W );

     for Y := 0 to H-1 do
     begin
          Image_.GetRow( 0, 0, Y, W, @Row[ 0 ] );

          Q := @Buf[ NativeInt( Y ) * W * SizeOf( TByteRGBA ) ];

          for X := 0 to W-1 do
          begin
               Q^ := TByteRGBA( Row[ X ] );  Q^.A := $FF;  Inc( Q );
          end;

          Image_.DoProgress( 0.9 * ( Y + 1 ) / H );  // 残り 0.1 は Skia による符号化
     end;

     Pixmap := TSkPixmap.Create( TSkImageInfo.Create( W, H, TSkColorType.BGRA8888, TSkAlphaType.Opaque ),
                                 @Buf[ 0 ], NativeUInt( W ) * SizeOf( TByteRGBA ) );

     Image := TSkImage.MakeFromRaster( Pixmap );

     if not Assigned( Image ) then raise EInOutError.Create( 'JPEG 用の画像を作れない' );

     Jpeg := Image.Encode( TSkEncodedImageFormat.JPEG, _Quality );

     if Length( Jpeg ) = 0 then raise EInOutError.Create( 'JPEG を符号化できない' );

     ///// 色空間：符号化されたバイト列へ APP2 ICC_PROFILE を挿入する

     if Assigned( Image_.ColorSpace ) then Jpeg := LuxJpegWithIcc( Jpeg, Image_.ColorSpace.IccProfile );

     Stream_.WriteBuffer( Jpeg[ 0 ], Length( Jpeg ) );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TLuxImageFilerJpg.Create;
begin
     inherited Create;

     _Quality := 90;
end;

//////////////////////////////////////////////////////////////////////// C L A S S

class function TLuxImageFilerJpg.Extensions :TArray<String>;
begin
     Result := [ '.jpg', '.jpeg', '.jpe' ];
end;

class function TLuxImageFilerJpg.Caption :String;
begin
     Result := 'JPEG';
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageFilerJpg.Assign( const Filer_:TLuxImageFiler );
begin
     inherited;

     if Filer_ is TLuxImageFilerJpg then _Quality := TLuxImageFilerJpg( Filer_ )._Quality;
end;

///// Skia のコーデックはヘッダだけで寸法を返せる

function TLuxImageFilerJpg.ImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;
var
   Codec :ISkCodec;
begin
     Width_ := 0;  Height_ := 0;

     Codec := TSkCodec.MakeFromFile( FileName_ );

     if not Assigned( Codec ) then Exit( False );

     Width_ := Codec.Width;  Height_ := Codec.Height;

     Result := ( Width_ > 0 ) and ( Height_ > 0 );
end;

initialization //############################################################### ■

     TLuxImageFiler.Regist( TLuxImageFilerJpg );

end. //######################################################################### ■
