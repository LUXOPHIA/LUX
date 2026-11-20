unit LUX.Data.Codec.Image.Png;

// PNG のコーデック（System.ZLib の上に、直接に書いてある）
//
//【復号】
// ・規格の定める形式のすべて：ビット深度 1・2・4・8・16、カラータイプ 0・2・3・4・6、
//   PLTE、tRNS の 3 つの形、Adam7 のインターレース。
// ・走査線を 1 本ずつ読んで渡すので、1 枚ぶんの一時の領域を持たない。インターレースも同じである
//   （パスの走査線は、横の歩みが 1 より大きい並びとして渡す）。
//
//【符号化】
// ・RGBA（Alpha が False なら RGB）。置き場の Depth が 8 以下なら 8 ビット、それより大きければ 16 ビット。
// ・圧縮率（Level）が変えるのは、大きさと時間だけである。PNG は可逆なので、画素は変わらない。
//
//【色空間】
// ・書き：sRGB なら sRGB チャンク（＋規格の勧める gAMA と cHRM）。それ以外は iCCP ＋ cHRM
//   （伝達関数が純粋なガンマなら gAMA も）。色空間が nil なら、何も書かない。
// ・読み：iCCP ＞ sRGB ＞ gAMA＋cHRM の順に採る。どれも無ければ nil。

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.SysUtils, System.Classes,
     LUX.Data.Codec.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImagePngLevel

     // 圧縮率。zlib のレベルは 0〜9 あるが、大きさが実際に変わるのは、この 4 点である。
     TImagePngLevel = ( plNone,  // 無圧縮（deflate の stored ブロック）。最も速く、最も大きい
                   plFastest,    // 速さを優先
                   plDefault,    // zlib の標準
                   plMax );      // 小ささを優先。最も遅く、最も小さい

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecPng

     TImageCodecPng = class( TImageCodec )
     private
       _Alpha :Boolean;
       _Level :TImagePngLevel;
     protected
       ///// M E T H O D
       procedure DoDecode( const Stream_:TStream; const Raster_:TImageRaster ); override;
       procedure DoEncode( const Stream_:TStream; const Raster_:TImageRaster; const Header_:TImageHeader ); override;
       ///// A C C E S S O R
       function GetAlpha :Boolean; virtual;
       procedure SetAlpha( const Alpha_:Boolean ); virtual;
       function GetLevel :TImagePngLevel; virtual;
       procedure SetLevel( const Level_:TImagePngLevel ); virtual;
     public
       constructor Create; override;
       ///// C L A S S
       class function Extensions :TArray<String>; override;
       class function Caption :String; override;
       class function Matches( const Bytes_:TBytes ) :Boolean; override;
       ///// P R O P E R T Y
       property Alpha :Boolean   read GetAlpha write SetAlpha;       // α を書くか（既定は True）
       property Level :TImagePngLevel read GetLevel write SetLevel;  // 圧縮率（既定は plDefault）
       ///// M E T H O D
       procedure Assign( const Codec_:TImageCodec ); override;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.Math, System.ZLib,
     LUX, LUX.D2, LUX.Color, LUX.Color.Space;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngPass

     // 走査線の束。画素 ( I, J ) の位置は ( X0 + I * DX, Y0 + J * DY ) である。
     // インターレースの無い画像は、歩みが 1 のパス 1 つである。
     TPngPass = record
       X0, Y0 :Integer;
       DX, DY :Integer;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngHead

     // 最初の IDAT の前までのチャンク（IHDR・PLTE・tRNS・色空間）から得る、復号に要る情報。
     TPngHead = record
       Width      :Integer;
       Height     :Integer;
       Depth      :Integer;                             // 1・2・4・8・16
       Color      :Integer;                             // 0：グレイ　2：RGB　3：パレット　4：グレイ＋α　6：RGBA
       Interl     :Integer;                             // 0：無し　1：Adam7
       Chans      :Integer;                             // 画素あたりの標本の数
       Pal        :array [ 0..255 ] of TSingleRGBA;     // パレット（tRNS の α を当てはめ済み）
       PalN       :Integer;
       HasTrns    :Boolean;                             // カラータイプ 0・2 の透明色があるか
       Trns       :array [ 0..2 ] of Integer;           // 透明色（標本の値のまま）
       ColorSpace :TLuxColorSpace;
       IdatN      :Integer;                             // 最初の IDAT の中身の長さ
       ///// M E T H O D
       function BitsPix :Integer;                       // 画素あたりのビット数
       function FiltBpp :Integer;                       // フィルターが「左の画素」と見なす距離（バイト）
       function MaxVal :Integer;                        // 標本の最大値
       function RowBytes( const W_:Integer ) :Integer;  // W_ 画素の走査線のバイト数
       function Passes :TArray<TPngPass>;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngIdatReader

     // 連続する IDAT チャンクの中身だけを、つなげて読み出す流れ。
     TPngIdatReader = class( TStream )
     private
       _Stream :TStream;
       _Rest   :Integer;  // いまのチャンクの残りのバイト数
       _Pos    :Int64;    // 読み出したバイト数の合計（この流れの上の位置）
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

     // 書き込まれたバイトを、IDAT チャンクに小分けして出す流れ。
     TPngIdatWriter = class( TStream )
     private
       _Stream :TStream;
       _Buffer :TBytes;
       _Count  :Integer;
       _Pos    :Int64;  // 書き込んだバイト数の合計（この流れの上の位置）
     public
       constructor Create( const Stream_:TStream );
       ///// M E T H O D
       procedure Flush;
       function Read( var Buffer; Count:Longint ) :Longint; override;
       function Write( const Buffer; Count:Longint ) :Longint; override;
       function Seek( const Offset:Int64; Origin:TSeekOrigin ) :Int64; override;
     end;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      PNG_SIGN :array [ 0..8-1 ] of Byte = ( $89, $50, $4E, $47, $0D, $0A, $1A, $0A );

      // チャンクの種類（4 文字を、ビッグエンディアンの 32 ビットに読んだ値）
      PNG_IHDR = $49484452;
      PNG_PLTE = $504C5445;
      PNG_tRNS = $74524E53;
      PNG_sRGB = $73524742;
      PNG_iCCP = $69434350;
      PNG_gAMA = $67414D41;
      PNG_cHRM = $6348524D;
      PNG_IDAT = $49444154;
      PNG_IEND = $49454E44;

      PNG_GAMA_SRGB = 45455;  // sRGB の曲線を表す gAMA の値（規格の定める近似。1 / 2.2 × 100000）

      PNG_ZLEVEL :array [ TImagePngLevel ] of TZCompressionLevel = ( zcNone, zcFastest, zcDefault, zcMax );

      PNG_IDAT_MAX = 1 shl 20;  // IDAT チャンク 1 つの中身の最大のバイト数

      PNG_PASS_NONE  :array [ 0..1-1 ] of TPngPass = ( ( X0:0; Y0:0; DX:1; DY:1 ) );

      PNG_PASS_ADAM7 :array [ 0..7-1 ] of TPngPass = ( ( X0:0; Y0:0; DX:8; DY:8 ),
                                                       ( X0:4; Y0:0; DX:8; DY:8 ),
                                                       ( X0:0; Y0:4; DX:4; DY:8 ),
                                                       ( X0:2; Y0:0; DX:4; DY:4 ),
                                                       ( X0:0; Y0:2; DX:2; DY:4 ),
                                                       ( X0:1; Y0:0; DX:2; DY:2 ),
                                                       ( X0:0; Y0:1; DX:1; DY:2 ) );

