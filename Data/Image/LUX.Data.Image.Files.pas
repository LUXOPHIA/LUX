unit LUX.Data.Image.Files;

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.Classes,
     System.Skia,
     LUX.Data.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFiler

     ///// TLuxImage のファイル入出力
     ///// ・PNG は自前実装（行単位のストリーミング。8/16bit、サイズ制限は実質無し）
     ///// ・JPEG は Skia のコーデック（規格上 65,535 角まで。画像１枚分の連続バッファを一時的に要する）

     TLuxImageFiler = class
     private
     protected
     public
       ///// M E T H O D
       class procedure LoadFromFile( const Image_:TLuxImage; const FileName_:String );
       class procedure SaveToFile  ( const Image_:TLuxImage; const FileName_:String; const Quality_:Integer = 90 );
       ///// P N G
       class procedure LoadFromPng( const Image_:TLuxImage; const Stream_:TStream );
       class procedure SaveToPng  ( const Image_:TLuxImage; const Stream_:TStream );
       ///// J P E G
       class procedure LoadFromJpg( const Image_:TLuxImage; const FileName_:String );
       class procedure SaveToJpg  ( const Image_:TLuxImage; const FileName_:String; const Quality_:Integer );
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function LuxSkColorType( const Kind_:TLuxPixel ) :TSkColorType;  // 画素形式に対応する Skia のカラータイプ

function LuxImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;  // 画素を読まずに寸法だけ得る

implementation //############################################################### ■

uses System.SysUtils, System.Math, System.ZLib,
     LUX, LUX.Color;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngIdatReader

     ///// 連続する IDAT チャンクの中身だけを繋げて読み出すストリーム

     TPngIdatReader = class( TStream )
     private
       _Stream :TStream;
       _Rest   :Integer;   // 現チャンクの残りバイト数
       _Ended  :Boolean;
       ///// M E T H O D
       function NextChunk :Boolean;
     public
       constructor Create( const Stream_:TStream; const Rest_:Integer );
       ///// M E T H O D
       function Read( var Buffer; Count:Longint ) :Longint; override;
       function Write( const Buffer; Count:Longint ) :Longint; override;
       function Seek( const Offset:Int64; Origin:TSeekOrigin ) :Int64; override;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngIdatWriter

     ///// 書き込まれたバイト列を IDAT チャンクに小分けして出力するストリーム

     TPngIdatWriter = class( TStream )
     private
       _Stream :TStream;
       _Buffer :TBytes;
       _Count  :Integer;
     public
       constructor Create( const Stream_:TStream );
       destructor Destroy; override;
       ///// M E T H O D
       procedure Flush;
       function Read( var Buffer; Count:Longint ) :Longint; override;
       function Write( const Buffer; Count:Longint ) :Longint; override;
       function Seek( const Offset:Int64; Origin:TSeekOrigin ) :Int64; override;
     end;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      PNG_SIGN :array [ 0..7 ] of Byte = ( $89, $50, $4E, $47, $0D, $0A, $1A, $0A );

      PNG_IDAT_MAX = 1 shl 20;  // IDAT チャンク１個の最大バイト数

var //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 V A R I A B L E 】

    _CrcTab :array [ 0..255 ] of UInt32;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CRC-32

procedure InitCrcTab;
var
   I, J :Integer;
   C    :UInt32;
begin
     for I := 0 to 255 do
     begin
          C := I;

          for J := 1 to 8 do
          begin
               if ( C and 1 ) <> 0 then C := $EDB88320 xor ( C shr 1 )
                                   else C :=              ( C shr 1 );
          end;

          _CrcTab[ I ] := C;
     end;
end;

function UpdateCrc( const Crc_:UInt32; const Data_:PByte; const Size_:Integer ) :UInt32;
var
   I :Integer;
begin
     Result := Crc_;

     for I := 0 to Size_-1 do Result := _CrcTab[ ( Result xor Data_[ I ] ) and $FF ] xor ( Result shr 8 );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ビッグエンディアン

function SwapU32( const V_:UInt32 ) :UInt32; inline;
begin
     Result := ( V_ shr 24 ) or ( ( V_ shr 8 ) and $0000FF00 )
                              or ( ( V_ shl 8 ) and $00FF0000 ) or ( V_ shl 24 );
