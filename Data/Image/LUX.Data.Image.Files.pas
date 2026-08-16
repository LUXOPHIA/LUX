unit LUX.Data.Image.Files;

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.Classes, System.SysUtils,
     System.Skia,
     LUX.Data.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFiler

     ///// TLuxImage のファイル入出力
     ///// ・PNG は自前実装（行単位のストリーミング。8/16bit、サイズ制限は実質無し）
     /////   Alpha_ = False なら α を省いた RGB（カラータイプ 2）で書く。
     ///// ・JPEG は Skia のコーデック（規格上 65,535 角まで。画像１枚分の連続バッファを一時的に要する）
     ///// ・色空間：Image_.ColorSpace が指定されていれば、PNG は sRGB / iCCP（＋gAMA / cHRM）、
     /////   JPEG は APP2 の ICC_PROFILE として埋め込む。読み込みではそれらを解析して ColorSpace に設定する
     /////   （プリセットと同じ内容ならその共有インスタンス、違えば TLuxColorSpaces に登録した新しいインスタンス。
     /////   何も無ければ nil ）。画素値はどちらの向きでも変えない。

     TLuxImageFiler = class
     private
     protected
     public
       ///// M E T H O D
       class procedure LoadFromFile( const Image_:TLuxImage; const FileName_:String );
       class procedure SaveToFile  ( const Image_:TLuxImage; const FileName_:String; const Quality_:Integer = 90; const Alpha_:Boolean = True );
       ///// P N G
       class procedure LoadFromPng( const Image_:TLuxImage; const Stream_:TStream );
       class procedure SaveToPng  ( const Image_:TLuxImage; const Stream_:TStream; const Alpha_:Boolean = True );
       ///// J P E G
       class procedure LoadFromJpg( const Image_:TLuxImage; const FileName_:String );
       class procedure SaveToJpg  ( const Image_:TLuxImage; const FileName_:String; const Quality_:Integer );
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function LuxSkColorType( const Kind_:TLuxPixel ) :TSkColorType;  // 画素形式に対応する Skia のカラータイプ

function LuxImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;  // 画素を読まずに寸法だけ得る

function LuxJpegIcc( const Jpeg_:TBytes ) :TBytes;                                    // JPEG の APP2 ICC_PROFILE を繋げて取り出す（無ければ空）
function LuxJpegWithIcc( const Jpeg_,Icc_:TBytes ) :TBytes;                            // JPEG に APP2 ICC_PROFILE を挿入したものを返す

implementation //############################################################### ■

uses System.Math, System.ZLib,
     LUX, LUX.D2, LUX.Color, LUX.Color.Space;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngHead

     ///// IHDR ＋ PLTE ＋ tRNS をまとめた、復号に必要な情報

     TPngHead = record
     public
       Width     :Integer;
       Height    :Integer;
       Depth     :Integer;   // 1 / 2 / 4 / 8 / 16
       Color     :Integer;   // 0=グレイ 2=RGB 3=パレット 4=グレイ+α 6=RGBA
       Interlace :Integer;   // 0=無し 1=Adam7
       Chans     :Integer;   // 標本の数／画素
       BitsPix   :Integer;   // ビット数／画素
       FiltBpp   :Integer;   // フィルタ用のバイト数／画素（最低 1 ）
       MaxVal    :Integer;   // ( 1 shl Depth ) - 1
       /////
       Pal       :array [ 0..255 ] of TSingleRGBA;  // カラータイプ 3 用（ tRNS 適用済み）
       PalN      :Integer;
       /////
       HasTrns   :Boolean;                          // カラータイプ 0 / 2 用の透明色
       Trns      :array [ 0..2 ] of Integer;        // 標本値そのもの（ Depth の単位）
       ///// M E T H O D
       function RowBytes( const W_:Integer ) :Integer;  // W_ 画素ぶんのバイト数
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngIdatReader

     ///// 連続する IDAT チャンクの中身だけを繋げて読み出すストリーム

     TPngIdatReader = class( TStream )
     private
       _Stream :TStream;
       _Rest   :Integer;   // 現チャンクの残りバイト数
       _Pos    :Int64;     // 読み出した総バイト数（＝このストリーム上の位置）
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
       _Pos    :Int64;     // 書き込んだ総バイト数（＝このストリーム上の位置）
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

      ///// Adam7 インターレースの７つのパス（開始位置と刻み）

      PNG_PASS_X0 :array [ 0..6 ] of Integer = ( 0, 4, 0, 2, 0, 1, 0 );
      PNG_PASS_Y0 :array [ 0..6 ] of Integer = ( 0, 0, 4, 0, 2, 0, 1 );
      PNG_PASS_DX :array [ 0..6 ] of Integer = ( 8, 8, 4, 4, 2, 2, 1 );
      PNG_PASS_DY :array [ 0..6 ] of Integer = ( 8, 8, 8, 4, 4, 2, 2 );

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

