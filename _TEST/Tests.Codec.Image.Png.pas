unit Tests.Codec.Image.Png;

// LUX.Data.Codec.Image.Png の試験
//
//【復号の確かめ方】
// ・試験の側で、規格のとおりに PNG を組み立てる（TPngMaker）。標本の値は、位置と成分から決まる式で作る。
// ・同じ式から、復号の結果であるべき画素を、コーデックとは別に求め、復号の結果と比べる。
// ・組み立てる PNG は、走査線ごとにフィルターの種類を変えるので、5 種類のフィルターのすべてを通る。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecPngTests

     [TestFixture]
     TImageCodecPngTests = class
     public
       [Test] procedure DecodesEveryFormat;
       [Test] procedure DecodesTinyInterlaced;
       [Test] procedure DecodesSplitIdat;
       [Test] procedure RoundTrip8;
       [Test] procedure RoundTrip16;
       [Test] procedure AlphaOff;
       [Test] procedure LevelsKeepPixels;
       [Test] procedure ColorSpaceNone;
       [Test] procedure ColorSpaceSRGB;
       [Test] procedure ColorSpaceIcc;
       [Test] procedure ColorSpaceGamaChrm;
       [Test] procedure RejectsBrokenData;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Classes, System.Math, System.ZLib,
     LUX.Color, LUX.Color.Space,
     LUX.Data.Codec.Image,
     LUX.Data.Codec.Image.Png,
     Tests.Codec.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngMaker

     // 規格のとおりに PNG を組み立てる。
     // 標本の値は Sample で決まり、復号の結果であるべき画素は Pixel で求まる。
     TPngMaker = record
       Width  :Integer;
       Height :Integer;
       Depth  :Integer;                                     // 1・2・4・8・16
       Color  :Integer;                                     // 0・2・3・4・6
       Interl :Boolean;                                     // Adam7
       Trns   :Boolean;                                     // tRNS を付けるか
       IdatN  :Integer;                                     // IDAT 1 つの中身の最大のバイト数（0：1 つにまとめる）
       Extras :TBytes;                                      // IHDR の直後に置く、組み立て済みのチャンク
       ///// M E T H O D
       function Chans :Integer;                             // 画素あたりの標本の数
       function PalN :Integer;                              // パレットの色の数
       function Sample( const X_,Y_,C_:Integer ) :Integer;  // 位置 ( X_, Y_ ) の、C_ 番目の標本
       function Palette( const I_:Integer ) :TSingleRGBA;   // パレットの I_ 番目の色（tRNS を含む）
       function Pixel( const X_,Y_:Integer ) :TSingleRGBA;  // 復号の結果であるべき画素
       function Make :TBytes;
     end;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      SIGN :array [ 0..8-1 ] of Byte = ( $89, $50, $4E, $47, $0D, $0A, $1A, $0A );

      // Adam7 の 7 つのパス（始点と歩み）
      PASS_X0 :array [ 0..7-1 ] of Integer = ( 0, 4, 0, 2, 0, 1, 0 );
      PASS_Y0 :array [ 0..7-1 ] of Integer = ( 0, 0, 4, 0, 2, 0, 1 );
      PASS_DX :array [ 0..7-1 ] of Integer = ( 8, 8, 4, 4, 2, 2, 1 );
      PASS_DY :array [ 0..7-1 ] of Integer = ( 8, 8, 8, 4, 4, 2, 2 );

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function U32( const V_:UInt32 ) :TBytes;
begin
     Result := [ V_ shr 24, ( V_ shr 16 ) and $FF, ( V_ shr 8 ) and $FF, V_ and $FF ];
end;

// チャンク：長さ・種類（4 文字）・中身・CRC（種類と中身に対するもの）

function Chunk( const Kind_:String; const Data_:TBytes ) :TBytes;
var
   B :TBytes;
begin
     B := TEncoding.ASCII.GetBytes( Kind_ ) + Data_;

     Result := U32( Length( Data_ ) ) + B + U32( crc32( 0, @B[ 0 ], Length( B ) ) );
end;

function Deflate( const Data_:TBytes ) :TBytes;
var
   P :Pointer;
   N :Integer;
begin
     ZCompress( @Data_[ 0 ], Length( Data_ ), P, N );
     try
        SetLength( Result, N );

        Move( P^, Result[ 0 ], N );
     finally
        FreeMem( P );
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

// 走査線にフィルターを掛ける。Prv_ は、1 つ上の走査線（掛ける前）である。