end;

function ReadU32( const Stream_:TStream ) :UInt32;
begin
     Stream_.ReadBuffer( Result, 4 );  Result := SwapU32( Result );
end;

procedure WriteU32( const Stream_:TStream; const V_:UInt32 );
var
   T :UInt32;
begin
     T := SwapU32( V_ );  Stream_.WriteBuffer( T, 4 );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% WriteChunk

procedure WriteChunk( const Stream_:TStream; const Kind_:array of Byte; const Data_:PByte; const Size_:Integer );
var
   C :UInt32;
begin
     WriteU32( Stream_, Size_ );

     Stream_.WriteBuffer( Kind_[ 0 ], 4 );

     if Size_ > 0 then Stream_.WriteBuffer( Data_^, Size_ );

     C := UpdateCrc( $FFFFFFFF, @Kind_[ 0 ], 4 );
     C := UpdateCrc( C, Data_, Size_ );

     WriteU32( Stream_, C xor $FFFFFFFF );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% LuxSkColorType

function LuxSkColorType( const Kind_:TLuxPixel ) :TSkColorType;
begin
     case Kind_ of
       bpUInt08: Result := TSkColorType.BGRA8888;      // TByteRGBA   の記憶順は B,G,R,A
       bpUInt16: Result := TSkColorType.RGBA16161616;  // TWordRGBA
       bpSFlo16: Result := TSkColorType.RGBAF16;       // THalfRGBA
       bpSFlo32: Result := TSkColorType.RGBAF32;       // TSingleRGBA
     else        Result := TSkColorType.Unknown;
     end;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% LuxImageSize

function LuxImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;
var
   E :String;
   S :TFileStream;
   B :array [ 0..7 ] of Byte;
   C :ISkCodec;
begin
     Result := False;  Width_ := 0;  Height_ := 0;

     E := LowerCase( ExtractFileExt( FileName_ ) );

     if E = '.png' then
     begin
          S := TFileStream.Create( FileName_, fmOpenRead or fmShareDenyWrite );
          try
               S.ReadBuffer( B[ 0 ], 8 );

               if not CompareMem( @B[ 0 ], @PNG_SIGN[ 0 ], 8 ) then Exit;

               ReadU32( S );  S.Seek( 4, soCurrent );  // 長さ ＋ 'IHDR'

               Width_  := ReadU32( S );
               Height_ := ReadU32( S );

               Result := True;
          finally
               S.Free;
          end;
     end
     else
     begin
          C := TSkCodec.MakeFromFile( FileName_ );

          if not Assigned( C ) then Exit;

          Width_  := C.Width;
          Height_ := C.Height;

          Result := True;
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngIdatReader

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

function TPngIdatReader.NextChunk :Boolean;
var
   N :UInt32;
   K :array [ 0..3 ] of Byte;
begin
     _Stream.Seek( 4, soCurrent );  // 直前チャンクの CRC

     if _Stream.Position + 8 > _Stream.Size then Exit( False );

     N := ReadU32( _Stream );

     _Stream.ReadBuffer( K[ 0 ], 4 );

     if ( K[0] = Ord( 'I' ) ) and ( K[1] = Ord( 'D' ) ) and ( K[2] = Ord( 'A' ) ) and ( K[3] = Ord( 'T' ) ) then
     begin
          _Rest := N;  Result := True;
     end
     else Result := False;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TPngIdatReader.Create( const Stream_:TStream; const Rest_:Integer );
begin
     inherited Create;

     _Stream := Stream_;
     _Rest   := Rest_;
     _Ended  := False;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

function TPngIdatReader.Read( var Buffer; Count:Longint ) :Longint;
var
   D :PByte;
   C :Longint;
begin
     Result := 0;  D := @Buffer;

     while ( Result < Count ) and not _Ended do
     begin
          if _Rest = 0 then
          begin
               if not NextChunk then
               begin
                    _Ended := True;  Break;
               end;
          end;

          C := Min( Count - Result, _Rest );

          C := _Stream.Read( D^, C );

          if C = 0 then
          begin
               _Ended := True;  Break;
          end;

          Inc( D, C );  Dec( _Rest, C );  Inc( Result, C );
     end;
