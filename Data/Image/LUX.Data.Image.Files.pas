unit LUX.Data.Image.Files;

interface //#################################################################### ■

uses System.Classes, System.SysUtils,
     LUX.Data.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TLuxImageFiler = class;

     TLuxImageFilerClass = class of TLuxImageFiler;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFiler

     ///// 画像ファイル形式の基底クラス
     /////
     ///// ・形式ごとに派生クラスを作り、Extensions ・ Caption ・ DoLoad ・ DoSave を実装する。
     /////   派生ユニットの initialization で Regist すれば、拡張子からの選択にも加わる。
     ///// ・形式固有の設定（PNG の圧縮率、JPEG の品質など）は**引数ではなくプロパティ**として
     /////   派生クラスが持つ。したがって共通のメソッド署名に形式固有の引数が混ざらない。
     ///// ・入出力の入口はこのクラスであり、TLuxImage 側にファイル入出力のメソッドは無い。
     /////
     /////   Png := TLuxImageFilerPng.Create;
     /////   try
     /////      Png.Level := plNone;
     /////      Png.SaveToFileAsync( Image, 'x.png' );   // 設定は複製されるので、すぐ解放してよい
     /////   finally
     /////      Png.Free;
     /////   end;
     /////
     ///// ・非同期版は TLuxImage の非同期機構で走るので、進捗は Image.Progress ・ Image.OnProgress、
     /////   完了は Image.OnLoaded ・ Image.OnSaved、待ち合わせは Image.WaitFor で受ける。

     TLuxImageFiler = class
     private
       class var _Filers :TArray<TLuxImageFilerClass>;
     protected
       ///// M E T H O D
       procedure DoLoad( const Image_:TLuxImage; const Stream_:TStream ); virtual; abstract;  // 実際の復号
       procedure DoSave( const Image_:TLuxImage; const Stream_:TStream ); virtual; abstract;  // 実際の符号化
     public
       ///// C L A S S
       class function Extensions :TArray<String>; virtual; abstract;   // ( '.png' ) など。先頭が既定の拡張子
       class function Caption :String; virtual; abstract;              // 'PNG' など（ダイアログの説明用）
       class function Handles( const FileName_:String ) :Boolean;      // この形式が扱う拡張子か
       /////
       class procedure Regist( const Filer_:TLuxImageFilerClass );     // 派生ユニットの initialization から呼ぶ
       class function Filers :TArray<TLuxImageFilerClass>;             // 登録済みの形式
       class function ClassFor( const FileName_:String ) :TLuxImageFilerClass;  // 拡張子に対応するクラス（無ければ nil ）
       class function CreateFor( const FileName_:String ) :TLuxImageFiler;      // 同上のインスタンス（無ければ nil ）
       class function DialogFilter( const All_:Boolean = True ) :String;        // TOpenDialog / TSaveDialog の Filter
       ///// M E T H O D
       function Clone :TLuxImageFiler;                                 // 同じ設定の新しいインスタンス
       procedure Assign( const Filer_:TLuxImageFiler ); virtual;       // 設定を写す（派生クラスが上書きする）
       /////
       procedure LoadFromStream( const Image_:TLuxImage; const Stream_:TStream );
       procedure SaveToStream  ( const Image_:TLuxImage; const Stream_:TStream );
       procedure LoadFromFile( const Image_:TLuxImage; const FileName_:String );
       procedure SaveToFile  ( const Image_:TLuxImage; const FileName_:String );
       /////
       procedure LoadFromFileAsync( const Image_:TLuxImage; const FileName_:String );  // 別スレッドで読む
       procedure SaveToFileAsync  ( const Image_:TLuxImage; const FileName_:String );  // 別スレッドで書く
       /////
       function ImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean; virtual;  // 画素を読まずに寸法だけ得る
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function LuxImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;  // 拡張子から形式を選んで寸法だけ得る

implementation //############################################################### ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFiler

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////////// C L A S S

class function TLuxImageFiler.Handles( const FileName_:String ) :Boolean;
var
   E, X :String;
begin
     E := LowerCase( ExtractFileExt( FileName_ ) );

     for X in Extensions do if X = E then Exit( True );

     Result := False;
end;

//------------------------------------------------------------------------------

class procedure TLuxImageFiler.Regist( const Filer_:TLuxImageFilerClass );
var
   F :TLuxImageFilerClass;
begin
     for F in TLuxImageFiler._Filers do if F = Filer_ then Exit;

     TLuxImageFiler._Filers := TLuxImageFiler._Filers + [ Filer_ ];
end;

class function TLuxImageFiler.Filers :TArray<TLuxImageFilerClass>;
begin
     Result := TLuxImageFiler._Filers;
end;

class function TLuxImageFiler.ClassFor( const FileName_:String ) :TLuxImageFilerClass;
var
   F :TLuxImageFilerClass;
begin
     for F in TLuxImageFiler._Filers do if F.Handles( FileName_ ) then Exit( F );

     Result := nil;
