unit LUX.Data.Model.TriFlip;

interface //#################################################################### ■

uses LUX,
     LUX.Data.Model.Poins,
     LUX.Data.Model.Faces;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TTriPoin   <TPos_> = class;
     TTriPoinSet<TPos_> = class;

     TTriFace   <TPos_> = class;
     TTriFaceSet<TPos_> = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TCornIter

     TCornIter<_TPos_> = record
       type TPoin_ = TTriPoin<_TPos_>;
       type TFace_ = TTriFace<_TPos_>;
     private
       _Face :TFace_;
       _Corn :Byte;
       ///// A C C E S S O R
       function GetFlip :TCornIter<_TPos_>;
       procedure SetFlip( Flip_:TCornIter<_TPos_> );
       function GetFacePrev :TCornIter<_TPos_>;
       function GetFaceNext :TCornIter<_TPos_>;
       function GetVertPrev :TCornIter<_TPos_>;
       procedure SetVertPrev( VertPrev_:TCornIter<_TPos_> );
       function GetVertNext :TCornIter<_TPos_>;
       procedure SetVertNext( VertNext_:TCornIter<_TPos_> );
       function GetVert :TPoin_;
     public
       constructor Create( Face_:TFace_; Corn_:Byte );
       ///// P R O P E R T Y
       property Face     :TFace_            read   _Face     write   _Face    ;
       property Corn     :Byte              read   _Corn     write   _Corn    ;
       property Flip     :TCornIter<_TPos_> read GetFlip     write SetFlip    ;
       property FacePrev :TCornIter<_TPos_> read GetFacePrev                  ;
       property FaceNext :TCornIter<_TPos_> read GetFaceNext                  ;
       property VertPrev :TCornIter<_TPos_> read GetVertPrev write SetVertPrev;
       property VertNext :TCornIter<_TPos_> read GetVertNext write SetVertNext;
       property Vert     :TPoin_            read GetVert                      ;
       ///// O P E R A T O R
       class operator Equal( const A_,B_:TCornIter<_TPos_> ) :Boolean;
       class operator NotEqual( const A_,B_:TCornIter<_TPos_> ) :Boolean;
       ///// M E T H O D
       procedure GoFlip;
       procedure GoFacePrev;
       procedure GoFaceNext;
       procedure GoVertPrev;
       procedure GoVertNext;
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTriPoin<TPos_>

     TTriPoin<TPos_> = class( TPoin<TPos_,TTriPoinSet<TPos_>> )
     private
       type TFace_ = TTriFace <TPos_>;
       type TCorn_ = TCornIter<TPos_>;
     protected
       _Face :TFace_;
       _Corn :Byte;
       ///// A C C E S S O R
       function GetFace :TFace_; virtual;
       procedure SetFace( const Face_:TFace_ ); virtual;
       function GetCorn :Byte; virtual;
       procedure SetCorn( const Corn_:Byte ); virtual;
       function GetFacesN :Integer; virtual;
     public
       ///// P R O P E R T Y
       property Face   :TFace_  read GetFace   write SetFace;
       property Corn   :Byte    read GetCorn   write SetCorn;
       property FacesN :Integer read GetFacesN              ;
       ///// M E T H O D
       class function JoinOK( const C1_,C2_:TCorn_ ) :Boolean;
       procedure JoinEdge;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTriPoinSet<TPos_>

     TTriPoinSet<TPos_> = class( TPoinSet<TPos_,TTriPoin<TPos_>> )
     private
     protected
     public
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTriFace<TPos_>

     TTriFace<TPos_> = class( TFace<TPos_,TTriFaceSet<TPos_>> )
     private
       type TPoin_ = TTriPoin <TPos_>;
       type TFace_ = TTriFace <TPos_>;
       type TCorn_ = TCornIter<TPos_>;
     protected
       _Poin :array [ 1..3 ] of TPoin_;
       _Face :array [ 1..3 ] of TFace_;
       _Data :Byte;
       ///// A C C E S S O R
       function GetPoin( const I_:Byte ) :TPoin_; virtual;
       procedure SetPoin( const I_:Byte; const Poin_:TPoin_ ); virtual;
       function GetFace( const I_:Byte ) :TFace_; virtual;
       procedure SetFace( const I_:Byte; const Face_:TFace_ ); virtual;
       function GetCorn( const I_:Byte ) :Byte; virtual;
       procedure SetCorn( const I_,Corn_:Byte ); virtual;
       function GetFlip :Boolean; virtual;
       procedure SetFlip( const Flip_:Boolean ); virtual;
       function GetFlag :Boolean; virtual;
       procedure SetFlag( const Flag_:Boolean ); virtual;
     public
       constructor Create; override;
       destructor Destroy; override;
       ///// P R O P E R T Y
       property Poin[ const I_:Byte ] :TPoin_  read GetPoin write SetPoin;
       property Face[ const I_:Byte ] :TFace_  read GetFace write SetFace;
       property Corn[ const I_:Byte ] :Byte    read GetCorn write SetCorn;
       property Flip                  :Boolean read GetFlip write SetFlip;
       property Flag                  :Boolean read GetFlag write SetFlag;
       ///// M E T H O D
       procedure BasteCorn( const Corn_:Byte );
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTriFaceSet<TPos_>

     TTriFaceSet<TPos_> = class( TFaceSet<TPos_,TTriFace<TPos_>> )
     private
       type TPoin_    = TTriPoin   <TPos_>;
       type TPoinSet_ = TTriPoinSet<TPos_>;
       type TFace_    = TTriFace   <TPos_>;
     protected
       _Poinset :TPoinSet_;
       ///// A C C E S S O R
       function GetPoinset :TPoinSet_; virtual;
       procedure SetPoinset( const Poinset_:TPoinSet_ ); virtual;
     public
       ///// P R O P E R T Y
       property Poinset :TPoinSet_ read GetPoinset write SetPoinset;
       ///// M E T H O D
       function CheckEdges :Integer;
       function CheckFaceLings :Integer;
     end;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      _Inc_ :array [ 1..3 ] of Byte = ( 2, 3, 1 );
      _Dec_ :array [ 1..3 ] of Byte = ( 3, 1, 2 );

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TCornIter<_TPos_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