end;

function TPngIdatReader.Write( const Buffer; Count:Longint ) :Longint;
begin
     raise EInOutError.Create( 'TPngIdatReader は読み込み専用' );
end;

function TPngIdatReader.Seek( const Offset:Int64; Origin:TSeekOrigin ) :Int64;
begin
     if ( Offset = 0 ) and ( Origin = soCurrent ) then Exit( 0 );

     raise EInOutError.Create( 'TPngIdatReader は順次読み込み専用' );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngIdatWriter

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TPngIdatWriter.Create( const Stream_:TStream );
begin
     inherited Create;

     _Stream := Stream_;
     _Count  := 0;

     SetLength( _Buffer, PNG_IDAT_MAX );
end;

destructor TPngIdatWriter.Destroy;
begin
     Flush;

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TPngIdatWriter.Flush;
begin
     if _Count > 0 then
     begin
          WriteChunk( _Stream, [ Ord( 'I' ), Ord( 'D' ), Ord( 'A' ), Ord( 'T' ) ], @_Buffer[ 0 ], _Count );

          _Count := 0;
     end;
end;

function TPngIdatWriter.Read( var Buffer; Count:Longint ) :Longint;
begin
     raise EInOutError.Create( 'TPngIdatWriter は書き込み専用' );
end;

function TPngIdatWriter.Write( const Buffer; Count:Longint ) :Longint;
var
   S :PByte;
   C :Longint;
begin
     Result := Count;  S := @Buffer;

     while Count > 0 do
     begin
          C := Min( Count, PNG_IDAT_MAX - _Count );

          Move( S^, _Buffer[ _Count ], C );

          Inc( _Count, C );  Inc( S, C );  Dec( Count, C );

          if _Count = PNG_IDAT_MAX then Flush;
     end;
end;

function TPngIdatWriter.Seek( const Offset:Int64; Origin:TSeekOrigin ) :Int64;
begin
     Result := 0;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFiler

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

class procedure TLuxImageFiler.LoadFromFile( const Image_:TLuxImage; const FileName_:String );
var
   E :String;
   S :TFileStream;
begin
     E := LowerCase( ExtractFileExt( FileName_ ) );

     if E = '.png' then
     begin
          S := TFileStream.Create( FileName_, fmOpenRead or fmShareDenyWrite );
          try
               LoadFromPng( Image_, S );
          finally
               S.Free;
          end;
     end
     else
     if ( E = '.jpg' ) or ( E = '.jpeg' ) or ( E = '.jpe' ) then LoadFromJpg( Image_, FileName_ )
     else raise EInOutError.Create( '未対応の拡張子： ' + E );
end;

class procedure TLuxImageFiler.SaveToFile( const Image_:TLuxImage; const FileName_:String; const Quality_:Integer = 90 );
var
   E :String;
   S :TFileStream;
begin
     E := LowerCase( ExtractFileExt( FileName_ ) );

     if E = '.png' then
     begin
          S := TFileStream.Create( FileName_, fmCreate );
          try
               SaveToPng( Image_, S );
          finally
               S.Free;
          end;
     end
     else
     if ( E = '.jpg' ) or ( E = '.jpeg' ) or ( E = '.jpe' ) then SaveToJpg( Image_, FileName_, Quality_ )
     else raise EInOutError.Create( '未対応の拡張子： ' + E );
end;

//////////////////////////////////////////////////////////////////////// P N G

class procedure TLuxImageFiler.LoadFromPng( const Image_:TLuxImage; const Stream_:TStream );
var
   Sign             :array [ 0..7 ] of Byte;
   Kind             :array [ 0..3 ] of Byte;
   Size             :UInt32;
   W, H             :Integer;
   Depth, Color     :Byte;
   Chans, Bpp, RowN :Integer;
   Idat             :TPngIdatReader;
   Zlib             :TZDecompressionStream;
   Raw0, Raw1, Swap :TBytes;
   Row              :TArray<TSingleRGBA>;
   Filt             :Byte;
   X, Y, I          :Integer;
   A, B, C, P, PA, PB, PC :Integer;
   Q                :PByte;
   V                :array [ 0..3 ] of Single;
   Found            :Boolean;
