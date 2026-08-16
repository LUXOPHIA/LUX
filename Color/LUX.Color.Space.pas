unit LUX.Color.Space;

interface //#################################################################### ■

uses System.SysUtils, System.Classes, System.Generics.Collections,
     LUX, LUX.D2, LUX.D3, LUX.D3x3, LUX.Color;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxTransfer

     ///// 伝達関数（符号化値 V ⇄ 線形値 L）。ICC の parametricCurveType 型 4 と同じ 7 係数で表す。
     /////
     /////   L = ( a·V + b )^g + e   ( V ≧ d )
     /////   L =   c·V + f           ( V ＜ d )
     /////
     ///// 線形・純ガンマ・sRGB・Rec.709/2020・ROMM など、実用上の全ての曲線がこの形に収まる。
     ///// 負の入力は符号を保って絶対値に適用する（浮動小数形式の画像のため）。

     TLuxTransfer = record
     public
       G, A, B, C, D, E, F :Double;
       ///// M E T H O D
       function Decode( const V_:Double ) :Double;   // 符号化 → 線形
       function Encode( const L_:Double ) :Double;   // 線形 → 符号化
       function IsLinear :Boolean;
       function IsGamma :Boolean;                    // 純ガンマ（ L = V^g ）か
       function Same( const T_:TLuxTransfer; const Tol_:Double = 1E-3 ) :Boolean;
       ///// C L A S S
       class function Create( const G_,A_,B_,C_,D_,E_,F_:Double ) :TLuxTransfer; static;
       class function Linear :TLuxTransfer; static;
       class function Gamma( const G_:Double ) :TLuxTransfer; static;
       class function sRGB :TLuxTransfer; static;      // IEC 61966-2-1
       class function Rec709 :TLuxTransfer; static;    // ITU-R BT.709 / BT.2020 ( SDR )
       class function ROMM :TLuxTransfer; static;      // ROMM RGB / ProPhoto RGB
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxColorSpace

     ///// RGB 色空間の基底クラス。RGB 原色と白色点の色度座標（CIE xy）と伝達関数で定義される。
     /////
     ///// ・派生クラスでプリセットを定義してもよいし、Create に値を渡してその場で作ってもよい。
     ///// ・生成後は不変。TLuxImage などは所有せず参照するだけなので、寿命はプログラムと同じにする
     /////   （プリセットは TLuxColorSpaces が持つ。自作のものも TLuxColorSpaces.Intern に登録できる）。
     ///// ・ICC v4 プロファイル（行列＋TRC）の書き出しと読み込みができる。

     TLuxColorSpace = class
     private
       _Icc :TBytes;   // IccProfile のキャッシュ
     protected
       _Name     :String;
       _RedXY    :TDouble2D;
       _GreenXY  :TDouble2D;
       _BlueXY   :TDouble2D;
       _WhiteXY  :TDouble2D;
       _Transfer :TLuxTransfer;
       _ToXYZ    :TDoubleM3;   // 線形 RGB → XYZ（この空間の白色点）
       _FromXYZ  :TDoubleM3;
       _ToXYZD50 :TDoubleM3;   // 線形 RGB → XYZ（D50 へ Bradford 適応）
       ///// M E T H O D
       procedure Init;         // 色度座標から行列を求める（コンストラクタの最後に呼ぶ）
     public
       constructor Create( const Name_:String;
                           const RedXY_,GreenXY_,BlueXY_,WhiteXY_:TDouble2D;
                           const Transfer_:TLuxTransfer );
       ///// P R O P E R T Y
       property Name     :String       read _Name    ;
       property RedXY    :TDouble2D    read _RedXY   ;
       property GreenXY  :TDouble2D    read _GreenXY ;
       property BlueXY   :TDouble2D    read _BlueXY  ;
       property WhiteXY  :TDouble2D    read _WhiteXY ;
       property Transfer :TLuxTransfer read _Transfer;
       property ToXYZ    :TDoubleM3    read _ToXYZ   ;   // 線形 RGB → XYZ
       property FromXYZ  :TDoubleM3    read _FromXYZ ;   // XYZ → 線形 RGB
       property ToXYZD50 :TDoubleM3    read _ToXYZD50;   // 線形 RGB → XYZ( D50 )  ICC 用
       ///// M E T H O D
       function IsLinear :Boolean;
       function Same( const S_:TLuxColorSpace ) :Boolean;                // 原色・白色点・伝達関数が同じか（許容誤差付き）
       function ToLinear( const C_:TSingleRGB ) :TSingleRGB;             // 符号化 → 線形
       function ToEncoded( const C_:TSingleRGB ) :TSingleRGB;            // 線形 → 符号化
       function ToSpace( const To_:TLuxColorSpace ) :TDoubleM3;          // 線形 RGB → 別の空間の線形 RGB（白色点は Bradford で適応）
       function IccProfile :TBytes;                                       // ICC v4 表示クラス（行列＋TRC）
       ///// C L A S S
       class function FromIcc( const Icc_:TBytes ) :TLuxColorSpace;      // ICC を解析して新しい色空間を作る。行列＋TRC 型でなければ nil
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% プリセット

     TLuxColorSpaceSRGB           = class( TLuxColorSpace ) public constructor Create; end;   // sRGB ( IEC 61966-2-1 )
     TLuxColorSpaceLinearSRGB     = class( TLuxColorSpace ) public constructor Create; end;   // sRGB 原色・線形
     TLuxColorSpaceDisplayP3      = class( TLuxColorSpace ) public constructor Create; end;   // Display P3 ( DCI-P3 原色・D65・sRGB 曲線 )
     TLuxColorSpaceLinearDisplayP3= class( TLuxColorSpace ) public constructor Create; end;   // Display P3 原色・線形
     TLuxColorSpaceAdobeRGB       = class( TLuxColorSpace ) public constructor Create; end;   // Adobe RGB (1998)
     TLuxColorSpaceLinearAdobeRGB = class( TLuxColorSpace ) public constructor Create; end;   // Adobe RGB 原色・線形
     TLuxColorSpaceRec2020        = class( TLuxColorSpace ) public constructor Create; end;   // ITU-R BT.2020 ( SDR 曲線 )
     TLuxColorSpaceLinearRec2020  = class( TLuxColorSpace ) public constructor Create; end;   // BT.2020 原色・線形
     TLuxColorSpaceProPhotoRGB    = class( TLuxColorSpace ) public constructor Create; end;   // ProPhoto RGB / ROMM RGB ( D50 )
     TLuxColorSpaceACEScg         = class( TLuxColorSpace ) public constructor Create; end;   // ACEScg ( AP1 原色・ACES 白・線形 )

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxColorSpaces

     ///// 色空間の置き場。プリセットの共有インスタンスと、内容で重複排除された登録済みインスタンスを持つ。
     ///// ここにあるインスタンスはプログラムの終了まで生きるので、TLuxImage.ColorSpace などから安心して参照できる。

     TLuxColorSpaces = class
     private
       class var _sRGB            :TLuxColorSpace;
       class var _LinearSRGB      :TLuxColorSpace;
       class var _DisplayP3       :TLuxColorSpace;
       class var _LinearDisplayP3 :TLuxColorSpace;
       class var _AdobeRGB        :TLuxColorSpace;
       class var _LinearAdobeRGB  :TLuxColorSpace;
       class var _Rec2020         :TLuxColorSpace;
       class var _LinearRec2020   :TLuxColorSpace;
       class var _ProPhotoRGB     :TLuxColorSpace;
       class var _ACEScg          :TLuxColorSpace;
       class var _Presets         :TArray<TLuxColorSpace>;
       class var _Interns         :TObjectList<TLuxColorSpace>;
       class constructor Create;
       class destructor Destroy;
     public
       class property sRGB            :TLuxColorSpace read _sRGB           ;
       class property LinearSRGB      :TLuxColorSpace read _LinearSRGB     ;
       class property DisplayP3       :TLuxColorSpace read _DisplayP3      ;
       class property LinearDisplayP3 :TLuxColorSpace read _LinearDisplayP3;
       class property AdobeRGB        :TLuxColorSpace read _AdobeRGB       ;
       class property LinearAdobeRGB  :TLuxColorSpace read _LinearAdobeRGB ;
       class property Rec2020         :TLuxColorSpace read _Rec2020        ;
       class property LinearRec2020   :TLuxColorSpace read _LinearRec2020  ;
       class property ProPhotoRGB     :TLuxColorSpace read _ProPhotoRGB    ;
       class property ACEScg          :TLuxColorSpace read _ACEScg         ;
       class property Presets         :TArray<TLuxColorSpace> read _Presets;
       ///// M E T H O D
       class function Find( const S_:TLuxColorSpace ) :TLuxColorSpace;    // 内容が同じ登録済みインスタンスを返す（無ければ nil ）
       class function Intern( const S_:TLuxColorSpace ) :TLuxColorSpace;  // 内容が同じものが既にあればそれを返して S_ を破棄、無ければ S_ を登録して返す
       class function FromIcc( const Icc_:TBytes ) :TLuxColorSpace;       // ICC を解析し、登録済みか登録して返す。解析できなければ nil
       class function ByName( const Name_:String ) :TLuxColorSpace;       // プリセットを名前で引く（無ければ nil ）
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function LuxXYZ( const XY_:TDouble2D; const Y_:Double = 1 ) :TDouble3D;                 // 色度座標 xy と輝度 Y から XYZ
function LuxBradford( const FromWhite_,ToWhite_:TDouble2D ) :TDoubleM3;               // 白色点適応の行列（ XYZ → XYZ ）
function LuxRGBToXYZ( const R_,G_,B_,W_:TDouble2D ) :TDoubleM3;                        // 原色と白色点から 線形 RGB → XYZ の行列

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      LUX_WHITE_D65  :TDouble2D = ( _1D:( 0.3127 , 0.3290  ) );   // 色度座標 xy
      LUX_WHITE_D50  :TDouble2D = ( _1D:( 0.3457 , 0.3585  ) );
      LUX_WHITE_ACES :TDouble2D = ( _1D:( 0.32168, 0.33767 ) );