var //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 V A R I A B L E 】

    _CrcTab :array [ 0..255 ] of UInt32;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

procedure Error( const Text_:String );
begin
     raise EImageCodec.Create( 'PNG: ' + Text_ );
end;

//------------------------------------------------------------------------------ CRC-32

procedure InitCrcTab;
var
   I, J :Integer;
   C :UInt32;
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

//------------------------------------------------------------------------------ ビッグエンディアン

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

function GetU16( const P_:PByte ) :Integer; inline;
begin
     Result := ( P_[ 0 ] shl 8 ) or P_[ 1 ];
end;

function GetU32( const P_:PByte ) :UInt32; inline;
begin
     Result := ( UInt32( P_[ 0 ] ) shl 24 ) or ( P_[ 1 ] shl 16 ) or ( P_[ 2 ] shl 8 ) or P_[ 3 ];
end;

procedure PutU16( const P_:PByte; const V_:Integer ); inline;
begin
     P_[ 0 ] := V_ shr 8;  P_[ 1 ] := V_ and $FF;
end;

procedure PutU32( const P_:PByte; const V_:UInt32 ); inline;
begin
     P_[ 0 ] := V_ shr 24;  P_[ 1 ] := ( V_ shr 16 ) and $FF;  P_[ 2 ] := ( V_ shr 8 ) and $FF;  P_[ 3 ] := V_ and $FF;
end;

//------------------------------------------------------------------------------ チャンク

procedure WriteChunk( const Stream_:TStream; const Kind_:UInt32; const Data_:PByte; const Size_:Integer );
var
   K :array [ 0..4-1 ] of Byte;
   C :UInt32;