begin
     Stream_.ReadBuffer( Sign[ 0 ], 8 );

     if not CompareMem( @Sign[ 0 ], @PNG_SIGN[ 0 ], 8 ) then raise EInOutError.Create( 'PNG の署名ではない' );

     W := 0;  H := 0;  Depth := 0;  Color := 0;  Found := False;

     ///// IHDR ～ 最初の IDAT まで

     repeat
           Size := ReadU32( Stream_ );

           Stream_.ReadBuffer( Kind[ 0 ], 4 );

           if ( Kind[0] = Ord('I') ) and ( Kind[1] = Ord('H') ) and ( Kind[2] = Ord('D') ) and ( Kind[3] = Ord('R') ) then
           begin
                W := ReadU32( Stream_ );
                H := ReadU32( Stream_ );

                Stream_.ReadBuffer( Depth, 1 );
                Stream_.ReadBuffer( Color, 1 );

                Stream_.Seek( 3, soCurrent );  // 圧縮法・フィルタ法・インターレース法
                Stream_.Seek( 4, soCurrent );  // CRC

                if Stream_.Position >= Stream_.Size then Break;
           end
           else
           if ( Kind[0] = Ord('I') ) and ( Kind[1] = Ord('D') ) and ( Kind[2] = Ord('A') ) and ( Kind[3] = Ord('T') ) then
           begin
                Found := True;  Break;
           end
           else
           begin
                Stream_.Seek( Size + 4, soCurrent );  // 中身 ＋ CRC

                if Stream_.Position >= Stream_.Size then Break;
           end;
     until False;

     if not Found then raise EInOutError.Create( 'PNG に IDAT が無い' );

     if ( Depth <> 8 ) and ( Depth <> 16 ) then raise EInOutError.Create( 'PNG のビット深度 ' + Depth.ToString + ' は未対応（8/16 のみ）' );

     case Color of
       0: Chans := 1;  // グレイ
       2: Chans := 3;  // RGB
       4: Chans := 2;  // グレイ＋α
       6: Chans := 4;  // RGBA
     else raise EInOutError.Create( 'PNG のカラータイプ ' + Color.ToString + ' は未対応（0/2/4/6 のみ）' );
     end;

     Bpp  := Chans * ( Depth div 8 );
     RowN := W * Bpp;

     Image_.SetSize( W, H );

     SetLength( Raw0, RowN );
     SetLength( Raw1, RowN );
     SetLength( Row , W    );

     FillChar( Raw1[ 0 ], RowN, 0 );

     Idat := TPngIdatReader.Create( Stream_, Integer( Size ) );
     try
          Zlib := TZDecompressionStream.Create( Idat );
          try
               for Y := 0 to H-1 do
               begin
                    Zlib.ReadBuffer( Filt, 1 );
                    Zlib.ReadBuffer( Raw0[ 0 ], RowN );

                    ///// フィルタ解除

                    case Filt of
                      0: ;
                      1: for I := Bpp to RowN-1 do Raw0[ I ] := ( Raw0[ I ] + Raw0[ I - Bpp ] ) and $FF;
                      2: for I := 0 to RowN-1 do Raw0[ I ] := ( Raw0[ I ] + Raw1[ I ] ) and $FF;
                      3: for I := 0 to RowN-1 do
                         begin
                              if I >= Bpp then A := Raw0[ I - Bpp ] else A := 0;

                              Raw0[ I ] := ( Raw0[ I ] + ( A + Raw1[ I ] ) div 2 ) and $FF;
                         end;
                      4: for I := 0 to RowN-1 do
                         begin
                              if I >= Bpp then begin  A := Raw0[ I - Bpp ];  C := Raw1[ I - Bpp ];  end
                                          else begin  A := 0             ;  C := 0             ;  end;

                              B := Raw1[ I ];

                              P := A + B - C;  PA := Abs( P - A );  PB := Abs( P - B );  PC := Abs( P - C );

                              if ( PA <= PB ) and ( PA <= PC ) then P := A
                                                               else if PB <= PC then P := B
                                                                                else P := C;

                              Raw0[ I ] := ( Raw0[ I ] + P ) and $FF;
                         end;
                    else raise EInOutError.Create( 'PNG のフィルタ種別 ' + Filt.ToString + ' が不正' );
                    end;

                    ///// 画素へ変換

                    Q := @Raw0[ 0 ];

                    for X := 0 to W-1 do
                    begin
                         if Depth = 8 then for I := 0 to Chans-1 do V[ I ] := Q[ I ] / $FF
                                      else for I := 0 to Chans-1 do V[ I ] := ( Q[ I*2 ] * 256 + Q[ I*2+1 ] ) / $FFFF;

                         case Chans of
                           1: Row[ X ] := TSingleRGBA.Create( V[0], V[0], V[0], 1    );
                           2: Row[ X ] := TSingleRGBA.Create( V[0], V[0], V[0], V[1] );
                           3: Row[ X ] := TSingleRGBA.Create( V[0], V[1], V[2], 1    );
                           4: Row[ X ] := TSingleRGBA.Create( V[0], V[1], V[2], V[3] );
                         end;

                         Inc( Q, Bpp );
                    end;

                    Image_.SetRow( 0, 0, Y, W, @Row[ 0 ] );

                    Image_.DoProgress( ( Y + 1 ) / H );

                    ///// 次行のために入れ替え（Raw0 は次の ReadBuffer で全上書きされる）

                    Swap := Raw1;  Raw1 := Raw0;  Raw0 := Swap;
               end;
          finally
               Zlib.Free;
          end;
     finally
          Idat.Free;
     end;

     Image_.Changed;