function ReadU08( const Stream_:TStream ) :Byte;
begin
     Stream_.ReadBuffer( Result, 1 );
end;

procedure WriteU32( const Stream_:TStream; const V_:UInt32 );
var
   T :UInt32;
begin
     T := SwapU32( V_ );  Stream_.WriteBuffer( T, 4 );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% PNG の復号

///// 1 / 2 / 4 / 8 / 16 ビットの標本を取り出す（ PNG は上位ビットから詰める）

function PngSample( const P_:PByte; const I_,Depth_:Integer ) :Integer; inline;
var
   B, S :Integer;
begin
     case Depth_ of
       16: Result := ( P_[ I_ * 2 ] shl 8 ) or P_[ I_ * 2 + 1 ];
        8: Result :=   P_[ I_ ];
     else
       B := ( I_ * Depth_ ) shr 3;                  // 何バイト目か
       S := 8 - Depth_ - ( ( I_ * Depth_ ) and 7 ); // そのバイト内で何ビット右へ寄せるか
       Result := ( P_[ B ] shr S ) and ( ( 1 shl Depth_ ) - 1 );
     end;
end;

///// 行フィルタを解除する（ Cur_ を書き換える。Prv_ は解除済みの前行）

procedure PngUnfilter( const Filt_:Byte; const Cur_,Prv_:PByte; const N_,Bpp_:Integer );
var
   I, A, B, C, P, PA, PB, PC :Integer;
begin
     case Filt_ of
       0: ;                                                                                  // None
       1: for I := Bpp_ to N_-1 do Cur_[ I ] := ( Cur_[ I ] + Cur_[ I - Bpp_ ] ) and $FF;     // Sub
       2: for I := 0    to N_-1 do Cur_[ I ] := ( Cur_[ I ] + Prv_[ I        ] ) and $FF;     // Up
       3: for I := 0    to N_-1 do                                                            // Average
          begin
               if I >= Bpp_ then A := Cur_[ I - Bpp_ ] else A := 0;

               Cur_[ I ] := ( Cur_[ I ] + ( A + Prv_[ I ] ) div 2 ) and $FF;
          end;
       4: for I := 0    to N_-1 do                                                            // Paeth
          begin
               if I >= Bpp_ then begin  A := Cur_[ I - Bpp_ ];  C := Prv_[ I - Bpp_ ];  end
                            else begin  A := 0               ;  C := 0               ;  end;

               B := Prv_[ I ];

               P := A + B - C;  PA := Abs( P - A );  PB := Abs( P - B );  PC := Abs( P - C );

               if ( PA <= PB ) and ( PA <= PC ) then P := A
                                                else if PB <= PC then P := B
                                                                 else P := C;

               Cur_[ I ] := ( Cur_[ I ] + P ) and $FF;
          end;
     else raise EInOutError.Create( 'PNG のフィルタ種別 ' + Filt_.ToString + ' が不正' );
     end;
end;

///// 解除済みの 1 行を色へ変換する（全ビット深度・全カラータイプ）

procedure PngRowToColors( const H_:TPngHead; const Raw_:PByte; const N_:Integer; const Dst_:PSingleRGBA );
var
   X, I, S :Integer;
   V       :array [ 0..3 ] of Integer;
   M       :Single;