function TCornIter<_TPos_>.GetFlip :TCornIter<_TPos_>;
begin
     Result.Face := _Face.Face[ _Corn ];
     Result.Corn := _Face.Corn[ _Corn ];
end;

procedure TCornIter<_TPos_>.SetFlip( Flip_:TCornIter<_TPos_> );
begin
     _Face.Face[ _Corn ] := Flip_.Face;
     _Face.Corn[ _Corn ] := Flip_.Corn;
end;

function TCornIter<_TPos_>.GetFacePrev :TCornIter<_TPos_>;
begin
     Result.Face :=        _Face  ;
     Result.Corn := _Dec_[ _Corn ];
end;

function TCornIter<_TPos_>.GetFaceNext :TCornIter<_TPos_>;
begin
     Result.Face :=        _Face  ;
     Result.Corn := _Inc_[ _Corn ];
end;

function TCornIter<_TPos_>.GetVertPrev :TCornIter<_TPos_>;
begin
     Result := FaceNext.Flip;
end;

procedure TCornIter<_TPos_>.SetVertPrev( VertPrev_:TCornIter<_TPos_> );
begin
     FaceNext.Flip := VertPrev_;
end;

function TCornIter<_TPos_>.GetVertNext :TCornIter<_TPos_>;
begin
     Result := Flip.FacePrev;
end;

procedure TCornIter<_TPos_>.SetVertNext( VertNext_:TCornIter<_TPos_> );
begin
     Flip := VertNext_.FaceNext;
end;

function TCornIter<_TPos_>.GetVert :TPoin_;
begin
     Result := _Face.Poin[ _Corn ];
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TCornIter<_TPos_>.Create( Face_:TFace_; Corn_:Byte );
begin
     _Face := Face_;
     _Corn := Corn_;
end;

//////////////////////////////////////////////////////////////// O P E R A T O R

class operator TCornIter<_TPos_>.Equal( const A_,B_:TCornIter<_TPos_> ) :Boolean;
begin
     Result := ( A_.Face = B_.Face ) and ( A_.Corn = B_.Corn )
end;

class operator TCornIter<_TPos_>.NotEqual( const A_,B_:TCornIter<_TPos_> ) :Boolean;
begin
     Result := not ( A_ = B_ );
end;

//////////////////////////////////////////////////////////////// A C C E S S O R

procedure TCornIter<_TPos_>.GoFlip;
var
   F :TCornIter<_TPos_>;
