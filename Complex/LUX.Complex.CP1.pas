unit LUX.Complex.CP1;

// 複素射影直線 CP¹(リーマン球面)上の複素数
//
// 複素数 z を斉次座標のペア z = Z / W で保持する。
//   ・W = 0 が唯一の無限遠点。例外的な値ではなく、ただの表現可能な点。
//   ・すべての演算の後に、成分の指数部だけを 2^-E 倍して正規化する。
//     2 の冪による正規化は仮数部に触れないため、丸め誤差が一切生じない。
//   ・その結果、反復計算(z ← z² + c 等)でオーバーフローが原理的に発生しない。
//
// 旧 INFTools / INFComplexTools( C = 1/(x²+1) を直接保存する方式 )の代替。
//   ・旧方式は x を二乗して保存するため実効精度が半減し、|x| < 1E-8 が 0 に潰れた。
//   ・本方式は素の倍精度(53bit)を完全に維持する。
//   ・旧 TDoubleINF.C と同じ意味の値は ReC / ImC プロパティで得られる。
//     ( DCT 彩色の波形 ArcSin( 2C - 1 ) の互換用 )

interface //#################################################################### ■

uses LUX.Complex;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleCP1

     TSingleCP1 = record
     private
       ///// A C C E S S O R
       class function GetZero :TSingleCP1; static;
       class function GetInfinity :TSingleCP1; static;
       //--------
       function GetIsZero :Boolean;
       function GetIsInf :Boolean;
       function GetRe :Single;
       function GetIm :Single;
       function GetReC :Single;
       function GetImC :Single;
       function GetAbs2 :Single;
       function GetAbso :Single;
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
       class property Zero     :TSingleCP1 read GetZero    ;
       class property Infinity :TSingleCP1 read GetInfinity;
       //--------
       property IsZero :Boolean read GetIsZero;
       property IsInf  :Boolean read GetIsInf ;
       property Re     :Single  read GetRe    ;   // Re( Z/W )。無限遠では +∞
       property Im     :Single  read GetIm    ;
       property ReC    :Single  read GetReC   ;   // 1/(Re²+1) ∈ [0,1]。無限遠 = 0
       property ImC    :Single  read GetImC   ;   // 1/(Im²+1) ∈ [0,1]。無限遠 = 0
       property Abs2   :Single  read GetAbs2  ;   // |z|²
       property Abso   :Single  read GetAbso  ;   // |z|
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
       class operator Explicit( const P_:TSingleCP1 ) :TSingleC;   // = Z/W(無限遠は +∞,+∞)
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDoubleCP1

     TDoubleCP1 = record
     private
       ///// A C C E S S O R
       class function GetZero :TDoubleCP1; static;
       class function GetInfinity :TDoubleCP1; static;
       //--------
       function GetIsZero :Boolean;
       function GetIsInf :Boolean;
       function GetRe :Double;
       function GetIm :Double;
       function GetReC :Double;
       function GetImC :Double;
       function GetAbs2 :Double;
       function GetAbso :Double;
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
       class property Zero     :TDoubleCP1 read GetZero    ;
       class property Infinity :TDoubleCP1 read GetInfinity;
       //--------
       property IsZero :Boolean read GetIsZero;
       property IsInf  :Boolean read GetIsInf ;
       property Re     :Double  read GetRe    ;   // Re( Z/W )。無限遠では +∞
       property Im     :Double  read GetIm    ;
       property ReC    :Double  read GetReC   ;   // 1/(Re²+1) ∈ [0,1]。無限遠 = 0
       property ImC    :Double  read GetImC   ;   // 1/(Im²+1) ∈ [0,1]。無限遠 = 0
       property Abs2   :Double  read GetAbs2  ;   // |z|²
       property Abso   :Double  read GetAbso  ;   // |z|
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
       class operator Explicit( const P_:TDoubleCP1 ) :TDoubleC;   // = Z/W(無限遠は +∞,+∞)
       class operator Implicit( const P_:TSingleCP1 ) :TDoubleCP1;
       class operator Implicit( const P_:TDoubleCP1 ) :TSingleCP1;
     end;

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
   A, D2 :Single;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( System.Math.Infinity );

     A := Z.R * W.R + Z.I * W.I;                       // Re( Z・W~ )

     if System.Abs( A ) < D2 * 1E37 then Result := A / D2
                                    else Result := Sign( A ) * System.Math.Infinity;
end;

function TSingleCP1.GetIm :Single;
var
   B, D2 :Single;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( System.Math.Infinity );

     B := Z.I * W.R - Z.R * W.I;                       // Im( Z・W~ )

     if System.Abs( B ) < D2 * 1E37 then Result := B / D2
                                    else Result := Sign( B ) * System.Math.Infinity;
end;

function TSingleCP1.GetReC :Single;
var
   A, D2, M, An, Dn :Single;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( 0 );                         // 無限遠点 → C = 0

     A := Z.R * W.R + Z.I * W.I;                       // Re( Z・W~ ) = Re(z)・|W|²

     M := System.Abs( A );  if D2 > M then M := D2;    // M ≧ 双方 かつ M > 0

     An := A  / M;                                     // |An| ≦ 1
     Dn := D2 / M;                                     //  Dn  ≦ 1、少なくとも一方は 1

     Result := Sqr( Dn ) / ( Sqr( An ) + Sqr( Dn ) );  // = 1 / ( Re(z)² + 1 )
end;

