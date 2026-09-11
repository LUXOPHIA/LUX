unit LUX.Complex.CP1;

// 複素射影直線 CP¹(リーマン球面)上の複素数
//
// 複素数 z を斉次座標のペア z = Z / W で保持する。
//   ・Z ≠ 0、W = 0 が無限遠点を表す。
//   ・演算後の正規化で各成分を 2^-E 倍し、二次反復の成分の大きさを制御する。
//   ・2 の冪の倍率変更も、アンダーフローで小さい成分が失われる場合は正確ではない。
//     乗算・加算・除算などの丸めや、反復による誤差の増幅も残る。
//
// 旧 INFTools / INFComplexTools の圧縮値を直接保持する方式に代わり、
// 斉次成分を Single / Double で保持する。任意精度・厳密演算ではない。
// Re / Im は分母を二乗前に正規化して通常の成分値へ戻す。
// 中間計算は Double で行い、返却型の範囲外だけ符号付き無限大とする。
// 不定形に与える値は実装上の方針であり、数学上の一意な値を定めるものではない。

interface //#################################################################### ■

uses LUX.Complex;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleCP1

     TSingleCP1 = record
     private
       ///// A C C E S S O R
       class function GetImaginary :TSingleCP1; static;
       class function GetZero :TSingleCP1; static;
       class function GetInfinity :TSingleCP1; static;
       //--------
       function GetIsZero :Boolean;
       function GetIsInf :Boolean;
       function GetRe :Single;
       procedure SetRe( const Value_:Single );
       function GetIm :Single;
       procedure SetIm( const Value_:Single );
       function GetAbs2 :Single;
       function GetAbso :Single;
       procedure SetAbso( const Abso_:Single );
       function GetUnitor :TSingleCP1;
       procedure SetUnitor( const Unitor_:TSingleCP1 );
       function GetConj :TSingleCP1;
       procedure SetConj( const Conj_:TSingleCP1 );
       function GetAngle :Single;
       ///// M E T H O D
       procedure Normalize;
     public
       Z :TSingleC;   // 分子
       W :TSingleC;   // 分母( W = 0 が無限遠点 )
       /////
       constructor Create( const Re_:Single ); overload;
       constructor Create( const Re_,Im_:Single ); overload;
       constructor Create( const Z_,W_:TSingleC ); overload;
       ///// P R O P E R T Y
       class property Imaginary :TSingleCP1 read GetImaginary;
       class property Zero     :TSingleCP1 read GetZero    ;
       class property Infinity :TSingleCP1 read GetInfinity;
       //--------
       property IsZero :Boolean read GetIsZero;
       property IsInf  :Boolean read GetIsInf ;
       property Re :Single read GetRe write SetRe;   // Re( Z/W )。無限遠では +∞
       property Im :Single read GetIm write SetIm;
       property R  :Single read GetRe write SetRe;
       property I  :Single read GetIm write SetIm;
       property Abs2   :Single  read GetAbs2  ;   // |z|²
       property Abso   :Single read GetAbso write SetAbso;   // |z|
       property Unitor :TSingleCP1 read GetUnitor write SetUnitor;
       property Conj   :TSingleCP1 read GetConj write SetConj;
       property Angle  :Single read GetAngle;
       ///// O P E R A T O R
       class operator Negative( const V_:TSingleCP1 ) :TSingleCP1;
       class operator Positive( const V_:TSingleCP1 ) :TSingleCP1;
       class operator Add( const A_,B_:TSingleCP1 ) :TSingleCP1;
       class operator Subtract( const A_,B_:TSingleCP1 ) :TSingleCP1;
       class operator Multiply( const A_,B_:TSingleCP1 ) :TSingleCP1;
       class operator Multiply( const A_:TSingleCP1; const B_:Single ) :TSingleCP1;
       class operator Multiply( const A_:Single; const B_:TSingleCP1 ) :TSingleCP1;
       class operator Divide( const A_,B_:TSingleCP1 ) :TSingleCP1;
       class operator Divide( const A_:TSingleCP1; const B_:Single ) :TSingleCP1;
       class operator Equal( const A_,B_:TSingleCP1 ) :Boolean;
       class operator NotEqual( const A_,B_:TSingleCP1 ) :Boolean;
       ///// C A S T
       class operator Implicit( const V_:Single ) :TSingleCP1;
       class operator Implicit( const C_:TSingleC ) :TSingleCP1;
       class operator Implicit( const C_:TDoubleC ) :TSingleCP1;
       class operator Explicit( const P_:TSingleCP1 ) :TDoubleC;
       class operator Explicit( const P_:TSingleCP1 ) :TSingleC;   // = Z/W(無限遠は +∞,+∞)
       ///// M E T H O D
       class function RandG( const SD_:Single = 1 ) :TSingleCP1; overload; static;
       class function RandG( const SD_:TSingleCP1 ) :TSingleCP1; overload; static;
       class function RandG( const SD_:TSingleC ) :TSingleCP1; overload; static;
       class function RandBS1 :TSingleCP1; static;
       class function RandBS2 :TSingleCP1; static;
       class function RandBS4 :TSingleCP1; static;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDoubleCP1

     TDoubleCP1 = record
     private
       ///// A C C E S S O R
       class function GetImaginary :TDoubleCP1; static;
       class function GetZero :TDoubleCP1; static;
       class function GetInfinity :TDoubleCP1; static;
       //--------
       function GetIsZero :Boolean;
       function GetIsInf :Boolean;
       function GetRe :Double;
       procedure SetRe( const Value_:Double );
       function GetIm :Double;
       procedure SetIm( const Value_:Double );
       function GetAbs2 :Double;
       function GetAbso :Double;
       procedure SetAbso( const Abso_:Double );
       function GetUnitor :TDoubleCP1;
       procedure SetUnitor( const Unitor_:TDoubleCP1 );
       function GetConj :TDoubleCP1;
       procedure SetConj( const Conj_:TDoubleCP1 );
       function GetAngle :Double;
       ///// M E T H O D
       procedure Normalize;
     public
       Z :TDoubleC;   // 分子
       W :TDoubleC;   // 分母( W = 0 が無限遠点 )
       /////
       constructor Create( const Re_:Double ); overload;
       constructor Create( const Re_,Im_:Double ); overload;
       constructor Create( const Z_,W_:TDoubleC ); overload;
       ///// P R O P E R T Y
       class property Imaginary :TDoubleCP1 read GetImaginary;
       class property Zero     :TDoubleCP1 read GetZero    ;
       class property Infinity :TDoubleCP1 read GetInfinity;
       //--------
       property IsZero :Boolean read GetIsZero;
       property IsInf  :Boolean read GetIsInf ;
       property Re :Double read GetRe write SetRe;   // Re( Z/W )。無限遠では +∞
       property Im :Double read GetIm write SetIm;
       property R  :Double read GetRe write SetRe;
       property I  :Double read GetIm write SetIm;
       property Abs2   :Double  read GetAbs2  ;   // |z|²
       property Abso   :Double read GetAbso write SetAbso;   // |z|
       property Unitor :TDoubleCP1 read GetUnitor write SetUnitor;
       property Conj   :TDoubleCP1 read GetConj write SetConj;
       property Angle  :Double read GetAngle;
       ///// O P E R A T O R
       class operator Negative( const V_:TDoubleCP1 ) :TDoubleCP1;
       class operator Positive( const V_:TDoubleCP1 ) :TDoubleCP1;
       class operator Add( const A_,B_:TDoubleCP1 ) :TDoubleCP1;
       class operator Subtract( const A_,B_:TDoubleCP1 ) :TDoubleCP1;
       class operator Multiply( const A_,B_:TDoubleCP1 ) :TDoubleCP1;
       class operator Multiply( const A_:TDoubleCP1; const B_:Double ) :TDoubleCP1;
       class operator Multiply( const A_:Double; const B_:TDoubleCP1 ) :TDoubleCP1;
       class operator Divide( const A_,B_:TDoubleCP1 ) :TDoubleCP1;
       class operator Divide( const A_:TDoubleCP1; const B_:Double ) :TDoubleCP1;
       class operator Equal( const A_,B_:TDoubleCP1 ) :Boolean;
       class operator NotEqual( const A_,B_:TDoubleCP1 ) :Boolean;
       ///// C A S T
       class operator Implicit( const V_:Double ) :TDoubleCP1;
       class operator Implicit( const C_:TDoubleC ) :TDoubleCP1;
       class operator Implicit( const C_:TSingleC ) :TDoubleCP1;
       class operator Explicit( const P_:TDoubleCP1 ) :TSingleC;
       class operator Explicit( const P_:TDoubleCP1 ) :TDoubleC;   // = Z/W(無限遠は +∞,+∞)
       class operator Implicit( const P_:TSingleCP1 ) :TDoubleCP1;
       class operator Implicit( const P_:TDoubleCP1 ) :TSingleCP1;
       ///// M E T H O D
       class function RandG( const SD_:Double = 1 ) :TDoubleCP1; overload; static;
       class function RandG( const SD_:TDoubleCP1 ) :TDoubleCP1; overload; static;
       class function RandG( const SD_:TDoubleC ) :TDoubleCP1; overload; static;
       class function RandBS1 :TDoubleCP1; static;
       class function RandBS2 :TDoubleCP1; static;
       class function RandBS4 :TDoubleCP1; static;
     end;

     TSingleCP1Func = reference to function ( const C_:TSingleCP1 ) :TSingleCP1;
     TDoubleCP1Func = reference to function ( const C_:TDoubleCP1 ) :TDoubleCP1;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Pow2

