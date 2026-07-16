unit LUX.Data.Tree;

// 汎用のツリー構造
//
//【ノード】
// ・TTreeRoot<TChildr_>          … 根。親に所属できず、子を持てる。
// ・TTreeKnot<TParent_,TChildr_> … 節。親に所属でき、子も持てる。
// ・TTreeLeaf<TParent_>          … 葉。親に所属でき、子は持てない（子リストの費用を一切払わない）。
// ・すべて TTreeNode の派生であり、TTreeNode として一様に扱える
//   （Parent / Root / Level / Prev / Next / Childrs / for-in / All）。
//
//【型引数】
// ・TParent_ に指定できるのは「子を持てる型」（TTreeStem の派生）だけ。葉を親型にはできない。
// ・TChildr_ には TTreeNode の派生を指定する。制約が class なのは、子に自型を指定する
//   自己再帰型を許すため。TTreeNode 派生以外のノードを挿入すると実行時に ETreeError となる。
//
//【走査】
// ・for C in Node do     … 直下の子を列挙する。先読み方式のため、列挙中の Current の削除は安全。
// ・for N in Node.All do … 部分木全体（自分を含む）を先行順で列挙する。再帰もスタックもヒープ確保も
//   使わない。ただし先読みをしないため、列挙中に木の構造を変更してはならない。
//
//【所有権】
// ・Free は部分木ごと解放する。Remove は切り離すだけで解放しない（外した部分木は呼び出し側の所有）。
// ・Parent への代入は自動移籍（旧親から外れ、新親の末尾へ付く）。
// ・子リストは最初の子が付くときに遅延生成される。
//
//【保護と通知】
// ・木を壊す操作 — 循環（自分の先祖や自分自身を子にする）・TTreeRoot の所属・受け入れ不可の子型 —
//   は ETreeError を送出する（Release ビルドでも有効）。
// ・子の増減は AcceptChild（受け入れ判定）→ ChildAdopted / ChildOrphaned（通知）として親ノードに
//   届く。いずれも override 可。通知の中で子リストを操作しないこと。破棄中の親には通知されない。
// ・List 層由来の低水準操作（InsertPrev / InsertNext）は循環検査と Root の所属検査を通らない。
//   木の操作は本ユニットの API（Add / InsertHead / InsertTail / Parent / Create）で行うこと。

interface //#################################################################### ■

