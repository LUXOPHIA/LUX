unit LUX.Curve.BSpline;

interface //#################################################################### ■

uses LUX,
     LUX.D1,
     LUX.D2,
     LUX.D3,
     LUX.D4;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【型】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TBSInterp
     //
     //  00    01    02    03    04    05    06    07    08    09    10    11
     //  │    │    ┃    ┃    ┃    ┃    ┃    ┃    ┃    ┃    │    │
     //  ○----○----◆----●━━●━━●━━●━━●━━●----◆----○----○
     //  │    │    ┃    ┃    ┃    ┃    ┃    ┃    ┃    ┃    │    │
     // -03   -02   -01    00   +01   +02   +03   +04   +05   +06   +07   +08
     //  │          ┃    ┃                            ┃    ┃          │
     //  │          ┃<１>┃<-----------Curv----------->┃<１>┃          │
     //  │<---FW--->┃<-----------------Vert----------------->┃<---FW--->│
     //  │<-----------------------------Poin----------------------------->│

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TCurve<_TPoin_>

     TCurve<_TPoin_:record> = class
     private
     protected
       _FilterW  :Integer;
       _Poins    :TArray<_TPoin_>;  upPoins :Boolean;
       _CurvMinI :Integer;
       _CurvMaxI :Integer;
       ///// アクセス
       function GetFilterW :Integer; virtual;
       procedure SetFilterW( const FilterW_:Integer ); virtual;
       function GetPoinMinI :Integer; virtual;
       function GetPoinMaxI :Integer; virtual;
       function GetPoins( const I_:Integer ) :_TPoin_;
       procedure SetPoins( const I_:Integer; const Poins_:_TPoin_ );
       function GetCurvMinI :Integer; virtual;
       procedure SetCurvMinI( const CurvMinI_:Integer ); virtual;
       function GetCurvMaxI :Integer; virtual;
       procedure SetCurvMaxI( const CurvMaxI_:Integer ); virtual;
       ///// メソッド
       procedure MakePoins; virtual;
     public
       constructor Create;
       procedure AfterConstruction; override;
       destructor Destroy; override;
       ///// プロパティ
       property FilterW                   :Integer read GetFilterW  write SetFilterW ;
       property PoinMinI                  :Integer read GetPoinMinI                  ;
       property PoinMaxI                  :Integer read GetPoinMaxI                  ;
       property Poins[ const I_:Integer ] :_TPoin_ read GetPoins    write SetPoins   ;
       property CurvMinI                  :Integer read GetCurvMinI write SetCurvMinI;
       property CurvMaxI                  :Integer read GetCurvMaxI write SetCurvMaxI;
       ///// メソッド
       function Curv( const X_:_TPoin_ ) :_TPoin_; virtual; abstract;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TBSCurve4<_TPoin_>

     TBSCurve4<_TPoin_:record> = class( TCurve<_TPoin_> )
     private
     protected
     public
       constructor Create;
       procedure AfterConstruction; override;
       destructor Destroy; override;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleBSCurve4

     TSingleBSCurve4 = class( TBSCurve4<Single> )
     private
     protected
     public
       ///// メソッド
       function Curv( const X_:Single ) :Single; override;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDoubleBSCurve4

     TDoubleBSCurve4 = class( TBSCurve4<Double> )
     private
     protected
     public
       ///// メソッド
       function Curv( const X_:Double ) :Double; override;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TBSInterp<_TPoin_,_TCurve_>

     TBSInterp<_TPoin_:record;_TCurve_:constructor,TBSCurve4<_TPoin_>> = class( TCurve<_TPoin_> )
     private
     protected
       _Curve :TBSCurve4<_TPoin_>;
       _Verts :TArray<_TPoin_>;
       ///// アクセス
       function GetPoinMinI :Integer; override;
       function GetPoinMaxI :Integer; override;
       function GetVertMinI :Integer; virtual;
       function GetVertMaxI :Integer; virtual;
       function GetCurvMinI :Integer; override;
       procedure SetCurvMinI( const CurvMinI_:Integer ); override;
       function GetCurvMaxI :Integer; override;
       procedure SetCurvMaxI( const CurvMaxI_:Integer ); override;
       function GetVerts( const I_:Integer ) :_TPoin_; virtual;
       procedure SetVerts( const I_:Integer; const Verts_:_TPoin_ ); virtual;
       ///// メソッド
       procedure MakePoins; override;
       procedure MakeVerts; virtual; abstract;
     public
       constructor Create;
       procedure AfterConstruction; override;
       destructor Destroy; override;
       ///// プロパティ
       property VertMinI                  :Integer read GetVertMinI;
       property VertMaxI                  :Integer read GetVertMaxI;
       property Verts[ const I_:Integer ] :_TPoin_ read GetVerts   ;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleBSInterp

     TSingleBSInterp = class( TBSInterp<Single,TSingleBSCurve4> )
     private
     protected
       ///// メソッド
       procedure MakeVerts; override;
     public
       ///// メソッド
       function HEFilter3( const X_:Integer ) :Single;
       function HEFilter4( const X_:Integer ) :Single;
       function Curv( const X_:Single ) :Single; override;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDoubleBSInterp

     TDoubleBSInterp = class( TBSInterp<Double,TDoubleBSCurve4> )
     private
     protected
       ///// メソッド
       procedure MakeVerts; override;
     public
       ///// メソッド
       function HEFilter3( const X_:Integer ) :Double;
       function HEFilter4( const X_:Integer ) :Double;
       function Curv( const X_:Double ) :Double; override;
     end;