implementation //############################################################### ■

uses System.Math;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function LuxXYZ( const XY_:TDouble2D; const Y_:Double = 1 ) :TDouble3D;
begin
     Result := TDouble3D.Create( XY_.X * Y_ / XY_.Y, Y_, ( 1 - XY_.X - XY_.Y ) * Y_ / XY_.Y );
end;

function LuxBradford( const FromWhite_,ToWhite_:TDouble2D ) :TDoubleM3;
var
   MA   :TDoubleM3;
   S, D :TDouble3D;
begin
     MA := TDoubleM3.Create(  0.8951, 0.2664, -0.1614,
                             -0.7502, 1.7135,  0.0367,
                              0.0389,-0.0685,  1.0296 );   // Bradford の錐体応答行列

     S := MA * LuxXYZ( FromWhite_ );
     D := MA * LuxXYZ( ToWhite_   );

     Result := MA.Inverse * TDoubleM3.Create( D.X / S.X, 0, 0,
                                              0, D.Y / S.Y, 0,
                                              0, 0, D.Z / S.Z ) * MA;
end;

function LuxRGBToXYZ( const R_,G_,B_,W_:TDouble2D ) :TDoubleM3;
var
   P :TDoubleM3;
   S :TDouble3D;
begin
     ///// 各原色の XYZ（ Y = 1 に正規化 ）を列に並べ、白が W_ になるように列を伸縮する

     with P do
     begin
          _11 := R_.X / R_.Y;  _12 := G_.X / G_.Y;  _13 := B_.X / B_.Y;
          _21 := 1;            _22 := 1;            _23 := 1;
          _31 := ( 1 - R_.X - R_.Y ) / R_.Y;
          _32 := ( 1 - G_.X - G_.Y ) / G_.Y;
          _33 := ( 1 - B_.X - B_.Y ) / B_.Y;
     end;

     S := P.Inverse * LuxXYZ( W_ );

     with Result do
     begin
          _11 := P._11 * S.X;  _12 := P._12 * S.Y;  _13 := P._13 * S.Z;
          _21 := P._21 * S.X;  _22 := P._22 * S.Y;  _23 := P._23 * S.Z;
          _31 := P._31 * S.X;  _32 := P._32 * S.Y;  _33 := P._33 * S.Z;
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxTransfer

function TLuxTransfer.Decode( const V_:Double ) :Double;
var
   V :Double;
begin
     V := Abs( V_ );

     if V >= D then Result := Power( A * V + B, G ) + E
               else Result := C * V + F;

     if V_ < 0 then Result := -Result;
end;

function TLuxTransfer.Encode( const L_:Double ) :Double;
var
   L, T :Double;
begin
     L := Abs( L_ );

     T := C * D + F;   // 折れ点の線形値

     if L >= T then
     begin
          if A <> 0 then Result := ( Power( Max( L - E, 0 ), 1 / G ) - B ) / A
                    else Result := 0;
     end
     else
     begin
          if C <> 0 then Result := ( L - F ) / C
                    else Result := 0;
     end;

     if L_ < 0 then Result := -Result;
end;

function TLuxTransfer.IsLinear :Boolean;
begin
     Result := IsGamma and ( Abs( G - 1 ) < 1E-6 );
end;

function TLuxTransfer.IsGamma :Boolean;
begin
     Result := ( Abs( A - 1 ) < 1E-9 ) and ( Abs( B ) < 1E-9 ) and ( Abs( D ) < 1E-9 ) and ( Abs( E ) < 1E-9 ) and ( Abs( F ) < 1E-9 );
end;

function TLuxTransfer.Same( const T_:TLuxTransfer; const Tol_:Double = 1E-3 ) :Boolean;
var
   I :Integer;
   V :Double;
begin
     ///// 係数比較ではなく、曲線として比較する（同じ曲線でも係数の表し方が違い得るため）

     for I := 0 to 64 do
     begin
          V := I / 64;

          if Abs( Decode( V ) - T_.Decode( V ) ) > Tol_ then Exit( False );
     end;

     Result := True;
end;

class function TLuxTransfer.Create( const G_,A_,B_,C_,D_,E_,F_:Double ) :TLuxTransfer;
begin
     with Result do
     begin
          G := G_;  A := A_;  B := B_;  C := C_;  D := D_;  E := E_;  F := F_;
     end;
end;

class function TLuxTransfer.Linear :TLuxTransfer;
begin
     Result := Create( 1, 1, 0, 0, 0, 0, 0 );
end;

class function TLuxTransfer.Gamma( const G_:Double ) :TLuxTransfer;
begin
     Result := Create( G_, 1, 0, 0, 0, 0, 0 );
end;

class function TLuxTransfer.sRGB :TLuxTransfer;
begin
     Result := Create( 2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045, 0, 0 );
end;

class function TLuxTransfer.Rec709 :TLuxTransfer;
const
      AL = 1.09929682680944;   // α
      BE = 0.018053968510807;  // β
begin
     Result := Create( 1 / 0.45, 1 / AL, ( AL - 1 ) / AL, 1 / 4.5, 4.5 * BE, 0, 0 );
end;

class function TLuxTransfer.ROMM :TLuxTransfer;
begin
     Result := Create( 1.8, 1, 0, 1 / 16, 16 * 0.001953125, 0, 0 );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxColorSpace

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxColorSpace.Init;
begin
     _ToXYZ    := LuxRGBToXYZ( _RedXY, _GreenXY, _BlueXY, _WhiteXY );
     _FromXYZ  := _ToXYZ.Inverse;
     _ToXYZD50 := LuxBradford( _WhiteXY, LUX_WHITE_D50 ) * _ToXYZ;
     _Icc      := nil;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TLuxColorSpace.Create( const Name_:String;
                                   const RedXY_,GreenXY_,BlueXY_,WhiteXY_:TDouble2D;
                                   const Transfer_:TLuxTransfer );