begin
     PutU32( @K, Kind_ );

     WriteU32( Stream_, Size_ );

     Stream_.WriteBuffer( K, 4 );

     if Size_ > 0 then Stream_.WriteBuffer( Data_^, Size_ );

     C := UpdateCrc( $FFFFFFFF, @K, 4 );
     C := UpdateCrc( C, Data_, Size_ );

     WriteU32( Stream_, C xor $FFFFFFFF );
end;

// チャンクの中身を読み、続く CRC を飛ばす。

function ReadChunk( const Stream_:TStream; const Size_:Integer ) :TBytes;
begin
     SetLength( Result, Size_ );

     if Size_ > 0 then Stream_.ReadBuffer( Result[ 0 ], Size_ );

     Stream_.Seek( 4, soCurrent );
end;

//------------------------------------------------------------------------------ 色空間のチャンク

// gAMA：1 / γ × 100000

procedure WriteGama( const Stream_:TStream; const Gama_:UInt32 );
var
   B :array [ 0..4-1 ] of Byte;
begin
     PutU32( @B, Gama_ );

     WriteChunk( Stream_, PNG_gAMA, @B, 4 );
end;

// cHRM：白・赤・緑・青の色度座標 × 100000

procedure WriteChrm( const Stream_:TStream; const Space_:TLuxColorSpace );
var
   B :array [ 0..32-1 ] of Byte;
begin
     PutU32( @B[  0 ], Round( Space_.WhiteXY.X * 100000 ) );
     PutU32( @B[  4 ], Round( Space_.WhiteXY.Y * 100000 ) );
     PutU32( @B[  8 ], Round( Space_.RedXY  .X * 100000 ) );
     PutU32( @B[ 12 ], Round( Space_.RedXY  .Y * 100000 ) );
     PutU32( @B[ 16 ], Round( Space_.GreenXY.X * 100000 ) );
     PutU32( @B[ 20 ], Round( Space_.GreenXY.Y * 100000 ) );
     PutU32( @B[ 24 ], Round( Space_.BlueXY .X * 100000 ) );
     PutU32( @B[ 28 ], Round( Space_.BlueXY .Y * 100000 ) );

     WriteChunk( Stream_, PNG_cHRM, @B, 32 );
end;

// iCCP：名前（Latin-1 の 1〜79 文字）・0・圧縮の方法（0：deflate）・圧縮した ICC プロファイル

procedure WriteIccp( const Stream_:TStream; const Space_:TLuxColorSpace );
var
   Icc, B :TBytes;
   S :String;
   Name :TBytes;
   I :Integer;
   Zp :Pointer;
   Zn :Integer;
begin
     Icc := Space_.IccProfile;

     S := Copy( Space_.Name, 1, 79 );

     if S = '' then S := 'ICC';

     SetLength( Name, Length( S ) );

     for I := 0 to High( Name ) do
     begin
          if Ord( S[ I+1 ] ) <= $FF then Name[ I ] := Ord( S[ I+1 ] )  // Latin-1 は、Unicode の先頭の 256 字と同じ
                                    else Name[ I ] := Ord( '?' );
     end;

     ZCompress( @Icc[ 0 ], Length( Icc ), Zp, Zn );
     try
        SetLength( B, Length( Name ) + 2 + Zn );

        Move( Name[ 0 ], B[ 0 ], Length( Name ) );

        B[ Length( Name )     ] := 0;
        B[ Length( Name ) + 1 ] := 0;

        Move( Zp^, B[ Length( Name ) + 2 ], Zn );
     finally
        FreeMem( Zp );
     end;

     WriteChunk( Stream_, PNG_iCCP, @B[ 0 ], Length( B ) );
end;

function ReadIccp( const Data_:TBytes ) :TLuxColorSpace;
var
   I, Zn :Integer;
   Zp :Pointer;
   Icc :TBytes;
begin
     I := 0;
     while ( I < Length( Data_ ) ) and ( Data_[ I ] <> 0 ) do Inc( I );  // 名前の終わり

     if I + 2 >= Length( Data_ ) then Exit( nil );

     ZDecompress( @Data_[ I+2 ], Length( Data_ ) - I - 2, Zp, Zn );
     try
        SetLength( Icc, Zn );

        Move( Zp^, Icc[ 0 ], Zn );
     finally
        FreeMem( Zp );
     end;

     Result := TLuxColorSpaces.FromIcc( Icc );
end;

// gAMA と cHRM から、色空間を組み立てる。
// cHRM が無ければ sRGB の原色、gAMA が無ければ sRGB の曲線と見なす（規格の既定）。

function GamaChrmSpace( const Chrm_:TBytes; const Gama_:UInt32 ) :TLuxColorSpace;
var
   W, R, G, B :TDouble2D;
   T :TLuxTransfer;