function Filter( const Kind_:Integer; const Cur_,Prv_:TBytes; const Bpp_:Integer ) :TBytes;
var
   I, A, B, C, P, PA, PB, PC :Integer;
begin
     SetLength( Result, 1 + Length( Cur_ ) );

     Result[ 0 ] := Kind_;

     for I := 0 to High( Cur_ ) do
     begin
          if I >= Bpp_ then begin  A := Cur_[ I - Bpp_ ];  C := Prv_[ I - Bpp_ ];  end
                       else begin  A := 0               ;  C := 0               ;  end;

          B := Prv_[ I ];

          case Kind_ of
            0: P := 0;
            1: P := A;
            2: P := B;
            3: P := ( A + B ) div 2;
          else
               P := A + B - C;

               PA := Abs( P - A );  PB := Abs( P - B );  PC := Abs( P - C );

               if ( PA <= PB ) and ( PA <= PC ) then P := A
                                                else
               if PB <= PC                      then P := B
                                                else P := C;
          end;

          Result[ 1 + I ] := ( Cur_[ I ] - P ) and $FF;
     end;
end;

//------------------------------------------------------------------------------

// 流れを復号した結果（呼んだ側が解放する）

function Decoded( const Png_:TBytes ) :TTestRaster;
var
   C :TImageCodecPng;
   S :TStream;
begin
     Result := TTestRaster.Create;
     try
        C := TImageCodecPng.Create;
        S := StreamOf( Png_ );
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

function Encoded( const Raster_:TTestRaster; const Alpha_:Boolean = True; const Level_:TImagePngLevel = plDefault ) :TBytes;
var
   C :TImageCodecPng;
   S :TBytesStream;
begin
     C := TImageCodecPng.Create;
     S := TBytesStream.Create;
     try
        C.Alpha := Alpha_;
        C.Level := Level_;

        C.Encode( S, Raster_ );

        Result := Copy( S.Bytes, 0, S.Size );
     finally
        S.Free;
        C.Free;
     end;
end;

// 試験用の画像。標本の値は、Depth_ ビットで表せる値そのものなので、符号化と復号で変わらない。

function Sampled( const Width_,Height_,Depth_:Integer; const ColorSpace_:TLuxColorSpace ) :TTestRaster;
var
   X, Y, M :Integer;
begin
     M := ( 1 shl Depth_ ) - 1;

     Result := TTestRaster.Create( Width_, Height_, ColorSpace_, Depth_ );

     for Y := 0 to Height_-1 do
     for X := 0 to Width_ -1 do Result[ X, Y ] := TSingleRGBA.Create( ( ( X * 7919 + Y * 104729     ) and M ) / M,
                                                                       ( ( X * 31   + Y * 17    + 5 ) and M ) / M,
                                                                       ( ( X        + Y * 3         ) and M ) / M,
                                                                       ( ( X * 5    + Y * 11    + 1 ) and M ) / M );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TPngMaker

//////////////////////////////////////////////////////////////////// M E T H O D

function TPngMaker.Chans :Integer;
begin
     case Color of
       2: Result := 3;
       4: Result := 2;
       6: Result := 4;
     else Result := 1;
     end;
end;

function TPngMaker.PalN :Integer;
begin
     Result := Min( 1 shl Depth, 200 );  // 8 ビットでは、256 より少ないパレットにする
end;

function TPngMaker.Sample( const X_,Y_,C_:Integer ) :Integer;
begin
     Result := X_ * 7 + Y_ * 13 + C_ * 29 + X_ * Y_;

     if Color = 3 then Result := Result mod PalN
                  else Result := Result and ( ( 1 shl Depth ) - 1 );
end;

function TPngMaker.Palette( const I_:Integer ) :TSingleRGBA;
begin
     Result := TSingleRGBA.Create( ( I_ * 37 and $FF ) / 255, ( I_ * 59 and $FF ) / 255, ( I_ * 83 and $FF ) / 255, 1 );

     if Trns and ( I_ < PalN div 2 ) then Result.A := ( I_ * 101 and $FF ) / 255;  // tRNS は、パレットの前半にだけ α を与える
end;

function TPngMaker.Pixel( const X_,Y_:Integer ) :TSingleRGBA;
var
   M :Single;
   V :array [ 0..4-1 ] of Integer;
   C :Integer;