begin
     F.Face := _Face;
     F.Corn := _Corn;

     _Face := F.Face.Face[ F.Corn ];
     _Corn := F.Face.Corn[ F.Corn ];
end;

procedure TCornIter<_TPos_>.GoFacePrev;
begin
     _Corn := _Dec_[ _Corn ];
end;

procedure TCornIter<_TPos_>.GoFaceNext;
begin
     _Corn := _Inc_[ _Corn ];
end;

procedure TCornIter<_TPos_>.GoVertPrev;
begin
     GoFaceNext;
     GoFlip;
end;

procedure TCornIter<_TPos_>.GoVertNext;
begin
     GoFlip;
     GoFacePrev;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTriPoin<TPos_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTriPoin<TPos_>.GetFace :TTriFace<TPos_>;
begin
     Result := _Face;
end;

procedure TTriPoin<TPos_>.SetFace( const Face_:TTriFace<TPos_> );
begin
     _Face := Face_;
end;

function TTriPoin<TPos_>.GetCorn :Byte;
begin
     Result := _Corn;
end;

procedure TTriPoin<TPos_>.SetCorn( const Corn_:Byte );
begin
     _Corn := Corn_;
end;

function TTriPoin<TPos_>.GetFacesN :Integer;
var
   F, F0 :TFace_;
   C, C0 :Byte;
begin
     Result := 0;

     if Face <> nil then
     begin
          F := Face;
          C := _Inc_[ Corn ];

          repeat
                Inc( Result );

                F0 := F;
                C0 := C;

                F :=        F0.Face[ C0 ];
                C := _Dec_[ F0.Corn[ C0 ] ];

          until F = Face;
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

class function TTriPoin<TPos_>.JoinOK( const C1_,C2_:TCorn_ ) :Boolean;
begin
     Result := ( C1_.FaceNext.Vert = C2_.Vert );
end;

procedure TTriPoin<TPos_>.JoinEdge;
var
   T,  C,
   C0, C1,
   P0, P1, P2,
   H0, H1,
   T0, T1,
   S0, S1, S2, S3 :TCorn_;
begin
     T := TCorn_.Create( nil, 0 );

     C := TCorn_.Create( _Face, _Corn ).FaceNext;

     C1 := C;

     repeat
           C0 := C1;  C1 := C0.VertNext;

           if  T.Face = nil then
           begin
                C0.VertNext := C0;

                T := C0;
           end
           else
           begin
                P0 := T;
                P1 := C0;
                P2 := T.VertNext;

                P0.VertNext := P1;  P1.VertNext := P2;

                T0 := P0;  T1 := P1;
                           H0 := P1;  H1 := P2;

                ///// 後方

                S0 := H0;  S1 := H1;
                           S2 := H1;
                repeat
                     S3 := S2.VertNext;

                     if JoinOK( S2, S3 ) then
                     begin
                                     S2 := S3;
                     end
                     else
                     if JoinOK( S2, T1 ) then
                     begin
                          S0.VertNext := S3;  H1 := H0.VertNext;

                          T0.VertNext := S1;  S2.VertNext := T1;

                          T1 := S1;

                          S0 := H0;  S1 := H1;
                                     S2 := H1;
                     end
                     else
                     begin
                          S0 := S2;  S1 := S3;
                                     S2 := S3;
                     end;

                until S3 = T0;

                ///// 前方

                S0 := H0;  S1 := H1;
                           S2 := H1;
                repeat
                      S3 := S2.VertNext;

                      if JoinOK( S2, S3 ) then
                      begin
                                     S2 := S3;
                      end
                      else
                      if JoinOK( H0, S1 ) then
                      begin
                           S0.VertNext := S3;  H1 := H0.VertNext;

                           H0.VertNext := S1;  S2.VertNext := H1;

                           H0 := S2;

                           S0 := H0;  S1 := H1;
                                      S2 := H1;
                      end
                      else
                      begin
                           S0 := S2;  S1 := S3;
                                      S2 := S3;
                      end;

                until S3 = T1;

                T := H0;
           end;
     until C1 = C;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTriPoinSet<TPos_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTriFace<TPos_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTriFace<TPos_>.GetPoin( const I_:Byte ) :TPoin_;
begin
     Result := _Poin[ I_ ];
end;