//const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【定数】

//var //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【変数】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

function BSpline( const T_:Single; const I0,N1:Integer; const Ts_:array of Single ) :Single; overload;
function BSpline( const T_:Double; const I0,N1:Integer; const Ts_:array of Double ) :Double; overload;
function BSpline( const T_:TdSingle; const I0,N1:Integer; const Ts_:array of TdSingle ) :TdSingle; overload;
function BSpline( const T_:TdDouble; const I0,N1:Integer; const Ts_:array of TdDouble ) :TdDouble; overload;

function BSpline3( const X_:Single ) :Single; overload;
function BSpline3( const X_:Double ) :Double; overload;
function BSpline3( const X_:TdSingle ) :TdSingle; overload;
function BSpline3( const X_:TdDouble ) :TdDouble; overload;

function BSpline4( const X_:Single ) :Single; overload;
function BSpline4( const X_:Double ) :Double; overload;
function BSpline4( const X_:TdSingle ) :TdSingle; overload;
function BSpline4( const X_:TdDouble ) :TdDouble; overload;

procedure BSpline3( const T_:Single; out Ws_:TSingle4D ); overload;
procedure BSpline3( const T_:Double; out Ws_:TDouble4D ); overload;
procedure BSpline3( const T_:TdSingle; out Ws_:TdSingle4D ); overload;
procedure BSpline3( const T_:TdDouble; out Ws_:TdDouble4D ); overload;

procedure BSpline4( const T_:Single; out Ws_:TSingle4D ); overload;
procedure BSpline4( const T_:Double; out Ws_:TDouble4D ); overload;
procedure BSpline4( const T_:TdSingle; out Ws_:TdSingle4D ); overload;
procedure BSpline4( const T_:TdDouble; out Ws_:TdDouble4D ); overload;

function BSpline3( const P0_,P1_,P2_,P3_:Single; const T_:Single ) :Single; overload;
function BSpline3( const P0_,P1_,P2_,P3_:Double; const T_:Double ) :Double; overload;
function BSpline3( const P0_,P1_,P2_,P3_:TdSingle; const T_:TdSingle ) :TdSingle; overload;
function BSpline3( const P0_,P1_,P2_,P3_:TdDouble; const T_:TdDouble ) :TdDouble; overload;

function BSpline4( const P0_,P1_,P2_,P3_:Single; const T_:Single ) :Single; overload;
function BSpline4( const P0_,P1_,P2_,P3_:Double; const T_:Double ) :Double; overload;
function BSpline4( const P0_,P1_,P2_,P3_:TdSingle; const T_:TdSingle ) :TdSingle; overload;
function BSpline4( const P0_,P1_,P2_,P3_:TdDouble; const T_:TdDouble ) :TdDouble; overload;

function BSpline4( const Ps_:TSingle4D; const T_:Single ) :Single; overload;
function BSpline4( const Ps_:TDouble4D; const T_:Double ) :Double; overload;
function BSpline4( const Ps_:TdSingle4D; const T_:TdSingle ) :TdSingle; overload;
function BSpline4( const Ps_:TdDouble4D; const T_:TdDouble ) :TdDouble; overload;