begin
     if Color = 3 then Exit( Palette( Sample( X_, Y_, 0 ) ) );

     M := ( 1 shl Depth ) - 1;

     for C := 0 to Chans-1 do V[ C ] := Sample( X_, Y_, C );

     case Color of
       0: begin
               Result := TSingleRGBA.Create( V[ 0 ] / M, V[ 0 ] / M, V[ 0 ] / M, 1 );

               if Trns and ( V[ 0 ] = Sample( 1, 1, 0 ) ) then Result.A := 0;  // 透明色は、位置 ( 1, 1 ) の色
          end;
       2: begin
               Result := TSingleRGBA.Create( V[ 0 ] / M, V[ 1 ] / M, V[ 2 ] / M, 1 );

               if Trns and ( V[ 0 ] = Sample( 1, 1, 0 ) )
                       and ( V[ 1 ] = Sample( 1, 1, 1 ) )
                       and ( V[ 2 ] = Sample( 1, 1, 2 ) ) then Result.A := 0;
          end;
       4: Result := TSingleRGBA.Create( V[ 0 ] / M, V[ 0 ] / M, V[ 0 ] / M, V[ 1 ] / M );
     else Result := TSingleRGBA.Create( V[ 0 ] / M, V[ 1 ] / M, V[ 2 ] / M, V[ 3 ] / M );
     end;
end;

//------------------------------------------------------------------------------

function TPngMaker.Make :TBytes;
var
   Raw, Z, B :TBytes;
   P, PN :Integer;
   X0, Y0 :Integer;
   DX, DY :Integer;
   PW, PH :Integer;
   X, Y, C, I :Integer;
   S, K :Integer;
   Bits, Bpp :Integer;
   Cur, Prv :TBytes;
begin
     Bits := Chans * Depth;
     Bpp  := Max( 1, Bits div 8 );

     ///// 走査線（フィルターつき）を、パスの順に並べる

     Raw := nil;

     if Interl then PN := 7
               else PN := 1;

     K := 0;  // フィルターの種類。走査線ごとに 0〜4 を巡る

     for P := 0 to PN-1 do
     begin
          if Interl then begin  X0 := PASS_X0[ P ];  Y0 := PASS_Y0[ P ];  DX := PASS_DX[ P ];  DY := PASS_DY[ P ];  end
                    else begin  X0 := 0           ;  Y0 := 0           ;  DX := 1           ;  DY := 1           ;  end;

          PW := ( Width  - X0 + DX - 1 ) div DX;
          PH := ( Height - Y0 + DY - 1 ) div DY;

          if ( PW <= 0 ) or ( PH <= 0 ) then Continue;

          Prv := nil;  SetLength( Prv, ( PW * Bits + 7 ) div 8 );

          for Y := 0 to PH-1 do
          begin
               Cur := nil;  SetLength( Cur, ( PW * Bits + 7 ) div 8 );

               for X := 0 to PW-1 do
               for C := 0 to Chans-1 do
               begin
                    S := Sample( X0 + X * DX, Y0 + Y * DY, C );

                    I := ( X * Chans + C ) * Depth;  // 走査線の中の、ビットの位置

                    case Depth of
                      16: begin
                               Cur[ I div 8     ] := S shr 8;
                               Cur[ I div 8 + 1 ] := S and $FF;
                          end;
                       8: Cur[ I div 8 ] := S;
                    else  Cur[ I div 8 ] := Cur[ I div 8 ] or ( S shl ( 8 - Depth - I mod 8 ) );  // 上位のビットから詰める
                    end;
               end;

               Raw := Raw + Filter( K, Cur, Prv, Bpp );

               K := ( K + 1 ) mod 5;

               Prv := Cur;
          end;
     end;

     ///// チャンクを並べる

     Result := nil;

     SetLength( Result, 8 );

     Move( SIGN, Result[ 0 ], 8 );

     Result := Result + Chunk( 'IHDR', U32( Width ) + U32( Height ) + [ Depth, Color, 0, 0, Ord( Interl ) ] ) + Extras;

     if Color = 3 then
     begin
          B := nil;
          for I := 0 to PalN-1 do B := B + [ I * 37 and $FF, I * 59 and $FF, I * 83 and $FF ];

          Result := Result + Chunk( 'PLTE', B );

          if Trns then
          begin
               B := nil;
               for I := 0 to PalN div 2 - 1 do B := B + [ I * 101 and $FF ];

               Result := Result + Chunk( 'tRNS', B );
          end;
     end
     else
     if Trns then
     begin
          B := nil;
          for C := 0 to Chans-1 do B := B + [ Sample( 1, 1, C ) shr 8, Sample( 1, 1, C ) and $FF ];

          Result := Result + Chunk( 'tRNS', B );
     end;

     Z := Deflate( Raw );

     if IdatN = 0 then Result := Result + Chunk( 'IDAT', Z )
     else
     begin
          I := 0;
          while I < Length( Z ) do
          begin
               Result := Result + Chunk( 'IDAT', Copy( Z, I, IdatN ) );

               Inc( I, IdatN );
          end;
     end;

     Result := Result + Chunk( 'IEND', nil );