procedure TTriFace<TPos_>.SetPoin( const I_:Byte; const Poin_:TPoin_ );
begin
     _Poin[ I_ ] := Poin_;
end;

function TTriFace<TPos_>.GetFace( const I_:Byte ) :TTriFace<TPos_>;
begin
     Result := _Face[ I_ ];
end;

procedure TTriFace<TPos_>.SetFace( const I_:Byte; const Face_:TTriFace<TPos_> );
begin
     _Face[ I_ ] := Face_;
end;

function TTriFace<TPos_>.GetCorn( const I_:Byte ) :Byte;
begin
     Result := ( _Data shr ( I_ shl 1 ) ) and 3;
end;

procedure TTriFace<TPos_>.SetCorn( const I_,Corn_:Byte );
var
   I :Integer;
begin
     I := I_ shl 1;

     _Data := ( _Data and ( $FF - ( 3 shl I ) ) ) or ( Corn_ shl I );
end;

function TTriFace<TPos_>.GetFlip :Boolean;
begin
     Result := ( _Data and 1 <> 0 );
end;

procedure TTriFace<TPos_>.SetFlip( const Flip_:Boolean );
begin
     _Data := _Data and ($FF-1);  if Flip_ then _Data := _Data or 1;
end;

function TTriFace<TPos_>.GetFlag :Boolean;
begin
     Result := ( _Data and 2 <> 0 );
end;

procedure TTriFace<TPos_>.SetFlag( const Flag_:Boolean );
begin
     _Data := _Data and ($FF-2);  if Flag_ then _Data := _Data or 2;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTriFace<TPos_>.Create;
begin
     inherited;

     Poin[ 1 ] := nil;
     Poin[ 2 ] := nil;
     Poin[ 3 ] := nil;

     Face[ 1 ] := Self;  Corn[ 1 ] := 2;
     Face[ 2 ] := Self;  Corn[ 2 ] := 3;
     Face[ 3 ] := Self;  Corn[ 3 ] := 1;

     Flip := True;
     Flag := False;
end;

destructor TTriFace<TPos_>.Destroy;
begin

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TTriFace<TPos_>.BasteCorn( const Corn_:Byte );
var
   V :TPoin_;
   C0, C1, C2 :TCorn_;
begin
     V := _Poin[ Corn_ ];

     C1 := TCorn_.Create( Self, Corn_ ).FaceNext;

     if Assigned( V._Face ) then
     begin
          C0 := TCorn_.Create( V._Face, V._Corn ).FaceNext;

          C2 := C0.VertNext;

          C0.VertNext := C1;  C1.VertNext := C2;
     end
     else
     begin
          C1.VertNext := C1;
     end;

     V._Face := Self;
     V._Corn := Corn_;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTriFaceSet<TPos_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTriFaceSet<TPos_>.GetPoinset :TPoinSet_;
begin
     Result := _Poinset;
end;

procedure TTriFaceSet<TPos_>.SetPoinset( const Poinset_:TPoinSet_ );
begin
     _Poinset := Poinset_;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

function TTriFaceSet<TPos_>.CheckEdges :Integer;
var
   I, C0, C1 :Integer;
   F0, F1 :TFace_;
begin
     Result := 0;

     for I := 0 to ChildrsN-1 do
     begin
          F0 := Childrs[ I ];

          for C0 := 1 to 3 do
          begin
               C1 := F0.Corn[ C0 ];

               if C1 > 0 then
               begin
                    F1 := F0.Face[ C0 ];

                    if F1 = nil            then Inc( Result )
                                           else
                    if F1.Face[ C1 ] <> F0 then Inc( Result );
               end
               else Inc( Result );
          end;
     end;
end;

function TTriFaceSet<TPos_>.CheckFaceLings :Integer;
var
   V :TPoin_;
   F0, F, F1 :TFace_;
   I, K, C0, C, C1 :Integer;
begin
     Result := 0;

     for I := 0 to PoinSet.ChildrsN-1 do
     begin
          V := PoinSet.Childrs[ I ];

          F0 :=      V.Face;
          C0 := _Inc_[ V.Corn ];

          F1 := F0;
          C1 := C0;
          for K := 1 to V.FacesN do
          begin
                F := F1;
                C := C1;

                F1 :=        F.Face[ C ];
                C1 := _Dec_[ F.Corn[ C ] ];
          end;

          if F1 <> F0 then Inc( Result );
     end
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
