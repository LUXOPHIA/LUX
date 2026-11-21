unit LUX.Data.Image.Codec;

// TLuxImage と、画像のコーデック（LUX.Data.Codec.Image）をつなぐ橋
//
//【構成する型】
// ・TLuxImageRaster … TLuxImage を、コーデックの画素の置き場として見せる。
// ・TLuxImageFiler  … TLuxImage を、コーデックで読み書きする（縮小段の更新・進捗・非同期を含む）。
//
//【使い方】
//   TLuxImageFiler.LoadFromFileAsync( Image, FileName );          // 読むときは、中身から形式が選ばれる
//
//   Codec := TImageCodec.CreateFor( FileName );                   // 書くときは、拡張子から形式を選ぶ（形式を決めて作ってもよい）
//   try
//      TLuxImageFiler.SaveToFileAsync( Image, FileName, Codec );
//   finally
//      Codec.Free;                                                // 非同期の版は、設定を写してから走るので、すぐ解放してよい
//   end;
//
//【進捗と知らせ】
// ・進捗は、受け渡した画素の数の割合である。Image.Progress と Image.OnProgress で受ける。
// ・非同期の版の終わりは、Image.OnLoaded・Image.OnSaved で受ける。待つには Image.WaitFor を使う。
// ・読み込みは、縮小段の更新までを済ませる（最初の描画で作ると、その間、表示が止まるため）。

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.SysUtils, System.Classes,
     LUX.Color,
     LUX.Data.Codec.Image,
     LUX.Data.Image;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageRaster

     // 置き場は、画像の段 0 である。画像は所有しない。
     // 並びを 1 つ受け渡すたびに、画像の進捗（受け渡した画素の数 ÷ 全部の画素の数）を進める。
     TLuxImageRaster = class( TImageRaster )
     private
       _Image :TLuxImage;
       _Count :Int64;  // 受け渡した画素の数
       ///// M E T H O D
       procedure Passed( const N_:Integer );
     protected
       ///// A C C E S S O R
       function GetHeader :TImageHeader; override;
       procedure SetHeader( const Header_:TImageHeader ); override;
     public
       constructor Create( const Image_:TLuxImage );
       ///// P R O P E R T Y
       property Image :TLuxImage read _Image;
       ///// M E T H O D
       procedure GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); override;
       procedure SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); override;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFiler

     TLuxImageFiler = class
     private
     protected
     public
       ///// M E T H O D
       class function CodecOf( const FileName_:String ) :TImageCodecClass;                                           // ファイルの中身の形式（無ければ nil）
       class procedure LoadFromStream( const Image_:TLuxImage; const Stream_:TStream );
       class procedure SaveToStream( const Image_:TLuxImage; const Stream_:TStream; const Codec_:TImageCodec );
       class procedure LoadFromFile( const Image_:TLuxImage; const FileName_:String );
       class procedure SaveToFile( const Image_:TLuxImage; const FileName_:String; const Codec_:TImageCodec );
       class procedure LoadFromFileAsync( const Image_:TLuxImage; const FileName_:String );                          // 別のスレッドで読む
       class procedure SaveToFileAsync( const Image_:TLuxImage; const FileName_:String; const Codec_:TImageCodec );  // 別のスレッドで書く
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      LOAD_DECODE = 0.75;  // 読み込みの進捗のうち、復号が占める割合（残りは、縮小段の更新）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageRaster

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageRaster.Passed( const N_:Integer );
begin
     Inc( _Count, N_ );

     _Image.DoProgress( _Count / ( Int64( _Image.Width ) * _Image.Height ) );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////// A C C E S S O R

// 標本の精度は、画素の大きさ（4 標本ぶんのバイト数）から決まる。

function TLuxImageRaster.GetHeader :TImageHeader;
begin
     Result := TImageHeader.Create( _Image.Width, _Image.Height, _Image.ColorSpace, _Image.PixelSize * 8 div 4 );
end;

// 画像の標本の精度は、画像のクラスで決まっているので、Depth には従わない。

procedure TLuxImageRaster.SetHeader( const Header_:TImageHeader );
begin
     _Image.SetSize( Header_.Width, Header_.Height );

     _Image.ColorSpace := Header_.ColorSpace;

     _Count := 0;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TLuxImageRaster.Create( const Image_:TLuxImage );
begin
     inherited Create;

     _Image := Image_;
     _Count := 0;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

// 右へ進む並びは、画像の行の読み書きそのものである。それ以外の歩みは、1 画素ずつ進む。

procedure TLuxImageRaster.GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );
var
   I :Integer;