//······································
     function XY( const I_:Integer ) :TDouble2D;
     begin
          Result := TDouble2D.Create( GetU32( @Chrm_[ I_ * 8     ] ) / 100000,
                                      GetU32( @Chrm_[ I_ * 8 + 4 ] ) / 100000 );
     end;
//······································
begin
     if Length( Chrm_ ) >= 32 then
     begin
          W := XY( 0 );  R := XY( 1 );  G := XY( 2 );  B := XY( 3 );
     end
     else
     with TLuxColorSpaces.sRGB do
     begin
          W := WhiteXY;  R := RedXY;  G := GreenXY;  B := BlueXY;
     end;

     if ( Gama_ = 0 ) or ( Abs( Int64( Gama_ ) - PNG_GAMA_SRGB ) <= 5 ) then T := TLuxTransfer.sRGB
                                                                        else T := TLuxTransfer.Gamma( 100000 / Gama_ );

     Result := TLuxColorSpaces.Intern( TLuxColorSpace.Create( 'PNG', R, G, B, W, T ) );
end;

//------------------------------------------------------------------------------ 走査線

// 標本を 1 つ取り出す。8 ビットに満たない標本は、上位のビットから詰めてある。

function Sample( const P_:PByte; const I_,Depth_:Integer ) :Integer; inline;
var
   B :Integer;
begin
     case Depth_ of
       16: Result := GetU16( @P_[ I_ * 2 ] );
        8: Result :=          P_[ I_     ]  ;
     else
          B := I_ * Depth_;

          Result := ( P_[ B shr 3 ] shr ( 8 - Depth_ - ( B and 7 ) ) ) and ( ( 1 shl Depth_ ) - 1 );
     end;
end;

// Paeth の予測：左 A・上 B・左上 C のうち、A + B - C に最も近いもの。

function Paeth( const A_,B_,C_:Integer ) :Integer; inline;
var
   PA, PB, PC :Integer;
begin
     PA := Abs( B_ - C_ );
     PB := Abs( A_ - C_ );
     PC := Abs( A_ + B_ - 2 * C_ );

     if ( PA <= PB ) and ( PA <= PC ) then Result := A_
                                      else
     if PB <= PC                      then Result := B_
                                      else Result := C_;
end;

// 走査線のフィルターを解く。Cur_ を書き換える。Prv_ は、解いた後の 1 つ上の走査線である。

procedure Unfilter( const Filt_:Byte; const Cur_,Prv_:PByte; const N_,Bpp_:Integer );
var
   I, A, C :Integer;
begin
     case Filt_ of
       0: ;
       1: for I := Bpp_ to N_-1 do Cur_[ I ] := ( Cur_[ I ] + Cur_[ I - Bpp_ ] ) and $FF;
       2: for I := 0    to N_-1 do Cur_[ I ] := ( Cur_[ I ] + Prv_[ I        ] ) and $FF;
       3: for I := 0    to N_-1 do
          begin
               if I >= Bpp_ then A := Cur_[ I - Bpp_ ]
                            else A := 0;

               Cur_[ I ] := ( Cur_[ I ] + ( A + Prv_[ I ] ) div 2 ) and $FF;
          end;
       4: for I := 0    to N_-1 do
          begin
               if I >= Bpp_ then begin  A := Cur_[ I - Bpp_ ];  C := Prv_[ I - Bpp_ ];  end
                            else begin  A := 0               ;  C := 0               ;  end;

               Cur_[ I ] := ( Cur_[ I ] + Paeth( A, Prv_[ I ], C ) ) and $FF;
          end;
     else Error( 'invalid filter type ' + Filt_.ToString );
     end;
end;

// Paeth のフィルターを掛ける。Out_ の先頭は、フィルターの種類である。

procedure FilterPaeth( const Cur_,Prv_,Out_:PByte; const N_,Bpp_:Integer );
var
   I, A, C :Integer;
begin
     Out_[ 0 ] := 4;

     for I := 0 to N_-1 do
     begin
          if I >= Bpp_ then begin  A := Cur_[ I - Bpp_ ];  C := Prv_[ I - Bpp_ ];  end
                       else begin  A := 0               ;  C := 0               ;  end;

          Out_[ I + 1 ] := ( Cur_[ I ] - Paeth( A, Prv_[ I ], C ) ) and $FF;
     end;
end;

// フィルターを解いた走査線を、画素にする。

procedure RowToPixels( const Head_:TPngHead; const Raw_:PByte; const N_:Integer; const Pixels_:PSingleRGBA );
var
   X, I, S :Integer;
   V :array [ 0..4-1 ] of Integer;
   M :Single;