end;

// 復号が、例外で断ること

procedure Rejects( const Png_:TBytes; const Name_:String );
begin
     Assert.WillRaise( procedure begin Decoded( Png_ ).Free; end, nil, Name_ );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodecPngTests

// 組み立てた PNG を復号し、あるべき画素と比べる。
// 標本を最大値で割る計算の、丸めの違いだけを許す。

procedure CheckDecoded( const Maker_:TPngMaker; const Name_:String );
const
     TOL = 1e-6;
var
   R :TTestRaster;
   X, Y :Integer;
   P, Q :TSingleRGBA;
begin
     R := Decoded( Maker_.Make );
     try
        Assert.AreEqual( Maker_.Width , R.Header.Width , Name_ );
        Assert.AreEqual( Maker_.Height, R.Header.Height, Name_ );
        Assert.AreEqual( Maker_.Depth , R.Header.Depth , Name_ );

        Assert.IsTrue( R.WrittenOnce, Name_ + '：どの画素も、ちょうど 1 回' );

        for Y := 0 to Maker_.Height-1 do
        for X := 0 to Maker_.Width -1 do
        begin
             P := R[ X, Y ];
             Q := Maker_.Pixel( X, Y );

             if ( Abs( P.R - Q.R ) > TOL ) or ( Abs( P.G - Q.G ) > TOL )
             or ( Abs( P.B - Q.B ) > TOL ) or ( Abs( P.A - Q.A ) > TOL ) then Assert.Fail( Format( '%s：画素 (%d, %d)', [ Name_, X, Y ] ) );
        end;
     finally
        R.Free;
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 規格の許す、カラータイプとビット深度の組のすべてを、インターレースと tRNS の有無の両方で復号できる
procedure TImageCodecPngTests.DecodesEveryFormat;
const
     COLORS :array [ 0..5-1 ] of Integer = ( 0, 2, 3, 4, 6 );
     DEPTHS :array [ 0..5-1 ] of Integer = ( 1, 2, 4, 8, 16 );
var
   M :TPngMaker;
   C, D, I, T :Integer;
   Legal :Boolean;
   N :Integer;
begin
     N := 0;

     for C in COLORS do
     for D in DEPTHS do
     begin
          case C of
            0: Legal := True;
            3: Legal := D <= 8;
          else Legal := D >= 8;
          end;

          if not Legal then Continue;

          for I := 0 to 1 do
          for T := 0 to 1 do
          begin
               if ( T = 1 ) and ( C in [ 4, 6 ] ) then Continue;  // α を持つカラータイプに、tRNS は無い

               M := Default( TPngMaker );

               M.Width  := 13;
               M.Height := 11;
               M.Depth  := D;
               M.Color  := C;
               M.Interl := I = 1;
               M.Trns   := T = 1;

               CheckDecoded( M, Format( 'カラータイプ %d・%d ビット・インターレース %d・tRNS %d', [ C, D, I, T ] ) );

               Inc( N );
          end;
     end;

     Assert.AreEqual( 52, N, '確かめた形式の数' );
end;

// インターレースで、画素の無いパスが出るほど小さい画像も復号できる
procedure TImageCodecPngTests.DecodesTinyInterlaced;
const
     SIZES :array [ 0..4-1, 0..2-1 ] of Integer = ( ( 1, 1 ), ( 2, 1 ), ( 1, 5 ), ( 3, 2 ) );
var
   M :TPngMaker;
   I :Integer;
begin
     for I := 0 to High( SIZES ) do
     begin
          M := Default( TPngMaker );

          M.Width  := SIZES[ I, 0 ];
          M.Height := SIZES[ I, 1 ];
          M.Depth  := 8;
          M.Color  := 6;
          M.Interl := True;

          CheckDecoded( M, Format( '%d × %d', [ M.Width, M.Height ] ) );
     end;