function TSingleCP1.GetImC :Single;
var
   B, D2, M, Bn, Dn :Single;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( 0 );

     B := Z.I * W.R - Z.R * W.I;                       // Im( Z・W~ ) = Im(z)・|W|²

     M := System.Abs( B );  if D2 > M then M := D2;

     Bn := B  / M;
     Dn := D2 / M;

     Result := Sqr( Dn ) / ( Sqr( Bn ) + Sqr( Dn ) );  // = 1 / ( Im(z)² + 1 )
end;

function TSingleCP1.GetAbs2 :Single;
var
   N2, D2 :Single;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( System.Math.Infinity );

     N2 := Z.Abs2;

     if N2 < D2 * 1E37 then Result := N2 / D2
                       else Result := System.Math.Infinity;
end;

function TSingleCP1.GetAbso :Single;
begin
     Result := Sqrt( GetAbs2 );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

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

     Z.R := Ldexp( Z.R, -E );                          // 2 の冪の倍率は仮数部を変えない
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

class operator TSingleCP1.Explicit( const P_:TSingleCP1 ) :TSingleC;
begin
     Result := TSingleC.Create( P_.GetRe, P_.GetIm );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDoubleCP1

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

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
   A, D2 :Double;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( System.Math.Infinity );

     A := Z.R * W.R + Z.I * W.I;                       // Re( Z・W~ )

     if System.Abs( A ) < D2 * 1E307 then Result := A / D2
                                     else Result := Sign( A ) * System.Math.Infinity;
end;

function TDoubleCP1.GetIm :Double;
var
   B, D2 :Double;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( System.Math.Infinity );

     B := Z.I * W.R - Z.R * W.I;                       // Im( Z・W~ )

     if System.Abs( B ) < D2 * 1E307 then Result := B / D2
                                     else Result := Sign( B ) * System.Math.Infinity;
end;

function TDoubleCP1.GetReC :Double;
var
   A, D2, M, An, Dn :Double;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( 0 );                         // 無限遠点 → C = 0

     A := Z.R * W.R + Z.I * W.I;                       // Re( Z・W~ ) = Re(z)・|W|²

     M := System.Abs( A );  if D2 > M then M := D2;    // M ≧ 双方 かつ M > 0

     An := A  / M;                                     // |An| ≦ 1
     Dn := D2 / M;                                     //  Dn  ≦ 1、少なくとも一方は 1

     Result := Sqr( Dn ) / ( Sqr( An ) + Sqr( Dn ) );  // = 1 / ( Re(z)² + 1 )
end;

function TDoubleCP1.GetImC :Double;
var
   B, D2, M, Bn, Dn :Double;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( 0 );

     B := Z.I * W.R - Z.R * W.I;                       // Im( Z・W~ ) = Im(z)・|W|²

     M := System.Abs( B );  if D2 > M then M := D2;

     Bn := B  / M;
     Dn := D2 / M;

     Result := Sqr( Dn ) / ( Sqr( Bn ) + Sqr( Dn ) );  // = 1 / ( Im(z)² + 1 )
end;

function TDoubleCP1.GetAbs2 :Double;
var
   N2, D2 :Double;
begin
     D2 := W.Abs2;
     if D2 = 0 then Exit( System.Math.Infinity );

     N2 := Z.Abs2;

     if N2 < D2 * 1E307 then Result := N2 / D2
                        else Result := System.Math.Infinity;
end;

function TDoubleCP1.GetAbso :Double;
begin
     Result := Sqrt( GetAbs2 );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

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

     Z.R := Ldexp( Z.R, -E );                          // 2 の冪の倍率は仮数部を変えない
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
begin
     if X_.IsInf then Exit( TSingleCP1.Infinity );

     // √( Z/W ) = √( Z・W~ ) / |W|
     Result.Z := LUX.Complex.Roo2( X_.Z * X_.W.Conj );
     Result.W := X_.W.Abso;
     Result.Normalize;
end;

function Roo2( const X_:TDoubleCP1 ) :TDoubleCP1;
begin
     if X_.IsInf then Exit( TDoubleCP1.Infinity );

     // √( Z/W ) = √( Z・W~ ) / |W|
     Result.Z := LUX.Complex.Roo2( X_.Z * X_.W.Conj );
     Result.W := X_.W.Abso;
     Result.Normalize;
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
   ZW :TSingleC;
begin
     if A_.IsInf then Exit( TSingleCP1.Infinity );                   // ln ∞ = ∞

     NA := A_.Z.Abso;
     if NA = 0 then Exit( TSingleCP1.Infinity );                     // ln 0 = -∞ → 射影平面の∞

     DA := A_.W.Abso;

     ZW := A_.Z * A_.W.Conj;

     Result := TSingleCP1.Create( System.Ln( NA ) - System.Ln( DA ),
                                  ArcTan2( ZW.I, ZW.R ) );
end;

function Ln( const A_:TDoubleCP1 ) :TDoubleCP1;
var
   NA, DA :Double;
   ZW :TDoubleC;
begin
     if A_.IsInf then Exit( TDoubleCP1.Infinity );                   // ln ∞ = ∞

     NA := A_.Z.Abso;
     if NA = 0 then Exit( TDoubleCP1.Infinity );                     // ln 0 = -∞ → 射影平面の∞

     DA := A_.W.Abso;

     ZW := A_.Z * A_.W.Conj;

     Result := TDoubleCP1.Create( System.Ln( NA ) - System.Ln( DA ),
                                  ArcTan2( ZW.I, ZW.R ) );
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
     Result := TSingleCP1.Create( Pi / 2 ) - ArcSin( X_ );
end;

function ArcCos( const X_:TDoubleCP1 ) :TDoubleCP1;
begin
     Result := TDoubleCP1.Create( Pi / 2 ) - ArcSin( X_ );
end;

end. //######################################################################### ■