begin
     M := 1 / Head_.MaxVal;

     for X := 0 to N_-1 do
     begin
          if Head_.Color = 3 then
          begin
               S := Sample( Raw_, X, Head_.Depth );

               if S >= Head_.PalN then Error( 'palette index ' + S.ToString + ' is out of range' );

               Pixels_[ X ] := Head_.Pal[ S ];

               Continue;
          end;

          for I := 0 to Head_.Chans-1 do V[ I ] := Sample( Raw_, X * Head_.Chans + I, Head_.Depth );

          case Head_.Color of
            0: begin
                    Pixels_[ X ] := TSingleRGBA.Create( V[ 0 ] * M, V[ 0 ] * M, V[ 0 ] * M, 1 );

                    if Head_.HasTrns and ( V[ 0 ] = Head_.Trns[ 0 ] ) then Pixels_[ X ].A := 0;
               end;
            2: begin
                    Pixels_[ X ] := TSingleRGBA.Create( V[ 0 ] * M, V[ 1 ] * M, V[ 2 ] * M, 1 );

                    if  Head_.HasTrns
                    and ( V[ 0 ] = Head_.Trns[ 0 ] )
                    and ( V[ 1 ] = Head_.Trns[ 1 ] )
                    and ( V[ 2 ] = Head_.Trns[ 2 ] ) then Pixels_[ X ].A := 0;
               end;
            4: Pixels_[ X ] := TSingleRGBA.Create( V[ 0 ] * M, V[ 0 ] * M, V[ 0 ] * M, V[ 1 ] * M );
            6: Pixels_[ X ] := TSingleRGBA.Create( V[ 0 ] * M, V[ 1 ] * M, V[ 2 ] * M, V[ 3 ] * M );
          end;
     end;
end;

// 画素を、RGB（Chans_ = 3）か RGBA（Chans_ = 4）の走査線にする。

procedure PixelsToRow( const Pixels_:PSingleRGBA; const N_,Chans_,Depth_:Integer; const Raw_:PByte );
var
   X, I, M :Integer;
   V :array [ 0..4-1 ] of Single;
   Q :PByte;
begin
     M := ( 1 shl Depth_ ) - 1;

     Q := Raw_;
     for X := 0 to N_-1 do
     begin
          V[ 0 ] := Pixels_[ X ].R;
          V[ 1 ] := Pixels_[ X ].G;
          V[ 2 ] := Pixels_[ X ].B;
          V[ 3 ] := Pixels_[ X ].A;

          for I := 0 to Chans_-1 do
          begin
               if Depth_ = 8 then begin  Q^ := Round( Clamp( V[ I ], 0, 1 ) * M );              Inc( Q, 1 );  end
                             else begin  PutU16( Q, Round( Clamp( V[ I ], 0, 1 ) * M ) );  Inc( Q, 2 );  end;
          end;
     end;
end;

//------------------------------------------------------------------------------ ヘッダー

// 署名から、最初の IDAT の頭までを読む。流れは、最初の IDAT の中身の先頭で止まる。

function ReadHead( const Stream_:TStream ) :TPngHead;
var
   Sign :array [ 0..8-1 ] of Byte;
   Size :Integer;
   Kind :UInt32;
   B :TBytes;
   I :Integer;
   Chrm :TBytes;
   Gama :UInt32;
   SRGB :Boolean;
