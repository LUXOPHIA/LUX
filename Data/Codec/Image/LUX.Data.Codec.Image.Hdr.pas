unit LUX.Data.Codec.Image.Hdr;

// Radiance の画像（.hdr・.pic）のコーデック
//
// 形式の定義は、Radiance の公式の実装（src/common の color.c・color.h・resolu.c・header.c）に従う。
//
//【ファイルの構成】
// ・ヘッダー：「#?」で始まる行、「変数=値」の行の並び、空の行。文字は ASCII、行の終わりは LF。
// ・解像度の行：「{+-}{XY} 個数 {+-}{YX} 個数」。先の軸が走査線の並ぶ向き、後の軸が走査線の中の向きである。
//   ファイルの座標は、X が右向き、Y が上向きである。
// ・画素：1 画素は 4 バイト（3 つの仮数と、共通の指数）。走査線ごとに、次のどれかで入っている。
//     新しい連長 … 先頭が ( 2, 2, 長さの上位, 長さの下位 )。成分ごとに、1 本ぶんを連長で詰める。
//     古い連長   … 画素 ( 1, 1, 1, 回数 ) が、直前の画素の繰り返しを表す。
//     無圧縮     … 古い連長で、繰り返しが 1 つも無いもの。
//
//【復号】
// ・走査線の 3 つの入り方と、解像度の行の 8 通りの向きの、すべてを読む。
//   走査線は、向きに応じた歩みの並びとして渡すので、1 枚ぶんの一時の領域を持たない。
// ・形式は、FORMAT=32-bit_rle_rgbe と 32-bit_rle_xyze（FORMAT が無ければ前者）。
//   XYZ の画素は、色空間の RGB に直して渡す。
// ・渡す値は、ファイルに入っている値そのものである（EXPOSURE と COLORCORR は当てはめない）。α は 1。
//
//【符号化】
// ・形式は 32-bit_rle_rgbe、向きは標準（-Y 高さ +X 幅）。幅が 17〜32767 なら新しい連長、それ以外は無圧縮。
// ・この形式は α を持たないので、α は捨てる。負の成分は 0 になる。
//
//【色空間】
// ・この形式の画素は、線形である。原色は、PRIMARIES= があればその値、無ければ Radiance の既定である。
// ・読み：その原色の、線形の色空間を渡す。
// ・書き：置き場に色空間があれば、画素を線形に直し、原色を PRIMARIES= に書く。
//   色空間が nil なら、画素をそのまま書き、PRIMARIES= は書かない。

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.SysUtils, System.Classes,
     LUX.Data.Codec.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecHdr

     TImageCodecHdr = class( TImageCodec )
     private
     protected
       ///// M E T H O D
       procedure DoDecode( const Stream_:TStream; const Raster_:TImageRaster ); override;
       procedure DoEncode( const Stream_:TStream; const Raster_:TImageRaster; const Header_:TImageHeader ); override;
     public
       ///// C L A S S
       class function Extensions :TArray<String>; override;
       class function Caption :String; override;
       class function Matches( const Bytes_:TBytes ) :Boolean; override;
       ///// M E T H O D
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.Math,
     LUX, LUX.D2, LUX.D3, LUX.D3x3, LUX.Color, LUX.Color.Space;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% THdrPixel

     // ファイルの中の 1 画素。成分の順は、ファイルのとおり（3 つの仮数・指数）である。
     THdrPixel = packed record
       Cs :array [ 0..4-1 ] of Byte;
     end;

     PHdrPixel = ^THdrPixel;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% THdrInput

     // 流れを、まとめて読んで、1 バイトずつ渡す。
     // 走査線の復号は 1 バイトずつ進むので、流れを 1 バイトずつ呼ぶと、呼び出しの費用が画素の数に比例してしまう。
     THdrInput = record
     private
       _Stream :TStream;
       _Buffer :TBytes;
       _Head   :Integer;  // 次に渡すバイトの位置
       _Tail   :Integer;  // 読んであるバイトの終わり
       ///// M E T H O D
       procedure Fill;
     public
       constructor Create( const Stream_:TStream );
       ///// M E T H O D
       function Take :Byte; inline;                               // 1 バイト
       procedure TakeTo( const Bytes_:PByte; const N_:Integer );  // N_ バイト
       function TakeLine :String;                                 // LF までの 1 行（LF は含めない）
       procedure Close;                                           // 読みすぎた分だけ、流れの位置を戻す
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% THdrAxis

     // 解像度の行の、軸 1 つ。
     // ファイルの座標は X が右向き・Y が上向き、画像の座標は X が右向き・Y が下向きである。
     // ゆえに、ファイルの進む向きが画像の座標と逆になるのは、X では符号が - のとき、Y では + のときである。
     THdrAxis = record
       IsY    :Boolean;
       Minus  :Boolean;
       Count  :Integer;
       ///// M E T H O D
       function Rever :Boolean;                      // 画像の座標と逆向きに進むか
       function Start( const I_:Integer ) :Integer;  // I_ 番目の位置（画像の座標）
       function Step :Integer;                       // 1 つ進んだときの、位置の変化
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% THdrHead

     // ヘッダーと解像度の行から得る、復号に要る情報。
     THdrHead = record
       IsXYZ      :Boolean;   // 画素が XYZ（32-bit_rle_xyze）か
       ColorSpace :TLuxColorSpace;
       Major      :THdrAxis;  // 走査線の並ぶ向き
       Minor      :THdrAxis;  // 走査線の中の向き
       ///// M E T H O D
       function Width :Integer;
       function Height :Integer;
     end;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      HDR_MAGIC     = '#?';
      HDR_PROGRAM   = 'RADIANCE';
      HDR_FORMAT    = 'FORMAT=';
      HDR_PRIMARIES = 'PRIMARIES=';
      HDR_RGBE      = '32-bit_rle_rgbe';
      HDR_XYZE      = '32-bit_rle_xyze';

      HDR_LINE_MAX  = 2048;  // ヘッダーの 1 行の最大の長さ（公式の実装の MAXLINE）

      HDR_ENCO_MIN  = 17;     // 新しい連長で書く、走査線の最小の長さ（公式の実装の MINELEN）
      HDR_ENCO_MAX  = $7FFF;  // 新しい連長で表せる、走査線の最大の長さ（長さの上位のバイトの最上位ビットは 0）
      HDR_RUN_MIN   = 4;      // 繰り返しとして書く、最小の長さ（それより短いと、そのまま書くより長くなる）
      HDR_RUN_MAX   = 127;    // 繰り返し 1 つの最大の長さ
      HDR_RAW_MAX   = 128;    // そのまま書くまとまり 1 つの最大の長さ

      // 既定の原色と白（color.h の STDPRIMS）
      HDR_RED_XY   :TDouble2D = ( _1D:( 0.640, 0.330 ) );
      HDR_GREEN_XY :TDouble2D = ( _1D:( 0.290, 0.600 ) );
      HDR_BLUE_XY  :TDouble2D = ( _1D:( 0.150, 0.060 ) );
      HDR_WHITE_XY :TDouble2D = ( _1D:( 1/3  , 1/3   ) );

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

