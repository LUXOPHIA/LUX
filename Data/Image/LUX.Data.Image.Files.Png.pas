unit LUX.Data.Image.Files.Png;

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.Classes, System.SysUtils,
     LUX.Data.Image, LUX.Data.Image.Files;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxPngLevel

     ///// PNG の圧縮率。PNG は可逆なので画質には一切影響せず、変わるのは大きさと時間だけである。
     ///// zlib のレベルは 0〜9 あるが、実際に意味が変わるのはこの４点で、中間値は大きさが
     ///// ほとんど変わらないのに時間だけ延びる（画像編集ソフトが３〜４段階しか出さないのもそのため）。

     TLuxPngLevel = ( plNone,      // 無圧縮（ deflate の stored ブロック）。最速・最大
                      plFastest,   // 速さ優先
                      plDefault,   // 既定（ zlib の標準 ）
                      plMax );     // 小ささ優先。最遅・最小

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFilerPng

     ///// PNG の読み書き（ System.ZLib の上に直接実装。Skia も FireMonkey も使わない ）
     /////
     ///// ・読み：規格の定める全ての形式に対応する。ビット深度 1/2/4/8/16、カラータイプ 0/2/3/4/6、
     /////   PLTE、tRNS の３形態、Adam7 インターレース。
     ///// ・書き：RGBA（ Alpha = False なら α 無しの RGB ）。TLuxImageUInt08 なら 8bit、それ以外は 16bit。
     ///// ・非インターレースの読み書きは行単位のストリーミングなので、ファイルがどれだけ大きくても
     /////   画像１枚分の一時領域を確保しない。
     ///// ・色空間：Image.ColorSpace が sRGB なら sRGB チャンク（＋規格の勧める gAMA と cHRM）、
     /////   それ以外は iCCP ＋ cHRM（伝達関数が純ガンマなら gAMA も）。読みは iCCP ＞ sRGB ＞ gAMA＋cHRM。

     TLuxImageFilerPng = class( TLuxImageFiler )
     private
       _Alpha :Boolean;
       _Level :TLuxPngLevel;
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
       property Alpha :Boolean      read _Alpha write _Alpha;  // α を書くか（既定 True ）
       property Level :TLuxPngLevel read _Level write _Level;  // 圧縮率（既定 plDefault ）
       ///// M E T H O D
       procedure Assign( const Filer_:TLuxImageFiler ); override;
       function ImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean; override;
     end;

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

      ///// TLuxPngLevel → zlib のレベル（ 0 / 1 / 6 / 9 ）

      PNG_ZLEVEL :array [ TLuxPngLevel ] of TZCompressionLevel = ( zcNone, zcFastest, zcDefault, zcMax );

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


//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFilerPng

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageFilerPng.DoLoad( const Image_:TLuxImage; const Stream_:TStream );
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

procedure TLuxImageFilerPng.DoSave( const Image_:TLuxImage; const Stream_:TStream );
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

     if _Alpha then Chans := 4 else Chans := 3;

     Bpp  := Chans * ( Depth div 8 );
     RowN := W * Bpp;

     ///// 署名

     Stream_.WriteBuffer( PNG_SIGN[ 0 ], 8 );

     ///// IHDR

     SetLength( Head, 13 );

     U := SwapU32( W );  Move( U, Head[ 0 ], 4 );
     U := SwapU32( H );  Move( U, Head[ 4 ], 4 );

     Head[  8 ] := Depth;
     if _Alpha then Head[ 9 ] := 6   // RGBA
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
          ///// windowBits 15 ＝ zlib のヘッダ付き（ PNG が要求する RFC 1950 の形式 ）。
          ///// plNone は deflate の stored ブロックになり、規格上も正当な PNG である。

          Zlib := TZCompressionStream.Create( Idat, PNG_ZLEVEL[ _Level ], 15 );
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

                              if _Alpha then Q[ 3 ] := Round( Clamp( Row[X].A, 0, 1 ) * $FF );

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

                              if _Alpha then
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

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TLuxImageFilerPng.Create;
begin
     inherited Create;

     _Alpha := True;
     _Level := plDefault;
end;

//////////////////////////////////////////////////////////////////////// C L A S S

class function TLuxImageFilerPng.Extensions :TArray<String>;
begin
     Result := [ '.png' ];
end;

class function TLuxImageFilerPng.Caption :String;
begin
     Result := 'PNG';
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageFilerPng.Assign( const Filer_:TLuxImageFiler );
begin
     inherited;

     if Filer_ is TLuxImageFilerPng then
     begin
          _Alpha := TLuxImageFilerPng( Filer_ )._Alpha;
          _Level := TLuxImageFilerPng( Filer_ )._Level;
     end;
end;

///// IHDR は署名の直後にあるので、そこだけ読めば寸法が判る

function TLuxImageFilerPng.ImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;
var
   S    :TFileStream;
   Head :array [ 0..23 ] of Byte;
begin
     Width_ := 0;  Height_ := 0;  Result := False;

     S := TFileStream.Create( FileName_, fmOpenRead or fmShareDenyWrite );
     try
        if S.Size < SizeOf( Head ) then Exit;

        S.ReadBuffer( Head[ 0 ], SizeOf( Head ) );

        if not CompareMem( @Head[ 0 ], @PNG_SIGN[ 0 ], 8 ) then Exit;

        if ( Head[ 12 ] <> Ord('I') ) or ( Head[ 13 ] <> Ord('H') )
        or ( Head[ 14 ] <> Ord('D') ) or ( Head[ 15 ] <> Ord('R') ) then Exit;

        Width_  := ( Head[16] shl 24 ) or ( Head[17] shl 16 ) or ( Head[18] shl 8 ) or Head[19];
        Height_ := ( Head[20] shl 24 ) or ( Head[21] shl 16 ) or ( Head[22] shl 8 ) or Head[23];

        Result := ( Width_ > 0 ) and ( Height_ > 0 );
     finally
        S.Free;
     end;
end;

initialization //############################################################### ■

     InitCrcTab;

     TLuxImageFiler.Regist( TLuxImageFilerPng );

end. //######################################################################### ■