begin
     Stream_.ReadBuffer( Sign, 8 );  // 署名（Decode が確かめ済み）

     Result := Default( TPngHead );

     Chrm := nil;  Gama := 0;  SRGB := False;

     while True do
     begin
          Size := ReadU32( Stream_ );
          Kind := ReadU32( Stream_ );

          if Size < 0 then Error( 'invalid chunk length' );

          if Kind = PNG_IDAT then Break;
          if Kind = PNG_IEND then Error( 'no IDAT chunk' );

          B := ReadChunk( Stream_, Size );

          case Kind of
            PNG_IHDR:
               begin
                    if Size < 13 then Error( 'IHDR is too short' );

                    Result.Width  := GetU32( @B[ 0 ] );
                    Result.Height := GetU32( @B[ 4 ] );
                    Result.Depth  := B[  8 ];
                    Result.Color  := B[  9 ];
                    Result.Interl := B[ 12 ];
               end;
            PNG_PLTE:
               begin
                    Result.PalN := Min( Size div 3, 256 );

                    for I := 0 to Result.PalN-1 do Result.Pal[ I ] := TSingleRGBA.Create( B[ I * 3     ] / 255,
                                                                                          B[ I * 3 + 1 ] / 255,
                                                                                          B[ I * 3 + 2 ] / 255, 1 );
               end;
            PNG_tRNS:
               case Result.Color of
                 0: if Size >= 2 then
                    begin
                         Result.HasTrns   := True;
                         Result.Trns[ 0 ] := GetU16( @B[ 0 ] );
                    end;
                 2: if Size >= 6 then
                    begin
                         Result.HasTrns   := True;
                         Result.Trns[ 0 ] := GetU16( @B[ 0 ] );
                         Result.Trns[ 1 ] := GetU16( @B[ 2 ] );
                         Result.Trns[ 2 ] := GetU16( @B[ 4 ] );
                    end;
                 3: for I := 0 to Min( Size, Result.PalN ) - 1 do Result.Pal[ I ].A := B[ I ] / 255;
               end;
            PNG_sRGB: SRGB := True;
            PNG_iCCP: Result.ColorSpace := ReadIccp( B );
            PNG_gAMA: if Size >=  4 then Gama := GetU32( @B[ 0 ] );
            PNG_cHRM: if Size >= 32 then Chrm := B;
          end;
     end;

     Result.IdatN := Size;

     ///// 色空間：iCCP が読めなければ sRGB、それも無ければ gAMA と cHRM

     if not Assigned( Result.ColorSpace ) then
     begin
          if SRGB                                then Result.ColorSpace := TLuxColorSpaces.sRGB
                                                 else
          if Assigned( Chrm ) or ( Gama > 0 )    then Result.ColorSpace := GamaChrmSpace( Chrm, Gama );
     end;

     ///// 形の検査

     if ( Result.Width < 1 ) or ( Result.Height < 1 ) then Error( 'invalid size' );

     case Result.Color of
       0: if Result.Depth in [ 1, 2, 4, 8, 16 ] then Result.Chans := 1;
       2: if Result.Depth in [          8, 16 ] then Result.Chans := 3;
       3: if Result.Depth in [ 1, 2, 4, 8     ] then Result.Chans := 1;
       4: if Result.Depth in [          8, 16 ] then Result.Chans := 2;
       6: if Result.Depth in [          8, 16 ] then Result.Chans := 4;
     end;

     if Result.Chans = 0 then Error( 'invalid combination of colour type ' + Result.Color.ToString
                                                        + ' and bit depth ' + Result.Depth.ToString );

     if Result.Interl > 1 then Error( 'invalid interlace method ' + Result.Interl.ToString );

     if ( Result.Color = 3 ) and ( Result.PalN = 0 ) then Error( 'no PLTE chunk' );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngHead

//////////////////////////////////////////////////////////////////// M E T H O D

function TPngHead.BitsPix :Integer;
begin
     Result := Chans * Depth;
end;

function TPngHead.FiltBpp :Integer;
begin
     Result := Max( 1, BitsPix div 8 );
end;

function TPngHead.MaxVal :Integer;
begin
     Result := ( 1 shl Depth ) - 1;
end;

function TPngHead.RowBytes( const W_:Integer ) :Integer;
begin
     Result := ( W_ * BitsPix + 7 ) div 8;
end;

function TPngHead.Passes :TArray<TPngPass>;
var
   I :Integer;
begin
     if Interl = 0 then
     begin
          SetLength( Result, Length( PNG_PASS_NONE ) );

          for I := 0 to High( Result ) do Result[ I ] := PNG_PASS_NONE[ I ];
     end
     else
     begin
          SetLength( Result, Length( PNG_PASS_ADAM7 ) );

          for I := 0 to High( Result ) do Result[ I ] := PNG_PASS_ADAM7[ I ];
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngIdatReader

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

// 直前のチャンクの CRC を飛ばし、次のチャンクが IDAT なら、その中身の先頭へ進む。

function TPngIdatReader.NextChunk :Boolean;
var
   N :Integer;
begin
     _Stream.Seek( 4, soCurrent );

     N := ReadU32( _Stream );

     Result := ReadU32( _Stream ) = PNG_IDAT;

     if Result then _Rest := N;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TPngIdatReader.Create( const Stream_:TStream; const Rest_:Integer );
begin
     inherited Create;

     _Stream := Stream_;
     _Rest   := Rest_  ;
     _Pos    := 0      ;
     _Ended  := False  ;
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
          if ( _Rest = 0 ) and not NextChunk then
          begin
               _Ended := True;  Break;
          end;

          C := _Stream.Read( D^, Min( Count - Result, _Rest ) );

          if ( C = 0 ) and ( _Rest > 0 ) then
          begin
               _Ended := True;  Break;
          end;

          Inc( D, C );  Dec( _Rest, C );  Inc( Result, C );
     end;

     Inc( _Pos, Result );
end;

function TPngIdatReader.Write( const Buffer; Count:Longint ) :Longint;
begin
     raise EImageCodec.Create( 'PNG: the IDAT reader is read-only' );
end;

// 伸長の流れ（TZDecompressionStream）は、読むたびに元の流れの位置を尋ね、
// 自分の覚えている位置と違えば、戻そうとする。いまの位置を正しく答えれば、戻しは起こらない。