function Pow2( const X_:TSingleCP1 ) :TSingleCP1; overload;
function Pow2( const X_:TDoubleCP1 ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Roo2

function Roo2( const X_:TSingleCP1 ) :TSingleCP1; overload;
function Roo2( const X_:TDoubleCP1 ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Pow

function Pow( const X_:TSingleCP1; const N_:Single ) :TSingleCP1; overload;
function Pow( const X_:TDoubleCP1; const N_:Double ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Exp

function Exp( const A_:TSingleCP1 ) :TSingleCP1; overload;
function Exp( const A_:TDoubleCP1 ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Expi

function Expi( const X_:Single ) :TSingleCP1; overload;
function Expi( const X_:Double ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Ln

function Ln( const A_:TSingleCP1 ) :TSingleCP1; overload;
function Ln( const A_:TDoubleCP1 ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Cos

function Cos( const A_:TSingleCP1 ) :TSingleCP1; overload;
function Cos( const A_:TDoubleCP1 ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Sin

function Sin( const A_:TSingleCP1 ) :TSingleCP1; overload;
function Sin( const A_:TDoubleCP1 ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Tan

function Tan( const A_:TSingleCP1 ) :TSingleCP1; overload;
function Tan( const A_:TDoubleCP1 ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ArcSin

function ArcSin( const X_:TSingleCP1 ) :TSingleCP1; overload;
function ArcSin( const X_:TDoubleCP1 ) :TDoubleCP1; overload;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ArcCos

function ArcCos( const X_:TSingleCP1 ) :TSingleCP1; overload;
function ArcCos( const X_:TDoubleCP1 ) :TDoubleCP1; overload;

implementation //############################################################### ■

uses System.Math;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleCP1

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

class function TSingleCP1.GetImaginary :TSingleCP1;
begin
     Result := TSingleCP1.Create( 0, 1 );
end;

class function TSingleCP1.GetZero :TSingleCP1;
begin
     Result.Z := 0;
     Result.W := 1;
end;

class function TSingleCP1.GetInfinity :TSingleCP1;
begin
     Result.Z := 1;
     Result.W := 0;
end;

//------------------------------------------------------------------------------

function TSingleCP1.GetIsZero :Boolean;
begin
     Result := ( Z.R = 0 ) and ( Z.I = 0 ) and not GetIsInf;
end;

function TSingleCP1.GetIsInf :Boolean;
begin
     Result := ( W.R = 0 ) and ( W.I = 0 );
end;

function TSingleCP1.GetRe :Single;
var
   Scale, Wr, Wi, A, D :Double;
begin
     Scale := Max( Abs( W.R ), Abs( W.I ) );
     if Scale = 0 then Exit( System.Math.Infinity );

     ///// W を二乗する前に正規化する。求める成分は A / D。
     Wr := W.R / Scale;
     Wi := W.I / Scale;
     A := Z.R * Wr + Z.I * Wi;
     D := Scale * ( Sqr( Wr ) + Sqr( Wi ) );

     ///// 返却型の範囲を超える場合だけ、符号付き無限大にする。
     if D < 1 then
     begin
          if Abs( A ) > D * MaxSingle then Exit( Sign( A ) * System.Math.Infinity );
     end;
     Result := A / D;
end;

function TSingleCP1.GetIm :Single;
var
   Scale, Wr, Wi, A, D :Double;
begin
     Scale := Max( Abs( W.R ), Abs( W.I ) );
     if Scale = 0 then Exit( System.Math.Infinity );

     ///// W を二乗する前に正規化する。求める成分は A / D。
     Wr := W.R / Scale;
     Wi := W.I / Scale;
     A := Z.I * Wr - Z.R * Wi;
     D := Scale * ( Sqr( Wr ) + Sqr( Wi ) );

     ///// 返却型の範囲を超える場合だけ、符号付き無限大にする。
     if D < 1 then
     begin
          if Abs( A ) > D * MaxSingle then Exit( Sign( A ) * System.Math.Infinity );
     end;
     Result := A / D;
end;

procedure TSingleCP1.SetRe( const Value_:Single );
var
   P :TSingleCP1;
   S, Wr, Wi :Double;
begin
     if IsInf then Exit;   // 無限遠点には実部・虚部の別がない。
     P := Self;
     S := Max( Abs( W.R ), Abs( W.I ) );
     Wr := W.R / S;
     Wi := W.I / S;
     P.Z := TSingleC.Create( 0, Z.I * Wr - Z.R * Wi );
     P.W := TSingleC.Create( S * ( Sqr( Wr ) + Sqr( Wi ) ), 0 );
     P.Normalize;
     Self := P + TSingleCP1.Create( Value_ );
end;

procedure TSingleCP1.SetIm( const Value_:Single );
var
   P :TSingleCP1;
   S, Wr, Wi :Double;
begin
     if IsInf then Exit;
     P := Self;
     S := Max( Abs( W.R ), Abs( W.I ) );
     Wr := W.R / S;
     Wi := W.I / S;
     P.Z := TSingleC.Create( Z.R * Wr + Z.I * Wi, 0 );
     P.W := TSingleC.Create( S * ( Sqr( Wr ) + Sqr( Wi ) ), 0 );
     P.Normalize;
     Self := P + TSingleCP1.Create( 0, Value_ );
end;

function TSingleCP1.GetAbs2 :Single;
var
   N, D, M, Limit :Double;
   EN, ED, EM, EL, E :Integer;
begin
     D := Hypot( Double( W.R ), Double( W.I ) );
     if D = 0 then Exit( System.Math.Infinity );
     N := Hypot( Double( Z.R ), Double( Z.I ) );
     if N = 0 then Exit( 0 );

     // 仮数だけを二乗し、指数差は最後に適用する。
     Frexp( N, N, EN );
     Frexp( D, D, ED );
     M := Sqr( N / D );
     Frexp( M, M, EM );
     E := 2 * ( EN - ED ) + EM;
     Frexp( Double( MaxSingle ), Limit, EL );
     if ( E > EL ) or ( ( E = EL ) and ( M > Limit ) )
     then Exit( System.Math.Infinity );
     Result := Ldexp( M, E );
end;

function TSingleCP1.GetAbso :Single;
var
   N, D :Double;
begin
     D := Hypot( Double( W.R ), Double( W.I ) );
     if D = 0 then Exit( System.Math.Infinity );
     N := Hypot( Double( Z.R ), Double( Z.I ) );
     if D < 1 then
     begin
          if N > D * MaxSingle then Exit( System.Math.Infinity );
     end;
     Result := N / D;
end;

procedure TSingleCP1.SetAbso( const Abso_:Single );
begin
     Self := Abso_ * Unitor;
end;

function TSingleCP1.GetUnitor :TSingleCP1;
var
   N, D :Double;
   NZ, NW :TSingleC;
begin
     // 0/0 と ∞/∞ は既存の CP1 の規約に合わせる。
     if IsZero or IsInf then Exit( Infinity );
     N := Hypot( Double( Z.R ), Double( Z.I ) );
     D := Hypot( Double( W.R ), Double( W.I ) );
     NZ := TSingleC.Create( Z.R / N, Z.I / N );
     NW := TSingleC.Create( W.R / D, W.I / D );
     Result := TSingleCP1.Create( NZ * NW.Conj, TSingleC.Create( 1 ) );
end;

procedure TSingleCP1.SetUnitor( const Unitor_:TSingleCP1 );
var
   Magnitude :TSingleCP1;
begin
     // 通常型と同じく引数をそのまま掛ける。引数の再正規化はしない。
     Magnitude := TSingleCP1.Create(
          TSingleC.Create( Hypot( Double( Z.R ), Double( Z.I ) ) ),
          TSingleC.Create( Hypot( Double( W.R ), Double( W.I ) ) ) );
     Self := Magnitude * Unitor_;
end;

function TSingleCP1.GetConj :TSingleCP1;
begin
     Result.Z := Z.Conj;
     Result.W := W.Conj;
end;

procedure TSingleCP1.SetConj( const Conj_:TSingleCP1 );
begin
     Self := Conj_.Conj;
end;

function TSingleCP1.GetAngle :Single;
var
   U :TSingleCP1;
begin
     if IsInf then Exit( System.Math.NaN );   // 無限遠点に方向はない。
     if IsZero then Exit( 0 );
     U := Unitor;
     Result := ArcTan2( U.Z.I, U.Z.R );
end;

procedure TSingleCP1.Normalize;
var
   M, A :Single;
   E :Integer;
begin
     M := System.Abs( Z.R );
     A := System.Abs( Z.I );  if A > M then M := A;
     A := System.Abs( W.R );  if A > M then M := A;
     A := System.Abs( W.I );  if A > M then M := A;

     if ( M = 0 ) or ( ( 0.5 <= M ) and ( M < 2 ) ) then Exit;

     Frexp( M, A, E );                                 // M = A × 2^E

     Z.R := Ldexp( Z.R, -E );                          // アンダーフローしない範囲では正確な倍率変更
     Z.I := Ldexp( Z.I, -E );
     W.R := Ldexp( W.R, -E );
     W.I := Ldexp( W.I, -E );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TSingleCP1.Create( const Re_:Single );
begin
     Z := TSingleC.Create( Re_ );
     W := 1;
     Normalize;
end;

constructor TSingleCP1.Create( const Re_,Im_:Single );
begin
     Z := TSingleC.Create( Re_, Im_ );
     W := 1;
     Normalize;
end;

constructor TSingleCP1.Create( const Z_,W_:TSingleC );
begin
     Z := Z_;
     W := W_;
     Normalize;
end;

//////////////////////////////////////////////////////////////// O P E R A T O R

class operator TSingleCP1.Negative( const V_:TSingleCP1 ) :TSingleCP1;
begin
     Result.Z := -V_.Z;
     Result.W :=  V_.W;
end;

class operator TSingleCP1.Positive( const V_:TSingleCP1 ) :TSingleCP1;
begin
     Result := V_;
end;

class operator TSingleCP1.Add( const A_,B_:TSingleCP1 ) :TSingleCP1;
begin
     if A_.GetIsInf and B_.GetIsInf then Exit( GetInfinity );        // ∞+∞ → ∞(方針)

     Result.Z := A_.Z * B_.W + B_.Z * A_.W;
     Result.W := A_.W * B_.W;
     Result.Normalize;
end;

class operator TSingleCP1.Subtract( const A_,B_:TSingleCP1 ) :TSingleCP1;
begin
     if A_.GetIsInf and B_.GetIsInf then Exit( GetInfinity );        // ∞-∞ → ∞(方針)

     Result.Z := A_.Z * B_.W - B_.Z * A_.W;
     Result.W := A_.W * B_.W;
     Result.Normalize;
end;

class operator TSingleCP1.Multiply( const A_,B_:TSingleCP1 ) :TSingleCP1;
begin
     if ( A_.GetIsInf and B_.GetIsZero )
     or ( A_.GetIsZero and B_.GetIsInf ) then Exit( GetInfinity );   // 0・∞ → ∞(方針)

     Result.Z := A_.Z * B_.Z;
     Result.W := A_.W * B_.W;
     Result.Normalize;
end;

class operator TSingleCP1.Multiply( const A_:TSingleCP1; const B_:Single ) :TSingleCP1;
begin
     if A_.GetIsInf and ( B_ = 0 ) then Exit( GetInfinity );         // ∞・0 → ∞(方針)

     Result.Z := A_.Z * B_;
     Result.W := A_.W;
     Result.Normalize;
end;

class operator TSingleCP1.Multiply( const A_:Single; const B_:TSingleCP1 ) :TSingleCP1;
begin
     Result := B_ * A_;
end;

class operator TSingleCP1.Divide( const A_,B_:TSingleCP1 ) :TSingleCP1;
begin
     if ( A_.GetIsZero and B_.GetIsZero )
     or ( A_.GetIsInf  and B_.GetIsInf  ) then Exit( GetInfinity );  // 0/0, ∞/∞ → ∞(方針)

     Result.Z := A_.Z * B_.W;
     Result.W := A_.W * B_.Z;
     Result.Normalize;
end;

class operator TSingleCP1.Divide( const A_:TSingleCP1; const B_:Single ) :TSingleCP1;
begin
     if A_.GetIsZero and ( B_ = 0 ) then Exit( GetInfinity );        // 0/0 → ∞(方針)

     Result.Z := A_.Z;
     Result.W := A_.W * B_;
     Result.Normalize;
end;

class operator TSingleCP1.Equal( const A_,B_:TSingleCP1 ) :Boolean;
var
   X, Y :TSingleC;
begin
     X := A_.Z * B_.W;
     Y := B_.Z * A_.W;
     Result := ( X.R = Y.R ) and ( X.I = Y.I );
end;

class operator TSingleCP1.NotEqual( const A_,B_:TSingleCP1 ) :Boolean;
begin
     Result := not ( A_ = B_ );
end;

//////////////////////////////////////////////////////////////////////// C A S T

class operator TSingleCP1.Implicit( const V_:Single ) :TSingleCP1;
begin
     Result := TSingleCP1.Create( V_ );
end;

class operator TSingleCP1.Implicit( const C_:TSingleC ) :TSingleCP1;
begin
     Result.Z := C_;
     Result.W := 1;
     Result.Normalize;
end;

class operator TSingleCP1.Implicit( const C_:TDoubleC ) :TSingleCP1;
begin
     Result := TSingleCP1( TDoubleCP1( C_ ) );
end;

class operator TSingleCP1.Explicit( const P_:TSingleCP1 ) :TDoubleC;
begin
     Result := TDoubleC( TDoubleCP1( P_ ) );
end;

class operator TSingleCP1.Explicit( const P_:TSingleCP1 ) :TSingleC;
begin
     Result := TSingleC.Create( P_.GetRe, P_.GetIm );
end;

class function TSingleCP1.RandG( const SD_:Single ) :TSingleCP1;
begin
     Result := TSingleC.RandG( SD_ );
end;

class function TSingleCP1.RandG( const SD_:TSingleCP1 ) :TSingleCP1;
begin
     Result := TSingleC.RandG( TSingleC( SD_ ) );
end;

class function TSingleCP1.RandG( const SD_:TSingleC ) :TSingleCP1;
begin
     Result := TSingleC.RandG( SD_ );
end;

class function TSingleCP1.RandBS1 :TSingleCP1;
begin
     Result := TSingleC.RandBS1;
end;

class function TSingleCP1.RandBS2 :TSingleCP1;
begin
     Result := TSingleC.RandBS2;
end;

class function TSingleCP1.RandBS4 :TSingleCP1;
begin
     Result := TSingleC.RandBS4;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDoubleCP1

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

class function TDoubleCP1.GetImaginary :TDoubleCP1;
begin
     Result := TDoubleCP1.Create( 0, 1 );
end;

class function TDoubleCP1.GetZero :TDoubleCP1;
begin
     Result.Z := 0;
     Result.W := 1;
end;

class function TDoubleCP1.GetInfinity :TDoubleCP1;
begin
     Result.Z := 1;
     Result.W := 0;
end;

//------------------------------------------------------------------------------

function TDoubleCP1.GetIsZero :Boolean;
begin
     Result := ( Z.R = 0 ) and ( Z.I = 0 ) and not GetIsInf;
end;

function TDoubleCP1.GetIsInf :Boolean;
begin
     Result := ( W.R = 0 ) and ( W.I = 0 );
end;

function TDoubleCP1.GetRe :Double;
var
   Scale, Wr, Wi, A, D :Double;
begin
     Scale := Max( Abs( W.R ), Abs( W.I ) );
     if Scale = 0 then Exit( System.Math.Infinity );

     ///// W を二乗する前に正規化する。求める成分は A / D。
     Wr := W.R / Scale;
     Wi := W.I / Scale;
     A := Z.R * Wr + Z.I * Wi;
     D := Scale * ( Sqr( Wr ) + Sqr( Wi ) );

     ///// 返却型の範囲を超える場合だけ、符号付き無限大にする。
     if D < 1 then
     begin
          if Abs( A ) > D * MaxDouble then Exit( Sign( A ) * System.Math.Infinity );
     end;
     Result := A / D;
end;

function TDoubleCP1.GetIm :Double;
var
   Scale, Wr, Wi, A, D :Double;
begin
     Scale := Max( Abs( W.R ), Abs( W.I ) );
     if Scale = 0 then Exit( System.Math.Infinity );

     ///// W を二乗する前に正規化する。求める成分は A / D。
     Wr := W.R / Scale;
     Wi := W.I / Scale;
     A := Z.I * Wr - Z.R * Wi;
     D := Scale * ( Sqr( Wr ) + Sqr( Wi ) );

     ///// 返却型の範囲を超える場合だけ、符号付き無限大にする。
     if D < 1 then
     begin
          if Abs( A ) > D * MaxDouble then Exit( Sign( A ) * System.Math.Infinity );
     end;
     Result := A / D;
end;

procedure TDoubleCP1.SetRe( const Value_:Double );
var
   P :TDoubleCP1;
   S, Wr, Wi :Double;
begin
     if IsInf then Exit;   // 無限遠点には実部・虚部の別がない。
     P := Self;
     S := Max( Abs( W.R ), Abs( W.I ) );
     Wr := W.R / S;
     Wi := W.I / S;
     P.Z := TDoubleC.Create( 0, Z.I * Wr - Z.R * Wi );
     P.W := TDoubleC.Create( S * ( Sqr( Wr ) + Sqr( Wi ) ), 0 );
     P.Normalize;
     Self := P + TDoubleCP1.Create( Value_ );
end;

procedure TDoubleCP1.SetIm( const Value_:Double );
var
   P :TDoubleCP1;
   S, Wr, Wi :Double;
begin
     if IsInf then Exit;
     P := Self;
     S := Max( Abs( W.R ), Abs( W.I ) );
     Wr := W.R / S;
     Wi := W.I / S;
     P.Z := TDoubleC.Create( Z.R * Wr + Z.I * Wi, 0 );
     P.W := TDoubleC.Create( S * ( Sqr( Wr ) + Sqr( Wi ) ), 0 );
     P.Normalize;
     Self := P + TDoubleCP1.Create( 0, Value_ );
end;

function TDoubleCP1.GetAbs2 :Double;
var
   N, D, M, Limit :Double;
   EN, ED, EM, EL, E :Integer;
begin
     D := Hypot( Double( W.R ), Double( W.I ) );
     if D = 0 then Exit( System.Math.Infinity );
     N := Hypot( Double( Z.R ), Double( Z.I ) );
     if N = 0 then Exit( 0 );

     // 仮数だけを二乗し、指数差は最後に適用する。
     Frexp( N, N, EN );
     Frexp( D, D, ED );
     M := Sqr( N / D );
     Frexp( M, M, EM );
     E := 2 * ( EN - ED ) + EM;
     Frexp( Double( MaxDouble ), Limit, EL );
     if ( E > EL ) or ( ( E = EL ) and ( M > Limit ) )
     then Exit( System.Math.Infinity );
     Result := Ldexp( M, E );
end;

function TDoubleCP1.GetAbso :Double;
var
   N, D :Double;
begin
     D := Hypot( Double( W.R ), Double( W.I ) );
     if D = 0 then Exit( System.Math.Infinity );
     N := Hypot( Double( Z.R ), Double( Z.I ) );
     if D < 1 then
     begin
          if N > D * MaxDouble then Exit( System.Math.Infinity );
     end;
     Result := N / D;
end;

procedure TDoubleCP1.SetAbso( const Abso_:Double );
begin
     Self := Abso_ * Unitor;
end;

function TDoubleCP1.GetUnitor :TDoubleCP1;
var
   N, D :Double;
   NZ, NW :TDoubleC;
begin
     // 0/0 と ∞/∞ は既存の CP1 の規約に合わせる。
     if IsZero or IsInf then Exit( Infinity );
     N := Hypot( Double( Z.R ), Double( Z.I ) );
     D := Hypot( Double( W.R ), Double( W.I ) );
     NZ := TDoubleC.Create( Z.R / N, Z.I / N );
     NW := TDoubleC.Create( W.R / D, W.I / D );
     Result := TDoubleCP1.Create( NZ * NW.Conj, TDoubleC.Create( 1 ) );
end;

procedure TDoubleCP1.SetUnitor( const Unitor_:TDoubleCP1 );
var
   Magnitude :TDoubleCP1;
begin
     // 通常型と同じく引数をそのまま掛ける。引数の再正規化はしない。
     Magnitude := TDoubleCP1.Create(
          TDoubleC.Create( Hypot( Double( Z.R ), Double( Z.I ) ) ),
          TDoubleC.Create( Hypot( Double( W.R ), Double( W.I ) ) ) );
     Self := Magnitude * Unitor_;
end;

function TDoubleCP1.GetConj :TDoubleCP1;
begin
     Result.Z := Z.Conj;
     Result.W := W.Conj;
end;

procedure TDoubleCP1.SetConj( const Conj_:TDoubleCP1 );
begin
     Self := Conj_.Conj;
end;

function TDoubleCP1.GetAngle :Double;
var
   U :TDoubleCP1;
begin
     if IsInf then Exit( System.Math.NaN );   // 無限遠点に方向はない。
     if IsZero then Exit( 0 );
     U := Unitor;
     Result := ArcTan2( U.Z.I, U.Z.R );
end;

procedure TDoubleCP1.Normalize;
var
   M, A :Double;
   E :Integer;
begin
     M := System.Abs( Z.R );
     A := System.Abs( Z.I );  if A > M then M := A;
     A := System.Abs( W.R );  if A > M then M := A;
     A := System.Abs( W.I );  if A > M then M := A;

     if ( M = 0 ) or ( ( 0.5 <= M ) and ( M < 2 ) ) then Exit;

     Frexp( M, A, E );                                 // M = A × 2^E

     Z.R := Ldexp( Z.R, -E );                          // アンダーフローしない範囲では正確な倍率変更
     Z.I := Ldexp( Z.I, -E );
     W.R := Ldexp( W.R, -E );
     W.I := Ldexp( W.I, -E );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TDoubleCP1.Create( const Re_:Double );
begin
     Z := TDoubleC.Create( Re_ );
     W := 1;
     Normalize;
end;

constructor TDoubleCP1.Create( const Re_,Im_:Double );
begin
     Z := TDoubleC.Create( Re_, Im_ );
     W := 1;
     Normalize;
end;

constructor TDoubleCP1.Create( const Z_,W_:TDoubleC );
begin
     Z := Z_;
     W := W_;
     Normalize;
end;

//////////////////////////////////////////////////////////////// O P E R A T O R

class operator TDoubleCP1.Negative( const V_:TDoubleCP1 ) :TDoubleCP1;
begin
     Result.Z := -V_.Z;
     Result.W :=  V_.W;
end;

class operator TDoubleCP1.Positive( const V_:TDoubleCP1 ) :TDoubleCP1;
begin
     Result := V_;
end;

class operator TDoubleCP1.Add( const A_,B_:TDoubleCP1 ) :TDoubleCP1;
begin
     if A_.GetIsInf and B_.GetIsInf then Exit( GetInfinity );        // ∞+∞ → ∞(方針)

     Result.Z := A_.Z * B_.W + B_.Z * A_.W;
     Result.W := A_.W * B_.W;
     Result.Normalize;
end;

class operator TDoubleCP1.Subtract( const A_,B_:TDoubleCP1 ) :TDoubleCP1;
begin
     if A_.GetIsInf and B_.GetIsInf then Exit( GetInfinity );        // ∞-∞ → ∞(方針)

     Result.Z := A_.Z * B_.W - B_.Z * A_.W;
     Result.W := A_.W * B_.W;
     Result.Normalize;
end;

class operator TDoubleCP1.Multiply( const A_,B_:TDoubleCP1 ) :TDoubleCP1;
begin
     if ( A_.GetIsInf and B_.GetIsZero )
     or ( A_.GetIsZero and B_.GetIsInf ) then Exit( GetInfinity );   // 0・∞ → ∞(方針)

     Result.Z := A_.Z * B_.Z;
     Result.W := A_.W * B_.W;
     Result.Normalize;
end;

class operator TDoubleCP1.Multiply( const A_:TDoubleCP1; const B_:Double ) :TDoubleCP1;
begin
     if A_.GetIsInf and ( B_ = 0 ) then Exit( GetInfinity );         // ∞・0 → ∞(方針)

     Result.Z := A_.Z * B_;
     Result.W := A_.W;
     Result.Normalize;
end;

class operator TDoubleCP1.Multiply( const A_:Double; const B_:TDoubleCP1 ) :TDoubleCP1;
begin
     Result := B_ * A_;
end;

class operator TDoubleCP1.Divide( const A_,B_:TDoubleCP1 ) :TDoubleCP1;
begin
     if ( A_.GetIsZero and B_.GetIsZero )
     or ( A_.GetIsInf  and B_.GetIsInf  ) then Exit( GetInfinity );  // 0/0, ∞/∞ → ∞(方針)

     Result.Z := A_.Z * B_.W;
     Result.W := A_.W * B_.Z;
     Result.Normalize;
end;

class operator TDoubleCP1.Divide( const A_:TDoubleCP1; const B_:Double ) :TDoubleCP1;
begin
     if A_.GetIsZero and ( B_ = 0 ) then Exit( GetInfinity );        // 0/0 → ∞(方針)

     Result.Z := A_.Z;
     Result.W := A_.W * B_;
     Result.Normalize;
end;

class operator TDoubleCP1.Equal( const A_,B_:TDoubleCP1 ) :Boolean;
var
   X, Y :TDoubleC;
begin
     X := A_.Z * B_.W;
     Y := B_.Z * A_.W;
     Result := ( X.R = Y.R ) and ( X.I = Y.I );
end;

class operator TDoubleCP1.NotEqual( const A_,B_:TDoubleCP1 ) :Boolean;
begin
     Result := not ( A_ = B_ );
end;

//////////////////////////////////////////////////////////////////////// C A S T

class operator TDoubleCP1.Implicit( const V_:Double ) :TDoubleCP1;
begin
     Result := TDoubleCP1.Create( V_ );
end;

class operator TDoubleCP1.Implicit( const C_:TDoubleC ) :TDoubleCP1;
begin
     Result.Z := C_;
     Result.W := 1;
     Result.Normalize;
end;

class operator TDoubleCP1.Implicit( const C_:TSingleC ) :TDoubleCP1;
begin
     Result := TDoubleCP1.Create( C_.R, C_.I );
end;

class operator TDoubleCP1.Explicit( const P_:TDoubleCP1 ) :TSingleC;
begin
     Result := TSingleC.Create( P_.GetRe, P_.GetIm );
end;

class operator TDoubleCP1.Explicit( const P_:TDoubleCP1 ) :TDoubleC;
begin
     Result := TDoubleC.Create( P_.GetRe, P_.GetIm );
end;

class operator TDoubleCP1.Implicit( const P_:TSingleCP1 ) :TDoubleCP1;
begin
     Result.Z := P_.Z;
     Result.W := P_.W;
end;

class operator TDoubleCP1.Implicit( const P_:TDoubleCP1 ) :TSingleCP1;
begin
     Result.Z := P_.Z;
     Result.W := P_.W;
end;

class function TDoubleCP1.RandG( const SD_:Double ) :TDoubleCP1;
begin
     Result := TDoubleC.RandG( SD_ );
end;

class function TDoubleCP1.RandG( const SD_:TDoubleCP1 ) :TDoubleCP1;
begin
     Result := TDoubleC.RandG( TDoubleC( SD_ ) );
end;

class function TDoubleCP1.RandG( const SD_:TDoubleC ) :TDoubleCP1;
begin
     Result := TDoubleC.RandG( SD_ );
end;

class function TDoubleCP1.RandBS1 :TDoubleCP1;
begin
     Result := TDoubleC.RandBS1;
end;

class function TDoubleCP1.RandBS2 :TDoubleCP1;
begin
     Result := TDoubleC.RandBS2;
end;

class function TDoubleCP1.RandBS4 :TDoubleCP1;
begin
     Result := TDoubleC.RandBS4;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Pow2

function Pow2( const X_:TSingleCP1 ) :TSingleCP1;
begin
     Result.Z := X_.Z * X_.Z;
     Result.W := X_.W * X_.W;
     Result.Normalize;
end;

function Pow2( const X_:TDoubleCP1 ) :TDoubleCP1;
begin
     Result.Z := X_.Z * X_.Z;
     Result.W := X_.W * X_.W;
     Result.Normalize;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Roo2

function Roo2( const X_:TSingleCP1 ) :TSingleCP1;
var
   A, N, D :Double;
begin
     if X_.IsInf then Exit( TSingleCP1.Infinity );
     if X_.IsZero then Exit( TSingleCP1.Zero );
     A := X_.Angle / 2;
     N := Sqrt( Hypot( Double( X_.Z.R ), Double( X_.Z.I ) ) );
     D := Sqrt( Hypot( Double( X_.W.R ), Double( X_.W.I ) ) );
     Result := TSingleCP1.Create( TSingleC.Create( N * System.Cos( A ), N * System.Sin( A ) ),
                              TSingleC.Create( D ) );
end;

function Roo2( const X_:TDoubleCP1 ) :TDoubleCP1;
var
   A, N, D :Double;
begin
     if X_.IsInf then Exit( TDoubleCP1.Infinity );
     if X_.IsZero then Exit( TDoubleCP1.Zero );
     A := X_.Angle / 2;
     N := Sqrt( Hypot( Double( X_.Z.R ), Double( X_.Z.I ) ) );
     D := Sqrt( Hypot( Double( X_.W.R ), Double( X_.W.I ) ) );
     Result := TDoubleCP1.Create( TDoubleC.Create( N * System.Cos( A ), N * System.Sin( A ) ),
                              TDoubleC.Create( D ) );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Pow

function Pow( const X_:TSingleCP1; const N_:Single ) :TSingleCP1;
begin
     if X_.IsZero then
     begin
          if N_ > 0 then Exit( TSingleCP1.Zero     );
          if N_ < 0 then Exit( TSingleCP1.Infinity );
          Exit( TSingleCP1.Create( 1 ) );                            // 0^0 = 1(方針)
     end;
     if X_.IsInf then
     begin
          if N_ > 0 then Exit( TSingleCP1.Infinity );
          if N_ < 0 then Exit( TSingleCP1.Zero     );
          Exit( TSingleCP1.Create( 1 ) );                            // ∞^0 = 1(方針)
     end;

     Result := Exp( N_ * Ln( X_ ) );
end;

function Pow( const X_:TDoubleCP1; const N_:Double ) :TDoubleCP1;
begin
     if X_.IsZero then
     begin
          if N_ > 0 then Exit( TDoubleCP1.Zero     );
          if N_ < 0 then Exit( TDoubleCP1.Infinity );
          Exit( TDoubleCP1.Create( 1 ) );                            // 0^0 = 1(方針)
     end;
     if X_.IsInf then
     begin
          if N_ > 0 then Exit( TDoubleCP1.Infinity );
          if N_ < 0 then Exit( TDoubleCP1.Zero     );
          Exit( TDoubleCP1.Create( 1 ) );                            // ∞^0 = 1(方針)
     end;

     Result := Exp( N_ * Ln( X_ ) );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Exp

// e^(x+iy) は x ≧ 0 のとき ( cos y + i sin y : e^-x ) と斉次化すると
// 指数関数がオーバーフローしない( e^-x ≦ 1 )。e^-x のアンダーフロー(→0)は
// そのまま無限遠点となり、数学的な極限と一致する。

function Exp( const A_:TSingleCP1 ) :TSingleCP1;
var
   X, Y :Single;
begin
     if A_.IsInf then Exit( TSingleCP1.Infinity );                   // 本質的特異点(方針として∞)

     X := A_.Re;
     Y := A_.Im;

     if IsInfinite( Y ) then Exit( TSingleCP1.Infinity );            // 方針
     if IsInfinite( X ) then
     begin
          if X > 0 then Exit( TSingleCP1.Infinity )
                   else Exit( TSingleCP1.Zero     );
     end;

     if X >= 0 then
     begin
          Result.Z := TSingleC.Create( System.Cos( Y ), System.Sin( Y ) );
          Result.W := System.Exp( -X );
     end
     else
     begin
          Result.Z := System.Exp( X ) * TSingleC.Create( System.Cos( Y ), System.Sin( Y ) );
          Result.W := 1;
     end;
     Result.Normalize;
end;

function Exp( const A_:TDoubleCP1 ) :TDoubleCP1;
var
   X, Y :Double;
begin
     if A_.IsInf then Exit( TDoubleCP1.Infinity );                   // 本質的特異点(方針として∞)

     X := A_.Re;
     Y := A_.Im;

     if IsInfinite( Y ) then Exit( TDoubleCP1.Infinity );            // 方針
     if IsInfinite( X ) then
     begin
          if X > 0 then Exit( TDoubleCP1.Infinity )
                   else Exit( TDoubleCP1.Zero     );
     end;

     if X >= 0 then
     begin
          Result.Z := TDoubleC.Create( System.Cos( Y ), System.Sin( Y ) );
          Result.W := System.Exp( -X );
     end
     else
     begin
          Result.Z := System.Exp( X ) * TDoubleC.Create( System.Cos( Y ), System.Sin( Y ) );
          Result.W := 1;
     end;
     Result.Normalize;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Expi

function Expi( const X_:Single ) :TSingleCP1;
begin
     Result.Z := TSingleC.Create( System.Cos( X_ ), System.Sin( X_ ) );
     Result.W := 1;
end;

function Expi( const X_:Double ) :TDoubleCP1;
begin
     Result.Z := TDoubleC.Create( System.Cos( X_ ), System.Sin( X_ ) );
     Result.W := 1;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Ln

// ln|z| = ln|Z| - ln|W| :正規化済みの成分から直接求まるため
// |z| そのものを作らず、オーバーフローしない。

function Ln( const A_:TSingleCP1 ) :TSingleCP1;
var
   NA, DA :Single;
begin
     if A_.IsInf then Exit( TSingleCP1.Infinity );                   // ln ∞ = ∞

     NA := Hypot( Double( A_.Z.R ), Double( A_.Z.I ) );
     if NA = 0 then Exit( TSingleCP1.Infinity );                     // ln 0 = -∞ → 射影平面の∞

     DA := Hypot( Double( A_.W.R ), Double( A_.W.I ) );

     Result := TSingleCP1.Create( System.Ln( NA ) - System.Ln( DA ),
                                  A_.Angle );
end;

function Ln( const A_:TDoubleCP1 ) :TDoubleCP1;
var
   NA, DA :Double;
begin
     if A_.IsInf then Exit( TDoubleCP1.Infinity );                   // ln ∞ = ∞

     NA := Hypot( Double( A_.Z.R ), Double( A_.Z.I ) );
     if NA = 0 then Exit( TDoubleCP1.Infinity );                     // ln 0 = -∞ → 射影平面の∞

     DA := Hypot( Double( A_.W.R ), Double( A_.W.I ) );

     Result := TDoubleCP1.Create( System.Ln( NA ) - System.Ln( DA ),
                                  A_.Angle );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Cos

// cos(x+iy) = cos x・cosh y - i・sin x・sinh y
// |y| が大きいときは cosh/sinh ≒ e^|y|/2 なので、分母 e^-|y| で斉次化して
// オーバーフローを回避する。

function Cos( const A_:TSingleCP1 ) :TSingleCP1;
var
   X, Y, aY, E :Single;
begin
     if A_.IsInf then Exit( TSingleCP1.Infinity );

     X := A_.Re;
     Y := A_.Im;

     if IsInfinite( X ) or IsInfinite( Y ) then Exit( TSingleCP1.Infinity );  // 方針

     aY := System.Abs( Y );
     if aY > 20 then
     begin
          E := System.Exp( -2 * aY );
          Result.Z := TSingleC.Create(             System.Cos( X ) * ( 1 + E ) * 0.5,
                                       -Sign( Y )* System.Sin( X ) * ( 1 - E ) * 0.5 );
          Result.W := System.Exp( -aY );
     end
     else
     begin
          Result.Z := TSingleC.Create(  System.Cos( X ) * Cosh( Y ),
                                       -System.Sin( X ) * Sinh( Y ) );
          Result.W := 1;
     end;
     Result.Normalize;
end;

function Cos( const A_:TDoubleCP1 ) :TDoubleCP1;
var
   X, Y, aY, E :Double;
begin
     if A_.IsInf then Exit( TDoubleCP1.Infinity );

     X := A_.Re;
     Y := A_.Im;

     if IsInfinite( X ) or IsInfinite( Y ) then Exit( TDoubleCP1.Infinity );  // 方針

     aY := System.Abs( Y );
     if aY > 20 then
     begin
          E := System.Exp( -2 * aY );
          Result.Z := TDoubleC.Create(             System.Cos( X ) * ( 1 + E ) * 0.5,
                                       -Sign( Y )* System.Sin( X ) * ( 1 - E ) * 0.5 );
          Result.W := System.Exp( -aY );
     end
     else
     begin
          Result.Z := TDoubleC.Create(  System.Cos( X ) * Cosh( Y ),
                                       -System.Sin( X ) * Sinh( Y ) );
          Result.W := 1;
     end;
     Result.Normalize;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Sin

// sin(x+iy) = sin x・cosh y + i・cos x・sinh y (斉次化は Cos と同様)

function Sin( const A_:TSingleCP1 ) :TSingleCP1;
var
   X, Y, aY, E :Single;
begin
     if A_.IsInf then Exit( TSingleCP1.Infinity );

     X := A_.Re;
     Y := A_.Im;

     if IsInfinite( X ) or IsInfinite( Y ) then Exit( TSingleCP1.Infinity );  // 方針

     aY := System.Abs( Y );
     if aY > 20 then
     begin
          E := System.Exp( -2 * aY );
          Result.Z := TSingleC.Create(            System.Sin( X ) * ( 1 + E ) * 0.5,
                                       Sign( Y )* System.Cos( X ) * ( 1 - E ) * 0.5 );
          Result.W := System.Exp( -aY );
     end
     else
     begin
          Result.Z := TSingleC.Create( System.Sin( X ) * Cosh( Y ),
                                       System.Cos( X ) * Sinh( Y ) );
          Result.W := 1;
     end;
     Result.Normalize;
end;

function Sin( const A_:TDoubleCP1 ) :TDoubleCP1;
var
   X, Y, aY, E :Double;
begin
     if A_.IsInf then Exit( TDoubleCP1.Infinity );

     X := A_.Re;
     Y := A_.Im;

     if IsInfinite( X ) or IsInfinite( Y ) then Exit( TDoubleCP1.Infinity );  // 方針

     aY := System.Abs( Y );
     if aY > 20 then
     begin
          E := System.Exp( -2 * aY );
          Result.Z := TDoubleC.Create(            System.Sin( X ) * ( 1 + E ) * 0.5,
                                       Sign( Y )* System.Cos( X ) * ( 1 - E ) * 0.5 );
          Result.W := System.Exp( -aY );
     end
     else
     begin
          Result.Z := TDoubleC.Create( System.Sin( X ) * Cosh( Y ),
                                       System.Cos( X ) * Sinh( Y ) );
          Result.W := 1;
     end;
     Result.Normalize;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Tan

// tan = sin / cos。CP¹ の除算なので cos = 0 の極は自然に無限遠点となる。

function Tan( const A_:TSingleCP1 ) :TSingleCP1;
begin
     Result := Sin( A_ ) / Cos( A_ );
end;

function Tan( const A_:TDoubleCP1 ) :TDoubleCP1;
begin
     Result := Sin( A_ ) / Cos( A_ );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ArcSin

// arcsin z = -i・ln( iz + √( 1 - z² ) )  :すべて CP¹ 演算で閉じる。

function ArcSin( const X_:TSingleCP1 ) :TSingleCP1;
var
   U :TSingleCP1;
begin
     if X_.IsInf then Exit( TSingleCP1.Infinity );

     U := TSingleCP1.Create( 0, 1 ) * X_ + Roo2( TSingleCP1.Create( 1 ) - Pow2( X_ ) );

     Result := TSingleCP1.Create( 0, -1 ) * Ln( U );
end;

function ArcSin( const X_:TDoubleCP1 ) :TDoubleCP1;
var
   U :TDoubleCP1;
begin
     if X_.IsInf then Exit( TDoubleCP1.Infinity );

     U := TDoubleCP1.Create( 0, 1 ) * X_ + Roo2( TDoubleCP1.Create( 1 ) - Pow2( X_ ) );

     Result := TDoubleCP1.Create( 0, -1 ) * Ln( U );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ArcCos

// arccos z = π/2 - arcsin z

function ArcCos( const X_:TSingleCP1 ) :TSingleCP1;
begin
     if X_.IsInf then Exit( TSingleCP1.Infinity );
     Result := -TSingleCP1.Imaginary * Ln( X_ + TSingleCP1.Imaginary * Roo2( 1 - X_ * X_ ) );
end;

function ArcCos( const X_:TDoubleCP1 ) :TDoubleCP1;
begin
     if X_.IsInf then Exit( TDoubleCP1.Infinity );
     Result := -TDoubleCP1.Imaginary * Ln( X_ + TDoubleCP1.Imaginary * Roo2( 1 - X_ * X_ ) );
end;

end. //######################################################################### ■