begin
     inherited Create;

     _Name     := Name_;
     _RedXY    := RedXY_;
     _GreenXY  := GreenXY_;
     _BlueXY   := BlueXY_;
     _WhiteXY  := WhiteXY_;
     _Transfer := Transfer_;

     Init;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

function TLuxColorSpace.IsLinear :Boolean;
begin
     Result := _Transfer.IsLinear;
end;

function TLuxColorSpace.Same( const S_:TLuxColorSpace ) :Boolean;
const
      TOL = 2E-3;  // 色度座標の許容誤差（ ICC の s15Fixed16 と PNG の cHRM の丸めを吸収する ）
begin
     if not Assigned( S_ ) then Exit( False );

     Result := ( Abs( _RedXY  .X - S_._RedXY  .X ) < TOL ) and ( Abs( _RedXY  .Y - S_._RedXY  .Y ) < TOL )
           and ( Abs( _GreenXY.X - S_._GreenXY.X ) < TOL ) and ( Abs( _GreenXY.Y - S_._GreenXY.Y ) < TOL )
           and ( Abs( _BlueXY .X - S_._BlueXY .X ) < TOL ) and ( Abs( _BlueXY .Y - S_._BlueXY .Y ) < TOL )
           and ( Abs( _WhiteXY.X - S_._WhiteXY.X ) < TOL ) and ( Abs( _WhiteXY.Y - S_._WhiteXY.Y ) < TOL )
           and _Transfer.Same( S_._Transfer );
end;

function TLuxColorSpace.ToLinear( const C_:TSingleRGB ) :TSingleRGB;
begin
     Result.R := _Transfer.Decode( C_.R );
     Result.G := _Transfer.Decode( C_.G );
     Result.B := _Transfer.Decode( C_.B );
end;

function TLuxColorSpace.ToEncoded( const C_:TSingleRGB ) :TSingleRGB;
begin
     Result.R := _Transfer.Encode( C_.R );
     Result.G := _Transfer.Encode( C_.G );
     Result.B := _Transfer.Encode( C_.B );
end;

function TLuxColorSpace.ToSpace( const To_:TLuxColorSpace ) :TDoubleM3;
begin
     Result := To_.FromXYZ * LuxBradford( _WhiteXY, To_._WhiteXY ) * _ToXYZ;
end;

//------------------------------------------------------------------------------

///// ICC v4 の表示クラスプロファイル（行列＋TRC）を生成する。
/////   ヘッダ 128B ＋ タグ表 ＋ desc / cprt（mluc）, wtpt（D50）, chad（Bradford）,
/////   rXYZ / gXYZ / bXYZ（D50 適応済み）, rTRC / gTRC / bTRC（para）

function TLuxColorSpace.IccProfile :TBytes;
const
      SIGS :array [ 0..9 ] of AnsiString = ( 'desc', 'cprt', 'wtpt', 'chad', 'rXYZ', 'gXYZ', 'bXYZ', 'rTRC', 'gTRC', 'bTRC' );
var
   S      :TMemoryStream;
   TagOfs :array [ 0..9 ] of Integer;
   TagLen :array [ 0..9 ] of Integer;
   I      :Integer;
   M      :TDoubleM3;
   //--------------------------------------------
   procedure W32( const V_:UInt32 );
   var
        U :UInt32;
   begin
        U := ( V_ shr 24 ) or ( ( V_ shr 8 ) and $FF00 ) or ( ( V_ and $FF00 ) shl 8 ) or ( V_ shl 24 );
        S.WriteBuffer( U, 4 );
   end;
   procedure W16( const V_:UInt16 );
   var
        U :UInt16;
   begin
        U := ( V_ shr 8 ) or ( ( V_ and $FF ) shl 8 );  S.WriteBuffer( U, 2 );
   end;
   procedure WSig( const A_:AnsiString );
   begin
        S.WriteBuffer( A_[ 1 ], 4 );
   end;
   procedure WZero( const N_:Integer );
   var
        Z :array [ 0..127 ] of Byte;
   begin
        FillChar( Z, SizeOf( Z ), 0 );  S.WriteBuffer( Z, N_ );
   end;
   procedure WFix( const V_:Double );   // s15Fixed16
   begin
        W32( UInt32( Round( V_ * 65536 ) ) );
   end;
   procedure Pad4;
   begin
        while S.Size mod 4 <> 0 do WZero( 1 );
   end;
   procedure BeginTag( const I_:Integer );
   begin
        Pad4;  TagOfs[ I_ ] := S.Size;
   end;
   procedure EndTag( const I_:Integer );
   begin
        TagLen[ I_ ] := S.Size - TagOfs[ I_ ];
   end;
   procedure WriteXYZ( const I_:Integer; const V_:TDouble3D );
   begin
        BeginTag( I_ );  WSig( 'XYZ ' );  W32( 0 );  WFix( V_.X );  WFix( V_.Y );  WFix( V_.Z );  EndTag( I_ );
   end;
   procedure WriteSF32( const I_:Integer; const M_:TDoubleM3 );
   begin
        BeginTag( I_ );  WSig( 'sf32' );  W32( 0 );
        WFix( M_._11 );  WFix( M_._12 );  WFix( M_._13 );
        WFix( M_._21 );  WFix( M_._22 );  WFix( M_._23 );
        WFix( M_._31 );  WFix( M_._32 );  WFix( M_._33 );
        EndTag( I_ );
   end;
   procedure WritePara( const I_:Integer );
   begin
        BeginTag( I_ );  WSig( 'para' );  W32( 0 );

        with _Transfer do
        begin
             if IsGamma then
             begin
                  W16( 0 );  W16( 0 );  WFix( G );                                            // 型 0：V^g
             end
             else
             if ( Abs( E ) < 1E-9 ) and ( Abs( F ) < 1E-9 ) then
             begin
                  W16( 3 );  W16( 0 );  WFix( G );  WFix( A );  WFix( B );  WFix( C );  WFix( D );   // 型 3
             end
             else
             begin
                  W16( 4 );  W16( 0 );  WFix( G );  WFix( A );  WFix( B );  WFix( C );  WFix( D );  WFix( E );  WFix( F );   // 型 4
             end;
        end;

        EndTag( I_ );
   end;
   procedure WriteMluc( const I_:Integer; const Text_:String );
   var
        J :Integer;
   begin
        BeginTag( I_ );
        WSig( 'mluc' );  W32( 0 );
        W32( 1 );        // レコード数
        W32( 12 );       // レコード長
        WSig( 'enUS' );
        W32( Length( Text_ ) * 2 );   // 文字列のバイト数（UTF-16BE）
        W32( 28 );                    // 文字列のオフセット（このタグの先頭から）
        for J := 1 to Length( Text_ ) do W16( Ord( Text_[ J ] ) );
        EndTag( I_ );
   end;
   //--------------------------------------------