uses System.SysUtils,
     LUX.Data.List.core,
     LUX.Data.List;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TTreeNode    = class;
     TTreeChildrs = class;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ETreeError

     ETreeError = class( Exception );  // 木の不変条件（循環・Root の所属・子型）への違反

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeEnumer

     // 直下の子の列挙子。レコードなのでヒープ割り当てが無い。
     TTreeEnumer = record
     private
       _Childr :TTreeNode;
       _NextCh :TTreeNode;  // 先読み（列挙中の Current 削除を安全にする）
     public
       ///// P R O P E R T Y
       property Current :TTreeNode read _Childr;
       ///// M E T H O D
       function MoveNext :Boolean;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeEnumerAll

     // 部分木を先行順で歩く列挙子（自分を含む）。再帰・スタック・ヒープ割り当てなし。
     // 先読みをしないため、列挙中の木の構造変更は不可。
     TTreeEnumerAll = record
     private
       _Anchor :TTreeNode;
       _Childr :TTreeNode;
     public
       ///// P R O P E R T Y
       property Current :TTreeNode read _Childr;
       ///// M E T H O D
       function MoveNext :Boolean;
       function GetEnumerator :TTreeEnumerAll;  // for-in 対応（自身を返す）
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeNode

     TTreeNode = class( TListChildr )
     private
     protected
       ///// A C C E S S O R
       function GetChildrsRef :TTreeChildrs; virtual;  // 子リスト参照。子を持てるのは TTreeStem 系だけ（既定は nil）
       function GetParent :TTreeNode; reintroduce; inline;
       function GetRoot :TTreeNode;
       function GetLevel :Integer;
       function GetPrev :TTreeNode; reintroduce; inline;
       function GetNext :TTreeNode; reintroduce; inline;
       function GetChildrs( const I_:Integer ) :TTreeNode;
       function GetChildrsN :Integer; inline;
       function GetHeader :TTreeNode; inline;
       function GetTailer :TTreeNode; inline;
       function GetAll :TTreeEnumerAll;
     public
       ///// P R O P E R T Y
       property Parent                      :TTreeNode      read GetParent  ;
       property Root                        :TTreeNode      read GetRoot    ;  // 最上位ノード（どこにも属さなければ自分）
       property Level                       :Integer        read GetLevel   ;  // 深さ（最上位 = 0）
       property Prev                        :TTreeNode      read GetPrev    ;  // 前の兄弟（先頭では nil）
       property Next                        :TTreeNode      read GetNext    ;  // 次の兄弟（末尾では nil）
       property Childrs[ const I_:Integer ] :TTreeNode      read GetChildrs ;
       property ChildrsN                    :Integer        read GetChildrsN;  // Leaf は常に 0
       property Header                      :TTreeNode      read GetHeader  ;  // 先頭の子（無ければ nil）
       property Tailer                      :TTreeNode      read GetTailer  ;  // 末尾の子（無ければ nil）
       property All                         :TTreeEnumerAll read GetAll     ;  // 部分木の先行順列挙（自分を含む）: for N in Node.All do …
       ///// M E T H O D
       function IsUnder( const Node_:TTreeNode ) :Boolean;  // Node_ の部分木に属するか（Node_ 自身も真）
       function GetEnumerator :TTreeEnumer;  // 直下の子を TTreeNode として列挙（Leaf は空の列挙）
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeChildrs

     // 子リスト。挿抜の関所として、受け入れ判定（AcceptChild）と親への通知（ChildAdopted / ChildOrphaned）を行う。
     TTreeChildrs = class( TListParent<TTreeNode,TTreeNode> )
     private
     protected
       ///// E V E N T
       procedure OnInsertChild( const Childr_:TTreeNode ); override;
       procedure OnRemoveChild( const Childr_:TTreeNode ); override;
     public
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeEnumer<TChildr_>

     // 列挙子の型付け層。核のレコードを包んで転送する。
     TTreeEnumer<TChildr_:class> = record
     private
       _Enumer :TTreeEnumer;
       ///// A C C E S S O R
       function GetCurrent :TChildr_; inline;
     public
       ///// P R O P E R T Y
       property Current :TChildr_ read GetCurrent;
       ///// M E T H O D
       function MoveNext :Boolean; inline;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeStem

     // 「子を持てる」能力の基底。子リストの実体はここにあり、最初の子が付くときに遅延生成される。
     TTreeStem = class( TTreeNode )
     private
       _Childrs :TTreeChildrs;  // 子リスト（遅延生成。子を持たない限り nil）
       _Doomed  :Boolean;       // 破棄中（子の増減通知を止める）
       ///// M E T H O D
       function ForceChildrs :TTreeChildrs;  // 子リストを（必要なら生成して）返す
     protected
       ///// A C C E S S O R
       function GetChildrsRef :TTreeChildrs; override;
       ///// E V E N T
       function AcceptChild( const Childr_:TTreeNode ) :Boolean; virtual;  // 子として受け入れるか。override で子の型や状態を制限できる（拒否は ETreeError）
       procedure ChildAdopted( const Childr_:TTreeNode ); virtual;   // 子が付いた直後に呼ばれる。中で子リストを操作しないこと
       procedure ChildOrphaned( const Childr_:TTreeNode ); virtual;  // 子が外れる直前に呼ばれる。中で子リストを操作しないこと（破棄中の親では呼ばれない）
     public
       destructor Destroy; override;  // 部分木ごと解放
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeStem<TChildr_>

     // 子側の型付け層。TTreeRoot と TTreeKnot が共有する。TChildr_ には TTreeNode の派生を指定する。
     // 制約が class なのは、子に自型を指定する自己再帰型を許すため。派生以外の挿入は実行時に ETreeError となる。
     //【実装注意】TChildr_ は class 制約のため TTreeNode とキャスト互換ではない。実装内の相互変換は
     // TObject 経由の二段キャストで行っている。直接キャストに簡略化しないこと。
     TTreeStem<TChildr_:class> = class( TTreeStem )
     private
     protected
       ///// A C C E S S O R
       function GetChildrs( const I_:Integer ) :TChildr_;
       function GetHeader :TChildr_;
       function GetTailer :TChildr_;
       ///// E V E N T
       function AcceptChild( const Childr_:TTreeNode ) :Boolean; override;  // 既定実装: Childr_ is TChildr_
     public
       ///// P R O P E R T Y
       property Childrs[ const I_:Integer ] :TChildr_ read GetChildrs; default;
       property Header                      :TChildr_ read GetHeader ;
       property Tailer                      :TChildr_ read GetTailer ;
       ///// M E T H O D
       procedure InsertHead( const Childr_:TChildr_ );
       procedure InsertTail( const Childr_:TChildr_ );
       procedure Add( const Childr_:TChildr_ );
       procedure Clear;  // 子を部分木ごと全解放する
       function GetEnumerator :TTreeEnumer<TChildr_>;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeRoot<TChildr_>

     // 根。親には所属できず、子を持てる。
     TTreeRoot<TChildr_:class> = class( TTreeStem<TChildr_> )
     private
     protected
       ///// A C C E S S O R
       procedure SetParent( const Parent_:TListParent ); override;  // 所属を禁止する
     public
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeKnot<TParent_,TChildr_>

     // 節。親にも所属でき、子も持てる。親型は「子を持てる型」に限る。
     TTreeKnot<TParent_:TTreeStem;TChildr_:class> = class( TTreeStem<TChildr_> )
     private
     protected
       ///// A C C E S S O R
       function GetParent :TParent_;
       procedure SetParent( const Parent_:TParent_ ); reintroduce;
     public
       constructor Create( const Parent_:TParent_ ); overload; virtual;
       ///// P R O P E R T Y
       property Parent :TParent_ read GetParent write SetParent;  // 代入は自動移籍
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeLeaf<TParent_>

     // 葉。親に所属でき、子は持てない（子リストのフィールド自体を持たない）。
     TTreeLeaf<TParent_:TTreeStem> = class( TTreeNode )
     private
     protected
       ///// A C C E S S O R
       function GetParent :TParent_;
       procedure SetParent( const Parent_:TParent_ ); reintroduce;
     public
       constructor Create( const Parent_:TParent_ ); overload; virtual;
       ///// P R O P E R T Y
       property Parent :TParent_ read GetParent write SetParent;  // 代入は自動移籍
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeEnumer

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