implementation //############################################################### ■

uses System.Math,
     LUX.Curve;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TCurve<_TPoin_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TCurve<_TPoin_>.GetFilterW :Integer;
begin
     Result := _FilterW;
end;

procedure TCurve<_TPoin_>.SetFilterW( const FilterW_:Integer );
begin
     _FilterW := FilterW_;  MakePoins;
end;

//------------------------------------------------------------------------------

function TCurve<_TPoin_>.GetPoinMinI :Integer;
begin
     Result := CurvMinI - FilterW;
end;

function TCurve<_TPoin_>.GetPoinMaxI :Integer;
begin
     Result := CurvMaxI + FilterW;
end;

//------------------------------------------------------------------------------

function TCurve<_TPoin_>.GetPoins( const I_:Integer ) :_TPoin_;
begin
     Result := _Poins[ I_ - PoinMinI ];
end;

procedure TCurve<_TPoin_>.SetPoins( const I_:Integer; const Poins_:_TPoin_ );
begin
     _Poins[ I_ - PoinMinI ] := Poins_;  upPoins := True;
end;

//------------------------------------------------------------------------------

function TCurve<_TPoin_>.GetCurvMinI :Integer;
begin
     Result := _CurvMinI;
end;

procedure TCurve<_TPoin_>.SetCurvMinI( const CurvMinI_:Integer );
begin
     _CurvMinI := CurvMinI_;  MakePoins;
end;

function TCurve<_TPoin_>.GetCurvMaxI :Integer;
begin
     Result := _CurvMaxI;
end;

procedure TCurve<_TPoin_>.SetCurvMaxI( const CurvMaxI_:Integer );
begin
     _CurvMaxI := CurvMaxI_;  MakePoins;
end;

/////////////////////////////////////////////////////////////////////// メソッド

procedure TCurve<_TPoin_>.MakePoins;
begin
     SetLength( _Poins, PoinMaxI - PoinMinI + 1 );  upPoins := True;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TCurve<_TPoin_>.Create;
begin
     inherited;

end;

procedure TCurve<_TPoin_>.AfterConstruction;
begin
     inherited;

     FilterW  := 1;

     CurvMinI := 0;
     CurvMaxI := 1;
end;

destructor TCurve<_TPoin_>.Destroy;
begin

     inherited;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TBSCurve4<_TPoin_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TBSCurve4<_TPoin_>.Create;
begin
     inherited;

end;

procedure TBSCurve4<_TPoin_>.AfterConstruction;
begin
     inherited;

     FilterW := 1;
end;

destructor TBSCurve4<_TPoin_>.Destroy;
begin

     inherited;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleBSCurve4

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

/////////////////////////////////////////////////////////////////////// メソッド

function TSingleBSCurve4.Curv( const X_:Single ) :Single;
var
   X0, X1 :Integer;
   Xd :Single;
begin
     X0 := Floor( X_ );  Xd := X_ - X0;  X1 := Ceil( X_ );

     Result := BSpline4( Poins[ X0-1 ],
                         Poins[ X0   ],
                         Poins[ X1   ],
                         Poins[ X1+1 ], Xd );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDoubleBSCurve4

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

/////////////////////////////////////////////////////////////////////// メソッド

function TDoubleBSCurve4.Curv( const X_:Double ) :Double;
var
   X0, X1 :Integer;
   Xd :Double;
begin
     X0 := Floor( X_ );  Xd := X_ - X0;  X1 := Ceil( X_ );

     Result := BSpline4( Poins[ X0-1 ],
                         Poins[ X0   ],
                         Poins[ X1   ],
                         Poins[ X1+1 ], Xd );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TBSInterp<_TPoin_,_TCurve_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TBSInterp<_TPoin_,_TCurve_>.GetPoinMinI :Integer;
begin
     Result := VertMinI - FilterW;
end;

function TBSInterp<_TPoin_,_TCurve_>.GetPoinMaxI :Integer;
begin
     Result := VertMaxI + FilterW;
end;

//------------------------------------------------------------------------------

function TBSInterp<_TPoin_,_TCurve_>.GetVertMinI :Integer;
begin
     Result := CurvMinI - 1;
