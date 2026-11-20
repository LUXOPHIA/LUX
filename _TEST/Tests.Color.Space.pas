unit Tests.Color.Space;

// LUX.Color.Space の試験（原色と白色点から作る、線形 RGB → XYZ の行列）
//
// ・行列は、各原色の色度（ x, y, 1 - x - y ）を列に並べ、白が白色点になるように列を伸縮したものである。
// ・XYZ そのものも、原色 ( 1, 0 )・( 0, 1 )・( 0, 0 )、白 ( 1/3, 1/3 ) の色空間として表せる（行列は単位行列になる）。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxColorSpaceTests

     [TestFixture]
     TLuxColorSpaceTests = class
     public
       [Test] procedure SRGBMatrix;
       [Test] procedure WhiteMapsToWhite;
       [Test] procedure XYZAxesGiveIdentity;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Math,
     LUX, LUX.D2, LUX.D3, LUX.D3x3, LUX.Color.Space;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxColorSpaceTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// sRGB の行列は、規格（IEC 61966-2-1）の原色と D65 から決まる、広く知られた値になる
procedure TLuxColorSpaceTests.SRGBMatrix;
const
      E = 1e-7;
begin
     with TLuxColorSpaces.sRGB.ToXYZ do
     begin
          Assert.AreEqual( 0.4123908, _11, E );  Assert.AreEqual( 0.3575843, _12, E );  Assert.AreEqual( 0.1804808, _13, E );
          Assert.AreEqual( 0.2126390, _21, E );  Assert.AreEqual( 0.7151687, _22, E );  Assert.AreEqual( 0.0721923, _23, E );
          Assert.AreEqual( 0.0193308, _31, E );  Assert.AreEqual( 0.1191948, _32, E );  Assert.AreEqual( 0.9505322, _33, E );
     end;
end;

// どの色空間でも、RGB の白 ( 1, 1, 1 ) は、白色点の XYZ（ Y = 1 ）に写る
procedure TLuxColorSpaceTests.WhiteMapsToWhite;
const
      E = 1e-12;
var
   C :TLuxColorSpace;
   W, V :TDouble3D;
begin
     for C in TLuxColorSpaces.Presets do
     begin
          W := LuxXYZ( C.WhiteXY );

          V := C.ToXYZ * TDouble3D.Create( 1, 1, 1 );

          Assert.AreEqual( W.X, V.X, E, C.Name );
          Assert.AreEqual( W.Y, V.Y, E, C.Name );
          Assert.AreEqual( W.Z, V.Z, E, C.Name );
     end;
end;

// XYZ の軸を原色にすると、行列は単位行列になる（ y = 0 の原色でも、0 で割らない）
procedure TLuxColorSpaceTests.XYZAxesGiveIdentity;
const
      E = 1e-15;
var
   M :TDoubleM3;
begin
     M := LuxRGBToXYZ( TDouble2D.Create( 1, 0 ), TDouble2D.Create( 0, 1 ), TDouble2D.Create( 0, 0 ), TDouble2D.Create( 1/3, 1/3 ) );

     with M do
     begin
          Assert.AreEqual( 1.0, _11, E );  Assert.AreEqual( 0.0, _12, E );  Assert.AreEqual( 0.0, _13, E );
          Assert.AreEqual( 0.0, _21, E );  Assert.AreEqual( 1.0, _22, E );  Assert.AreEqual( 0.0, _23, E );
          Assert.AreEqual( 0.0, _31, E );  Assert.AreEqual( 0.0, _32, E );  Assert.AreEqual( 1.0, _33, E );
     end;
end;

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TLuxColorSpaceTests );

end. //######################################################################### ■