function TPngIdatReader.Seek( const Offset:Int64; Origin:TSeekOrigin ) :Int64;
begin
     if ( ( Origin = soBeginning ) and ( Offset = _Pos ) )
     or ( ( Origin = soCurrent   ) and ( Offset = 0    ) ) then Exit( _Pos );

     raise EImageCodec.Create( 'PNG: the IDAT reader is sequential' );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngIdatWriter

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TPngIdatWriter.Create( const Stream_:TStream );
begin
     inherited Create;

     _Stream := Stream_;
     _Count  := 0      ;
     _Pos    := 0      ;

     SetLength( _Buffer, PNG_IDAT_MAX );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

// たまっているバイトを、IDAT チャンク 1 つとして出す。

procedure TPngIdatWriter.Flush;
begin
     if _Count = 0 then Exit;

     WriteChunk( _Stream, PNG_IDAT, @_Buffer[ 0 ], _Count );

     _Count := 0;
end;

function TPngIdatWriter.Read( var Buffer; Count:Longint ) :Longint;
begin
     raise EImageCodec.Create( 'PNG: the IDAT writer is write-only' );
end;

function TPngIdatWriter.Write( const Buffer; Count:Longint ) :Longint;
var
   S :PByte;
   N :Longint;
   C :Longint;
begin
     Result := Count;

     S := @Buffer;  N := Count;
     while N > 0 do
     begin
          C := Min( N, PNG_IDAT_MAX - _Count );

          Move( S^, _Buffer[ _Count ], C );

          Inc( _Count, C );  Inc( S, C );  Dec( N, C );

          if _Count = PNG_IDAT_MAX then Flush;
     end;

     Inc( _Pos, Result );
end;

// 圧縮の流れ（TZCompressionStream）も、元の流れの位置を尋ねる（読む側と同じ）。

function TPngIdatWriter.Seek( const Offset:Int64; Origin:TSeekOrigin ) :Int64;
begin
     if ( ( Origin = soBeginning ) and ( Offset = _Pos ) )
     or ( ( Origin = soCurrent   ) and ( Offset = 0    ) ) then Exit( _Pos );

     raise EImageCodec.Create( 'PNG: the IDAT writer is sequential' );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecPng

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TImageCodecPng.GetAlpha :Boolean;
begin
     Result := _Alpha;
end;

procedure TImageCodecPng.SetAlpha( const Alpha_:Boolean );
begin
     _Alpha := Alpha_;
end;

function TImageCodecPng.GetLevel :TImagePngLevel;
begin
     Result := _Level;
end;

procedure TImageCodecPng.SetLevel( const Level_:TImagePngLevel );
begin
     _Level := Level_;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TImageCodecPng.Create;
begin
     inherited;

     _Alpha := True     ;
     _Level := plDefault;
end;

//////////////////////////////////////////////////////////////////////// C L A S S

class function TImageCodecPng.Extensions :TArray<String>;
begin
     Result := [ '.png' ];
end;

class function TImageCodecPng.Caption :String;
begin
     Result := 'PNG';
end;

class function TImageCodecPng.Matches( const Bytes_:TBytes ) :Boolean;
begin
     Result := ( Length( Bytes_ ) >= 8 ) and CompareMem( @Bytes_[ 0 ], @PNG_SIGN, 8 );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TImageCodecPng.Assign( const Codec_:TImageCodec );
begin
     inherited;

     _Alpha := ( Codec_ as TImageCodecPng ).Alpha;
     _Level := ( Codec_ as TImageCodecPng ).Level;
end;

//------------------------------------------------------------------------------

procedure TImageCodecPng.DoDecode( const Stream_:TStream; const Raster_:TImageRaster );
var
   H :TPngHead;
   Idat :TPngIdatReader;
   Zlib :TZDecompressionStream;
   Cur, Prv, T :TBytes;
   Row :TArray<TSingleRGBA>;
   P :TPngPass;
   PW, PH :Integer;
   N, Y :Integer;
   Filt :Byte;
