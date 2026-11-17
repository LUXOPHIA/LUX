unit LUX.FMX.Style;

// 共通のカスタムスタイル（明・暗 1 組）を当てる口と、スタイルの中の色・字を、役の名前で取る口
//
//【構成】
// ・TFmxStyle … 明暗を決めてスタイルを当てる（Dark）。スタイルの中の色（Color）・字（Font）・寸法（Span）を、役の名前で返す。
//
//【前提】
// ・スタイルは、実行ファイルの RCDATA のリソース 2 つ（名前は RES_LIGHT・RES_DARK）。LUX.FMX.Light.style と LUX.FMX.Dark.style を、
//   その名前でリソースに入れる。
// ・色は、スタイルの中の TBrushObject（名前は color.<役>）。字は TFontObject（名前は font.<役>）。寸法は TStyleTag（名前は span.<役>。値は TagFloat）。
//   役の名前は、スタイルの中のオブジェクトの名前（color.〜・font.〜・span.〜）の〜の所。
// ・寸法は、FMX が定義から取らない所（木の一覧の行の高さ ItemHeight など）と、スタイルを読めない所（埋め込みのページ）に、同じ値を渡すために取る。
// ・定義が描く地の色（Ground）は、定義の名前（StyleLookup に書く名前）から引く：その定義の図形の塗りの色（色のオブジェクトを参照していれば、
//   参照の先の色）。フォームの地の定義（backgroundstyle など）が描く色を、スタイルの外（窓が出る前の下塗り）に渡すために取る。
//
//【色の正】
// ・色の正は、スタイルである。ここは色の値を持たず、聞かれるたびにスタイルから引く（明暗を替えた後は、替えた後の値が返る）。
// ・自分で描く部品は、描くときに Color で引くか、スタイルの当て直しのとき（ApplyStyle）に引き直す。値を、明暗をまたいで持ち続けない。
//
//【拡張の方法】
// ・FMX の公開の口だけを使う（TStyleManager.TrySetStyleFromResource・ActiveStyle・FindStyleResource）。

interface //#################################################################### ■

uses System.SysUtils, System.UITypes,
     FMX.Types, FMX.Graphics;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TFmxStyle = class;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TFmxStyle

     // 共通のカスタムスタイルの口
     TFmxStyle = class
     private
       class var _Dark :Boolean;
       class var _Used :Boolean;  // スタイルを当ててある
     protected
       ///// A C C E S S O R
       class procedure SetDark( const Dark_:Boolean ); static;
       ///// M E T H O D
       class function Find( const Name_:String ) :TFmxObject; static;
     public
       ///// P R O P E R T Y
       class property Dark :Boolean read _Dark write SetDark;               // 暗い見た目（替えると、スタイルを当て直す）
       ///// C O N S T A N T
       const RES_LIGHT = 'LUX_FMX_LIGHT';                                   // 明るいスタイルのリソースの名前
       const RES_DARK  = 'LUX_FMX_DARK' ;                                   // 暗いスタイルのリソースの名前
       ///// M E T H O D
       class procedure Apply; static;                                       // 今の明暗のスタイルを当てる（アプリの始めに、フォームを作る前に呼ぶ）
       class function Color( const Role_:String ) :TAlphaColor; static;     // 役の色（スタイルの color.<役>）
       class function Font( const Role_:String ) :TFont; static;            // 役の字（スタイルの font.<役>。スタイルの持ち物なので、書き換えない・持ち続けない）
       class function Span( const Role_:String ) :Single; static;           // 役の寸法（スタイルの span.<役>）
       class function Ground( const Lookup_:String ) :TAlphaColor; static;  // 定義（StyleLookup に書く名前）が描く地の色。定義は、単色で塗る図形であること
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.Classes,
     FMX.Objects, FMX.Styles;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TFmxStyle

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

class procedure TFmxStyle.SetDark( const Dark_:Boolean );
begin
     if _Used and ( Dark_ = _Dark ) then Exit;

     _Dark := Dark_;

     Apply;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

class function TFmxStyle.Find( const Name_:String ) :TFmxObject;
begin
     if not _Used then Apply;  // 当てる前に聞かれたら、今の明暗のスタイルを当ててから答える（既定のスタイルには、役の色が無い）

     Result := TStyleManager.ActiveStyle( nil ).FindStyleResource( Name_ );

     if Result = nil then raise EArgumentException.Create( 'スタイルに、この名前のものが無い：' + Name_ );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

class procedure TFmxStyle.Apply;
var
   N :String;
begin
     if _Dark then N := RES_DARK
              else N := RES_LIGHT;

     // 当てている途中で、FMX は「スタイルが替わった」の知らせ（TStyleChangedMessage）を配り、受けた側が色を聞きに来る（Color）。
     // そのとき「まだ当てていない」と見なして当て直すと、知らせと当て直しが際限なく繰り返されるので、当てる前に「当てた」にする
     // （知らせの時点で、新しいスタイルは、もう TStyleManager に入っている：FMX.Styles の TStyleManager.SetStyle）
     _Used := True;

     if not TStyleManager.TrySetStyleFromResource( N ) then raise EResNotFound.Create( 'スタイルのリソースが、実行ファイルに無い：' + N );
end;

//------------------------------------------------------------------------------

class function TFmxStyle.Color( const Role_:String ) :TAlphaColor;
begin
     Result := ( Find( 'color.' + Role_ ) as TBrushObject ).Brush.Color;
end;

class function TFmxStyle.Font( const Role_:String ) :TFont;
begin
     Result := ( Find( 'font.' + Role_ ) as TFontObject ).Font;
end;

class function TFmxStyle.Span( const Role_:String ) :Single;
begin
     Result := Find( 'span.' + Role_ ).TagFloat;
end;

class function TFmxStyle.Ground( const Lookup_:String ) :TAlphaColor;
var
   O :TFmxObject;
   B :TBrush;
begin
     O := Find( Lookup_ );

     if not ( O is TShape ) then raise EArgumentException.Create( 'スタイルのこの定義は、塗りを持つ図形ではない：' + Lookup_ );

     B := TShape( O ).Fill;

     // 塗りが、色のオブジェクトを参照していれば、参照の先の筆（定義は、色を、役の色のオブジェクトへの参照で持つ）
     if B.Kind = TBrushKind.Resource then B := B.Resource.Brush;

     if ( B = nil ) or ( B.Kind <> TBrushKind.Solid ) then raise EArgumentException.Create( 'スタイルのこの定義は、単色で塗られていない：' + Lookup_ );

     Result := B.Color;
end;

end. //######################################################################### ■
