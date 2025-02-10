unit LUX.Data.List;

interface //#################################################################### ■

uses LUX.Data.List.core;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TListChildr<TParent_:class> = class;
     TListParent<TChildr_:class> = class;
     TListEnumer<TChildr_:class> = class;

     TListChildr<TOwnere_,TParent_:class> = class;
     TListParent<TOwnere_,TChildr_:class> = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListChildr<TParent_>

     TListChildr<TParent_:class> = class( TListChildr )
     private
     protected
       ///// A C C E S S O R
       function GetParent :TParent_; reintroduce;
       procedure SetParent( const Parent_:TParent_ ); reintroduce;
     public
       constructor Create( const Parent_:TParent_ ); overload; virtual;
       ///// P R O P E R T Y
       property Parent :TParent_ read GetParent write SetParent;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParent<TChildr_>

     TListParent<TChildr_:class> = class( TListParent )
     private
     protected
       ///// A C C E S S O R
       function GetHeader :TChildr_; reintroduce; virtual;
       function GetTailer :TChildr_; reintroduce; virtual;
       function GetChildrs( const I_:Integer ) :TChildr_; reintroduce; virtual;
       procedure SetChildrs( const I_:Integer; const Childr_:TChildr_ ); reintroduce; virtual;
       ///// E V E N T
       procedure OnInsertChild( const Childr_:TListChildr ); override;
       procedure OnRemoveChild( const Childr_:TListChildr ); override;
       procedure OnInsertChild( const Childr_:TChildr_ ); overload; virtual;
       procedure OnRemoveChild( const Childr_:TChildr_ ); overload; virtual;
     public
       ///// P R O P E R T Y
       property Header                      :TChildr_ read GetHeader                  ;
       property Tailer                      :TChildr_ read GetTailer                  ;
       property Childrs[ const I_:Integer ] :TChildr_ read GetChildrs write SetChildrs; default;
       property Items[ const I_:Integer ]   :TChildr_ read GetChildrs write SetChildrs;
       ///// M E T H O D
       procedure InsertHead( const Childr_:TChildr_ ); overload;
       procedure InsertTail( const Childr_:TChildr_ ); overload;
       procedure Add( const Childr_:TChildr_ ); overload;
       function GetEnumerator: TListEnumer<TChildr_>;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListEnumer<TChildr_>

     TListEnumer<TChildr_:class> = class( TListEnumer )
     private
     protected
       ///// A C C E S S O R
       function GetCurrent: TChildr_; reintroduce; virtual;
     public
       ///// P R O P E R T Y
       property Current :TChildr_ read GetCurrent;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListChildr<TOwnere_,TParent_>

     TListChildr<TOwnere_,TParent_:class> = class( TListChildr<TParent_> )
     private
     protected
       ///// A C C E S S O R
       function GetOwnere :TOwnere_;
     public
       ///// P R O P E R T Y
       property Ownere :TOwnere_ read GetOwnere;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParent<TOwnere_,TChildr_>

     TListParent<TOwnere_,TChildr_:class> = class( TListParent<TChildr_> )
     private
     protected
       _Ownere :TOwnere_;
       ///// A C C E S S O R
       function GetOwnere :TOwnere_;
     public
       constructor Create; overload; override;
       constructor Create( const Ownere_:TOwnere_ ); overload; virtual;
       ///// P R O P E R T Y
       property Ownere :TOwnere_ read GetOwnere;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListChildr<TParent_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TListChildr<TParent_>.GetParent :TParent_;
begin
     Result := TParent_( inherited Parent );
end;

procedure TListChildr<TParent_>.SetParent( const Parent_:TParent_ );
begin
     inherited Parent := TListParent( Parent_ );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TListChildr<TParent_>.Create( const Parent_:TParent_ );
begin
     inherited Create( TListParent( Parent_ ) );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParent<TChildr_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

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

////////////////////////////////////////////////////////////////////// E V E N T

procedure TListParent<TChildr_>.OnInsertChild( const Childr_:TListChildr );
begin
     OnInsertChild( TChildr_( Childr_ ) );
end;

procedure TListParent<TChildr_>.OnRemoveChild( const Childr_:TListChildr );
begin
     OnRemoveChild( TChildr_( Childr_ ) );
end;

procedure TListParent<TChildr_>.OnInsertChild( const Childr_:TChildr_ );
begin

end;

procedure TListParent<TChildr_>.OnRemoveChild( const Childr_:TChildr_ );
begin

end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TListParent<TChildr_>.InsertHead( const Childr_:TChildr_ );
begin
     inherited InsertHead( TListChildr( Childr_ ) );
end;

procedure TListParent<TChildr_>.InsertTail( const Childr_:TChildr_ );
begin
     inherited InsertTail( TListChildr( Childr_ ) );
end;

procedure TListParent<TChildr_>.Add( const Childr_:TChildr_ );
begin
     inherited Add( TListChildr( Childr_ ) );
end;

//------------------------------------------------------------------------------

function TListParent<TChildr_>.GetEnumerator: TListEnumer<TChildr_>;
begin
     Result := TListEnumer<TChildr_>.Create( Self );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListEnumer<TChildr_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TListEnumer<TChildr_>.GetCurrent: TChildr_;
begin
     Result := TChildr_( inherited Current );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListChildr<TOwnere_,TParent_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TListChildr<TOwnere_,TParent_>.GetOwnere :TOwnere_;
type
    TListChildr_ = TListChildr<TOwnere_,TParent_>;
    TListParent_ = TListParent<TOwnere_,TListChildr_>;
begin
     Result := TListParent_( Parent ).Ownere;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TListParent<TOwnere_,TChildr_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TListParent<TOwnere_,TChildr_>.GetOwnere :TOwnere_;
begin
     Result := _Ownere;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TListParent<TOwnere_,TChildr_>.Create;
begin
     inherited;

     _Ownere := nil;
end;

constructor TListParent<TOwnere_,TChildr_>.Create( const Ownere_:TOwnere_ );
begin
     Create;

     _Ownere := Ownere_;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
