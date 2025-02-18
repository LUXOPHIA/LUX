unit LUX.D2.Diff;

interface //#################################################################### ■

uses LUX,
     LUX.D2,
     LUX.D1.Diff;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TdSingle2D

     TdSingle2D = record
     private
       ///// A C C E S S O R
       function Geto :TSingle2D;
       procedure Seto( const o_:TSingle2D );
       function Getd :TSingle2D;
       procedure Setd( const d_:TSingle2D );
     public
       X :TdSingle;
       Y :TdSingle;
       /////
       constructor Create( const X_,Y_:TdSingle ); overload;
       constructor Create( const o_,d_:TSingle2D ); overload;
       ///// P R O P E R T Y
       property o :TSingle2D read Geto write Seto;
       property d :TSingle2D read Getd write Setd;
       ///// O P E R A T O R
       class operator Positive( const V_:TdSingle2D ) :TdSingle2D;
       class operator Negative( const V_:TdSingle2D ) :TdSingle2D;
       class operator Add( const A_,B_:TdSingle2D ) :TdSingle2D;
       class operator Subtract( const A_,B_:TdSingle2D ) :TdSingle2D;
       class operator Multiply( const A_:TdSingle; const B_:TdSingle2D ) :TdSingle2D;
       class operator Multiply( const A_:TdSingle2D; const B_:TdSingle ) :TdSingle2D;
       class operator Divide( const A_:TdSingle2D; const B_:TdSingle ) :TdSingle2D;
       ///// C A S T
       class operator Implicit( const V_:Integer ) :TdSingle2D;
       class operator Implicit( const V_:Int64 ) :TdSingle2D;
       class operator Implicit( const V_:Single ) :TdSingle2D;
       class operator Implicit( const V_:TdSingle ) :TdSingle2D;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TdDouble2D

     TdDouble2D = record
     private
       ///// A C C E S S O R
       function Geto :TDouble2D;
       procedure Seto( const o_:TDouble2D );
       function Getd :TDouble2D;
       procedure Setd( const d_:TDouble2D );
     public
       X :TdDouble;
       Y :TdDouble;
       /////
       constructor Create( const X_,Y_:TdDouble ); overload;
       constructor Create( const o_,d_:TDouble2D ); overload;
       ///// P R O P E R T Y
       property o :TDouble2D read Geto write Seto;
       property d :TDouble2D read Getd write Setd;
       ///// O P E R A T O R
       class operator Positive( const V_:TdDouble2D ) :TdDouble2D;
       class operator Negative( const V_:TdDouble2D ) :TdDouble2D;
       class operator Add( const A_,B_:TdDouble2D ) :TdDouble2D;
       class operator Subtract( const A_,B_:TdDouble2D ) :TdDouble2D;
       class operator Multiply( const A_:TdDouble; const B_:TdDouble2D ) :TdDouble2D;
       class operator Multiply( const A_:TdDouble2D; const B_:TdDouble ) :TdDouble2D;
       class operator Divide( const A_:TdDouble2D; const B_:TdDouble ) :TdDouble2D;
       ///// C A S T
       class operator Implicit( const V_:Integer ) :TdDouble2D;
       class operator Implicit( const V_:Int64 ) :TdDouble2D;
       class operator Implicit( const V_:Double ) :TdDouble2D;
       class operator Implicit( const V_:TdDouble ) :TdDouble2D;
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.Math;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TdSingle2D

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TdSingle2D.Geto :TSingle2D;
begin
     Result.X := X.o;
     Result.Y := Y.o;
end;

procedure TdSingle2D.Seto( const o_:TSingle2D );
begin
     X.o := o_.X;
     Y.o := o_.Y;
end;

function TdSingle2D.Getd :TSingle2D;
begin
     Result.X := X.d;
     Result.Y := Y.d;
end;

procedure TdSingle2D.Setd( const d_:TSingle2D );
begin
     X.d := d_.X;
     Y.d := d_.Y;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TdSingle2D.Create( const X_,Y_:TdSingle );
begin
     X := X_;
     Y := Y_;
end;

constructor TdSingle2D.Create( const o_,d_:TSingle2D );
begin
     o := o_;
     d := d_;
end;

//////////////////////////////////////////////////////////////// O P E R A T O R

class operator TdSingle2D.Positive( const V_:TdSingle2D ) :TdSingle2D;
begin
     Result.o := +V_.o;
     Result.d := +V_.d;
end;

class operator TdSingle2D.Negative( const V_:TdSingle2D ) :TdSingle2D;
begin
     Result.o := -V_.o;
     Result.d := -V_.d;
end;