end;

function TBSInterp<_TPoin_,_TCurve_>.GetVertMaxI :Integer;
begin
     Result := CurvMaxI + 1;
end;

//------------------------------------------------------------------------------

function TBSInterp<_TPoin_,_TCurve_>.GetCurvMinI :Integer;
begin
     Result := _CurvMinI;
end;

procedure TBSInterp<_TPoin_,_TCurve_>.SetCurvMinI( const CurvMinI_:Integer );
begin
     _CurvMinI := CurvMinI_;  MakePoins;
end;

function TBSInterp<_TPoin_,_TCurve_>.GetCurvMaxI :Integer;
begin
     Result := _CurvMaxI;
end;

procedure TBSInterp<_TPoin_,_TCurve_>.SetCurvMaxI( const CurvMaxI_:Integer );
begin
     _CurvMaxI := CurvMaxI_;  MakePoins;
end;

//------------------------------------------------------------------------------

function TBSInterp<_TPoin_,_TCurve_>.GetVerts( const I_:Integer ) :_TPoin_;
begin
     if upPoins then
     begin
          MakeVerts;

          upPoins := False;
     end;

     Result := _Verts[ I_ - VertMinI ];
end;

procedure TBSInterp<_TPoin_,_TCurve_>.SetVerts( const I_:Integer; const Verts_:_TPoin_ );
begin
     _Verts[ I_ - VertMinI ] := Verts_;
end;

/////////////////////////////////////////////////////////////////////// メソッド

procedure TBSInterp<_TPoin_,_TCurve_>.MakePoins;
begin
     inherited;

     SetLength( _Verts, VertMaxI - VertMinI + 1 + 1 );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TBSInterp<_TPoin_,_TCurve_>.Create;
begin
     inherited;

     _Curve := _TCurve_.Create;
end;

procedure TBSInterp<_TPoin_,_TCurve_>.AfterConstruction;
begin
     inherited;

     FilterW := 4;
end;

destructor TBSInterp<_TPoin_,_TCurve_>.Destroy;
begin
     _Curve.Free;

     inherited;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TSingleBSInterp

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// メソッド

procedure TSingleBSInterp.MakeVerts;
var
   I, X :Integer;
   C :Single;
begin
     for I := VertMinI to VertMaxI do
     begin
          C := 0;

          for X := -FilterW to +FilterW do
          begin
               C := C + HEFilter4( X ) * Poins[ I + X ];
          end;

          SetVerts( I, C );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

/////////////////////////////////////////////////////////////////////// メソッド

function TSingleBSInterp.HEFilter3( const X_:Integer ) :Single;
begin
     Result := Sqrt(2) * IntPower( 2*Sqrt(2)-3, Abs( X_ ) );
end;

function TSingleBSInterp.HEFilter4( const X_:Integer ) :Single;
begin
     Result := Sqrt(3) * IntPower( Sqrt(3)-2, Abs( X_ ) );
end;

//------------------------------------------------------------------------------

function TSingleBSInterp.Curv( const X_:Single ) :Single;
var
   Xi :Integer;
   Xd :Single;
begin
     if upPoins then
     begin
          MakeVerts;

          upPoins := False;
     end;

     Xi := Floor( X_ );  Xd := X_ - Xi;

     Result := BSpline4( Verts[ Xi-1 ],
                         Verts[ Xi   ],
                         Verts[ Xi+1 ],
                         Verts[ Xi+2 ], Xd );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TDoubleBSInterp

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// メソッド

procedure TDoubleBSInterp.MakeVerts;
var
   I, X :Integer;
   C :Double;
begin
     for I := VertMinI to VertMaxI do
     begin
          C := 0;

          for X := -FilterW to +FilterW do
          begin
               C := C + HEFilter4( X ) * Poins[ I + X ];
          end;

          SetVerts( I, C );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

/////////////////////////////////////////////////////////////////////// メソッド

function TDoubleBSInterp.HEFilter3( const X_:Integer ) :Double;
begin
     Result := Sqrt(2) * IntPower( 2*Sqrt(2)-3, Abs( X_ ) );
end;

function TDoubleBSInterp.HEFilter4( const X_:Integer ) :Double;
begin
     Result := Sqrt(3) * IntPower( Sqrt(3)-2, Abs( X_ ) );