begin
     if Length( _Icc ) > 0 then Exit( _Icc );

     S := TMemoryStream.Create;
     try
        ///// ヘッダ 128B（サイズは最後に埋める）

        W32( 0 );                 // profile size
        W32( 0 );                 // preferred CMM
        W32( $04200000 );         // version 4.2
        WSig( 'mntr' );           // device class: display
        WSig( 'RGB ' );           // colour space
        WSig( 'XYZ ' );           // PCS
        WZero( 12 );              // date/time
        WSig( 'acsp' );           // signature
        W32( 0 );                 // platform
        W32( 0 );                 // flags
        W32( 0 );  W32( 0 );      // manufacturer / model
        WZero( 8 );               // attributes
        W32( 0 );                 // rendering intent: perceptual
        WFix( 0.9642 );  WFix( 1.0 );  WFix( 0.8249 );   // PCS illuminant D50
        W32( 0 );                 // creator
        WZero( 16 );              // profile ID
        WZero( 28 );              // reserved

        ///// タグ表（オフセット・長さは後で埋める）

        W32( Length( SIGS ) );
        WZero( Length( SIGS ) * 12 );

        ///// タグ本体

        M := _ToXYZD50;

        WriteMluc( 0, _Name );
        WriteMluc( 1, 'Public domain' );
        WriteXYZ ( 2, TDouble3D.Create( 0.9642, 1.0, 0.8249 ) );                  // wtpt = D50（ v4 の表示クラスでは D50 固定 ）
        WriteSF32( 3, LuxBradford( _WhiteXY, LUX_WHITE_D50 ) );                   // chad = 実際の白から D50 への適応行列
        WriteXYZ ( 4, TDouble3D.Create( M._11, M._21, M._31 ) );                  // rXYZ
        WriteXYZ ( 5, TDouble3D.Create( M._12, M._22, M._32 ) );                  // gXYZ
        WriteXYZ ( 6, TDouble3D.Create( M._13, M._23, M._33 ) );                  // bXYZ
        WritePara( 7 );
        WritePara( 8 );
        WritePara( 9 );
        Pad4;

        ///// タグ表とサイズを埋める

        for I := 0 to High( SIGS ) do
        begin
             S.Position := 128 + 4 + I * 12;
             WSig( SIGS[ I ] );  W32( TagOfs[ I ] );  W32( TagLen[ I ] );
        end;

        S.Position := 0;  W32( S.Size );

        SetLength( _Icc, S.Size );
        Move( S.Memory^, _Icc[ 0 ], S.Size );

        Result := _Icc;
     finally
        S.Free;
     end;
end;

//////////////////////////////////////////////////////////////////////// C L A S S

///// ICC プロファイル（行列＋TRC 型）を解析する。
///// ・rXYZ / gXYZ / bXYZ は D50 に適応された値なので、chad があればその逆で、無ければ wtpt から
/////   Bradford の逆で、元の白色点へ戻してから色度座標を求める。
///// ・TRC は para（型 0〜4）と curv（要素 0＝線形、1＝ガンマ、n＝表）を受け付ける。
/////   表は既知の曲線（線形・sRGB・Rec.709・ROMM・純ガンマ）に当てはめ、最も近いものを採用する。
///// ・A2B0 だけの LUT 型プロファイルは扱えない（ nil ）。

