unit LUX.Data.List;

interface //#################################################################### ■

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【型】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TNodeProc<_INode_>

     TListObject   = class;
       TListParent = class;
       TListChildr = class;

     TNodeProc<_TNode_:class> = reference to procedure( const Node_:_TNode_ );

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListObject

     TListObject = class
     private
     protected
       _Prev :TListChildr;
       _Next :TListChildr;
       ///// アクセス
       function GetPrev :TListChildr;
       function GetNext :TListChildr;
     public
       constructor Create; overload; virtual;
       ///// プロパティ
       property Prev :TListChildr read GetPrev;
       property Next :TListChildr read GetNext;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParent

     TListParent = class( TListObject )
     private
       ///// アクセス
       function Get_Zero :TListChildr;
       procedure Set_Zero( const Zero_:TListChildr );
       function Get_Links( const I_:Integer ) :TListChildr;
       procedure Set_Links( const I_:Integer; const Link_:TListChildr );
       function Get_LinksN :Integer;
       procedure Set_LinksN( const LinksN_:Integer );
     protected
       FLinks    :TArray<TListChildr>;
       _ChildrsN :Integer;
       _MaxOrder :Integer;
       ///// アクセス
       function GetHead :TListChildr;
       function GetTail :TListChildr;
       function GetChildrs( const I_:Integer ) :TListChildr;
       procedure SetChildrs( const I_:Integer; const Child_:TListChildr );
       function GetChildrsN :Integer;
       ///// プロパティ
       property _Zero                      :TListChildr read Get_Zero   write Set_Zero  ;
       property _Links[ const I_:Integer ] :TListChildr read Get_Links  write Set_Links ;
       property _LinksN                    :Integer     read Get_LinksN write Set_LinksN;
       ///// メソッド
       procedure FindTo( const Childr_:TListChildr ); overload;
       procedure FindTo( const Order_:Integer   ); overload;
       class procedure Bind( const C0_,C1_:TListChildr ); overload; inline;
       class procedure Bind( const C0_,C1_,C2_:TListChildr ); overload; inline;
       class procedure Bind( const C0_,C1_,C2_,C3_:TListChildr ); overload; inline;
       procedure _Insert( const C0_,C1_,C2_:TListChildr );
       procedure _InsertHead( const Childr_:TListChildr );
       procedure _InsertTail( const Childr_:TListChildr );
       ///// イベント
       procedure OnInsertChild( const Childr_:TListChildr ); virtual;
       procedure OnRemoveChild( const Childr_:TListChildr ); virtual;
     public
       constructor Create; overload; override;
       destructor Destroy; override;
       ///// プロパティ
       property Head                        :TListChildr read GetHead                     ;
       property Tail                        :TListChildr read GetTail                     ;
       property Childrs[ const I_:Integer ] :TListChildr read GetChildrs  write SetChildrs; default;
       property ChildrsN                    :Integer     read GetChildrsN                 ;
       ///// メソッド
       procedure Clear; virtual;
       procedure InsertHead( const Childr_:TListChildr );
       procedure InsertTail( const Childr_:TListChildr );
       class procedure Swap( const C1_,C2_:TListChildr ); overload;
       procedure Swap( const I1_,I2_:Integer ); overload;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListChildr

     TListChildr = class( TListObject )
     private
       ///// アクセス
       function GetIsOrdered :Boolean;
     protected
       _Parent :TListParent;
       _Order  :Integer;
       ///// プロパティ
       property IsOrdered :Boolean read GetIsOrdered;
       ///// アクセス
       function GetParent :TListParent; virtual;
       procedure SetParent( const Parent_:TListParent ); virtual;
       function GetOrder :Integer; virtual;
       procedure SetOrder( const Order_:Integer ); virtual;
       ///// メソッド
       procedure _Remove;
     public
       constructor Create; overload; override;
       constructor Create( const Parent_:TListParent ); overload; virtual;
       destructor Destroy; override;
       ///// プロパティ
       property Parent :TListParent read GetParent write SetParent;
       property Order  :Integer     read GetOrder  write SetOrder ;
       ///// メソッド
       procedure Remove;
       procedure InsertPrev( const Siblin_:TListChildr );
       procedure InsertNext( const Siblin_:TListChildr );
     end;

//const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【定数】

//var //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【変数】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListObject

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TListObject.GetPrev :TListChildr;
begin
     Result := _Prev;
end;