end;

//------------------------------------------------------------------------------

function TDoubleBSInterp.Curv( const X_:Double ) :Double;
var
   Xi :Integer;
   Xd :Double;
begin
     if upPoins then
     begin
          MakeVerts;

          upPoins := False;
     end;

     Xi := Floor( X_ );  Xd := X_ - Xi;

     Result := BSpline4( Verts[ Xi-1 ],
                         Verts[ Xi   ],
                         Verts[ Xi+1 ],
                         Verts[ Xi+2 ], Xd );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

function BSpline( const T_:Single; const I0,N1:Integer; const Ts_:array of Single ) :Single;
var
   I1, N0 :Integer;
   T0, T1, T2, T3 :Single;
begin
     I1 := I0 + 1;

     T0 := Ts_[ I0      ];
     T2 := Ts_[ I0 + N1 ];
     T1 := Ts_[ I1      ];
     T3 := Ts_[ I1 + N1 ];

     if N1 = 1 then
     begin
          {    I0      I1
             ━╋━━━╋━━━╋━
               T0      T2
               ├─N1─┤
                       T1      T3
                       ├─N1─┤    }

          if ( T_ < T0 ) or ( T3 < T_ ) then Result := 0
          else
          begin
               if T_ < T2 then Result := ( T_ - T0 ) / ( T2 - T0 )
                          else
               if T_ > T1 then Result := ( T3 - T_ ) / ( T3 - T1 )
                          else Result := 1;
          end;
     end
     else
     begin
          {    I0      I1
             ━╋━━━╋━━━╋━━━╋━━━╋━
               T0                      T2
               ├─────N1─────┤
                       T1                      T3
                       ├─────N1─────┤    }

          N0 := N1 - 1;

          Result := 0;

          if T2 > T0 then Result := Result + ( T_ - T0 ) / ( T2 - T0 ) * BSpline( T_, I0, N0, Ts_ );
          if T3 > T1 then Result := Result + ( T3 - T_ ) / ( T3 - T1 ) * BSpline( T_, I1, N0, Ts_ );
     end;
end;

function BSpline( const T_:Double; const I0,N1:Integer; const Ts_:array of Double ) :Double;
var
   I1, N0 :Integer;
   T0, T1, T2, T3 :Double;
begin
     I1 := I0 + 1;

     T0 := Ts_[ I0      ];
     T2 := Ts_[ I0 + N1 ];
     T1 := Ts_[ I1      ];
     T3 := Ts_[ I1 + N1 ];

     if N1 = 1 then
     begin
          {    I0      I1
             ━╋━━━╋━━━╋━
               T0      T2
               ├─N1─┤
                       T1      T3
                       ├─N1─┤    }

          if ( T_ < T0 ) or ( T3 < T_ ) then Result := 0
          else
          begin
               if T_ < T2 then Result := ( T_ - T0 ) / ( T2 - T0 )
                          else
               if T_ > T1 then Result := ( T3 - T_ ) / ( T3 - T1 )
                          else Result := 1;
          end;
     end
     else
     begin
          {    I0      I1
             ━╋━━━╋━━━╋━━━╋━━━╋━
               T0                      T2
               ├─────N1─────┤
                       T1                      T3
                       ├─────N1─────┤    }

          N0 := N1 - 1;

          Result := 0;

          if T2 > T0 then Result := Result + ( T_ - T0 ) / ( T2 - T0 ) * BSpline( T_, I0, N0, Ts_ );
          if T3 > T1 then Result := Result + ( T3 - T_ ) / ( T3 - T1 ) * BSpline( T_, I1, N0, Ts_ );
     end;
end;

function BSpline( const T_:TdSingle; const I0,N1:Integer; const Ts_:array of TdSingle ) :TdSingle;
var
   I1, N0 :Integer;
   T0, T1, T2, T3 :TdSingle;