class function TLuxColorSpace.FromIcc( const Icc_:TBytes ) :TLuxColorSpace;
var
   N, I, Ofs, Len :Integer;
   Sig            :AnsiString;
   OfsRXYZ, OfsGXYZ, OfsBXYZ, OfsWtpt, OfsChad, OfsTRC, OfsDesc :Integer;
   LenTRC, LenDesc :Integer;
   M, Ad          :TDoubleM3;
   W, RW, GW, BW  :TDouble3D;
   RXY, GXY, BXY, WXY :TDouble2D;
   TF             :TLuxTransfer;
   Name           :String;
   //--------------------------------------------
   function R32( const P_:Integer ) :UInt32;
   begin
        Result := ( UInt32( Icc_[ P_ ] ) shl 24 ) or ( UInt32( Icc_[ P_+1 ] ) shl 16 ) or ( UInt32( Icc_[ P_+2 ] ) shl 8 ) or Icc_[ P_+3 ];
   end;
   function R16( const P_:Integer ) :UInt16;
   begin
        Result := ( UInt16( Icc_[ P_ ] ) shl 8 ) or Icc_[ P_+1 ];
   end;
   function RFix( const P_:Integer ) :Double;   // s15Fixed16
   begin
        Result := Int32( R32( P_ ) ) / 65536;
   end;
   function RSig( const P_:Integer ) :AnsiString;
   begin
        SetLength( Result, 4 );  Move( Icc_[ P_ ], Result[ 1 ], 4 );
   end;
   function RXYZ( const P_:Integer ) :TDouble3D;
   begin
        Result := TDouble3D.Create( RFix( P_+8 ), RFix( P_+12 ), RFix( P_+16 ) );
   end;
   function XYOf( const V_:TDouble3D ) :TDouble2D;
   var
        S :Double;
   begin
        S := V_.X + V_.Y + V_.Z;
        Result := TDouble2D.Create( V_.X / S, V_.Y / S );
   end;
   //----- TRC の解析（成功なら True ）
   function ReadTRC( const P_,L_:Integer; out T_:TLuxTransfer ) :Boolean;
   var
        K, C, J    :Integer;
        Tab        :TArray<Double>;
        Best, Err  :Double;
        Cand       :TArray<TLuxTransfer>;
        SumXY, SumXX, LX, LY :Double;
        //---
        function TabErr( const T:TLuxTransfer ) :Double;
        var
             Q :Integer;
        begin
             Result := 0;
             for Q := 0 to High( Tab ) do Result := Max( Result, Abs( T.Decode( Q / High( Tab ) ) - Tab[ Q ] ) );
        end;
   begin
        Result := False;

        if RSig( P_ ) = 'para' then
        begin
             K := R16( P_+8 );

             case K of
               0: T_ := TLuxTransfer.Gamma( RFix( P_+12 ) );
               1: T_ := TLuxTransfer.Create( RFix( P_+12 ), RFix( P_+16 ), RFix( P_+20 ), 0, -RFix( P_+20 ) / RFix( P_+16 ), 0, 0 );
               2: T_ := TLuxTransfer.Create( RFix( P_+12 ), RFix( P_+16 ), RFix( P_+20 ), 0, -RFix( P_+20 ) / RFix( P_+16 ), RFix( P_+24 ), RFix( P_+24 ) );
               3: T_ := TLuxTransfer.Create( RFix( P_+12 ), RFix( P_+16 ), RFix( P_+20 ), RFix( P_+24 ), RFix( P_+28 ), 0, 0 );
               4: T_ := TLuxTransfer.Create( RFix( P_+12 ), RFix( P_+16 ), RFix( P_+20 ), RFix( P_+24 ), RFix( P_+28 ), RFix( P_+32 ), RFix( P_+36 ) );
             else Exit;
             end;

             Exit( True );
        end;

        if RSig( P_ ) = 'curv' then
        begin
             C := R32( P_+8 );

             if C = 0 then begin T_ := TLuxTransfer.Linear;  Exit( True );  end;
             if C = 1 then begin T_ := TLuxTransfer.Gamma( R16( P_+12 ) / 256 );  Exit( True );  end;

             if P_ + 12 + C * 2 > Length( Icc_ ) then Exit;

             SetLength( Tab, C );
             for J := 0 to C-1 do Tab[ J ] := R16( P_+12+J*2 ) / 65535;

             ///// 既知の曲線に当てはめる（最小二乗でガンマも推定して候補に加える）

             SumXY := 0;  SumXX := 0;
             for J := 1 to C-1 do
             begin
                  if Tab[ J ] <= 0 then Continue;
                  LX := Ln( J / ( C-1 ) );  LY := Ln( Tab[ J ] );
                  SumXY := SumXY + LX * LY;  SumXX := SumXX + LX * LX;
             end;

             Cand := [ TLuxTransfer.Linear, TLuxTransfer.sRGB, TLuxTransfer.Rec709, TLuxTransfer.ROMM,
                       TLuxTransfer.Gamma( 1.8 ), TLuxTransfer.Gamma( 2.2 ), TLuxTransfer.Gamma( 563/256 ) ];

             if SumXX > 0 then Cand := Cand + [ TLuxTransfer.Gamma( SumXY / SumXX ) ];

             Best := MaxDouble;

             for J := 0 to High( Cand ) do
             begin
                  Err := TabErr( Cand[ J ] );

                  if Err < Best then begin Best := Err;  T_ := Cand[ J ];  end;
             end;

             Exit( True );
        end;
   end;
   //----- desc の解析
   function ReadDesc( const P_,L_:Integer ) :String;
   var
        K, J, Cnt, Ofs :Integer;
   begin
        Result := '';

        if RSig( P_ ) = 'mluc' then
        begin
             if R32( P_+8 ) < 1 then Exit;
             Cnt := R32( P_+20 );  Ofs := R32( P_+24 );   // 最初のレコードの長さ（バイト）とオフセット
             for J := 0 to Cnt div 2 - 1 do Result := Result + Char( R16( P_+Ofs+J*2 ) );
        end
        else
        if RSig( P_ ) = 'desc' then   // v2 textDescriptionType：ASCII 部
        begin
             K := R32( P_+8 );
             for J := 0 to K-2 do Result := Result + Char( Icc_[ P_+12+J ] );
        end;

        Result := Trim( Result );
   end;
   //--------------------------------------------