function TTreeEnumer.MoveNext :Boolean;
begin
     _Childr := _NextCh;  // 次要素を先読みしているため、列挙中の削除は Current に対してのみ安全

     Result := Assigned( _Childr );

     if Result then _NextCh := _Childr.Next;  // TTreeNode.Next は末尾で nil
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeEnumerAll

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

function TTreeEnumerAll.MoveNext :Boolean;
var
   N :TTreeNode;
begin
     if not Assigned( _Childr ) then _Childr := _Anchor  // 最初は部分木の頂点（自分）
     else
     begin
          N := _Childr.Header;  // まず子へ降りる

          if not Assigned( N ) then
          begin
               N := _Childr;
               while ( N <> _Anchor ) and not Assigned( N.Next ) do N := N.Parent;  // 右の兄弟が現れるまで上がる

               if N = _Anchor then N := nil  // 頂点まで戻ったら終了
                              else N := N.Next;
          end;

          _Childr := N;
     end;

     Result := Assigned( _Childr );
end;

//------------------------------------------------------------------------------

function TTreeEnumerAll.GetEnumerator :TTreeEnumerAll;
begin
     Result := Self;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeNode

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTreeNode.GetChildrsRef :TTreeChildrs;
begin
     Result := nil;  // 子リストは TTreeStem 系だけが持つ
end;

//------------------------------------------------------------------------------

function TTreeNode.GetParent :TTreeNode;
begin
     if Assigned( _Parent ) then Result := TTreeNode( _Parent.OwnereObject )  // 子リストの持ち主が親ノード
                            else Result := nil;
end;

//------------------------------------------------------------------------------

function TTreeNode.GetRoot :TTreeNode;
var
   P :TTreeNode;
begin
     Result := Self;

     P := GetParent;
     while Assigned( P ) do
     begin
          Result := P;  P := P.GetParent;
     end;
end;

function TTreeNode.GetLevel :Integer;
var
   P :TTreeNode;
begin
     Result := 0;

     P := GetParent;
     while Assigned( P ) do
     begin
          Inc( Result );  P := P.GetParent;
     end;
end;

//------------------------------------------------------------------------------

function TTreeNode.GetPrev :TTreeNode;
begin
     if ( _Parent = nil ) or ( TObject( _Prev ) = TObject( _Parent ) ) then Result := nil  // 端では番兵（親自身）を指すため nil に変換する
                                                                      else Result := TTreeNode( _Prev );
end;