begin
     I1 := I0 + 1;

     T0 := Ts_[ I0      ];
     T2 := Ts_[ I0 + N1 ];
     T1 := Ts_[ I1      ];
     T3 := Ts_[ I1 + N1 ];

     if N1 = 1 then
     begin
          {    I0      I1
             ━╋━━━╋━━━╋━
               T0      T2
               ├─N1─┤
                       T1      T3
                       ├─N1─┤    }

          if ( T_ < T0 ) or ( T3 < T_ ) then Result := 0
          else
          begin
               if T_ < T2 then Result := ( T_ - T0 ) / ( T2 - T0 )
                          else
               if T_ > T1 then Result := ( T3 - T_ ) / ( T3 - T1 )
                          else Result := 1;
          end;
     end
     else
     begin
          {    I0      I1
             ━╋━━━╋━━━╋━━━╋━━━╋━
               T0                      T2
               ├─────N1─────┤
                       T1                      T3
                       ├─────N1─────┤    }

          N0 := N1 - 1;

          Result := 0;

          if T2 > T0 then Result := Result + ( T_ - T0 ) / ( T2 - T0 ) * BSpline( T_, I0, N0, Ts_ );
          if T3 > T1 then Result := Result + ( T3 - T_ ) / ( T3 - T1 ) * BSpline( T_, I1, N0, Ts_ );
     end;
end;

function BSpline( const T_:TdDouble; const I0,N1:Integer; const Ts_:array of TdDouble ) :TdDouble;
var
   I1, N0 :Integer;
   T0, T1, T2, T3 :TdDouble;
begin
     I1 := I0 + 1;

     T0 := Ts_[ I0      ];
     T2 := Ts_[ I0 + N1 ];
     T1 := Ts_[ I1      ];
     T3 := Ts_[ I1 + N1 ];

     if N1 = 1 then
     begin
          {    I0      I1
             ━╋━━━╋━━━╋━
               T0      T2
               ├─N1─┤
                       T1      T3
                       ├─N1─┤    }

          if ( T_ < T0 ) or ( T3 < T_ ) then Result := 0
          else
          begin
               if T_ < T2 then Result := ( T_ - T0 ) / ( T2 - T0 )
                          else
               if T_ > T1 then Result := ( T3 - T_ ) / ( T3 - T1 )
                          else Result := 1;
          end;
     end
     else
     begin
          {    I0      I1
             ━╋━━━╋━━━╋━━━╋━━━╋━
               T0                      T2
               ├─────N1─────┤
                       T1                      T3
                       ├─────N1─────┤    }

          N0 := N1 - 1;

          Result := 0;

          if T2 > T0 then Result := Result + ( T_ - T0 ) / ( T2 - T0 ) * BSpline( T_, I0, N0, Ts_ );
          if T3 > T1 then Result := Result + ( T3 - T_ ) / ( T3 - T1 ) * BSpline( T_, I1, N0, Ts_ );
     end;
end;

//------------------------------------------------------------------------------

function BSpline3( const X_:Single ) :Single;
var
   X :Single;
begin
     X := Abs( X_ );

     if X < 0.5 then Result := 0.75 - Pow2( X )
                else
     if X < 1.5 then Result := 0.5 * Pow2( X - 1.5 )
                else Result := 0;
end;

function BSpline3( const X_:Double ) :Double;
var
   X :Double;
begin
     X := Abs( X_ );

     if X < 0.5 then Result := 0.75 - Pow2( X )
                else
     if X < 1.5 then Result := 0.5 * Pow2( X - 1.5 )
                else Result := 0;
end;

function BSpline3( const X_:TdSingle ) :TdSingle;
var
   X :TdSingle;
begin
     X := Abso( X_ );

     if X < 0.5 then Result := 0.75 - Pow2( X )
                else
     if X < 1.5 then Result := 0.5 * Pow2( X - 1.5 )
                else Result := 0;
end;

function BSpline3( const X_:TdDouble ) :TdDouble;
var
   X :TdDouble;
begin
     X := Abso( X_ );

     if X < 0.5 then Result := 0.75 - Pow2( X )
                else
     if X < 1.5 then Result := 0.5 * Pow2( X - 1.5 )
                else Result := 0;
end;

//------------------------------------------------------------------------------

function BSpline4( const X_:Single ) :Single;
const
     A :Single = 1/6;
     B :Single = 4/3;
     C :Single = 2/3;
var
   X :Single;
begin
     X := Abs( X_ );

     if X < 1 then Result := ( 0.5 * X - 1 ) * X * X + C
              else
     if X < 2 then Result := ( ( 1 - A * X ) * X - 2 ) * X + B
              else Result := 0;