begin
     Result := nil;

     if Length( Icc_ ) < 132 then Exit;
     if RSig( 36 ) <> 'acsp' then Exit;
     if RSig( 16 ) <> 'RGB ' then Exit;

     N := R32( 128 );

     if 132 + N * 12 > Length( Icc_ ) then Exit;

     OfsRXYZ := -1;  OfsGXYZ := -1;  OfsBXYZ := -1;  OfsWtpt := -1;  OfsChad := -1;  OfsTRC := -1;  OfsDesc := -1;
     LenTRC  := 0;   LenDesc := 0;

     for I := 0 to N-1 do
     begin
          Sig := RSig( 132 + I*12 );
          Ofs := R32( 136 + I*12 );
          Len := R32( 140 + I*12 );

          if Ofs + Len > Length( Icc_ ) then Continue;

          if Sig = 'rXYZ' then OfsRXYZ := Ofs else
          if Sig = 'gXYZ' then OfsGXYZ := Ofs else
          if Sig = 'bXYZ' then OfsBXYZ := Ofs else
          if Sig = 'wtpt' then OfsWtpt := Ofs else
          if Sig = 'chad' then OfsChad := Ofs else
          if Sig = 'rTRC' then begin OfsTRC := Ofs;  LenTRC := Len;  end else
          if Sig = 'desc' then begin OfsDesc := Ofs;  LenDesc := Len;  end;
     end;

     if ( OfsRXYZ < 0 ) or ( OfsGXYZ < 0 ) or ( OfsBXYZ < 0 ) or ( OfsTRC < 0 ) then Exit;  // 行列＋TRC 型でない

     if not ReadTRC( OfsTRC, LenTRC, TF ) then Exit;

     ///// D50 適応済みの原色を元の白色点へ戻す

     with M do
     begin
          RW := RXYZ( OfsRXYZ );  GW := RXYZ( OfsGXYZ );  BW := RXYZ( OfsBXYZ );

          _11 := RW.X;  _12 := GW.X;  _13 := BW.X;
          _21 := RW.Y;  _22 := GW.Y;  _23 := BW.Y;
          _31 := RW.Z;  _32 := GW.Z;  _33 := BW.Z;
     end;

     if OfsChad >= 0 then
     begin
          Ad := TDoubleM3.Create( RFix( OfsChad+8  ), RFix( OfsChad+12 ), RFix( OfsChad+16 ),
                                  RFix( OfsChad+20 ), RFix( OfsChad+24 ), RFix( OfsChad+28 ),
                                  RFix( OfsChad+32 ), RFix( OfsChad+36 ), RFix( OfsChad+40 ) );

          M := Ad.Inverse * M;
     end
     else
     if OfsWtpt >= 0 then
     begin
          W := RXYZ( OfsWtpt );

          if ( Abs( W.X - 0.9642 ) > 1E-3 ) or ( Abs( W.Z - 0.8249 ) > 1E-3 ) then   // v2：wtpt が実際の白
            M := LuxBradford( LUX_WHITE_D50, XYOf( W ) ) * M;
     end;

     RXY := XYOf( TDouble3D.Create( M._11, M._21, M._31 ) );
     GXY := XYOf( TDouble3D.Create( M._12, M._22, M._32 ) );
     BXY := XYOf( TDouble3D.Create( M._13, M._23, M._33 ) );
     WXY := XYOf( M * TDouble3D.Create( 1, 1, 1 ) );

     if OfsDesc >= 0 then Name := ReadDesc( OfsDesc, LenDesc ) else Name := '';
     if Name = '' then Name := 'ICC';

     Result := TLuxColorSpace.Create( Name, RXY, GXY, BXY, WXY, TF );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% プリセット

constructor TLuxColorSpaceSRGB.Create;
begin
     inherited Create( 'sRGB', TDouble2D.Create( 0.64, 0.33 ), TDouble2D.Create( 0.30, 0.60 ), TDouble2D.Create( 0.15, 0.06 ), LUX_WHITE_D65, TLuxTransfer.sRGB );
end;

constructor TLuxColorSpaceLinearSRGB.Create;
begin
     inherited Create( 'Linear sRGB', TDouble2D.Create( 0.64, 0.33 ), TDouble2D.Create( 0.30, 0.60 ), TDouble2D.Create( 0.15, 0.06 ), LUX_WHITE_D65, TLuxTransfer.Linear );
end;