end;

class function TLuxImageFiler.CreateFor( const FileName_:String ) :TLuxImageFiler;
var
   F :TLuxImageFilerClass;
begin
     F := ClassFor( FileName_ );

     if Assigned( F ) then Result := F.Create
                      else Result := nil;
end;

///// 「画像 (*.png;*.jpg)|*.png;*.jpg|PNG (*.png)|*.png|JPEG (*.jpg)|*.jpg」の形

class function TLuxImageFiler.DialogFilter( const All_:Boolean = True ) :String;
var
   F     :TLuxImageFilerClass;
   X     :String;
   Every :String;
   One   :String;
begin
     Result := '';  Every := '';

     for F in TLuxImageFiler._Filers do
     begin
          One := '';

          for X in F.Extensions do
          begin
               if One   <> '' then One   := One   + ';';
               if Every <> '' then Every := Every + ';';

               One   := One   + '*' + X;
               Every := Every + '*' + X;
          end;

          if Result <> '' then Result := Result + '|';

          Result := Result + Format( '%s (%s)|%s', [ F.Caption, One, One ] );
     end;

     if All_ and ( Every <> '' ) then Result := Format( '%s (%s)|%s|', [ '画像', Every, Every ] ) + Result;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

function TLuxImageFiler.Clone :TLuxImageFiler;
begin
     Result := TLuxImageFilerClass( ClassType ).Create;

     Result.Assign( Self );
end;

procedure TLuxImageFiler.Assign( const Filer_:TLuxImageFiler );
begin
end;

//------------------------------------------------------------------------------

procedure TLuxImageFiler.LoadFromStream( const Image_:TLuxImage; const Stream_:TStream );
begin
     Image_.BeginProgress;

     Image_.ProgRange( 0, 0.75 );  DoLoad( Image_, Stream_ );

     ///// 表示に要る縮小段も、ここで作り終えてしまう。
     ///// 最初の描画時に作ると、その分だけ UI が止まってしまうため。

     Image_.ProgRange( 0.75, 1 );  Image_.UpdateLevels;

     Image_.ProgRange( 0, 1 );     Image_.DoProgress( 1 );
end;

procedure TLuxImageFiler.SaveToStream( const Image_:TLuxImage; const Stream_:TStream );
begin
     Image_.BeginProgress;

     Image_.ProgRange( 0, 1 );  DoSave( Image_, Stream_ );

     Image_.DoProgress( 1 );
end;

//------------------------------------------------------------------------------

procedure TLuxImageFiler.LoadFromFile( const Image_:TLuxImage; const FileName_:String );
var
   S :TFileStream;
begin
     S := TFileStream.Create( FileName_, fmOpenRead or fmShareDenyWrite );
     try
        LoadFromStream( Image_, S );
     finally
        S.Free;
     end;
end;

procedure TLuxImageFiler.SaveToFile( const Image_:TLuxImage; const FileName_:String );
var
   S :TFileStream;
begin
     S := TFileStream.Create( FileName_, fmCreate );
     try
        SaveToStream( Image_, S );
     finally
        S.Free;
     end;
end;

//------------------------------------------------------------------------------

///// 設定を複製してから走らせるので、呼び出し側はこのファイラをすぐ解放してよい

procedure TLuxImageFiler.LoadFromFileAsync( const Image_:TLuxImage; const FileName_:String );
var
   C :TLuxImageFiler;
   F :String;
begin
     C := Clone;  F := FileName_;

     Image_.RunAsync( procedure
                      begin
                           try
                              C.LoadFromFile( Image_, F );
                           finally
                              C.Free;
                           end;
                      end, False );
end;

procedure TLuxImageFiler.SaveToFileAsync( const Image_:TLuxImage; const FileName_:String );
var
   C :TLuxImageFiler;
   F :String;
begin
     C := Clone;  F := FileName_;

     Image_.RunAsync( procedure
                      begin
                           try
                              C.SaveToFile( Image_, F );
                           finally
                              C.Free;
                           end;
                      end, True );
end;

//------------------------------------------------------------------------------

///// 既定は「実際に読んでみる」。ヘッダだけで判る形式は派生クラスが上書きする。

function TLuxImageFiler.ImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;
var
   I :TLuxImage;
begin
     Width_ := 0;  Height_ := 0;

     I := TLuxImageUInt08.Create;
     try
        try
           LoadFromFile( I, FileName_ );

           Width_ := I.Width;  Height_ := I.Height;

           Result := ( Width_ > 0 ) and ( Height_ > 0 );
        except
           Result := False;
        end;
     finally
        I.Free;
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% LuxImageSize

function LuxImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;
var
   F :TLuxImageFiler;
begin
     Width_ := 0;  Height_ := 0;

     F := TLuxImageFiler.CreateFor( FileName_ );

     if not Assigned( F ) then Exit( False );

     try
        Result := F.ImageSize( FileName_, Width_, Height_ );
     finally
        F.Free;
     end;
end;

end. //######################################################################### ■