begin
     M := 1 / H_.MaxVal;

     for X := 0 to N_-1 do
     begin
          if H_.Color = 3 then
          begin
               S := PngSample( Raw_, X, H_.Depth );

               if S < H_.PalN then Dst_[ X ] := H_.Pal[ S ]
                              else Dst_[ X ] := TSingleRGBA.Create( 0, 0, 0, 1 );  // 範囲外は黒

               Continue;
          end;

          for I := 0 to H_.Chans-1 do V[ I ] := PngSample( Raw_, X * H_.Chans + I, H_.Depth );

          case H_.Color of
            0: begin  // グレイ
                    Dst_[ X ] := TSingleRGBA.Create( V[0] * M, V[0] * M, V[0] * M, 1 );

                    if H_.HasTrns and ( V[0] = H_.Trns[0] ) then Dst_[ X ].A := 0;
               end;
            2: begin  // RGB
                    Dst_[ X ] := TSingleRGBA.Create( V[0] * M, V[1] * M, V[2] * M, 1 );

                    if H_.HasTrns and ( V[0] = H_.Trns[0] )
                                  and ( V[1] = H_.Trns[1] )
                                  and ( V[2] = H_.Trns[2] ) then Dst_[ X ].A := 0;
               end;
            4:      // グレイ ＋ α
                    Dst_[ X ] := TSingleRGBA.Create( V[0] * M, V[0] * M, V[0] * M, V[1] * M );
            6:      // RGBA
                    Dst_[ X ] := TSingleRGBA.Create( V[0] * M, V[1] * M, V[2] * M, V[3] * M );
          end;
     end;
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

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% PNG の色空間チャンク

///// gAMA（ 1/γ × 100000 ）

procedure WritePngGama( const Stream_:TStream; const Gama_:UInt32 );
var
   U :UInt32;
begin
     U := SwapU32( Gama_ );

     WriteChunk( Stream_, [ Ord('g'), Ord('A'), Ord('M'), Ord('A') ], @U, 4 );
end;

///// cHRM（ 白 xy・赤 xy・緑 xy・青 xy × 100000 ）

procedure WritePngChrm( const Stream_:TStream; const Space_:TLuxColorSpace );
var
   Buf :array [ 0..7 ] of UInt32;
begin
     Buf[ 0 ] := SwapU32( Round( Space_.WhiteXY.X * 100000 ) );
     Buf[ 1 ] := SwapU32( Round( Space_.WhiteXY.Y * 100000 ) );
     Buf[ 2 ] := SwapU32( Round( Space_.RedXY  .X * 100000 ) );
     Buf[ 3 ] := SwapU32( Round( Space_.RedXY  .Y * 100000 ) );
     Buf[ 4 ] := SwapU32( Round( Space_.GreenXY.X * 100000 ) );
     Buf[ 5 ] := SwapU32( Round( Space_.GreenXY.Y * 100000 ) );
     Buf[ 6 ] := SwapU32( Round( Space_.BlueXY .X * 100000 ) );
     Buf[ 7 ] := SwapU32( Round( Space_.BlueXY .Y * 100000 ) );

     WriteChunk( Stream_, [ Ord('c'), Ord('H'), Ord('R'), Ord('M') ], @Buf[ 0 ], 32 );
end;

///// gAMA と cHRM だけから色空間を組み立てる（ iCCP も sRGB も無いとき ）。
///// cHRM が無ければ sRGB の原色、gAMA が無ければ sRGB の曲線とみなす。
///// gAMA = 45455 は規格上 sRGB の近似なので、原色が sRGB ならプリセットの sRGB を返す。

function PngColorSpace( const HasChrm_:Boolean; const Chrm_:array of Double; const Gama_:UInt32 ) :TLuxColorSpace;
var
   R, G, B, W :TDouble2D;
   T          :TLuxTransfer;
   S          :TLuxColorSpace;
begin
     if HasChrm_ then
     begin
          W := TDouble2D.Create( Chrm_[ 0 ], Chrm_[ 1 ] );
          R := TDouble2D.Create( Chrm_[ 2 ], Chrm_[ 3 ] );
          G := TDouble2D.Create( Chrm_[ 4 ], Chrm_[ 5 ] );
          B := TDouble2D.Create( Chrm_[ 6 ], Chrm_[ 7 ] );
     end
     else
     begin
          W := TLuxColorSpaces.sRGB.WhiteXY;
          R := TLuxColorSpaces.sRGB.RedXY;
          G := TLuxColorSpaces.sRGB.GreenXY;
          B := TLuxColorSpaces.sRGB.BlueXY;
     end;

     if ( Gama_ = 0 ) or ( Abs( Integer( Gama_ ) - 45455 ) <= 5 ) then T := TLuxTransfer.sRGB
                                                                   else T := TLuxTransfer.Gamma( 100000 / Gama_ );

     S := TLuxColorSpace.Create( 'PNG', R, G, B, W, T );

     Result := TLuxColorSpaces.Intern( S );   // sRGB 等と同じ内容ならプリセットになる
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% JPEG の APP2 ICC_PROFILE

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

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngHead

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

