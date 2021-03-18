unit LUX.Data.List;

interface //#################################################################### ■

uses LUX.Data.List.core;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【型】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TNodeProc<_INode_>

     TListParent<TChildr_:class>           = class;
       TListChildr<TParent_:class>         = class;
     TListParentEnumerator<TChildr_:class> = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParent<TChildr_>

     TListParent<TChildr_:class> = class( TListParent )
     private
     protected
       ///// アクセス
       function GetHeader :TChildr_; reintroduce; virtual;
       function GetTailer :TChildr_; reintroduce; virtual;
       function GetChildrs( const I_:Integer ) :TChildr_; reintroduce; virtual;
       procedure SetChildrs( const I_:Integer; const Childr_:TChildr_ ); reintroduce; virtual;
     public
       ///// プロパティ
       property Header                      :TChildr_ read GetHeader                  ;
       property Tailer                      :TChildr_ read GetTailer                  ;
       property Childrs[ const I_:Integer ] :TChildr_ read GetChildrs write SetChildrs; default;
       ///// メソッド
       function GetEnumerator: TListParentEnumerator<TChildr_>;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListChildr<TParent_>

     TListChildr<TParent_:class> = class( TListChildr )
     private
     protected
       ///// アクセス
       function GetParent :TParent_; reintroduce; virtual;
       procedure SetParent( const Parent_:TParent_ ); reintroduce; virtual;
     public
       ///// プロパティ
       property Parent :TParent_ read GetParent write SetParent;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParentEnumerator<TChildr_>

     TListParentEnumerator<TChildr_:class> = class( TListParentEnumerator )
     private
     protected
       ///// アクセス
       function GetCurrent: TChildr_; reintroduce; virtual;
     public
       ///// プロパティ
       property Current :TChildr_ read GetCurrent;
     end;

//const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【定数】

//var //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【変数】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParent<TChildr_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TListParent<TChildr_>.GetHeader :TChildr_;
begin
     Result := TChildr_( inherited Header );
end;

function TListParent<TChildr_>.GetTailer :TChildr_;
begin
     Result := TChildr_( inherited Tailer );
end;

//------------------------------------------------------------------------------

function TListParent<TChildr_>.GetChildrs( const I_:Integer ) :TChildr_;
begin
     Result := TChildr_( inherited Childrs[ I_ ] );
end;

procedure TListParent<TChildr_>.SetChildrs( const I_:Integer; const Childr_:TChildr_ );
begin
     inherited Childrs[ I_ ] := TListChildr( Childr_ );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

/////////////////////////////////////////////////////////////////////// メソッド

function TListParent<TChildr_>.GetEnumerator: TListParentEnumerator<TChildr_>;
begin
     Result := TListParentEnumerator<TChildr_>.Create( Self );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListChildr<TParent_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TListChildr<TParent_>.GetParent :TParent_;
begin
     Result := TParent_( inherited Parent );
end;

procedure TListChildr<TParent_>.SetParent( const Parent_:TParent_ );
begin
     inherited Parent := TListParent( Parent_ );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParentEnumerator<TChildr_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TListParentEnumerator<TChildr_>.GetCurrent: TChildr_;
begin
     Result := TChildr_( inherited Current );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

end. //######################################################################### ■