procedure Error( const Text_:String );
begin
     raise EImageCodec.Create( 'Radiance HDR: ' + Text_ );
end;

//------------------------------------------------------------------------------ ヘッダー

// 線形の色空間。同じ中身の色空間が登録済みなら、それになる。

function LinearSpace( const R_,G_,B_,W_:TDouble2D ) :TLuxColorSpace;
begin
     Result := TLuxColorSpaces.Intern( TLuxColorSpace.Create( 'Radiance RGB', R_, G_, B_, W_, TLuxTransfer.Linear ) );
end;

// PRIMARIES= の値：赤・緑・青・白の色度座標（8 つの実数）

function ReadPrimaries( const Value_:String ) :TLuxColorSpace;
var
   Ws :TArray<String>;
   Vs :array [ 0..8-1 ] of Double;
   I :Integer;
begin
     Ws := Value_.Split( [ ' ', #9 ], TStringSplitOptions.ExcludeEmpty );

     if Length( Ws ) <> 8 then Error( 'invalid ' + HDR_PRIMARIES + Value_ );

     for I := 0 to 8-1 do
     begin
          if not TryStrToFloat( Ws[ I ], Vs[ I ], TFormatSettings.Invariant ) then Error( 'invalid ' + HDR_PRIMARIES + Value_ );
     end;

     Result := LinearSpace( TDouble2D.Create( Vs[ 0 ], Vs[ 1 ] ),
                            TDouble2D.Create( Vs[ 2 ], Vs[ 3 ] ),
                            TDouble2D.Create( Vs[ 4 ], Vs[ 5 ] ),
                            TDouble2D.Create( Vs[ 6 ], Vs[ 7 ] ) );
end;

function WritePrimaries( const Space_:TLuxColorSpace ) :String;
//······································
     function XY( const P_:TDouble2D ) :String;
     begin
          Result := ' ' + FormatFloat( '0.0000', P_.X, TFormatSettings.Invariant )
                  + ' ' + FormatFloat( '0.0000', P_.Y, TFormatSettings.Invariant );
     end;
//······································
begin
     Result := HDR_PRIMARIES + XY( Space_.RedXY ) + XY( Space_.GreenXY ) + XY( Space_.BlueXY ) + XY( Space_.WhiteXY );
end;

// 解像度の行の、軸 1 つ（「符号と名前」と「個数」）

function ReadAxis( const Name_,Count_:String ) :THdrAxis;
begin
     if  ( Length( Name_ ) = 2 )
     and ( ( Name_[ 1 ] = '+' ) or ( Name_[ 1 ] = '-' ) )
     and ( ( Name_[ 2 ] = 'X' ) or ( Name_[ 2 ] = 'Y' ) )
     and TryStrToInt( Count_, Result.Count ) and ( Result.Count >= 1 ) then
     begin
          Result.Minus := Name_[ 1 ] = '-';
          Result.IsY   := Name_[ 2 ] = 'Y';
     end
     else Error( 'invalid resolution "' + Name_ + ' ' + Count_ + '"' );
end;

// 流れの先頭から、解像度の行までを読む。

function ReadHead( var Input_:THdrInput ) :THdrHead;
var
   L :String;
   Ws :TArray<String>;
begin
     Result := Default( THdrHead );

     Input_.TakeLine;  // 「#?」で始まる行（Decode が確かめ済み）

     ///// 変数の行（空の行まで）。同じ変数が何度も現れたら、後のものが有効である

     L := Input_.TakeLine.TrimRight;
     while L <> '' do
     begin
          if L.StartsWith( HDR_FORMAT ) then
          begin
               L := L.Substring( Length( HDR_FORMAT ) ).Trim;

               if L = HDR_XYZE then Result.IsXYZ := True
                               else
               if L = HDR_RGBE then Result.IsXYZ := False
                               else Error( 'unsupported ' + HDR_FORMAT + L );
          end
          else
          if L.StartsWith( HDR_PRIMARIES ) then Result.ColorSpace := ReadPrimaries( L.Substring( Length( HDR_PRIMARIES ) ) );

          L := Input_.TakeLine.TrimRight;
     end;

     if not Assigned( Result.ColorSpace ) then Result.ColorSpace := LinearSpace( HDR_RED_XY, HDR_GREEN_XY, HDR_BLUE_XY, HDR_WHITE_XY );

     ///// 解像度の行

     L := Input_.TakeLine;

     Ws := L.Split( [ ' ', #9, #13 ], TStringSplitOptions.ExcludeEmpty );

     if Length( Ws ) <> 4 then Error( 'invalid resolution line "' + L + '"' );

     Result.Major := ReadAxis( Ws[ 0 ], Ws[ 1 ] );
     Result.Minor := ReadAxis( Ws[ 2 ], Ws[ 3 ] );

     if Result.Major.IsY = Result.Minor.IsY then Error( 'invalid resolution line "' + L + '"' );
end;

//------------------------------------------------------------------------------ 走査線の復号

// 新しい連長。成分ごとに、1 本ぶんが続けて入っている。
// 長さのバイトが 128 を超えるときは、超えた数だけ、次の 1 バイトを繰り返す。
// そうでないときは、その数だけ、バイトがそのまま続く。

procedure ReadScanNew( var Input_:THdrInput; const Scan_:PHdrPixel; const N_:Integer );
var
   C, I, K, J :Integer;
   V :Byte;
begin
     for C := 0 to 4-1 do
     begin
          I := 0;
          while I < N_ do
          begin
               K := Input_.Take;

               if K > 128 then
               begin
                    K := K - 128;

                    if I + K > N_ then Error( 'a run exceeds the scanline' );

                    V := Input_.Take;

                    for J := I to I + K - 1 do Scan_[ J ].Cs[ C ] := V;
               end
               else
               begin
                    if I + K > N_ then Error( 'a run exceeds the scanline' );

                    for J := I to I + K - 1 do Scan_[ J ].Cs[ C ] := Input_.Take;
               end;

               Inc( I, K );
          end;
     end;
end;

// 古い連長。画素がそのまま並ぶ。Scan_[ 0 ] は、既に読んである。
// 画素 ( 1, 1, 1, 回数 ) は、直前の画素の繰り返しを表す。続けて現れると、回数の桁が 8 ビットずつ上がる。
// 繰り返しが走査線の終わりを越える分は、形式の定義により、無いものとする。

procedure ReadScanOld( var Input_:THdrInput; const Scan_:PHdrPixel; const N_:Integer );
var
   I, S :Integer;
   K :Int64;
   P :THdrPixel;
begin
     P := Scan_[ 0 ];

     I := 0;  S := 0;
     while True do
     begin
          if ( P.Cs[ 0 ] = 1 ) and ( P.Cs[ 1 ] = 1 ) and ( P.Cs[ 2 ] = 1 ) then
          begin
               if I = 0 then Error( 'a scanline begins with a repeat' );

               K := Min( Int64( P.Cs[ 3 ] ) shl Min( S, 32 ), N_ - I );

               while K > 0 do
               begin
                    Scan_[ I ] := Scan_[ I-1 ];

                    Inc( I );  Dec( K );
               end;

               Inc( S, 8 );
          end
          else
          begin
               Scan_[ I ] := P;

               Inc( I );  S := 0;
          end;

          if I = N_ then Break;

          Input_.TakeTo( @P, 4 );
     end;
end;

// 走査線を 1 本読む。
// 新しい連長の先頭は ( 2, 2, 長さの上位, 長さの下位 ) であり、上位のバイトの最上位ビットは 0 である。
// 正規化された画素は、どれかの仮数の最上位ビットが 1 なので、この 4 バイトは画素ではありえない。

procedure ReadScan( var Input_:THdrInput; const Scan_:PHdrPixel; const N_:Integer );
var
   P :PHdrPixel;
begin
     P := @Scan_[ 0 ];

     Input_.TakeTo( @P^, 4 );

     if ( P^.Cs[ 0 ] = 2 ) and ( P^.Cs[ 1 ] = 2 ) and ( P^.Cs[ 2 ] < $80 ) then
     begin
          if ( P^.Cs[ 2 ] shl 8 ) or P^.Cs[ 3 ] <> N_ then Error( 'the length of an encoded scanline does not match the resolution' );

          ReadScanNew( Input_, Scan_, N_ );
     end
     else ReadScanOld( Input_, Scan_, N_ );
end;

//------------------------------------------------------------------------------ 走査線の符号化

// 成分 C_ の 1 本ぶんを、新しい連長で書く。
// 長さ HDR_RUN_MIN 以上の繰り返しを探し、そこまでをそのまま書き、繰り返しを 2 バイトで書く。

procedure WriteComp( const Output_:TStream; const Scan_:PHdrPixel; const N_,C_:Integer );
var
   I, J, K, L, M :Integer;
   B :array [ 0..1 + HDR_RAW_MAX - 1 ] of Byte;
//······································
     // J_ から、同じ値が続く長さ（HDR_RUN_MAX まで）
     function RunAt( const J_:Integer ) :Integer;
     begin
          Result := 1;
          while ( Result < HDR_RUN_MAX ) and ( J_ + Result < N_ ) and ( Scan_[ J_ + Result ].Cs[ C_ ] = Scan_[ J_ ].Cs[ C_ ] ) do Inc( Result );
     end;
//······································
begin
     I := 0;
     while I < N_ do
     begin
          ///// J：次の繰り返しの始まり（無ければ N_）　L：その長さ（無ければ 0）

          J := I;  L := 0;
          while J < N_ do
          begin
               L := RunAt( J );

               if L >= HDR_RUN_MIN then Break;

               Inc( J, L );  L := 0;
          end;

          ///// I から J の手前までを、そのまま書く

          while I < J do
          begin
               K := Min( J - I, HDR_RAW_MAX );

               B[ 0 ] := K;
               for M := 1 to K do B[ M ] := Scan_[ I + M - 1 ].Cs[ C_ ];

               Output_.WriteBuffer( B, 1 + K );

               Inc( I, K );
          end;

          ///// 繰り返しを書く

          if L > 0 then
          begin
               B[ 0 ] := 128 + L;
               B[ 1 ] := Scan_[ J ].Cs[ C_ ];

               Output_.WriteBuffer( B, 2 );

               Inc( I, L );
          end;
     end;
end;

// 走査線を 1 本書く。新しい連長で表せない長さは、無圧縮で書く。

procedure WriteScan( const Output_:TStream; const Scan_:PHdrPixel; const N_:Integer );
var
   B :THdrPixel;
   C :Integer;
begin
     if ( N_ < HDR_ENCO_MIN ) or ( N_ > HDR_ENCO_MAX ) then
     begin
          Output_.WriteBuffer( Scan_^, 4 * N_ );

          Exit;
     end;

     B.Cs[ 0 ] := 2;
     B.Cs[ 1 ] := 2;
     B.Cs[ 2 ] := N_ shr 8;
     B.Cs[ 3 ] := N_ and $FF;

     Output_.WriteBuffer( B, 4 );

     for C := 0 to 4-1 do WriteComp( Output_, Scan_, N_, C );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% THdrInput

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

procedure THdrInput.Fill;
begin
     _Head := 0;
     _Tail := _Stream.Read( _Buffer[ 0 ], Length( _Buffer ) );

     if _Tail = 0 then Error( 'unexpected end of the stream' );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor THdrInput.Create( const Stream_:TStream );
begin
     _Stream := Stream_;
     _Head   := 0;
     _Tail   := 0;

     SetLength( _Buffer, 1 shl 16 );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

function THdrInput.Take :Byte;
begin
     if _Head = _Tail then Fill;

     Result := _Buffer[ _Head ];

     Inc( _Head );
end;

procedure THdrInput.TakeTo( const Bytes_:PByte; const N_:Integer );
var
   I :Integer;
begin
     for I := 0 to N_-1 do Bytes_[ I ] := Take;
end;

function THdrInput.TakeLine :String;
var
   B :Byte;
begin
     Result := '';

     B := Take;
     while B <> 10 do
     begin
          if Length( Result ) = HDR_LINE_MAX then Error( 'a header line is too long' );

          Result := Result + Char( B );

          B := Take;
     end;
end;

procedure THdrInput.Close;
begin
     _Stream.Seek( Int64( _Head ) - _Tail, soCurrent );

     _Head := _Tail;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% THdrAxis

//////////////////////////////////////////////////////////////////// M E T H O D

function THdrAxis.Rever :Boolean;
begin
     Result := Minus xor IsY;
end;

function THdrAxis.Start( const I_:Integer ) :Integer;
begin
     if Rever then Result := Count-1 - I_
              else Result :=           I_;
end;

function THdrAxis.Step :Integer;
begin
     if Rever then Result := -1
              else Result := +1;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% THdrHead

//////////////////////////////////////////////////////////////////// M E T H O D

function THdrHead.Width :Integer;
begin
     if Major.IsY then Result := Minor.Count
                  else Result := Major.Count;
end;

function THdrHead.Height :Integer;
begin
     if Major.IsY then Result := Major.Count
                  else Result := Minor.Count;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecHdr

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TImageCodecHdr.DoEncode( const Stream_:TStream; const Raster_:TImageRaster; const Header_:TImageHeader );
var
   CS :TLuxColorSpace;
   Head :String;
   B :TBytes;
   Row :TArray<TSingleRGBA>;
   Scan :TArray<THdrPixel>;
   C :TSingleRGB;
   E :TByteRGBE;
   X, Y :Integer;
begin
     CS := Header_.ColorSpace;

     ///// ヘッダーと解像度の行

     Head := HDR_MAGIC + HDR_PROGRAM + #10
           + HDR_FORMAT + HDR_RGBE   + #10;

     if Assigned( CS ) then Head := Head + WritePrimaries( CS ) + #10;

     Head := Head + #10
           + '-Y ' + Header_.Height.ToString + ' +X ' + Header_.Width.ToString + #10;

     B := TEncoding.ASCII.GetBytes( Head );

     Stream_.WriteBuffer( B[ 0 ], Length( B ) );

     ///// 画素

     SetLength( Row , Header_.Width );
     SetLength( Scan, Header_.Width );

     for Y := 0 to Header_.Height-1 do
     begin
          Raster_.GetLine( 0, Y, 1, 0, Header_.Width, @Row[ 0 ] );

          for X := 0 to Header_.Width-1 do
          begin
               C := Row[ X ].C;

               if Assigned( CS ) then C := CS.ToLinear( C );

               E := C;

               Scan[ X ].Cs[ 0 ] := E.R;
               Scan[ X ].Cs[ 1 ] := E.G;
               Scan[ X ].Cs[ 2 ] := E.B;
               Scan[ X ].Cs[ 3 ] := E.E;
          end;

          WriteScan( Stream_, @Scan[ 0 ], Header_.Width );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////////// C L A S S

class function TImageCodecHdr.Extensions :TArray<String>;
begin
     Result := [ '.hdr', '.pic' ];
end;

class function TImageCodecHdr.Caption :String;
begin
     Result := 'Radiance HDR';
end;

class function TImageCodecHdr.Matches( const Bytes_:TBytes ) :Boolean;
begin
     Result := ( Length( Bytes_ ) >= 2 ) and ( Bytes_[ 0 ] = Ord( '#' ) ) and ( Bytes_[ 1 ] = Ord( '?' ) );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TImageCodecHdr.DoDecode( const Stream_:TStream; const Raster_:TImageRaster );
var
   I :THdrInput;
   H :THdrHead;
   M :TSingleM3;
   Scan :TArray<THdrPixel>;
   Row :TArray<TSingleRGBA>;
   C :TSingleRGB;
   V :TSingle3D;
   N :Integer;
   J, K :Integer;
begin
     I := THdrInput.Create( Stream_ );

     H := ReadHead( I );

     Raster_.Header := TImageHeader.Create( H.Width, H.Height, H.ColorSpace, 32 );

     if H.IsXYZ then M := TSingleM3( H.ColorSpace.FromXYZ );

     N := H.Minor.Count;

     SetLength( Scan, N );
     SetLength( Row , N );

     for J := 0 to H.Major.Count-1 do
     begin
          ReadScan( I, @Scan[ 0 ], N );

          for K := 0 to N-1 do
          begin
               C := TByteRGBE.Create( Scan[ K ].Cs[ 0 ], Scan[ K ].Cs[ 1 ], Scan[ K ].Cs[ 2 ], Scan[ K ].Cs[ 3 ] );

               if H.IsXYZ then
               begin
                    V := M * TSingle3D.Create( C.R, C.G, C.B );

                    C := TSingleRGB.Create( V.X, V.Y, V.Z );
               end;

               Row[ K ] := TSingleRGBA.Create( C.R, C.G, C.B, 1 );
          end;

          ///// 走査線は、Minor の向きに進む並びである

          if H.Major.IsY then Raster_.SetLine( H.Minor.Start( 0 ), H.Major.Start( J ), H.Minor.Step, 0, N, @Row[ 0 ] )
                         else Raster_.SetLine( H.Major.Start( J ), H.Minor.Start( 0 ), 0, H.Minor.Step, N, @Row[ 0 ] );
     end;

     I.Close;
end;

initialization //############################################################### ■

     TImageCodec.Regist( TImageCodecHdr );

end. //######################################################################### ■