function TPngHead.RowBytes( const W_:Integer ) :Integer;
begin
     Result := ( W_ * BitsPix + 7 ) div 8;
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
     _Pos    := 0;
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

     Inc( _Pos, Result );
end;

function TPngIdatReader.Write( const Buffer; Count:Longint ) :Longint;
begin
     raise EInOutError.Create( 'TPngIdatReader は読み込み専用' );
end;

function TPngIdatReader.Seek( const Offset:Int64; Origin:TSeekOrigin ) :Int64;
begin
     ///// TZDecompressionStream は読み出しの度に Position を照会し、ずれていれば
     ///// 引き戻そうとする。現在位置を正しく返せば、その引き戻しは起こらない。

     case Origin of
       soBeginning: if Offset = _Pos then Exit( _Pos );
       soCurrent  : if Offset = 0    then Exit( _Pos );
       soEnd      : ;
     end;

     raise EInOutError.Create( 'TPngIdatReader は順次読み込み専用' );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngIdatWriter

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TPngIdatWriter.Create( const Stream_:TStream );
begin
     inherited Create;

     _Stream := Stream_;
     _Count  := 0;
     _Pos    := 0;

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

     Inc( _Pos, Result );
end;

function TPngIdatWriter.Seek( const Offset:Int64; Origin:TSeekOrigin ) :Int64;
begin
     ///// TZCompressionStream も Position を照会する（読み出し側と同じ理由）

     case Origin of
       soBeginning: if Offset = _Pos then Exit( _Pos );
       soCurrent  : if Offset = 0    then Exit( _Pos );
       soEnd      : ;
     end;

     raise EInOutError.Create( 'TPngIdatWriter は順次書き込み専用' );
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

class procedure TLuxImageFiler.SaveToFile( const Image_:TLuxImage; const FileName_:String; const Quality_:Integer = 90; const Alpha_:Boolean = True );
var
   E :String;
   S :TFileStream;
begin
     E := LowerCase( ExtractFileExt( FileName_ ) );

     if E = '.png' then
     begin
          S := TFileStream.Create( FileName_, fmCreate );
          try
               SaveToPng( Image_, S, Alpha_ );
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
   Sign     :array [ 0..7 ] of Byte;
   Kind     :array [ 0..3 ] of Byte;
   Size     :UInt32;
   Hd       :TPngHead;
   Buf      :TBytes;
   Idat     :TPngIdatReader;
   Zlib     :TZDecompressionStream;
   Raw0, Raw1, Swap :TBytes;
   Row      :TArray<TSingleRGBA>;
   Filt     :Byte;
   I, X, Y  :Integer;
   Pass     :Integer;
   PW, PH   :Integer;
   RowN     :Integer;
   Done, All :Integer;
   Found    :Boolean;
   ///// 色空間
   HasSRGB, HasChrm :Boolean;
   Gama     :UInt32;
   Chrm     :array [ 0..7 ] of Double;   // 白 xy・赤 xy・緑 xy・青 xy
   Icc      :TBytes;
   Zp       :Pointer;
   Zn       :Integer;

   ///// パスの 1 行を読んで解除し、色へ変換して Row へ入れる

   procedure ReadPassRow( const W_:Integer );
   begin
        RowN := Hd.RowBytes( W_ );

        Zlib.ReadBuffer( Filt, 1 );
        Zlib.ReadBuffer( Raw0[ 0 ], RowN );

        PngUnfilter( Filt, @Raw0[ 0 ], @Raw1[ 0 ], RowN, Hd.FiltBpp );

        PngRowToColors( Hd, @Raw0[ 0 ], W_, @Row[ 0 ] );

        Swap := Raw1;  Raw1 := Raw0;  Raw0 := Swap;  // 解除済みの行が次の「前行」になる
   end;