begin
     H := ReadHead( Stream_ );

     Raster_.Header := TImageHeader.Create( H.Width, H.Height, H.ColorSpace, H.Depth );

     ///// 走査線の領域は、最も幅の広いパス（＝画像の幅）に合わせる

     SetLength( Cur, H.RowBytes( H.Width ) );
     SetLength( Prv, H.RowBytes( H.Width ) );
     SetLength( Row, H.Width               );

     Idat := TPngIdatReader.Create( Stream_, H.IdatN );
     try
        Zlib := TZDecompressionStream.Create( Idat );
        try
           for P in H.Passes do
           begin
                PW := ( H.Width  - P.X0 + P.DX - 1 ) div P.DX;
                PH := ( H.Height - P.Y0 + P.DY - 1 ) div P.DY;

                if ( PW <= 0 ) or ( PH <= 0 ) then Continue;  // 画像が小さいと、画素の無いパスがある

                N := H.RowBytes( PW );

                FillChar( Prv[ 0 ], N, 0 );                   // パスの最初の走査線の「上」は、0 である

                for Y := 0 to PH-1 do
                begin
                     Zlib.ReadBuffer( Filt, 1 );
                     Zlib.ReadBuffer( Cur[ 0 ], N );

                     Unfilter( Filt, @Cur[ 0 ], @Prv[ 0 ], N, H.FiltBpp );

                     RowToPixels( H, @Cur[ 0 ], PW, @Row[ 0 ] );

                     Raster_.SetLine( P.X0, P.Y0 + Y * P.DY, P.DX, 0, PW, @Row[ 0 ] );

                     T := Prv;  Prv := Cur;  Cur := T;
                end;
           end;
        finally
           Zlib.Free;
        end;
     finally
        Idat.Free;
     end;
end;

//------------------------------------------------------------------------------

procedure TImageCodecPng.DoEncode( const Stream_:TStream; const Raster_:TImageRaster; const Header_:TImageHeader );
var
   Depth :Integer;
   Chans :Integer;
   Bpp, N, Y :Integer;
   B :array [ 0..13-1 ] of Byte;
   Idat :TPngIdatWriter;
   Zlib :TZCompressionStream;
   Cur, Prv, T :TBytes;
   Out_ :TBytes;
   Row :TArray<TSingleRGBA>;
begin
     if Header_.Depth <= 8 then Depth :=  8
                     else Depth := 16;

     if _Alpha then Chans := 4
               else Chans := 3;

     Bpp := Chans * ( Depth div 8 );
     N   := Header_.Width * Bpp;

     ///// 署名と IHDR

     Stream_.WriteBuffer( PNG_SIGN, 8 );

     PutU32( @B[ 0 ], Header_.Width  );
     PutU32( @B[ 4 ], Header_.Height );

     B[  8 ] := Depth;
     B[  9 ] := 2 + 4 * Ord( _Alpha );  // 2：RGB　6：RGBA
     B[ 10 ] := 0;                      // 圧縮の方法
     B[ 11 ] := 0;                      // フィルターの方法
     B[ 12 ] := 0;                      // インターレース無し

     WriteChunk( Stream_, PNG_IHDR, @B, 13 );

     ///// 色空間（IDAT より前に置く）。sRGB チャンクと iCCP は、規格上、同時に書かない

     if Header_.ColorSpace = TLuxColorSpaces.sRGB then
     begin
          B[ 0 ] := 0;  // 描画の意図：知覚的

          WriteChunk( Stream_, PNG_sRGB, @B, 1 );

          WriteGama( Stream_, PNG_GAMA_SRGB );
          WriteChrm( Stream_, Header_.ColorSpace );
     end
     else
     if Assigned( Header_.ColorSpace ) then
     begin
          WriteIccp( Stream_, Header_.ColorSpace );

          if Header_.ColorSpace.Transfer.IsGamma then WriteGama( Stream_, Round( 100000 / Header_.ColorSpace.Transfer.G ) );

          WriteChrm( Stream_, Header_.ColorSpace );
     end;

     ///// IDAT

     SetLength( Cur , N       );
     SetLength( Prv , N       );        // 0 で埋まっている（最初の走査線の「上」）
     SetLength( Out_, N + 1   );
     SetLength( Row , Header_.Width );

     Idat := TPngIdatWriter.Create( Stream_ );
     try
        // 窓のビット数 15 は、zlib のヘッダーつきの形（PNG が求める RFC 1950）である。
        Zlib := TZCompressionStream.Create( Idat, PNG_ZLEVEL[ _Level ], 15 );
        try
           for Y := 0 to Header_.Height-1 do
           begin
                Raster_.GetLine( 0, Y, 1, 0, Header_.Width, @Row[ 0 ] );

                PixelsToRow( @Row[ 0 ], Header_.Width, Chans, Depth, @Cur[ 0 ] );

                FilterPaeth( @Cur[ 0 ], @Prv[ 0 ], @Out_[ 0 ], N, Bpp );

                Zlib.WriteBuffer( Out_[ 0 ], N + 1 );

                T := Prv;  Prv := Cur;  Cur := T;
           end;
        finally
           Zlib.Free;  // 残りを Idat へ出し切る
        end;

        Idat.Flush;
     finally
        Idat.Free;
     end;

     WriteChunk( Stream_, PNG_IEND, nil, 0 );
end;

initialization //############################################################### ■

     InitCrcTab;

     TImageCodec.Regist( TImageCodecPng );

end. //######################################################################### ■