end;

// 画素のデータが、いくつもの IDAT に分かれていても復号できる
procedure TImageCodecPngTests.DecodesSplitIdat;
var
   M :TPngMaker;
begin
     M := Default( TPngMaker );

     M.Width  := 40;
     M.Height := 30;
     M.Depth  := 16;
     M.Color  := 6;
     M.IdatN  := 7;

     CheckDecoded( M, 'IDAT が 7 バイトずつ' );
end;

// 8 ビットで表せる画素は、符号化して復号すると、元に戻る
procedure TImageCodecPngTests.RoundTrip8;
var
   A, B :TTestRaster;
begin
     A := Sampled( 37, 23, 8, nil );
     B := nil;
     try
        B := Decoded( Encoded( A ) );

        Assert.AreEqual( 8, B.Header.Depth );
        Assert.IsTrue( A.Distance( B ) < 1e-6 );
     finally
        B.Free;
        A.Free;
     end;
end;

// 置き場の精度が 8 ビットを超えると、16 ビットで書かれ、16 ビットで表せる画素は、元に戻る
procedure TImageCodecPngTests.RoundTrip16;
var
   A, B :TTestRaster;
begin
     A := Sampled( 37, 23, 16, nil );
     B := nil;
     try
        B := Decoded( Encoded( A ) );

        Assert.AreEqual( 16, B.Header.Depth );
        Assert.IsTrue( A.Distance( B ) < 1e-6 );
     finally
        B.Free;
        A.Free;
     end;
end;

// Alpha を False にすると、α の無い形で書かれ、復号した α は 1 になる。色は変わらない
procedure TImageCodecPngTests.AlphaOff;
var
   A, B :TTestRaster;
   X, Y :Integer;
   Z :TBytes;
begin
     A := Sampled( 9, 7, 8, nil );
     B := nil;
     try
        Z := Encoded( A, False );

        Assert.AreEqual( 2, Integer( Z[ 8 + 8 + 9 ] ), 'IHDR のカラータイプ' );

        B := Decoded( Z );

        for Y := 0 to 7-1 do
        for X := 0 to 9-1 do
        begin
             Assert.AreEqual( Single( 1 ), B[ X, Y ].A );

             Assert.IsTrue( ( Abs( A[ X, Y ].R - B[ X, Y ].R ) < 1e-6 )
                        and ( Abs( A[ X, Y ].G - B[ X, Y ].G ) < 1e-6 )
                        and ( Abs( A[ X, Y ].B - B[ X, Y ].B ) < 1e-6 ) );
        end;
     finally
        B.Free;
        A.Free;
     end;
end;

// 圧縮率は、大きさだけを変える。どの圧縮率でも、復号した画素は同じであり、無圧縮が最も大きい
procedure TImageCodecPngTests.LevelsKeepPixels;
var
   A, B :TTestRaster;
   L :TImagePngLevel;
   Z :TBytes;
   Ns :array [ TImagePngLevel ] of Integer;
begin
     A := Sampled( 64, 64, 8, nil );
     try
        for L := Low( TImagePngLevel ) to High( TImagePngLevel ) do
        begin
             Z := Encoded( A, True, L );

             Ns[ L ] := Length( Z );

             B := Decoded( Z );
             try
                Assert.IsTrue( A.Distance( B ) < 1e-6 );
             finally
                B.Free;
             end;
        end;

        Assert.IsTrue( Ns[ plNone ] > 64 * 64 * 4, '無圧縮は、画素のバイト数より大きい' );
        Assert.IsTrue( Ns[ plNone ] > Ns[ plFastest ] );
        Assert.IsTrue( Ns[ plNone ] > Ns[ plDefault ] );
        Assert.IsTrue( Ns[ plNone ] > Ns[ plMax     ] );
     finally
        A.Free;
     end;
end;

// 色空間が無ければ、色空間のチャンクは書かれず、復号した色空間も無い
procedure TImageCodecPngTests.ColorSpaceNone;
var
   A, B :TTestRaster;
   Z :TBytes;
begin
     A := Sampled( 5, 5, 8, nil );
     B := nil;
     try
        Z := Encoded( A );

        Assert.IsTrue( ( Find( Z, 'sRGB' ) < 0 ) and ( Find( Z, 'iCCP' ) < 0 ) and ( Find( Z, 'gAMA' ) < 0 ) and ( Find( Z, 'cHRM' ) < 0 ) );

        B := Decoded( Z );

        Assert.IsTrue( B.Header.ColorSpace = nil );
     finally
        B.Free;
        A.Free;
     end;