begin
     Stream_.ReadBuffer( Sign[ 0 ], 8 );

     if not CompareMem( @Sign[ 0 ], @PNG_SIGN[ 0 ], 8 ) then raise EInOutError.Create( 'PNG の署名ではない' );

     FillChar( Hd, SizeOf( Hd ), 0 );

     Size  := 0;
     Found := False;

     HasSRGB := False;  HasChrm := False;  Gama := 0;  Icc := nil;

     ///// IHDR ～ 最初の IDAT まで（ PLTE ・ tRNS ・ 色空間のチャンクを拾う）

     repeat
           if Stream_.Position + 8 > Stream_.Size then Break;

           Size := ReadU32( Stream_ );

           Stream_.ReadBuffer( Kind[ 0 ], 4 );

           ///// IHDR

           if ( Kind[0] = Ord('I') ) and ( Kind[1] = Ord('H') ) and ( Kind[2] = Ord('D') ) and ( Kind[3] = Ord('R') ) then
           begin
                Hd.Width  := ReadU32( Stream_ );
                Hd.Height := ReadU32( Stream_ );

                Hd.Depth     := ReadU08( Stream_ );
                Hd.Color     := ReadU08( Stream_ );

                Stream_.Seek( 2, soCurrent );  // 圧縮法・フィルタ法（ともに 0 のみ）

                Hd.Interlace := ReadU08( Stream_ );

                Stream_.Seek( 4, soCurrent );  // CRC
           end
           else
           ///// PLTE

           if ( Kind[0] = Ord('P') ) and ( Kind[1] = Ord('L') ) and ( Kind[2] = Ord('T') ) and ( Kind[3] = Ord('E') ) then
           begin
                Hd.PalN := Min( Integer( Size ) div 3, 256 );

                SetLength( Buf, Size );  Stream_.ReadBuffer( Buf[ 0 ], Size );

                for I := 0 to Hd.PalN-1 do
                  Hd.Pal[ I ] := TSingleRGBA.Create( Buf[ I*3 ] / 255, Buf[ I*3+1 ] / 255, Buf[ I*3+2 ] / 255, 1 );

                Stream_.Seek( 4, soCurrent );  // CRC
           end
           else
           ///// tRNS

           if ( Kind[0] = Ord('t') ) and ( Kind[1] = Ord('R') ) and ( Kind[2] = Ord('N') ) and ( Kind[3] = Ord('S') ) then
           begin
                SetLength( Buf, Size );  if Size > 0 then Stream_.ReadBuffer( Buf[ 0 ], Size );

                case Hd.Color of
                  0: if Size >= 2 then
                     begin
                          Hd.HasTrns := True;
                          Hd.Trns[0] := Buf[0] * 256 + Buf[1];
                     end;
                  2: if Size >= 6 then
                     begin
                          Hd.HasTrns := True;
                          Hd.Trns[0] := Buf[0] * 256 + Buf[1];
                          Hd.Trns[1] := Buf[2] * 256 + Buf[3];
                          Hd.Trns[2] := Buf[4] * 256 + Buf[5];
                     end;
                  3: for I := 0 to Min( Integer( Size ), Hd.PalN ) - 1 do Hd.Pal[ I ].A := Buf[ I ] / 255;
                end;

                Stream_.Seek( 4, soCurrent );  // CRC
           end
           else
           ///// sRGB / iCCP / gAMA / cHRM（色空間。優先順位は iCCP ＞ sRGB ＞ gAMA＋cHRM ）

           if ( Kind[0] = Ord('s') ) and ( Kind[1] = Ord('R') ) and ( Kind[2] = Ord('G') ) and ( Kind[3] = Ord('B') ) then
           begin
                HasSRGB := True;

                Stream_.Seek( Size + 4, soCurrent );
           end
           else
           if ( Kind[0] = Ord('i') ) and ( Kind[1] = Ord('C') ) and ( Kind[2] = Ord('C') ) and ( Kind[3] = Ord('P') ) then
           begin
                SetLength( Buf, Size );  if Size > 0 then Stream_.ReadBuffer( Buf[ 0 ], Size );

                I := 0;  while ( I < Integer( Size ) ) and ( Buf[ I ] <> 0 ) do Inc( I );   // プロファイル名の終端

                if I + 2 < Integer( Size ) then
                begin
                     ZDecompress( @Buf[ I+2 ], Integer( Size ) - I - 2, Zp, Zn );
                     try
                          SetLength( Icc, Zn );  Move( Zp^, Icc[ 0 ], Zn );
                     finally
                          FreeMem( Zp );
                     end;
                end;

                Stream_.Seek( 4, soCurrent );  // CRC
           end
           else
           if ( Kind[0] = Ord('g') ) and ( Kind[1] = Ord('A') ) and ( Kind[2] = Ord('M') ) and ( Kind[3] = Ord('A') ) then
           begin
                if Size >= 4 then Gama := ReadU32( Stream_ ) else Stream_.Seek( Size, soCurrent );

                Stream_.Seek( 4, soCurrent );  // CRC
           end
           else
           if ( Kind[0] = Ord('c') ) and ( Kind[1] = Ord('H') ) and ( Kind[2] = Ord('R') ) and ( Kind[3] = Ord('M') ) then
           begin
                if Size >= 32 then
                begin
                     for I := 0 to 7 do Chrm[ I ] := ReadU32( Stream_ ) / 100000;

                     HasChrm := True;
                end
                else Stream_.Seek( Size, soCurrent );

                Stream_.Seek( 4, soCurrent );  // CRC
           end
           else
           ///// IDAT

           if ( Kind[0] = Ord('I') ) and ( Kind[1] = Ord('D') ) and ( Kind[2] = Ord('A') ) and ( Kind[3] = Ord('T') ) then
           begin
                Found := True;  Break;
           end
           else Stream_.Seek( Size + 4, soCurrent );  // 中身 ＋ CRC
     until False;

     if not Found then raise EInOutError.Create( 'PNG に IDAT が無い' );

     ///// 色空間を決める

     Image_.ColorSpace := nil;

     if Length( Icc ) > 0 then Image_.ColorSpace := TLuxColorSpaces.FromIcc( Icc );

     if not Assigned( Image_.ColorSpace ) then
     begin
          if HasSRGB then Image_.ColorSpace := TLuxColorSpaces.sRGB
          else
          if HasChrm or ( Gama > 0 ) then Image_.ColorSpace := PngColorSpace( HasChrm, Chrm, Gama );
     end;

     ///// ビット深度とカラータイプの組み合わせを検証する

     case Hd.Color of
       0: begin  Hd.Chans := 1;  if not ( Hd.Depth in [ 1, 2, 4, 8, 16 ] ) then Found := False;  end;
       2: begin  Hd.Chans := 3;  if not ( Hd.Depth in [       8, 16 ] ) then Found := False;  end;
       3: begin  Hd.Chans := 1;  if not ( Hd.Depth in [ 1, 2, 4, 8     ] ) then Found := False;  end;
       4: begin  Hd.Chans := 2;  if not ( Hd.Depth in [       8, 16 ] ) then Found := False;  end;
       6: begin  Hd.Chans := 4;  if not ( Hd.Depth in [       8, 16 ] ) then Found := False;  end;
     else raise EInOutError.Create( 'PNG のカラータイプ ' + Hd.Color.ToString + ' が不正' );
     end;

     if not Found then raise EInOutError.Create( 'PNG のカラータイプ ' + Hd.Color.ToString +
                                                 ' とビット深度 ' + Hd.Depth.ToString + ' の組み合わせが不正' );

     if Hd.Interlace > 1 then raise EInOutError.Create( 'PNG のインターレース法 ' + Hd.Interlace.ToString + ' が不正' );

     if ( Hd.Color = 3 ) and ( Hd.PalN = 0 ) then raise EInOutError.Create( 'PNG のパレット（ PLTE ）が無い' );

     Hd.BitsPix := Hd.Chans * Hd.Depth;
     Hd.FiltBpp := Max( 1, Hd.BitsPix div 8 );
     Hd.MaxVal  := ( 1 shl Hd.Depth ) - 1;

     Image_.SetSize( Hd.Width, Hd.Height );

     ///// 行バッファは、どのパスでも足りるように最大幅で確保する

     SetLength( Raw0, Hd.RowBytes( Hd.Width ) + 1 );
     SetLength( Raw1, Hd.RowBytes( Hd.Width ) + 1 );
     SetLength( Row , Hd.Width );

     Idat := TPngIdatReader.Create( Stream_, Integer( Size ) );
     try
          Zlib := TZDecompressionStream.Create( Idat );
          try
               if Hd.Interlace = 0 then
               begin
                    FillChar( Raw1[ 0 ], Length( Raw1 ), 0 );

                    for Y := 0 to Hd.Height-1 do
                    begin
                         ReadPassRow( Hd.Width );

                         Image_.SetRow( 0, 0, Y, Hd.Width, @Row[ 0 ] );

                         Image_.DoProgress( ( Y + 1 ) / Hd.Height );
                    end;
               end
               else
               begin
                    ///// Adam7 ： 7 つのパスを順に読み、画素を最終位置へ散らす

                    All := 0;

                    for Pass := 0 to 6 do
                    begin
                         PH := ( Hd.Height - PNG_PASS_Y0[ Pass ] + PNG_PASS_DY[ Pass ] - 1 ) div PNG_PASS_DY[ Pass ];

                         if ( Hd.Width - PNG_PASS_X0[ Pass ] ) > 0 then Inc( All, Max( PH, 0 ) );
                    end;

                    Done := 0;

                    for Pass := 0 to 6 do
                    begin
                         PW := ( Hd.Width  - PNG_PASS_X0[ Pass ] + PNG_PASS_DX[ Pass ] - 1 ) div PNG_PASS_DX[ Pass ];
                         PH := ( Hd.Height - PNG_PASS_Y0[ Pass ] + PNG_PASS_DY[ Pass ] - 1 ) div PNG_PASS_DY[ Pass ];

                         if ( PW <= 0 ) or ( PH <= 0 ) then Continue;

                         FillChar( Raw1[ 0 ], Length( Raw1 ), 0 );  // パス毎に前行は 0 から

                         for Y := 0 to PH-1 do
                         begin
                              ReadPassRow( PW );

                              for X := 0 to PW-1 do
                                Image_.SetRow( 0, PNG_PASS_X0[ Pass ] + X * PNG_PASS_DX[ Pass ],
                                                  PNG_PASS_Y0[ Pass ] + Y * PNG_PASS_DY[ Pass ], 1, @Row[ X ] );

                              Inc( Done );

                              Image_.DoProgress( Done / All );
                         end;
                    end;
               end;
          finally
               Zlib.Free;
          end;
     finally
          Idat.Free;
     end;

     Image_.Changed;