function TListObject.GetNext :TListChildr;
begin
     Result := _Next;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TListObject.Create;
begin
     inherited;

     _Prev := TListChildr( Self );
     _Next := TListChildr( Self );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParent

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

/////////////////////////////////////////////////////////////////////// アクセス

function TListParent.Get_Zero :TListChildr;
begin
     Result := _Links[ -1 ];
end;

procedure TListParent.Set_Zero( const Zero_:TListChildr );
begin
     _Links[ -1 ] := Zero_;
end;

function TListParent.Get_Links( const I_:Integer ) :TListChildr;
begin
     Result := FLinks[ 1 + I_ ];
end;

procedure TListParent.Set_Links( const I_:Integer; const Link_:TListChildr );
begin
     FLinks[ 1 + I_ ] := Link_;
end;

function TListParent.Get_LinksN :Integer;
begin
     Result := Length( FLinks ) - 1;
end;

procedure TListParent.Set_LinksN( const LinksN_:Integer );
begin
     SetLength( FLinks, 1 + LinksN_ );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TListParent.GetHead :TListChildr;
begin
     Result := _Zero._Next;
end;

function TListParent.GetTail :TListChildr;
begin
     Result := _Zero._Prev;
end;

//------------------------------------------------------------------------------

function TListParent.GetChildrs( const I_:Integer ) :TListChildr;
begin
     if I_ > _MaxOrder then FindTo( I_ );

     Result := _Links[ I_ ];
end;

procedure TListParent.SetChildrs( const I_:Integer; const Child_:TListChildr );
var
   S :TListChildr;
begin
     with Childrs[ I_ ] do
     begin
          S := Childrs[ I_ ]._Prev;

          Remove;
     end;

     S.InsertNext( Child_ );
end;

function TListParent.GetChildrsN :Integer;
begin
     Result := _ChildrsN;
end;

/////////////////////////////////////////////////////////////////////// メソッド

procedure TListParent.FindTo( const Childr_:TListChildr );
var
   P :TListChildr;
begin
     if _ChildrsN > _LinksN then _LinksN := _ChildrsN;

     P := _Links[ _MaxOrder ];

     repeat
           P := P._Next;

           Inc( _MaxOrder );

           _Links[ _MaxOrder ] := P;  P._Order := _MaxOrder;

     until P = Childr_;
end;

procedure TListParent.FindTo( const Order_:Integer );
var
   P :TListChildr;
   I :Integer;
begin
     if _ChildrsN > _LinksN then _LinksN := _ChildrsN;

     P := _Links[ _MaxOrder ];

     for I := _MaxOrder + 1 to Order_ do
     begin
           P := P._Next;

           _Links[ I ] := P;  P._Order := I;
     end;

     _MaxOrder := Order_;
end;

//------------------------------------------------------------------------------

class procedure TListParent.Bind( const C0_,C1_:TListChildr );
begin
     C0_._Next := C1_;
     C1_._Prev := C0_;
end;

class procedure TListParent.Bind( const C0_,C1_,C2_:TListChildr );
begin
     Bind( C0_, C1_ );
     Bind( C1_, C2_ );
end;

class procedure TListParent.Bind( const C0_,C1_,C2_,C3_:TListChildr );
begin
     Bind( C0_, C1_ );
     Bind( C1_, C2_ );
     Bind( C2_, C3_ );
end;

//------------------------------------------------------------------------------

procedure TListParent._Insert( const C0_,C1_,C2_:TListChildr );
begin
     C1_._Parent := Self;

     Bind( C0_, C1_, C2_ );

     Inc( _ChildrsN );

     OnInsertChild( C1_ );
end;

procedure TListParent._InsertHead( const Childr_:TListChildr );
begin
     _Insert( _Zero, Childr_, Head );

     _MaxOrder := -1;
end;

procedure TListParent._InsertTail( const Childr_:TListChildr );
begin
     _Insert( Tail, Childr_, _Zero );
end;

/////////////////////////////////////////////////////////////////////// イベント

procedure TListParent.OnInsertChild( const Childr_:TListChildr );
begin

end;

procedure TListParent.OnRemoveChild( const Childr_:TListChildr );
begin

end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TListParent.Create;
begin
     inherited;

     _ChildrsN := 0;
     _LinksN   := 0;
     _Zero     := TListChildr( Self );
     _MaxOrder := -1;
end;

destructor TListParent.Destroy;
begin
     Clear;

     inherited;