constructor TLuxColorSpaceDisplayP3.Create;
begin
     inherited Create( 'Display P3', TDouble2D.Create( 0.680, 0.320 ), TDouble2D.Create( 0.265, 0.690 ), TDouble2D.Create( 0.150, 0.060 ), LUX_WHITE_D65, TLuxTransfer.sRGB );
end;

constructor TLuxColorSpaceLinearDisplayP3.Create;
begin
     inherited Create( 'Linear Display P3', TDouble2D.Create( 0.680, 0.320 ), TDouble2D.Create( 0.265, 0.690 ), TDouble2D.Create( 0.150, 0.060 ), LUX_WHITE_D65, TLuxTransfer.Linear );
end;

constructor TLuxColorSpaceAdobeRGB.Create;
begin
     inherited Create( 'Adobe RGB (1998)', TDouble2D.Create( 0.64, 0.33 ), TDouble2D.Create( 0.21, 0.71 ), TDouble2D.Create( 0.15, 0.06 ), LUX_WHITE_D65, TLuxTransfer.Gamma( 563 / 256 ) );
end;

constructor TLuxColorSpaceLinearAdobeRGB.Create;
begin
     inherited Create( 'Linear Adobe RGB', TDouble2D.Create( 0.64, 0.33 ), TDouble2D.Create( 0.21, 0.71 ), TDouble2D.Create( 0.15, 0.06 ), LUX_WHITE_D65, TLuxTransfer.Linear );
end;

constructor TLuxColorSpaceRec2020.Create;
begin
     inherited Create( 'Rec.2020', TDouble2D.Create( 0.708, 0.292 ), TDouble2D.Create( 0.170, 0.797 ), TDouble2D.Create( 0.131, 0.046 ), LUX_WHITE_D65, TLuxTransfer.Rec709 );
end;

constructor TLuxColorSpaceLinearRec2020.Create;
begin
     inherited Create( 'Linear Rec.2020', TDouble2D.Create( 0.708, 0.292 ), TDouble2D.Create( 0.170, 0.797 ), TDouble2D.Create( 0.131, 0.046 ), LUX_WHITE_D65, TLuxTransfer.Linear );
end;

constructor TLuxColorSpaceProPhotoRGB.Create;
begin
     inherited Create( 'ProPhoto RGB', TDouble2D.Create( 0.7347, 0.2653 ), TDouble2D.Create( 0.1596, 0.8404 ), TDouble2D.Create( 0.0366, 0.0001 ), LUX_WHITE_D50, TLuxTransfer.ROMM );
end;

constructor TLuxColorSpaceACEScg.Create;
begin
     inherited Create( 'ACEScg', TDouble2D.Create( 0.713, 0.293 ), TDouble2D.Create( 0.165, 0.830 ), TDouble2D.Create( 0.128, 0.044 ), LUX_WHITE_ACES, TLuxTransfer.Linear );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxColorSpaces

class constructor TLuxColorSpaces.Create;
begin
     _sRGB            := TLuxColorSpaceSRGB           .Create;
     _LinearSRGB      := TLuxColorSpaceLinearSRGB     .Create;
     _DisplayP3       := TLuxColorSpaceDisplayP3      .Create;
     _LinearDisplayP3 := TLuxColorSpaceLinearDisplayP3.Create;
     _AdobeRGB        := TLuxColorSpaceAdobeRGB       .Create;
     _LinearAdobeRGB  := TLuxColorSpaceLinearAdobeRGB .Create;
     _Rec2020         := TLuxColorSpaceRec2020        .Create;
     _LinearRec2020   := TLuxColorSpaceLinearRec2020  .Create;
     _ProPhotoRGB     := TLuxColorSpaceProPhotoRGB    .Create;
     _ACEScg          := TLuxColorSpaceACEScg         .Create;

     _Presets := [ _sRGB, _LinearSRGB, _DisplayP3, _LinearDisplayP3, _AdobeRGB, _LinearAdobeRGB,
                   _Rec2020, _LinearRec2020, _ProPhotoRGB, _ACEScg ];

     _Interns := TObjectList<TLuxColorSpace>.Create( True );
end;

class destructor TLuxColorSpaces.Destroy;
var
   S :TLuxColorSpace;
begin
     _Interns.Free;

     for S in _Presets do S.Free;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

class function TLuxColorSpaces.Find( const S_:TLuxColorSpace ) :TLuxColorSpace;
var
   P :TLuxColorSpace;
begin
     for P in _Presets do if P.Same( S_ ) then Exit( P );
     for P in _Interns do if P.Same( S_ ) then Exit( P );

     Result := nil;
end;

class function TLuxColorSpaces.Intern( const S_:TLuxColorSpace ) :TLuxColorSpace;
begin
     if not Assigned( S_ ) then Exit( nil );

     Result := Find( S_ );

     if Assigned( Result ) then
     begin
          if Result <> S_ then S_.Free;
     end
     else
     begin
          _Interns.Add( S_ );  Result := S_;
     end;
end;

class function TLuxColorSpaces.FromIcc( const Icc_:TBytes ) :TLuxColorSpace;
begin
     Result := Intern( TLuxColorSpace.FromIcc( Icc_ ) );
end;

class function TLuxColorSpaces.ByName( const Name_:String ) :TLuxColorSpace;
var
   P :TLuxColorSpace;
begin
     for P in _Presets do if SameText( P.Name, Name_ ) then Exit( P );

     Result := nil;
end;

end. //######################################################################### ■
