unit LUX.Data.Tree;

interface //#################################################################### ■

uses LUX.Data.List.core;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【型】

     TTreeNode<TNode_:class> = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeChildr<TNode_>

     TTreeChildr<TNode_:class> = class( TListChildr )
     private
       type TTreeNode_ = TTreeNode<TNode_>;
     protected
       _Ownere :TTreeNode_;
       ///// アクセス
       function GetOwnere :TNode_;
     public
       constructor Create( const Ownere_:TTreeNode_ );
       ///// プロパティ
       property Ownere :TNode_ read GetOwnere;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeNode<TNode_>

     TTreeNode<TNode_:class> = class( TListParent )
     private
       type TTreeChildr_ = TTreeChildr<TNode_>;
            TTreeNode_   = TTreeNode<TNode_>;
       ///// アクセス
       function Get_Childr :TTreeChildr_; virtual;
     protected
       ///// アクセス
       function GetParent :TNode_; virtual;
       procedure SetParent( const Parent_:TNode_ ); virtual;
       function GetHeader :TNode_; reintroduce; virtual;
       function GetTailer :TNode_; reintroduce; virtual;
       function GetChildrs( const I_:Integer ) :TNode_; reintroduce; overload; virtual;
       procedure SetChildrs( const I_:Integer; const Childr_:TNode_ ); reintroduce; overload; virtual;
       ///// プロパティ
       property _Childr :TTreeChildr_ read Get_Childr;
     public
       constructor Create( const Parent_:TNode_ ); overload; virtual;
       ///// プロパティ
       property Parent                      :TNode_ read GetParent  write SetParent ;
       property Header                      :TNode_ read GetHeader                  ;
       property Tailer                      :TNode_ read GetTailer                  ;
       property Childrs[ const I_:Integer ] :TNode_ read GetChildrs write SetChildrs; default;
       property Items[ const I_:Integer ]   :TNode_ read GetChildrs write SetChildrs;
       ///// メソッド
       procedure InsertPrev( const Siblin_:TNode_ );
       procedure InsertNext( const Siblin_:TNode_ );
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeKnot<TNode_>

     TTreeKnot<TNode_:class> = class( TTreeNode<TNode_> )
       type TTreeChildr_ = TTreeChildr<TNode_>;
     private
       __Childr :TTreeChildr_;
       ///// アクセス
       function Get_Childr :TTreeChildr_; override;
     protected
       ///// プロパティ
       property _Childr :TTreeChildr_ read Get_Childr;
     public
       constructor Create; override;
       destructor Destroy; override;
     end;

//const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【定数】

//var //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【変数】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeChildr<TNode_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TTreeChildr<TNode_>.GetOwnere :TNode_;
begin
     Result := TNode_( _Ownere );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTreeChildr<TNode_>.Create( const Ownere_:TTreeNode_ );
begin
     inherited Create;

     _Ownere := Ownere_;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeNode<TNode_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

/////////////////////////////////////////////////////////////////////// アクセス

function TTreeNode<TNode_>.Get_Childr :TTreeChildr_;
begin
     Result := nil;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TTreeNode<TNode_>.GetParent :TNode_;
begin
     Result := TNode_( _Childr.Parent );
end;

procedure TTreeNode<TNode_>.SetParent( const Parent_:TNode_ );
begin
     _Childr.Parent := TListParent( Parent_ );
end;

//------------------------------------------------------------------------------

function TTreeNode<TNode_>.GetHeader :TNode_;
begin
     Result := TTreeChildr_( inherited Header ).Ownere;
end;

function TTreeNode<TNode_>.GetTailer :TNode_;
begin
     Result := TTreeChildr_( inherited Tailer ).Ownere;
end;

function TTreeNode<TNode_>.GetChildrs( const I_:Integer ) :TNode_;
begin
     Result := TTreeChildr_( inherited Childrs[ I_ ] ).Ownere;
end;

procedure TTreeNode<TNode_>.SetChildrs( const I_:Integer; const Childr_:TNode_ );
begin
     inherited Childrs[ I_ ] := TTreeNode_( Childr_ )._Childr;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTreeNode<TNode_>.Create( const Parent_:TNode_ );
begin
     Create;

     Parent := Parent_;
end;

/////////////////////////////////////////////////////////////////////// メソッド

procedure TTreeNode<TNode_>.InsertPrev( const Siblin_:TNode_ );
begin
     _Childr.InsertPrev( TTreeNode_( Siblin_ )._Childr );
end;

procedure TTreeNode<TNode_>.InsertNext( const Siblin_:TNode_ );
begin
     _Childr.InsertNext( TTreeNode_( Siblin_ )._Childr );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeKnot<TNode_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

/////////////////////////////////////////////////////////////////////// アクセス

function TTreeKnot<TNode_>.Get_Childr :TTreeChildr_;
begin
     Result := __Childr;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTreeKnot<TNode_>.Create;
begin
     inherited;

     __Childr := TTreeChildr_.Create( Self );
end;

destructor TTreeKnot<TNode_>.Destroy;
begin
     __Childr.Free;

     inherited;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

end. //######################################################################### ■