end;

class procedure TLuxImageFiler.SaveToPng( const Image_:TLuxImage; const Stream_:TStream );
var
   Head       :TBytes;
   W, H       :Integer;
   Depth, Bpp :Integer;
   RowN       :Integer;
   Idat       :TPngIdatWriter;
   Zlib       :TZCompressionStream;
   Raw0, Raw1 :TBytes;
   Out_       :TBytes;
   Row        :TArray<TSingleRGBA>;
   X, Y, I    :Integer;
   A, B, C, P, PA, PB, PC :Integer;
   Q          :PByte;
   U          :UInt32;
begin
     W := Image_.Width;
     H := Image_.Height;

     if ( W < 1 ) or ( H < 1 ) then raise EInOutError.Create( '空の画像は保存できない' );

     if Image_.PixelKind = bpUInt08 then Depth := 8 else Depth := 16;

     Bpp  := 4 * ( Depth div 8 );
     RowN := W * Bpp;

     ///// 署名

     Stream_.WriteBuffer( PNG_SIGN[ 0 ], 8 );

     ///// IHDR

     SetLength( Head, 13 );

     U := SwapU32( W );  Move( U, Head[ 0 ], 4 );
     U := SwapU32( H );  Move( U, Head[ 4 ], 4 );

     Head[  8 ] := Depth;
     Head[  9 ] := 6;  // RGBA
     Head[ 10 ] := 0;  // 圧縮法
     Head[ 11 ] := 0;  // フィルタ法
     Head[ 12 ] := 0;  // 非インターレース

     WriteChunk( Stream_, [ Ord('I'), Ord('H'), Ord('D'), Ord('R') ], @Head[ 0 ], 13 );

     ///// IDAT

     SetLength( Raw0, RowN     );
     SetLength( Raw1, RowN     );
     SetLength( Out_, RowN + 1 );
     SetLength( Row , W        );

     FillChar( Raw1[ 0 ], RowN, 0 );

     Idat := TPngIdatWriter.Create( Stream_ );
     try
          Zlib := TZCompressionStream.Create( Idat );
          try
               for Y := 0 to H-1 do
               begin
                    Image_.GetRow( 0, 0, Y, W, @Row[ 0 ] );

                    Q := @Raw0[ 0 ];

                    if Depth = 8 then
                    begin
                         for X := 0 to W-1 do
                         begin
                              Q[ 0 ] := Round( Clamp( Row[X].C.R, 0, 1 ) * $FF );
                              Q[ 1 ] := Round( Clamp( Row[X].C.G, 0, 1 ) * $FF );
                              Q[ 2 ] := Round( Clamp( Row[X].C.B, 0, 1 ) * $FF );
                              Q[ 3 ] := Round( Clamp( Row[X].A  , 0, 1 ) * $FF );

                              Inc( Q, 4 );
                         end;
                    end
                    else
                    begin
                         for X := 0 to W-1 do
                         begin
                              I := Round( Clamp( Row[X].C.R, 0, 1 ) * $FFFF );  Q[ 0 ] := I shr 8;  Q[ 1 ] := I and $FF;
                              I := Round( Clamp( Row[X].C.G, 0, 1 ) * $FFFF );  Q[ 2 ] := I shr 8;  Q[ 3 ] := I and $FF;
                              I := Round( Clamp( Row[X].C.B, 0, 1 ) * $FFFF );  Q[ 4 ] := I shr 8;  Q[ 5 ] := I and $FF;
                              I := Round( Clamp( Row[X].A  , 0, 1 ) * $FFFF );  Q[ 6 ] := I shr 8;  Q[ 7 ] := I and $FF;

                              Inc( Q, 8 );
                         end;
                    end;

                    ///// Paeth フィルタ

                    Out_[ 0 ] := 4;

                    for I := 0 to RowN-1 do
                    begin
                         if I >= Bpp then begin  A := Raw0[ I - Bpp ];  C := Raw1[ I - Bpp ];  end
                                     else begin  A := 0             ;  C := 0             ;  end;

                         B := Raw1[ I ];

                         P := A + B - C;  PA := Abs( P - A );  PB := Abs( P - B );  PC := Abs( P - C );

                         if ( PA <= PB ) and ( PA <= PC ) then P := A
                                                          else if PB <= PC then P := B
                                                                           else P := C;

                         Out_[ I + 1 ] := ( Raw0[ I ] - P ) and $FF;
                    end;

                    Zlib.WriteBuffer( Out_[ 0 ], RowN + 1 );

                    Image_.DoProgress( ( Y + 1 ) / H );

                    Move( Raw0[ 0 ], Raw1[ 0 ], RowN );
               end;
          finally
               Zlib.Free;
          end;
     finally
          Idat.Free;
     end;

     ///// IEND

     WriteChunk( Stream_, [ Ord('I'), Ord('E'), Ord('N'), Ord('D') ], nil, 0 );