end;

class procedure TLuxImageFiler.SaveToPng( const Image_:TLuxImage; const Stream_:TStream; const Alpha_:Boolean = True );
var
   Head       :TBytes;
   W, H       :Integer;
   Depth, Bpp :Integer;
   Chans      :Integer;
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
   Icc, Zicc  :TBytes;
   Buf        :TBytes;
   Name       :AnsiString;
   Zp         :Pointer;
   Zn         :Integer;
begin
     W := Image_.Width;
     H := Image_.Height;

     if ( W < 1 ) or ( H < 1 ) then raise EInOutError.Create( '空の画像は保存できない' );

     if Image_.PixelKind = bpUInt08 then Depth := 8 else Depth := 16;

     if Alpha_ then Chans := 4 else Chans := 3;

     Bpp  := Chans * ( Depth div 8 );
     RowN := W * Bpp;

     ///// 署名

     Stream_.WriteBuffer( PNG_SIGN[ 0 ], 8 );

     ///// IHDR

     SetLength( Head, 13 );

     U := SwapU32( W );  Move( U, Head[ 0 ], 4 );
     U := SwapU32( H );  Move( U, Head[ 4 ], 4 );

     Head[  8 ] := Depth;
     if Alpha_ then Head[ 9 ] := 6   // RGBA
               else Head[ 9 ] := 2;  // RGB
     Head[ 10 ] := 0;  // 圧縮法
     Head[ 11 ] := 0;  // フィルタ法
     Head[ 12 ] := 0;  // 非インターレース

     WriteChunk( Stream_, [ Ord('I'), Ord('H'), Ord('D'), Ord('R') ], @Head[ 0 ], 13 );

     ///// 色空間（ IDAT より前 ）
     /////   sRGB なら sRGB チャンク（＋規格が勧める gAMA と cHRM ）。iCCP とは排他なので書かない。
     /////   それ以外は iCCP に ICC プロファイルを同梱し、cHRM（原色は正確に表せる）と、
     /////   伝達関数が純ガンマのときだけ gAMA を書く。画素値は変えない。

     if Assigned( Image_.ColorSpace ) then
     begin
          if Image_.ColorSpace = TLuxColorSpaces.sRGB then
          begin
               Buf := [ 0 ];   // 描画意図：知覚的
               WriteChunk( Stream_, [ Ord('s'), Ord('R'), Ord('G'), Ord('B') ], @Buf[ 0 ], 1 );

               WritePngGama( Stream_, 45455 );
               WritePngChrm( Stream_, Image_.ColorSpace );
          end
          else
          begin
               Icc := Image_.ColorSpace.IccProfile;

               ZCompress( @Icc[ 0 ], Length( Icc ), Zp, Zn );
               try
                  Name := AnsiString( Copy( Image_.ColorSpace.Name, 1, 79 ) );  // iCCP のプロファイル名（Latin-1、1〜79 文字）
                  if Name = '' then Name := 'ICC';

                  SetLength( Zicc, Length( Name ) + 2 + Zn );
                  Move( Name[ 1 ], Zicc[ 0 ], Length( Name ) );
                  Zicc[ Length( Name )     ] := 0;   // 名前の終端
                  Zicc[ Length( Name ) + 1 ] := 0;   // 圧縮法 0 = deflate
                  Move( Zp^, Zicc[ Length( Name ) + 2 ], Zn );
               finally
                  FreeMem( Zp );
               end;

               WriteChunk( Stream_, [ Ord('i'), Ord('C'), Ord('C'), Ord('P') ], @Zicc[ 0 ], Length( Zicc ) );

               if Image_.ColorSpace.Transfer.IsGamma then WritePngGama( Stream_, Round( 100000 / Image_.ColorSpace.Transfer.G ) );

               WritePngChrm( Stream_, Image_.ColorSpace );
          end;
     end;

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

                              if Alpha_ then Q[ 3 ] := Round( Clamp( Row[X].A, 0, 1 ) * $FF );

                              Inc( Q, Bpp );
                         end;
                    end
                    else
                    begin
                         for X := 0 to W-1 do
                         begin
                              I := Round( Clamp( Row[X].C.R, 0, 1 ) * $FFFF );  Q[ 0 ] := I shr 8;  Q[ 1 ] := I and $FF;
                              I := Round( Clamp( Row[X].C.G, 0, 1 ) * $FFFF );  Q[ 2 ] := I shr 8;  Q[ 3 ] := I and $FF;
                              I := Round( Clamp( Row[X].C.B, 0, 1 ) * $FFFF );  Q[ 4 ] := I shr 8;  Q[ 5 ] := I and $FF;

                              if Alpha_ then
                              begin
                                   I := Round( Clamp( Row[X].A, 0, 1 ) * $FFFF );  Q[ 6 ] := I shr 8;  Q[ 7 ] := I and $FF;
                              end;

                              Inc( Q, Bpp );
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
   F     :TFileStream;
   Head  :TBytes;
   Icc   :TBytes;