begin
     if ( DX_ > 0 ) and ( DY_ = 0 ) then _Image.GetRow( 0, X_, Y_, DX_, N_, Pixels_ )
     else
     for I := 0 to N_-1 do _Image.GetRow( 0, X_ + I * DX_, Y_ + I * DY_, 1, 1, @Pixels_[ I ] );

     Passed( N_ );
end;

procedure TLuxImageRaster.SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );
var
   I :Integer;
begin
     if ( DX_ > 0 ) and ( DY_ = 0 ) then _Image.SetRow( 0, X_, Y_, DX_, N_, Pixels_ )
     else
     for I := 0 to N_-1 do _Image.SetRow( 0, X_ + I * DX_, Y_ + I * DY_, 1, 1, @Pixels_[ I ] );

     Passed( N_ );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageFiler

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

class function TLuxImageFiler.CodecOf( const FileName_:String ) :TImageCodecClass;
var
   S :TStream;
begin
     S := TFileStream.Create( FileName_, fmOpenRead or fmShareDenyWrite );
     try
        Result := TImageCodec.ClassOf( S );
     finally
        S.Free;
     end;
end;

//------------------------------------------------------------------------------

// 形式は、流れの中身から選ぶ。復号には、形式ごとの設定が無いので、既定のコーデックで足りる。

class procedure TLuxImageFiler.LoadFromStream( const Image_:TLuxImage; const Stream_:TStream );
var
   K :TImageCodecClass;
   C :TImageCodec;
   R :TLuxImageRaster;
begin
     K := TImageCodec.ClassOf( Stream_ );

     if not Assigned( K ) then raise EImageCodec.Create( 'The stream is in none of the registered image formats' );

     C := K.Create;
     R := TLuxImageRaster.Create( Image_ );
     try
        Image_.BeginProgress;

        Image_.ProgRange( 0, LOAD_DECODE );

        C.Decode( Stream_, R );

        Image_.Changed;

        Image_.ProgRange( LOAD_DECODE, 1 );

        Image_.UpdateLevels;

        Image_.ProgRange( 0, 1 );

        Image_.DoProgress( 1 );
     finally
        R.Free;
        C.Free;
     end;
end;

class procedure TLuxImageFiler.SaveToStream( const Image_:TLuxImage; const Stream_:TStream; const Codec_:TImageCodec );
var
   R :TLuxImageRaster;
begin
     R := TLuxImageRaster.Create( Image_ );
     try
        Image_.BeginProgress;

        Image_.ProgRange( 0, 1 );

        Codec_.Encode( Stream_, R );

        Image_.DoProgress( 1 );
     finally
        R.Free;
     end;
end;

//------------------------------------------------------------------------------

class procedure TLuxImageFiler.LoadFromFile( const Image_:TLuxImage; const FileName_:String );
var
   S :TStream;
begin
     S := TBufferedFileStream.Create( FileName_, fmOpenRead or fmShareDenyWrite );
     try
        LoadFromStream( Image_, S );
     finally
        S.Free;
     end;
end;

class procedure TLuxImageFiler.SaveToFile( const Image_:TLuxImage; const FileName_:String; const Codec_:TImageCodec );
var
   S :TStream;
begin
     S := TBufferedFileStream.Create( FileName_, fmCreate );
     try
        SaveToStream( Image_, S, Codec_ );
     finally
        S.Free;
     end;
end;

//------------------------------------------------------------------------------

class procedure TLuxImageFiler.LoadFromFileAsync( const Image_:TLuxImage; const FileName_:String );
var
   I :TLuxImage;
   F :String;
begin
     I := Image_;  F := FileName_;

     I.RunAsync( procedure
                 begin
                      LoadFromFile( I, F );
                 end, False );
end;

// 設定の写しを作ってから走らせるので、呼んだ側は、渡したコーデックをすぐ解放してよい。
// 写しは、仕事が終わったときに、仕事の側が解放する。仕事を始められなかったときは、ここで解放する。

class procedure TLuxImageFiler.SaveToFileAsync( const Image_:TLuxImage; const FileName_:String; const Codec_:TImageCodec );
var
   I :TLuxImage;
   F :String;
   C :TImageCodec;
begin
     I := Image_;  F := FileName_;  C := Codec_.Clone;
     try
        I.RunAsync( procedure
                    begin
                         try
                            SaveToFile( I, F, C );
                         finally
                            C.Free;
                         end;
                    end, True );
     except
        C.Free;

        raise;
     end;
end;

end. //######################################################################### ■