end;

/////////////////////////////////////////////////////////////////////// メソッド

procedure TListParent.Clear;
var
   N :Integer;
begin
     for N := 1 to _ChildrsN do _Zero._Prev.Free;
end;

//------------------------------------------------------------------------------

procedure TListParent.InsertHead( const Childr_:TListChildr );
begin
     Childr_.Remove;  _InsertHead( Childr_ );
end;

procedure TListParent.InsertTail( const Childr_:TListChildr );
begin
     Childr_.Remove;  _InsertTail( Childr_ );
end;

//------------------------------------------------------------------------------

class procedure TListParent.Swap( const C1_,C2_:TListChildr );
var
   P1, P2 :TListParent;
   C1n, C1u,
   C2n, C2u :TListChildr;
   B1, B2 :Boolean;
   I1, I2 :Integer;
begin
     with C1_ do
     begin
          P1 := _Parent   ;
          B1 :=  IsOrdered;
          I1 := _Order    ;

          C1n := _Prev;
          C1u := _Next;
     end;

     with C2_ do
     begin
          P2 := _Parent   ;
          B2 :=  IsOrdered;
          I2 := _Order    ;

          C2n := _Prev;
          C2u := _Next;
     end;

     C1_._Parent := P2;
     C2_._Parent := P1;

     if C1_ = C2n then Bind( C1n, C2_, C1_, C2u )
     else
     if C1_ = C2u then Bind( C2n, C1_, C2_, C1u )
     else
     begin
          Bind( C1n, C2_, C1u );
          Bind( C2n, C1_, C2u );
     end;

     if B1 then
     begin
          P1._Links[ I1 ] := C2_;  C2_._Order := I1;
     end;

     if B2 then
     begin
          P2._Links[ I2 ] := C1_;  C1_._Order := I2;
     end;
end;

procedure TListParent.Swap( const I1_,I2_:Integer );
begin
     Swap( Childrs[ I1_ ], Childrs[ I2_ ] );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListChildr

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

/////////////////////////////////////////////////////////////////////// アクセス

function TListChildr.GetIsOrdered :Boolean;
begin
     Result := ( _Order <= _Parent._MaxOrder ) and ( _Parent._Links[ _Order ] = Self );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TListChildr.GetParent :TListParent;
begin
     Result := _Parent;
end;

procedure TListChildr.SetParent( const Parent_:TListParent );
begin
     Remove;

     if Assigned( Parent_ ) then Parent_._InsertTail( Self );
end;

//------------------------------------------------------------------------------

function TListChildr.GetOrder :Integer;
begin
     if not IsOrdered then _Parent.FindTo( Self );

     Result := _Order;
end;

procedure TListChildr.SetOrder( const Order_:Integer );
begin
     TListParent.Swap( Self, _Parent.Childrs[ Order_ ] );
end;

/////////////////////////////////////////////////////////////////////// メソッド

procedure TListChildr._Remove;
begin
     TListParent.Bind( _Prev, _Next );

     if IsOrdered then _Parent._MaxOrder := _Order - 1;

     with _Parent do
     begin
          Dec( _ChildrsN );

          if _ChildrsN * 2 < _LinksN then _LinksN := _ChildrsN;

          OnRemoveChild( Self );
     end;

     _Parent := nil;
     _Order  := -1;
     _Prev   := Self;
     _Next   := Self;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TListChildr.Create;
begin
     inherited;

     _Parent := nil;
     _Order  := -1;
end;

constructor TListChildr.Create( const Parent_:TListParent );
begin
     Create;

     Parent_._InsertTail( Self );
end;

destructor TListChildr.Destroy;
begin
     Remove;

     inherited;
end;

/////////////////////////////////////////////////////////////////////// メソッド

procedure TListChildr.Remove;
begin
     if Assigned( _Parent ) then _Remove;
end;

//------------------------------------------------------------------------------

procedure TListChildr.InsertPrev( const Siblin_:TListChildr );
begin
     Siblin_.Remove;

     _Parent._Insert( _Prev, Siblin_, Self );

     if IsOrdered then _Parent._MaxOrder := _Order - 1;
end;

procedure TListChildr.InsertNext( const Siblin_:TListChildr );
begin
     Siblin_.Remove;

     _Parent._Insert( Self, Siblin_, _Next );

     if IsOrdered then _Parent._MaxOrder := _Order;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

end. //######################################################################### ■