function TTreeNode.GetNext :TTreeNode;
begin
     if ( _Parent = nil ) or ( TObject( _Next ) = TObject( _Parent ) ) then Result := nil  // 端では番兵（親自身）を指すため nil に変換する
                                                                      else Result := TTreeNode( _Next );
end;

//------------------------------------------------------------------------------

function TTreeNode.GetChildrs( const I_:Integer ) :TTreeNode;
var
   C :TTreeChildrs;
begin
     C := GetChildrsRef;

     if not Assigned( C ) then raise EArgumentOutOfRangeException.CreateFmt( 'TTreeNode.Childrs[%d]: 子がありません', [ I_ ] );

     Result := C.Childrs[ I_ ];
end;

function TTreeNode.GetChildrsN :Integer;
var
   C :TTreeChildrs;
begin
     C := GetChildrsRef;

     if Assigned( C ) then Result := C.ChildrsN
                      else Result := 0;
end;

//------------------------------------------------------------------------------

function TTreeNode.GetHeader :TTreeNode;
var
   C :TTreeChildrs;
begin
     C := GetChildrsRef;

     if Assigned( C ) then Result := C.Header
                      else Result := nil;
end;

function TTreeNode.GetTailer :TTreeNode;
var
   C :TTreeChildrs;
begin
     C := GetChildrsRef;

     if Assigned( C ) then Result := C.Tailer
                      else Result := nil;
end;

//------------------------------------------------------------------------------

function TTreeNode.GetAll :TTreeEnumerAll;
begin
     Result._Anchor := Self;
     Result._Childr := nil;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

function TTreeNode.IsUnder( const Node_:TTreeNode ) :Boolean;
var
   N :TTreeNode;
begin
     Result := True;

     N := Self;
     while Assigned( N ) do
     begin
          if N = Node_ then Exit;

          N := N.GetParent;
     end;

     Result := False;
end;

//------------------------------------------------------------------------------

function TTreeNode.GetEnumerator :TTreeEnumer;
begin
     Result._Childr := nil;
     Result._NextCh := GetHeader;  // Leaf・子なしでは nil ＝ 空の列挙
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeChildrs

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

////////////////////////////////////////////////////////////////////// E V E N T

procedure TTreeChildrs.OnInsertChild( const Childr_:TTreeNode );
var
   S :TTreeStem;
begin
     inherited;

     S := TTreeStem( Ownere );  // 子リストの持ち主は必ず TTreeStem（ForceChildrs でしか生成されない）

     if not S.AcceptChild( Childr_ )
     then raise ETreeError.Create( 'TTreeChildrs: この親には所属できない型のノードです' );

     S.ChildAdopted( Childr_ );
end;

procedure TTreeChildrs.OnRemoveChild( const Childr_:TTreeNode );
var
   S :TTreeStem;
begin
     S := TTreeStem( Ownere );

     if not S._Doomed then S.ChildOrphaned( Childr_ );  // 破棄中の親には通知しない

     inherited;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeEnumer<TChildr_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTreeEnumer<TChildr_>.GetCurrent :TChildr_;
begin
     Result := TChildr_( TObject( _Enumer.Current ) );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

function TTreeEnumer<TChildr_>.MoveNext :Boolean;
begin
     Result := _Enumer.MoveNext;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeStem

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

function TTreeStem.ForceChildrs :TTreeChildrs;
begin
     if not Assigned( _Childrs ) then _Childrs := TTreeChildrs.Create( Self );  // 遅延生成（最初の子が付くまで作らない）

     Result := _Childrs;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTreeStem.GetChildrsRef :TTreeChildrs;
begin
     Result := _Childrs;
end;

////////////////////////////////////////////////////////////////////// E V E N T

function TTreeStem.AcceptChild( const Childr_:TTreeNode ) :Boolean;
begin
     Result := True;  // 無型の Stem は何でも受け入れる
end;

procedure TTreeStem.ChildAdopted( const Childr_:TTreeNode );
begin

end;

procedure TTreeStem.ChildOrphaned( const Childr_:TTreeNode );
begin

end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

destructor TTreeStem.Destroy;
begin
     _Doomed := True;  // 以後、子の増減通知（ChildOrphaned）は発しない

     _Childrs.Free;    // 子は所有物なので部分木ごと解放される（nil なら何もしない）

     inherited;        // 親から自分を外す
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeStem<TChildr_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTreeStem<TChildr_>.GetChildrs( const I_:Integer ) :TChildr_;
begin
     Result := TChildr_( TObject( inherited GetChildrs( I_ ) ) );
end;

