﻿unit LUX.Curve.CatmullRom;

interface //#################################################################### ■

uses LUX.D4,
     LUX.Curve;

//type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function CatmullRom( const t:Single ) :TSingle4D; overload;
function CatmullRom( const t:Double ) :TDouble4D; overload;

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function CatmullRom( const t:Single ) :TSingle4D;
begin
     Result[1] := ( ( -0.5 * t + 1.0 ) * t - 0.5 ) * t      ;
     Result[2] := ( ( +1.5 * t - 2.5 ) * t       ) * t + 1.0;
     Result[3] := ( ( -1.5 * t + 2.0 ) * t + 0.5 ) * t      ;
     Result[4] := ( ( +0.5 * t - 0.5 ) * t       ) * t      ;
end;

function CatmullRom( const t:Double ) :TDouble4D;
begin
     Result[1] := ( ( -0.5 * t + 1.0 ) * t - 0.5 ) * t      ;
     Result[2] := ( ( +1.5 * t - 2.5 ) * t       ) * t + 1.0;
     Result[3] := ( ( -1.5 * t + 2.0 ) * t + 0.5 ) * t      ;
     Result[4] := ( ( +0.5 * t - 0.5 ) * t       ) * t      ;
end;

end. //######################################################################### ■