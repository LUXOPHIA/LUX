unit LUX.Data.Tree;

interface //#################################################################### ■

uses LUX.Data.List.core;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【型】

     TTreeNode = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeChildr

     TTreeChildr = class( TListChildr )
     protected
       _Ownere :TTreeNode;
     public
       constructor Create( const Ownere_:TTreeNode );
       ///// プロパティ
       property Ownere :TTreeNode read _Ownere;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeNode

     TTreeNode = class( TListParent )
     private
     protected
       _Childr :TTreeChildr;
       ///// アクセス
       function GetParent :TTreeNode; virtual;
       procedure SetParent( const Parent_:TTreeNode ); virtual;
       function GetHeader :TTreeNode; reintroduce; virtual;
       function GetTailer :TTreeNode; reintroduce; virtual;
       function GetChildrs( const I_:Integer ) :TTreeNode; reintroduce; overload; virtual;
       procedure SetChildrs( const I_:Integer; const Childr_:TTreeNode ); reintroduce; overload; virtual;
     public
       constructor Create; override;
       constructor Create( const Parent_:TTreeNode ); overload; virtual;
       destructor Destroy; override;
       ///// プロパティ
       property Parent                      :TTreeNode read GetParent  write SetParent ;
       property Header                      :TTreeNode read GetHeader                  ;
       property Tailer                      :TTreeNode read GetTailer                  ;
       property Childrs[ const I_:Integer ] :TTreeNode read GetChildrs write SetChildrs; default;
       property Items[ const I_:Integer ]   :TTreeNode read GetChildrs write SetChildrs;
       ///// メソッド
       procedure InsertPrev( const Siblin_:TTreeNode );
       procedure InsertNext( const Siblin_:TTreeNode );
     end;

//const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【定数】

//var //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【変数】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【レコード】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【クラス】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeChildr

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTreeChildr.Create( const Ownere_:TTreeNode );
begin
     inherited Create;

     _Ownere := Ownere_;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeNode

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

/////////////////////////////////////////////////////////////////////// アクセス

function TTreeNode.GetParent :TTreeNode;
begin
     Result := TTreeNode( _Childr.Parent );
end;

procedure TTreeNode.SetParent( const Parent_:TTreeNode );
begin
     _Childr.Parent := Parent_;
end;

//------------------------------------------------------------------------------

function TTreeNode.GetHeader :TTreeNode;
begin
     Result := TTreeChildr( inherited Header ).Ownere;
end;

function TTreeNode.GetTailer :TTreeNode;
begin
     Result := TTreeChildr( inherited Tailer ).Ownere;
end;

function TTreeNode.GetChildrs( const I_:Integer ) :TTreeNode;
begin
     Result := TTreeChildr( inherited Childrs[ I_ ] ).Ownere;
end;

procedure TTreeNode.SetChildrs( const I_:Integer; const Childr_:TTreeNode );
begin
     inherited Childrs[ I_ ] := Childr_._Childr;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTreeNode.Create;
begin
     inherited;

     _Childr := TTreeChildr.Create( Self );
end;

constructor TTreeNode.Create( const Parent_:TTreeNode );
begin
     Create;

     Parent := Parent_;
end;

destructor TTreeNode.Destroy;
begin
     _Childr.Free;

     inherited;
end;

/////////////////////////////////////////////////////////////////////// メソッド

procedure TTreeNode.InsertPrev( const Siblin_:TTreeNode );
begin
     _Childr.InsertPrev( Siblin_._Childr );
end;

procedure TTreeNode.InsertNext( const Siblin_:TTreeNode );
begin
     _Childr.InsertNext( Siblin_._Childr );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

end. //######################################################################### ■