function TTreeStem<TChildr_>.GetHeader :TChildr_;
begin
     Result := TChildr_( TObject( inherited GetHeader ) );
end;

function TTreeStem<TChildr_>.GetTailer :TChildr_;
begin
     Result := TChildr_( TObject( inherited GetTailer ) );
end;

////////////////////////////////////////////////////////////////////// E V E N T

function TTreeStem<TChildr_>.AcceptChild( const Childr_:TTreeNode ) :Boolean;
begin
     Result := Childr_ is TChildr_;  // 宣言した子型の派生だけを受け入れる
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TTreeStem<TChildr_>.InsertHead( const Childr_:TChildr_ );
var
   C :TTreeNode;
begin
     C := TTreeNode( TObject( Childr_ ) );

     if IsUnder( C ) then raise ETreeError.Create( 'TTreeStem.InsertHead: 自分の先祖（または自分自身）を子にはできません' );

     ForceChildrs.InsertHead( C );
end;

procedure TTreeStem<TChildr_>.InsertTail( const Childr_:TChildr_ );
var
   C :TTreeNode;
begin
     C := TTreeNode( TObject( Childr_ ) );

     if IsUnder( C ) then raise ETreeError.Create( 'TTreeStem.InsertTail: 自分の先祖（または自分自身）を子にはできません' );

     ForceChildrs.InsertTail( C );
end;

procedure TTreeStem<TChildr_>.Add( const Childr_:TChildr_ );
var
   C :TTreeNode;
begin
     C := TTreeNode( TObject( Childr_ ) );

     if IsUnder( C ) then raise ETreeError.Create( 'TTreeStem.Add: 自分の先祖（または自分自身）を子にはできません' );

     ForceChildrs.Add( C );
end;

//------------------------------------------------------------------------------

procedure TTreeStem<TChildr_>.Clear;
begin
     if Assigned( _Childrs ) then _Childrs.Clear;
end;

//------------------------------------------------------------------------------

function TTreeStem<TChildr_>.GetEnumerator :TTreeEnumer<TChildr_>;
begin
     Result._Enumer := inherited GetEnumerator;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeRoot<TChildr_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

procedure TTreeRoot<TChildr_>.SetParent( const Parent_:TListParent );
begin
     if Parent_ <> nil then raise ETreeError.Create( 'TTreeRoot: 親には所属できません' );

     inherited;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeKnot<TParent_,TChildr_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTreeKnot<TParent_,TChildr_>.GetParent :TParent_;
begin
     Result := TParent_( inherited GetParent );
end;

procedure TTreeKnot<TParent_,TChildr_>.SetParent( const Parent_:TParent_ );
begin
     if Assigned( Parent_ ) then
     begin
          if Parent_.IsUnder( Self ) then raise ETreeError.Create( 'TTreeKnot.SetParent: 自分の子孫（または自分自身）には所属できません' );
          if not Parent_.AcceptChild( Self ) then raise ETreeError.Create( 'TTreeKnot.SetParent: この親には所属できない型のノードです' );

          inherited SetParent( Parent_.ForceChildrs );  // 旧親から自動で移籍
     end
     else inherited SetParent( nil );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTreeKnot<TParent_,TChildr_>.Create( const Parent_:TParent_ );
begin
     if Assigned( Parent_ ) then inherited Create( Parent_.ForceChildrs )  // 事前検査は不要。挿入時に AcceptChild が検査し、失敗時はコンストラクタ例外で自動的に離脱する
                            else inherited Create;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TTreeLeaf<TParent_>

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

function TTreeLeaf<TParent_>.GetParent :TParent_;
begin
     Result := TParent_( inherited GetParent );
end;

procedure TTreeLeaf<TParent_>.SetParent( const Parent_:TParent_ );
begin
     if Assigned( Parent_ ) then
     begin
          if not Parent_.AcceptChild( Self ) then raise ETreeError.Create( 'TTreeLeaf.SetParent: この親には所属できない型のノードです' );

          inherited SetParent( Parent_.ForceChildrs );  // 旧親から自動で移籍
     end
     else inherited SetParent( nil );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TTreeLeaf<TParent_>.Create( const Parent_:TParent_ );
begin
     if Assigned( Parent_ ) then inherited Create( Parent_.ForceChildrs )  // 事前検査は不要。挿入時に AcceptChild が検査し、失敗時はコンストラクタ例外で自動的に離脱する
                            else inherited Create;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

end. //######################################################################### ■
