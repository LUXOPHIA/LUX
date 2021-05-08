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
     public
       constructor Create( const Ownere_:TTreeNode_ );
       ///// プロパティ
       property Ownere :TTreeNode_ read _Ownere;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeNode<TNode_>

     TTreeNode<TNode_:class> = class( TListParent )
     private
       type TTreeChildr_ = TTreeChildr<TNode_>;
            TTreeNode_   = TTreeNode<TNode_>;
     protected
       _Childr :TTreeChildr_;
       ///// アクセス
       function GetParent :TTreeNode_; virtual;
       procedure SetParent( const Parent_:TTreeNode_ ); virtual;
       function GetHeader :TTreeNode_; reintroduce; virtual;
       function GetTailer :TTreeNode_; reintroduce; virtual;
       function GetChildrs( const I_:Integer ) :TTreeNode_; reintroduce; overload; virtual;
       procedure SetChildrs( const I_:Integer; const Childr_:TTreeNode_ ); reintroduce; overload; virtual;
     public
       constructor Create; override;
       constructor Create( const Parent_:TTreeNode_ ); overload; virtual;
       destructor Destroy; override;
       ///// プロパティ
       property Parent                      :TTreeNode_ read GetParent  write SetParent ;
       property Header                      :TTreeNode_ read GetHeader                  ;
       property Tailer                      :TTreeNode_ read GetTailer                  ;
       property Childrs[ const I_:Integer ] :TTreeNode_ read GetChildrs write SetChildrs; default;
       property Items[ const I_:Integer ]   :TTreeNode_ read GetChildrs write SetChildrs;
       ///// メソッド
       procedure InsertPrev( const Siblin_:TTreeNode_ );
       procedure InsertNext( const Siblin_:TTreeNode_ );
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

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTreeChildr<TNode_>.Create( const Ownere_:TTreeNode_ );
begin
     inherited Create;

     _Ownere := Ownere_;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeNode<TNode_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TTreeNode<TNode_>.GetParent :TTreeNode_;
begin
     Result := TTreeNode_( _Childr.Parent );
end;

procedure TTreeNode<TNode_>.SetParent( const Parent_:TTreeNode_ );
begin
     _Childr.Parent := Parent_;
end;

//------------------------------------------------------------------------------

function TTreeNode<TNode_>.GetHeader :TTreeNode_;
begin
     Result := TTreeChildr_( inherited Header ).Ownere;
end;

function TTreeNode<TNode_>.GetTailer :TTreeNode_;
begin
     Result := TTreeChildr_( inherited Tailer ).Ownere;
end;

function TTreeNode<TNode_>.GetChildrs( const I_:Integer ) :TTreeNode_;
begin
     Result := TTreeChildr_( inherited Childrs[ I_ ] ).Ownere;
end;

procedure TTreeNode<TNode_>.SetChildrs( const I_:Integer; const Childr_:TTreeNode_ );
begin
     inherited Childrs[ I_ ] := Childr_._Childr;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTreeNode<TNode_>.Create;
begin
     inherited;

     _Childr := TTreeChildr_.Create( Self );
end;

constructor TTreeNode<TNode_>.Create( const Parent_:TTreeNode_ );
begin
     Create;

     Parent := Parent_;
end;

destructor TTreeNode<TNode_>.Destroy;
begin
     _Childr.Free;

     inherited;
end;

/////////////////////////////////////////////////////////////////////// メソッド

procedure TTreeNode<TNode_>.InsertPrev( const Siblin_:TTreeNode_ );
begin
     _Childr.InsertPrev( Siblin_._Childr );
end;

procedure TTreeNode<TNode_>.InsertNext( const Siblin_:TTreeNode_ );
begin
     _Childr.InsertNext( Siblin_._Childr );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

end. //######################################################################### ■