end;

// sRGB は、sRGB チャンク（と gAMA・cHRM）で書かれ、iCCP は書かれない。復号すると、同じ色空間になる
procedure TImageCodecPngTests.ColorSpaceSRGB;
var
   A, B :TTestRaster;
   Z :TBytes;
begin
     A := Sampled( 5, 5, 8, TLuxColorSpaces.sRGB );
     B := nil;
     try
        Z := Encoded( A );

        Assert.IsTrue( ( Find( Z, 'sRGB' ) > 0 ) and ( Find( Z, 'gAMA' ) > 0 ) and ( Find( Z, 'cHRM' ) > 0 ) );
        Assert.IsTrue( Find( Z, 'iCCP' ) < 0 );

        B := Decoded( Z );

        Assert.IsTrue( B.Header.ColorSpace = TLuxColorSpaces.sRGB );
     finally
        B.Free;
        A.Free;
     end;
end;

// そのほかの色空間は、iCCP で書かれ、復号すると、どのプリセットも、同じインスタンスに戻る
procedure TImageCodecPngTests.ColorSpaceIcc;
var
   CS :TLuxColorSpace;
   A, B :TTestRaster;
   Z :TBytes;
begin
     for CS in TLuxColorSpaces.Presets do
     begin
          A := Sampled( 5, 5, 8, CS );
          B := nil;
          try
             Z := Encoded( A );

             if CS <> TLuxColorSpaces.sRGB then Assert.IsTrue( Find( Z, 'iCCP' ) > 0, CS.Name );

             B := Decoded( Z );

             Assert.IsTrue( B.Header.ColorSpace = CS, CS.Name );
          finally
             B.Free;
             A.Free;
          end;
     end;
end;

// iCCP も sRGB も無いときは、gAMA と cHRM から色空間が組み立てられる
procedure TImageCodecPngTests.ColorSpaceGamaChrm;
var
   M :TPngMaker;
   R :TTestRaster;
begin
     M := Default( TPngMaker );

     M.Width  := 2;
     M.Height := 2;
     M.Depth  := 8;
     M.Color  := 2;

     ///// gAMA = 1.0（線形）と、sRGB の原色の cHRM（白・赤・緑・青）

     M.Extras := Chunk( 'gAMA', U32( 100000 ) )
               + Chunk( 'cHRM', U32( 31270 ) + U32( 32900 ) + U32( 64000 ) + U32( 33000 )
                              + U32( 30000 ) + U32( 60000 ) + U32( 15000 ) + U32(  6000 ) );

     R := Decoded( M.Make );
     try
        Assert.IsTrue( R.Header.ColorSpace = TLuxColorSpaces.LinearSRGB );
     finally
        R.Free;
     end;

     ///// gAMA だけ（sRGB の曲線の近似）：原色は sRGB と見なされる

     M.Extras := Chunk( 'gAMA', U32( 45455 ) );

     R := Decoded( M.Make );
     try
        Assert.IsTrue( R.Header.ColorSpace = TLuxColorSpaces.sRGB );
     finally
        R.Free;
     end;
end;

// 形式に合わないデータは、例外になる
procedure TImageCodecPngTests.RejectsBrokenData;
var
   M :TPngMaker;
   Z :TBytes;
begin
     M := Default( TPngMaker );

     M.Width  := 8;
     M.Height := 8;
     M.Depth  := 8;
     M.Color  := 2;

     Z := M.Make;

     Rejects( nil                              , '空' );
     Rejects( Copy( Z, 1, Length( Z ) - 1 )    , '署名が違う' );
     Rejects( Copy( Z, 0, Length( Z ) div 2 )  , '途中で終わる' );
     Rejects( Copy( Z, 0, 8 + 25 ) + Chunk( 'IEND', nil ), 'IDAT が無い' );

     M.Depth := 4;  // RGB に 4 ビットは無い

     Rejects( M.Make, 'カラータイプとビット深度の組が不正' );

     M.Depth := 8;
     M.Color := 3;

     Z := M.Make;

     Rejects( Copy( Z, 0, 8 + 25 ) + Copy( Z, 8 + 25 + 12 + M.PalN * 3, MaxInt ), 'パレットが無い' );
end;

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TImageCodecPngTests );

end. //######################################################################### ■