end;

//////////////////////////////////////////////////////////////////// J P E G

class procedure TLuxImageFiler.LoadFromJpg( const Image_:TLuxImage; const FileName_:String );
var
   Codec :ISkCodec;
   W, H  :Integer;
   Buf   :TBytes;
   Row   :TArray<TSingleRGBA>;
   S     :PByteRGBA;
   X, Y  :Integer;
begin
     Codec := TSkCodec.MakeFromFile( FileName_ );

     if not Assigned( Codec ) then raise EInOutError.Create( 'JPEG を開けない： ' + FileName_ );

     W := Codec.Width;
     H := Codec.Height;

     Image_.SetSize( W, H );

     ///// Skia のコーデックは画像１枚分の連続バッファを要求する。
     ///// また変換先は 8bit（ BGRA8888 ）しか確実に対応していないので、
     ///// JPEG が 8bit であることを踏まえて常に BGRA8888 で受け、必要なら書式変換する。

     SetLength( Buf, NativeInt( W ) * H * SizeOf( TByteRGBA ) );

     if not Codec.GetPixels( @Buf[ 0 ], NativeUInt( W ) * SizeOf( TByteRGBA ),
                             TSkColorType.BGRA8888, TSkAlphaType.Unpremul ) then
       raise EInOutError.Create( 'JPEG を復号できない： ' + FileName_ );

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

     Buf := nil;

     Image_.Changed;
end;

class procedure TLuxImageFiler.SaveToJpg( const Image_:TLuxImage; const FileName_:String; const Quality_:Integer );
var
   W, H    :Integer;
   Buf     :TBytes;
   Row     :TArray<TSingleRGBA>;
   X, Y    :Integer;
   Q       :PByteRGBA;
   Pixmap  :ISkPixmap;
   Image   :ISkImage;
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

     if not Image.EncodeToFile( FileName_, TSkEncodedImageFormat.JPEG, Quality_ ) then
       raise EInOutError.Create( 'JPEG を書き出せない： ' + FileName_ );
end;

initialization //############################################################### ■

     InitCrcTab;

end. //######################################################################### ■
