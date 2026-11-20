unit LUX.Data.Codec.Image;

// 画像のコーデック（流れと、画素の並びの間の変換）
//
//【構成する型】
// ・TImageHeader … 画像の形（大きさ・色空間・標本の精度）。
// ・TImageRaster … 画素の置き場への口。入れ物（画像のクラス・配列・GPU の画像など）ごとに派生させる。
// ・TImageCodec  … ファイルの形式。形式ごとに派生させる（PNG・JPEG・Radiance HDR）。
//
//【コーデックと入れ物】
// ・コーデックは、入れ物を知らない。知っているのは TImageRaster だけである。
//   ゆえに、入れ物を足すには TImageRaster の派生を 1 つ、形式を足すには TImageCodec の派生を 1 つ書けばよく、
//   互いを直さない。
// ・画素の通貨は TSingleRGBA だけである。8・16 ビットの整数も、RGBE も、32 ビットの実数で誤差なく表せる。
//
//【画素の並び】
// ・画素は「始点 ( X, Y )・歩み ( DX, DY )・個数 N」の並びで受け渡す。I 番目の画素の位置は
//   ( X + I * DX, Y + I * DY ) である。原点は左上で、X は右向き、Y は下向きである。
// ・上から順の行は、歩み ( 1, 0 ) の並びである。インターレースの飛び飛びの画素も、逆順の行も、
//   縦に進む走査線も、歩みの違う同じ並びなので、コーデックは 1 枚ぶんの一時の領域を持たずに済む。
//
//【復号と符号化の約束】
// ・Decode は、流れの先頭が、その形式の印であることを確かめてから、形式ごとの DoDecode を呼ぶ。
//   DoDecode は、まず Raster.Header を書き（置き場は、ここで大きさと色空間を決める）、
//   その後、どの画素もちょうど 1 回、SetLine で渡す。
// ・Encode は、置き場の大きさが 1 以上であることを確かめてから、形式ごとの DoEncode を呼ぶ。
//   DoEncode は、要る画素を GetLine で取る。
//
//【設定と複製】
// ・形式に固有の設定（PNG の圧縮率・JPEG の品質など）は、派生のプロパティである。
// ・コーデックは、設定のほかに状態を持たない。ゆえに、Clone した写しを別のスレッドで走らせられる。
//
//【形式の選択】
// ・派生のユニットは、initialization で Regist する。選択は、登録された形式だけを見る。
// ・読むときは、中身で選ぶ：ClassOf が、流れの先頭のバイトを、登録された形式の Matches に順に見せる。
//   ゆえに、拡張子が違っていても、無くても、読める。
// ・書くときは、拡張子で選ぶ：ClassFor / CreateFor / DialogFilter。

interface //#################################################################### ■

uses System.SysUtils, System.Classes,
     LUX.Color, LUX.Color.Space;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TImageRaster = class;
     TImageCodec  = class;

     TImageCodecClass = class of TImageCodec;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% EImageCodec

     EImageCodec = class( Exception );  // 形式に合わないデータ・形式が表せない画像

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageHeader

     // 画像の形。Width と Height は 1 以上である。
     TImageHeader = record
     public
       Width      :Integer;         // 画素の数（横）
       Height     :Integer;         // 画素の数（縦）
       ColorSpace :TLuxColorSpace;  // 画素の値の色空間（nil：分からない）。所有しない
       Depth      :Integer;         // 標本 1 つの精度（ビット数）。実数は 32
       /////
       constructor Create( const Width_,Height_:Integer; const ColorSpace_:TLuxColorSpace; const Depth_:Integer );
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageRaster

     // 画素の置き場への口。
     // Header を書くと、置き場は、その大きさと色空間になる（それまでの画素は失われる）。
     // 置き場の標本の精度が決まっているときは、Depth に従わなくてよい。
     TImageRaster = class
     private
     protected
       ///// A C C E S S O R
       function GetHeader :TImageHeader; virtual; abstract;
       procedure SetHeader( const Header_:TImageHeader ); virtual; abstract;
     public
       ///// P R O P E R T Y
       property Header :TImageHeader read GetHeader write SetHeader;
       ///// M E T H O D
       procedure GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); virtual; abstract;  // 並びを読む
       procedure SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); virtual; abstract;  // 並びを書く
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodec

     // ファイルの形式の基底。
     TImageCodec = class
     private
       class var _Codecs :TArray<TImageCodecClass>;
     protected
       ///// M E T H O D
       procedure DoDecode( const Stream_:TStream; const Raster_:TImageRaster ); virtual; abstract;                              // 流れの先頭は、検査済み
       procedure DoEncode( const Stream_:TStream; const Raster_:TImageRaster; const Header_:TImageHeader ); virtual; abstract;  // Header_ は検査済み
     public
       constructor Create; virtual;
       ///// C L A S S
       class function Extensions :TArray<String>; virtual; abstract;                    // 拡張子（小文字・点つき）。先頭が既定
       class function Caption :String; virtual; abstract;                               // 形式の名前
       class function Handles( const FileName_:String ) :Boolean;                       // この形式の拡張子か
       class function Matches( const Bytes_:TBytes ) :Boolean; virtual; abstract;       // 流れの先頭のバイトが、この形式の印か
       class procedure Regist( const Codec_:TImageCodecClass );
       class function Codecs :TArray<TImageCodecClass>;                                 // 登録された形式（登録の順）
       class function ClassOf( const Stream_:TStream ) :TImageCodecClass;               // 中身の形式（無ければ nil）。流れの位置は変えない
       class function ClassFor( const FileName_:String ) :TImageCodecClass;             // 拡張子の形式（無ければ nil）
       class function CreateFor( const FileName_:String ) :TImageCodec;                 // 拡張子の形式を、既定の設定で作る（無ければ nil）
       class function DialogFilter( const Caption_:String = '' ) :String;               // ダイアログの Filter。Caption_ があれば、全形式をまとめた項目を先頭に置く
       ///// M E T H O D
       procedure Assign( const Codec_:TImageCodec ); virtual;                           // 設定を写す
       function Clone :TImageCodec;                                                     // 同じ設定の写し
       procedure Decode( const Stream_:TStream; const Raster_:TImageRaster ); virtual;  // 流れ → 置き場
       procedure Encode( const Stream_:TStream; const Raster_:TImageRaster ); virtual;  // 置き場 → 流れ
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      HEAD_SIZE = 8;  // 形式の印を見るために読む、流れの先頭のバイト数（最も長い印は、PNG の 8 バイト）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