class operator TdSingle2D.Add( const A_,B_:TdSingle2D ) :TdSingle2D;
begin
     Result.o := A_.o + B_.o;
     Result.d := A_.d + B_.d;
end;

class operator TdSingle2D.Subtract( const A_,B_:TdSingle2D ) :TdSingle2D;
begin
     Result.o := A_.o - B_.o;
     Result.d := A_.d - B_.d;
end;

class operator TdSingle2D.Multiply( const A_:TdSingle; const B_:TdSingle2D ) :TdSingle2D;
begin
     Result.X := A_ * B_.X;
     Result.Y := A_ * B_.Y;
end;

class operator TdSingle2D.Multiply( const A_:TdSingle2D; const B_:TdSingle ) :TdSingle2D;
begin
     Result.X := A_.X * B_;
     Result.Y := A_.Y * B_;
end;

class operator TdSingle2D.Divide( const A_:TdSingle2D; const B_:TdSingle ) :TdSingle2D;
begin
     Result.X := A_.X / B_;
     Result.Y := A_.Y / B_;
end;

//////////////////////////////////////////////////////////////////////// C A S T

class operator TdSingle2D.Implicit( const V_:Integer ) :TdSingle2D;
begin
     Result.o := V_;
     Result.d := 0;
end;

class operator TdSingle2D.Implicit( const V_:Int64 ) :TdSingle2D;
begin
     Result.o := V_;
     Result.d := 0;
end;

class operator TdSingle2D.Implicit( const V_:Single ) :TdSingle2D;
begin
     Result.o := V_;
     Result.d := 0;
end;

class operator TdSingle2D.Implicit( const V_:TdSingle ) :TdSingle2D;
begin
     Result.o := V_.o;
     Result.d := V_.d;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TdDouble2D

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TdDouble2D.Geto :TDouble2D;
begin
     Result.X := X.o;
     Result.Y := Y.o;
end;

procedure TdDouble2D.Seto( const o_:TDouble2D );
begin
     X.o := o_.X;
     Y.o := o_.Y;
end;

function TdDouble2D.Getd :TDouble2D;
begin
     Result.X := X.d;
     Result.Y := Y.d;
end;

procedure TdDouble2D.Setd( const d_:TDouble2D );
begin
     X.d := d_.X;
     Y.d := d_.Y;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TdDouble2D.Create( const X_,Y_:TdDouble );
begin
     X := X_;
     Y := Y_;
end;

constructor TdDouble2D.Create( const o_,d_:TDouble2D );
begin
     o := o_;
     d := d_;
end;

//////////////////////////////////////////////////////////////// O P E R A T O R

class operator TdDouble2D.Positive( const V_:TdDouble2D ) :TdDouble2D;
begin
     Result.o := +V_.o;
     Result.d := +V_.d;
end;

class operator TdDouble2D.Negative( const V_:TdDouble2D ) :TdDouble2D;
begin
     Result.o := -V_.o;
     Result.d := -V_.d;
end;

class operator TdDouble2D.Add( const A_,B_:TdDouble2D ) :TdDouble2D;
begin
     Result.o := A_.o + B_.o;
     Result.d := A_.d + B_.d;
end;

class operator TdDouble2D.Subtract( const A_,B_:TdDouble2D ) :TdDouble2D;
begin
     Result.o := A_.o - B_.o;
     Result.d := A_.d - B_.d;
end;

class operator TdDouble2D.Multiply( const A_:TdDouble; const B_:TdDouble2D ) :TdDouble2D;
begin
     Result.X := A_ * B_.X;
     Result.Y := A_ * B_.Y;
end;

class operator TdDouble2D.Multiply( const A_:TdDouble2D; const B_:TdDouble ) :TdDouble2D;
begin
     Result.X := A_.X * B_;
     Result.Y := A_.Y * B_;
end;

class operator TdDouble2D.Divide( const A_:TdDouble2D; const B_:TdDouble ) :TdDouble2D;
begin
     Result.X := A_.X / B_;
     Result.Y := A_.Y / B_;
end;

//////////////////////////////////////////////////////////////////////// C A S T

class operator TdDouble2D.Implicit( const V_:Integer ) :TdDouble2D;
begin
     Result.o := V_;
     Result.d := 0;
end;

class operator TdDouble2D.Implicit( const V_:Int64 ) :TdDouble2D;
begin
     Result.o := V_;
     Result.d := 0;
end;

class operator TdDouble2D.Implicit( const V_:Double ) :TdDouble2D;
begin
     Result.o := V_;
     Result.d := 0;
end;

class operator TdDouble2D.Implicit( const V_:TdDouble ) :TdDouble2D;
begin
     Result.o := V_.o;
     Result.d := V_.d;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