begin
     Codec := TSkCodec.MakeFromFile( FileName_ );

     if not Assigned( Codec ) then raise EInOutError.Create( 'JPEG を開けない： ' + FileName_ );

     W := Codec.Width;
     H := Codec.Height;

     Image_.SetSize( W, H );

     ///// 色空間：APP2 の ICC_PROFILE（ヘッダ部だけ読めばよいが、簡潔さを優先してファイル全体から探す）

     Image_.ColorSpace := nil;

     F := TFileStream.Create( FileName_, fmOpenRead or fmShareDenyWrite );
     try
        SetLength( Head, Min( F.Size, 4 * 1024 * 1024 ) );   // ICC はヘッダ部（先頭数 MB 以内）にある
        F.ReadBuffer( Head[ 0 ], Length( Head ) );
     finally
        F.Free;
     end;

     Icc := LuxJpegIcc( Head );  Head := nil;

     if Length( Icc ) > 0 then Image_.ColorSpace := TLuxColorSpaces.FromIcc( Icc );

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
   Jpeg    :TBytes;
   F       :TFileStream;
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

     if not Assigned( Image_.ColorSpace ) then
     begin
          if not Image.EncodeToFile( FileName_, TSkEncodedImageFormat.JPEG, Quality_ ) then
            raise EInOutError.Create( 'JPEG を書き出せない： ' + FileName_ );
     end
     else
     begin
          ///// 色空間：Skia に符号化させたバイト列へ APP2 ICC_PROFILE を挿入してから書く

          Jpeg := Image.Encode( TSkEncodedImageFormat.JPEG, Quality_ );

          if Length( Jpeg ) = 0 then raise EInOutError.Create( 'JPEG を符号化できない： ' + FileName_ );

          Jpeg := LuxJpegWithIcc( Jpeg, Image_.ColorSpace.IccProfile );

          F := TFileStream.Create( FileName_, fmCreate );
          try
             F.WriteBuffer( Jpeg[ 0 ], Length( Jpeg ) );
          finally
             F.Free;
          end;
     end;
end;

initialization //############################################################### ■

     InitCrcTab;

end. //######################################################################### ■