// 流れの先頭の HEAD_SIZE バイト（足りなければ、あるだけ）。流れの位置は、元に戻す。

function HeadOf( const Stream_:TStream ) :TBytes;
var
   N :Integer;
begin
     SetLength( Result, HEAD_SIZE );

     N := Stream_.Read( Result[ 0 ], HEAD_SIZE );

     Stream_.Seek( -N, soCurrent );

     SetLength( Result, N );
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageHeader

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TImageHeader.Create( const Width_,Height_:Integer; const ColorSpace_:TLuxColorSpace; const Depth_:Integer );
begin
     Width      := Width_     ;
     Height     := Height_    ;
     ColorSpace := ColorSpace_;
     Depth      := Depth_     ;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TImageCodec

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TImageCodec.Create;
begin
     inherited;

end;

//////////////////////////////////////////////////////////////////////// C L A S S

class function TImageCodec.Handles( const FileName_:String ) :Boolean;
var
   E, X :String;
begin
     E := LowerCase( ExtractFileExt( FileName_ ) );

     for X in Extensions do if X = E then Exit( True );

     Result := False;
end;

//------------------------------------------------------------------------------

class procedure TImageCodec.Regist( const Codec_:TImageCodecClass );
begin
     _Codecs := _Codecs + [ Codec_ ];
end;

class function TImageCodec.Codecs :TArray<TImageCodecClass>;
begin
     Result := _Codecs;
end;

class function TImageCodec.ClassOf( const Stream_:TStream ) :TImageCodecClass;
var
   H :TBytes;
   C :TImageCodecClass;
begin
     H := HeadOf( Stream_ );

     for C in _Codecs do if C.Matches( H ) then Exit( C );

     Result := nil;
end;

class function TImageCodec.ClassFor( const FileName_:String ) :TImageCodecClass;
var
   C :TImageCodecClass;
begin
     for C in _Codecs do if C.Handles( FileName_ ) then Exit( C );

     Result := nil;
end;

class function TImageCodec.CreateFor( const FileName_:String ) :TImageCodec;
var
   C :TImageCodecClass;
begin
     C := ClassFor( FileName_ );

     if Assigned( C ) then Result := C.Create
                      else Result := nil;
end;

//------------------------------------------------------------------------------

// Filter の項目は「見出し|拡張子の型」であり、項目どうしも | で区切る。

class function TImageCodec.DialogFilter( const Caption_:String = '' ) :String;
//······································
     function Item( const Name_,Masks_:String ) :String;
     begin
          Result := Name_ + ' (' + Masks_ + ')|' + Masks_;
     end;
//······································
var
   C :TImageCodecClass;
   X :String;
   M, Ms :String;
begin
     Result := '';  Ms := '';

     for C in _Codecs do
     begin
          M := '';
          for X in C.Extensions do M := M + ';*' + X;

          Result := Result + '|' + Item( C.Caption, M.Substring( 1 ) );

          Ms := Ms + M;
     end;

     if ( Caption_ <> '' ) and ( Ms <> '' ) then Result := '|' + Item( Caption_, Ms.Substring( 1 ) ) + Result;

     Result := Result.Substring( 1 );
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TImageCodec.Assign( const Codec_:TImageCodec );
begin

end;

function TImageCodec.Clone :TImageCodec;
begin
     Result := TImageCodecClass( ClassType ).Create;

     Result.Assign( Self );
end;

//------------------------------------------------------------------------------

// 流れの先頭の印は、ここで一度だけ検査する。

procedure TImageCodec.Decode( const Stream_:TStream; const Raster_:TImageRaster );
begin
     if not Matches( HeadOf( Stream_ ) ) then raise EImageCodec.CreateFmt( '%s: the stream is not in this format', [ Caption ] );

     DoDecode( Stream_, Raster_ );
end;

// 置き場の形は、ここで一度だけ検査する。派生は、検査済みの形を受け取る。

procedure TImageCodec.Encode( const Stream_:TStream; const Raster_:TImageRaster );
var
   H :TImageHeader;
begin
     H := Raster_.Header;

     if ( H.Width < 1 ) or ( H.Height < 1 ) then raise EImageCodec.CreateFmt( '%s: cannot encode an empty image (%d x %d)', [ Caption, H.Width, H.Height ] );

     DoEncode( Stream_, Raster_, H );
end;

end. //######################################################################### ■