end;

function BSpline4( const X_:Double ) :Double;
const
     A :Double = 1/6;
     B :Double = 4/3;
     C :Double = 2/3;
var
   X :Double;
begin
     X := Abs( X_ );

     if X < 1 then Result := ( 0.5 * X - 1 ) * X * X + C
              else
     if X < 2 then Result := ( ( 1 - A * X ) * X - 2 ) * X + B
              else Result := 0;
end;

function BSpline4( const X_:TdSingle ) :TdSingle;
const
     A :TdSingle = ( o:1/6; d:0 );
     B :TdSingle = ( o:4/3; d:0 );
     C :TdSingle = ( o:2/3; d:0 );
var
   X :TdSingle;
begin
     X := Abso( X_ );

     if X < 1 then Result := ( X / 2 - 1 ) * X * X + C
              else
     if X < 2 then Result := ( ( 1 - A * X ) * X - 2 ) * X + B
              else Result := 0;
end;

function BSpline4( const X_:TdDouble ) :TdDouble;
const
     A :TdDouble = ( o:1/6; d:0 );
     B :TdDouble = ( o:4/3; d:0 );
     C :TdDouble = ( o:2/3; d:0 );
var
   X :TdDouble;
begin
     X := Abso( X_ );

     if X < 1 then Result := ( X / 2 - 1 ) * X * X + C
              else
     if X < 2 then Result := ( ( 1 - A * X ) * X - 2 ) * X + B
              else Result := 0;
end;

//------------------------------------------------------------------------------

procedure BSpline3( const T_:Single; out Ws_:TSingle4D );
begin
     with Ws_ do
     begin
          _1 := BSpline3( T_ + 1 );
          _2 := BSpline3( T_     );
          _3 := BSpline3( T_ - 1 );
          _4 := BSpline3( T_ - 2 );
     end;
end;

procedure BSpline3( const T_:Double; out Ws_:TDouble4D );
begin
     with Ws_ do
     begin
          _1 := BSpline3( T_ + 1 );
          _2 := BSpline3( T_     );
          _3 := BSpline3( T_ - 1 );
          _4 := BSpline3( T_ - 2 );
     end;
end;

procedure BSpline3( const T_:TdSingle; out Ws_:TdSingle4D );
begin
     with Ws_ do
     begin
          _1 := BSpline3( T_ + 1 );
          _2 := BSpline3( T_     );
          _3 := BSpline3( T_ - 1 );
          _4 := BSpline3( T_ - 2 );
     end;
end;

procedure BSpline3( const T_:TdDouble; out Ws_:TdDouble4D );
begin
     with Ws_ do
     begin
          _1 := BSpline3( T_ + 1 );
          _2 := BSpline3( T_     );
          _3 := BSpline3( T_ - 1 );
          _4 := BSpline3( T_ - 2 );
     end;
end;

//------------------------------------------------------------------------------

procedure BSpline4( const T_:Single; out Ws_:TSingle4D );
begin
     with Ws_ do
     begin
          _1 := BSpline4( T_ + 1 );
          _2 := BSpline4( T_     );
          _3 := BSpline4( T_ - 1 );
          _4 := BSpline4( T_ - 2 );
     end;
end;

procedure BSpline4( const T_:Double; out Ws_:TDouble4D );
begin
     with Ws_ do
     begin
          _1 := BSpline4( T_ + 1 );
          _2 := BSpline4( T_     );
          _3 := BSpline4( T_ - 1 );
          _4 := BSpline4( T_ - 2 );
     end;
end;

procedure BSpline4( const T_:TdSingle; out Ws_:TdSingle4D );
begin
     with Ws_ do
     begin
          _1 := BSpline4( T_ + 1 );
          _2 := BSpline4( T_     );
          _3 := BSpline4( T_ - 1 );
          _4 := BSpline4( T_ - 2 );
     end;
end;

procedure BSpline4( const T_:TdDouble; out Ws_:TdDouble4D );
begin
     with Ws_ do
     begin
          _1 := BSpline4( T_ + 1 );
          _2 := BSpline4( T_     );
          _3 := BSpline4( T_ - 1 );
          _4 := BSpline4( T_ - 2 );
     end;
end;

//------------------------------------------------------------------------------

