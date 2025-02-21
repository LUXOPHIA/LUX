unit LUX.C2.Gamma.FMX.D3;

interface //#################################################################### ■

uses System.SysUtils, System.RTLConsts, System.Classes,
     System.Types, System.UITypes, System.Math.Vectors,
     FMX.Types3D, FMX.Controls3D, FMX.MaterialSources,
     LUX,
     LUX.D1.Diff,
     LUX.D2, LUX.D2.Diff,
     LUX.D3, LUX.D3.Diff,
     LUX.D4x4, LUX.D4x4.Diff,
     LUX.Complex,
     LUX.Complex.Diff,
     LUX.C2.Gamma,
     LUX.C2.Gamma.Diff,
     LUX.FMX.Graphics.D3;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TGamma3D

     TGamma3D = class( TF3DShaper )
     private
       ///// M E T H O D
       function XYtoI( const X_,Y_:Integer ) :Integer; inline;
     protected
       _Polygons :TMeshData;
       _Material :TLightMaterialSource;
       _DivX     :Integer;
       _DivY     :Integer;
       ///// A C C E S S O R
       procedure SetDivX( const DivX_:Integer );
       procedure SetDivY( const DivY_:Integer );
       ///// M E T H O D
       procedure Render; override;
       function TexToPos( const T_:TdDouble2D ) :TdDouble3D;
       procedure MakeGeometry; override;
       procedure MakeTopology; override;
     public
       constructor Create( Owner_:TComponent ); override;
       destructor Destroy; override;
       ///// P R O P E R T Y
       property Material :TLightMaterialSource read   _Material write   _Material;
       property DivX     :Integer              read   _DivX     write SetDivX    ;
       property DivY     :Integer              read   _DivY     write SetDivY    ;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TGamma3D

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

function TGamma3D.XYtoI( const X_,Y_:Integer ) :Integer;
begin
     Result := ( _DivX + 1 ) * Y_ + X_;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

procedure TGamma3D.SetDivX( const DivX_:Integer );
begin
     _DivX := DivX_;

     upGeometry := True;
     upTopology := True;

     Repaint;
end;

procedure TGamma3D.SetDivY( const DivY_:Integer );
begin
     _DivY := DivY_;

     upGeometry := True;
     upTopology := True;

     Repaint;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TGamma3D.Render;
begin
     inherited;

     _Polygons.Render( Context, TMaterialSource.ValidMaterial( _Material ), AbsoluteOpacity );
end;

function TGamma3D.TexToPos( const T_:TdDouble2D ) :TdDouble3D;
var
   C :TdDoubleC;
begin
     C.R := ( +5 - -5 ) * T_.X + -5;
     C.I := ( +5 - -5 ) * T_.Y + -5;

     Result.Y := Gamma( C ).Size;
     Result.X := C.R;
     Result.Z := C.I;
end;

procedure TGamma3D.MakeGeometry;
var
   X, Y, I :Integer;
   T :TDouble2D;
   M :TDoubleM4;
   C :TDoubleC;
   T2 :TPointF;
begin
     with _Polygons.VertexBuffer do
     begin
          Length := ( _DivX + 1 ) * ( _DivY + 1 );

          for Y := 0 to _DivY do
          begin
               T.Y := Y / _DivY;

               for X := 0 to _DivX do
               begin
                    T.X := X / _DivX;

                    M := TexToMatrix( T, TexToPos );

                    I := XYtoI( X, Y );

                    C.R := ( +5 - -5 ) * T.X + -5;
                    C.I := ( +5 - -5 ) * T.Y + -5;

                    C := Gamma( C );

                    C.Size := C.Size / ( 2*Sqrt(Pi) + C.Size );

                    T2.X := 0.5 + C.R / 2;
                    T2.Y := 0.5 + C.I / 2;

                    Vertices [ I ] := M.AxisP;
                    Normals  [ I ] := M.AxisZ;
                    TexCoord0[ I ] := T2;
               end;
          end;
     end;
end;

procedure TGamma3D.MakeTopology;
var
   X, Y, I :Integer;
begin
     with _Polygons.IndexBuffer do
     begin
          Length := 3{Poin} * 2{Face} * _DivX * _DivY;

          I := 0;
          for Y := 0 to _DivY-1 do
          begin
               for X := 0 to _DivX-1 do
               begin
                    //     X0     X1
                    //  Y0 +------+
                    //     |＼    |
                    //     |  ＼  |
                    //     |    ＼|
                    //  Y1 +------+

                    Indices[ I ] := XYtoI( X  , Y   );  Inc( I );
                    Indices[ I ] := XYtoI( X+1, Y   );  Inc( I );
                    Indices[ I ] := XYtoI( X+1, Y+1 );  Inc( I );

                    Indices[ I ] := XYtoI( X+1, Y+1 );  Inc( I );
                    Indices[ I ] := XYtoI( X  , Y+1 );  Inc( I );
                    Indices[ I ] := XYtoI( X  , Y   );  Inc( I );
               end;
          end;
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TGamma3D.Create( Owner_:TComponent );
begin
     inherited;

     _Polygons := TMeshData.Create;

     _Material := TLightMaterialSource.Create( Self );
     _Material.Specular := TAlphaColors.Null;

     DivX := 256;
     DivY := 256;
end;

destructor TGamma3D.Destroy;
begin
     _Polygons.Free;

     inherited;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■