function BSpline3( const P0_,P1_,P2_,P3_:Single; const T_:Single ) :Single;
var
   Ws :TSingle4D;
begin
     BSpline3( T_, Ws );

     Result := Ws._1 * P0_
             + Ws._2 * P1_
             + Ws._3 * P2_
             + Ws._4 * P3_;
end;

function BSpline3( const P0_,P1_,P2_,P3_:Double; const T_:Double ) :Double;
var
   Ws :TDouble4D;
begin
     BSpline3( T_, Ws );

     Result := Ws._1 * P0_
             + Ws._2 * P1_
             + Ws._3 * P2_
             + Ws._4 * P3_;
end;

function BSpline3( const P0_,P1_,P2_,P3_:TdSingle; const T_:TdSingle ) :TdSingle;
var
   Ws :TdSingle4D;
begin
     BSpline3( T_, Ws );

     Result := Ws._1 * P0_
             + Ws._2 * P1_
             + Ws._3 * P2_
             + Ws._4 * P3_;
end;

function BSpline3( const P0_,P1_,P2_,P3_:TdDouble; const T_:TdDouble ) :TdDouble;
var
   Ws :TdDouble4D;
begin
     BSpline3( T_, Ws );

     Result := Ws._1 * P0_
             + Ws._2 * P1_
             + Ws._3 * P2_
             + Ws._4 * P3_;
end;

//------------------------------------------------------------------------------

function BSpline4( const P0_,P1_,P2_,P3_:Single; const T_:Single ) :Single;
var
   Ws :TSingle4D;
begin
     BSpline4( T_, Ws );

     Result := Ws._1 * P0_
             + Ws._2 * P1_
             + Ws._3 * P2_
             + Ws._4 * P3_;
end;

function BSpline4( const P0_,P1_,P2_,P3_:Double; const T_:Double ) :Double;
var
   Ws :TDouble4D;
begin
     BSpline4( T_, Ws );

     Result := Ws._1 * P0_
             + Ws._2 * P1_
             + Ws._3 * P2_
             + Ws._4 * P3_;
end;

function BSpline4( const P0_,P1_,P2_,P3_:TdSingle; const T_:TdSingle ) :TdSingle;
var
   Ws :TdSingle4D;
begin
     BSpline4( T_, Ws );

     Result := Ws._1 * P0_
             + Ws._2 * P1_
             + Ws._3 * P2_
             + Ws._4 * P3_;
end;

function BSpline4( const P0_,P1_,P2_,P3_:TdDouble; const T_:TdDouble ) :TdDouble;
var
   Ws :TdDouble4D;
begin
     BSpline4( T_, Ws );

     Result := Ws._1 * P0_
             + Ws._2 * P1_
             + Ws._3 * P2_
             + Ws._4 * P3_;
end;

//------------------------------------------------------------------------------

function BSpline4( const Ps_:TSingle4D; const T_:Single ) :Single;
var
   Ws :TSingle4D;
begin
     BSpline4( T_, Ws );

     Result := Ws._1 * Ps_._1
             + Ws._2 * Ps_._2
             + Ws._3 * Ps_._3
             + Ws._4 * Ps_._4;
end;

function BSpline4( const Ps_:TDouble4D; const T_:Double ) :Double;
var
   Ws :TDouble4D;
begin
     BSpline4( T_, Ws );

     Result := Ws._1 * Ps_._1
             + Ws._2 * Ps_._2
             + Ws._3 * Ps_._3
             + Ws._4 * Ps_._4;
end;

function BSpline4( const Ps_:TdSingle4D; const T_:TdSingle ) :TdSingle;
var
   Ws :TdSingle4D;
begin
     BSpline4( T_, Ws );

     Result := Ws._1 * Ps_._1
             + Ws._2 * Ps_._2
             + Ws._3 * Ps_._3
             + Ws._4 * Ps_._4;
end;

function BSpline4( const Ps_:TdDouble4D; const T_:TdDouble ) :TdDouble;
var
   Ws :TdDouble4D;
begin
     BSpline4( T_, Ws );

     Result := Ws._1 * Ps_._1
             + Ws._2 * Ps_._2
             + Ws._3 * Ps_._3
             + Ws._4 * Ps_._4;
end;

//############################################################################## □

initialization //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ 初期化

finalization //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ 最終化

end. //######################################################################### ■