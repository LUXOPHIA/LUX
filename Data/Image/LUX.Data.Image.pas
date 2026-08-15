unit LUX.Data.Image;

interface //#################################################################### ■

{$POINTERMATH ON}

uses System.Classes, System.SysUtils, System.Threading,
     LUX, LUX.D1.Half, LUX.Color, LUX.Color.Half;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxPixel

     TLuxPixel = ( bpUInt08,    // TByteRGBA    ： 8bit 符号無整数 ×4
                   bpUInt16,    // TWordRGBA    ：16bit 符号無整数 ×4
                   bpSFlo16,    // THalfRGBA    ：16bit 符号付浮動小数 ×4
                   bpSFlo32 );  // TSingleRGBA  ：32bit 符号付浮動小数 ×4

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxTile

     TLuxTile = record
     public
       Data  :TArray<Byte>;   // LUXIMAGE_TILE² 画素ぶん。SetSize で確保され常に有効
       Stamp :Cardinal;       // 内容が変わるたびに増える（表示側のキャッシュ判定用）
       Dirty :Integer;        // 段 0 のみ：1 なら上の段への反映が未了
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxLevel

     TLuxLevel = record
     public
       Width  :Integer;              // この段の画素数（横）
       Height :Integer;              // この段の画素数（縦）
       TilesX :Integer;              // この段のタイル数（横）
       TilesY :Integer;              // この段のタイル数（縦）
       Tiles  :TArray<TLuxTile>;     // TilesY * TilesX 個
     end;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImage

     ///// 超高解像度画像の基底クラス
     /////
     ///// ・画素は LUXIMAGE_TILE 角のタイルに分割して保持する（巨大な連続確保を避けるため）
     ///// ・縮小ピラミッド（段）も含めて、全メモリを SetSize の時点で確保する。
     /////   確保できなければその場で EOutOfMemory になり、画像は空（ 0×0 ）に戻る。
     ///// ・GPU を一切前提としないので、CPU メモリの許す限りの大きさを扱える
     /////
     ///// 変更の追跡
     ///// ・段 0 のタイルには Dirty、全タイルには Stamp がある。
     ///// ・TileChanged( TX,TY ) ：段 0 のタイルを書き終えたら呼ぶ。任意のスレッドから、ロック無しで呼べる。
     /////   イベントは発火しない。表示を更新させたいときは Notify を（頻度を抑えて）呼ぶ。
     ///// ・UpdateLevels ：Dirty なタイルの足跡だけを段 1 以上に反映する。表示側が描画前に呼ぶ。
     ///// ・全タイルが確保済みなので、互いに素な領域への書き込みは複数スレッドから同時に行える。

     TLuxImage = class
     private
       ///// A C C E S S O R
       function GetLevelsN :Integer;
       function GetColors( const X_,Y_:Integer ) :TSingleRGBA;
       procedure SetColors( const X_,Y_:Integer; const C_:TSingleRGBA );
     protected
       _Width   :Integer;
       _Height  :Integer;
       _Levels  :TArray<TLuxLevel>;
       _Version :Cardinal;
       ///// 非同期
       _Task     :ITask;
       _Busy     :Boolean;
       _Closing  :Boolean;
       _Progress :Single;
       _Fired    :Single;   // 直前に通知した進捗（間引き用）
       _ProgA    :Single;   // DoProgress の 0 が対応する全体進捗
       _ProgB    :Single;   // DoProgress の 1 が対応する全体進捗
       ///// E V E N T
       _OnChange   :TDelegates;
       _OnProgress :TDelegates;
       _OnLoaded   :TDelegates;
       _OnSaved    :TDelegates;
       ///// M E T H O D
       procedure InitLevels;
       procedure FillLevels;
       procedure StartAsync( const Work_:TProc; const Saving_:Boolean );
       procedure ProgRange( const A_,B_:Single );  // 以降の DoProgress を全体の A_〜B_ に割り当てる
       /////
       procedure RowIn ( const Src_:Pointer; const Dst_:PSingleRGBA; const N_:Integer ); virtual; abstract;  // 記憶形式 → TSingleRGBA
       procedure RowOut( const Src_:PSingleRGBA; const Dst_:Pointer; const N_:Integer ); virtual; abstract;  // TSingleRGBA → 記憶形式
       procedure MipRow( const Src0_,Src1_,Dst_:Pointer; const N_:Integer ); virtual; abstract;             // 2N_×2 画素 → N_ 画素（平均）
       /////
       procedure MakeBlock( const L_,X_,Y_,W_,H_:Integer; const R0_,R1_,D_:Pointer );  // 段 L_-1 から段 L_ の矩形を作る
       procedure MakeChain( const TX_,TY_:Integer; const R0_,R1_,D_:Pointer );          // 段 0 のタイルの足跡を段 1〜LUXIMAGE_TILE_LOG に反映する
     public
       constructor Create; overload;
       constructor Create( const W_,H_:Integer ); overload;
       destructor Destroy; override;
       ///// C L A S S
       class function PixelKind :TLuxPixel; virtual; abstract;   // 画素形式
       class function PixelSize :Integer; virtual; abstract;     // １画素のバイト数
       class function IsFloat :Boolean; virtual;                 // 浮動小数形式か
       class function DefaultGamma :Single; virtual;             // 表示ガンマの既定値
       ///// P R O P E R T Y
       property Width                         :Integer     read _Width    ;
       property Height                        :Integer     read _Height   ;
       property LevelsN                       :Integer     read GetLevelsN;
       property Version                       :Cardinal    read _Version  ;  // 構造か全体が変わった版（表示側は全キャッシュを破棄する）
       property Busy                          :Boolean     read _Busy     ;  // 非同期の読み書きが進行中
       property Progress                      :Single      read _Progress ;  // 0 〜 1
       property Colors[ const X_,Y_:Integer ] :TSingleRGBA read GetColors write SetColors; default;
       ///// M E T H O D
       procedure SetSize( const W_,H_:Integer );  // 全段を確保する。確保できなければ EOutOfMemory
       procedure Clear;                           // 全段を 0 で埋める
       /////
       procedure Changed;                                 // 全体が変わった：全タイルを Dirty にし、Version を上げ、Notify する
       procedure TileChanged( const TX_,TY_:Integer );    // 段 0 のタイルが変わった：Dirty と Stamp を更新する（通知はしない）
       procedure Notify;                                  // OnChange をメインスレッドで発火する
       procedure UpdateLevels;                            // Dirty なタイルの足跡を段 1 以上へ反映する（呼び出しは直列化される）
       /////
       function LevelWidth ( const L_:Integer ) :Integer;
       function LevelHeight( const L_:Integer ) :Integer;
       function LevelTilesX( const L_:Integer ) :Integer;
       function LevelTilesY( const L_:Integer ) :Integer;
       function TileWidth  ( const L_,TX_:Integer ) :Integer;
       function TileHeight ( const L_,TY_:Integer ) :Integer;
       /////
       function TileData ( const L_,TX_,TY_:Integer ) :Pointer;   // タイルの先頭（常に有効。行ピッチは LUXIMAGE_TILE 画素）
       function TileStamp( const L_,TX_,TY_:Integer ) :Cardinal;  // タイルの内容の版
       /////
       procedure GetRaws( const L_,X_,Y_,N_:Integer; const Dst_:Pointer );  // 生画素を N_ 個読む（タイル跨ぎ対応）
       procedure SetRaws( const L_,X_,Y_,N_:Integer; const Src_:Pointer );  // 生画素を N_ 個書く（タイル跨ぎ対応）
       /////
       procedure GetRow( const L_,X_,Y_,N_:Integer; const Dst_:PSingleRGBA );  // 書式非依存の行読み
       procedure SetRow( const L_,X_,Y_,N_:Integer; const Src_:PSingleRGBA );  // 書式非依存の行書き
       /////
       procedure LoadFromFile( const FileName_:String );
       procedure SaveToFile( const FileName_:String; const Quality_:Integer = 90 );
       /////
       procedure LoadFromFileAsync( const FileName_:String );                            // 別スレッドで読む
       procedure SaveToFileAsync( const FileName_:String; const Quality_:Integer = 90 );  // 別スレッドで書く
       procedure WaitFor;                                                                 // 非同期処理の完了を待つ
       procedure DoProgress( const Ratio_:Single );                                       // 入出力側から進捗を報せる
       ///// E V E N T
       property OnChange   :TDelegates read _OnChange  ;
       property OnProgress :TDelegates read _OnProgress;  // 進捗値は Progress を読む
       property OnLoaded   :TDelegates read _OnLoaded  ;
       property OnSaved    :TDelegates read _OnSaved   ;
     end;

     TLuxImageClass = class of TLuxImage;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageUInt08

     TLuxImageUInt08 = class( TLuxImage )
     private
       ///// A C C E S S O R
       function GetPixels( const X_,Y_:Integer ) :TByteRGBA;
       procedure SetPixels( const X_,Y_:Integer; const P_:TByteRGBA );
     protected
       ///// M E T H O D
       procedure RowIn ( const Src_:Pointer; const Dst_:PSingleRGBA; const N_:Integer ); override;
       procedure RowOut( const Src_:PSingleRGBA; const Dst_:Pointer; const N_:Integer ); override;
       procedure MipRow( const Src0_,Src1_,Dst_:Pointer; const N_:Integer ); override;
     public
       ///// C L A S S
       class function PixelKind :TLuxPixel; override;
       class function PixelSize :Integer; override;
       ///// P R O P E R T Y
       property Pixels[ const X_,Y_:Integer ] :TByteRGBA read GetPixels write SetPixels;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageUInt16

     TLuxImageUInt16 = class( TLuxImage )
     private
       ///// A C C E S S O R
       function GetPixels( const X_,Y_:Integer ) :TWordRGBA;
       procedure SetPixels( const X_,Y_:Integer; const P_:TWordRGBA );
     protected
       ///// M E T H O D
       procedure RowIn ( const Src_:Pointer; const Dst_:PSingleRGBA; const N_:Integer ); override;
       procedure RowOut( const Src_:PSingleRGBA; const Dst_:Pointer; const N_:Integer ); override;
       procedure MipRow( const Src0_,Src1_,Dst_:Pointer; const N_:Integer ); override;
     public
       ///// C L A S S
       class function PixelKind :TLuxPixel; override;
       class function PixelSize :Integer; override;
       ///// P R O P E R T Y
       property Pixels[ const X_,Y_:Integer ] :TWordRGBA read GetPixels write SetPixels;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageSFlo16

     TLuxImageSFlo16 = class( TLuxImage )
     private
       ///// A C C E S S O R
       function GetPixels( const X_,Y_:Integer ) :THalfRGBA;
       procedure SetPixels( const X_,Y_:Integer; const P_:THalfRGBA );
     protected
       ///// M E T H O D
       procedure RowIn ( const Src_:Pointer; const Dst_:PSingleRGBA; const N_:Integer ); override;
       procedure RowOut( const Src_:PSingleRGBA; const Dst_:Pointer; const N_:Integer ); override;
       procedure MipRow( const Src0_,Src1_,Dst_:Pointer; const N_:Integer ); override;
     public
       ///// C L A S S
       class function PixelKind :TLuxPixel; override;
       class function PixelSize :Integer; override;
       class function IsFloat :Boolean; override;
       class function DefaultGamma :Single; override;
       ///// P R O P E R T Y
       property Pixels[ const X_,Y_:Integer ] :THalfRGBA read GetPixels write SetPixels;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageSFlo32

     TLuxImageSFlo32 = class( TLuxImage )
     private
       ///// A C C E S S O R
       function GetPixels( const X_,Y_:Integer ) :TSingleRGBA;
       procedure SetPixels( const X_,Y_:Integer; const P_:TSingleRGBA );
     protected
       ///// M E T H O D
       procedure RowIn ( const Src_:Pointer; const Dst_:PSingleRGBA; const N_:Integer ); override;
       procedure RowOut( const Src_:PSingleRGBA; const Dst_:Pointer; const N_:Integer ); override;
       procedure MipRow( const Src0_,Src1_,Dst_:Pointer; const N_:Integer ); override;
     public
       ///// C L A S S
       class function PixelKind :TLuxPixel; override;
       class function PixelSize :Integer; override;
       class function IsFloat :Boolean; override;
       class function DefaultGamma :Single; override;
       ///// P R O P E R T Y
       property Pixels[ const X_,Y_:Integer ] :TSingleRGBA read GetPixels write SetPixels;
     end;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% LUXIMAGE_TILE

      LUXIMAGE_TILE_LOG = 8;                          // タイルの一辺の対数
      LUXIMAGE_TILE     = 1 shl LUXIMAGE_TILE_LOG;    // タイルの一辺（ 256 ）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

function LuxImageClass( const Kind_:TLuxPixel ) :TLuxImageClass;  // 画素形式に対応するクラス

function LuxFreeMemory :Int64;  // 物理メモリの空き（バイト）。得られない環境では -1

implementation //############################################################### ■

uses System.Math,
     {$IFDEF MSWINDOWS} Winapi.Windows, {$ENDIF}
     LUX.Data.Image.Files;

const //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C O N S T A N T 】

      UPDATE_CHUNK = 1024;  // UpdateLevels が一度に並列処理するタイル数（進捗通知の粒度）

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImage

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TLuxImage.GetLevelsN :Integer;
begin
     Result := Length( _Levels );
end;

//------------------------------------------------------------------------------

function TLuxImage.GetColors( const X_,Y_:Integer ) :TSingleRGBA;
begin
     GetRow( 0, X_, Y_, 1, @Result );
end;

procedure TLuxImage.SetColors( const X_,Y_:Integer; const C_:TSingleRGBA );
begin
     SetRow( 0, X_, Y_, 1, @C_ );

     TileChanged( X_ shr LUXIMAGE_TILE_LOG, Y_ shr LUXIMAGE_TILE_LOG );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////////// M E T H O D

///// 全段の枠とタイルの実体を確保する。確保できなければ空に戻して EOutOfMemory を送出する。
///// 必要量が物理メモリの空きを超える場合は、確保を試みずにその場で送出する
///// （ページファイルへ溢れさせて動くことは設計上想定しない）。

procedure TLuxImage.InitLevels;
var
   W, H, N, L, LL :Integer;
   Z, T, F        :Int64;
   M              :String;
begin
     _Levels := nil;

     if ( _Width < 1 ) or ( _Height < 1 ) then Exit;

     ///// 段の枠

     W := _Width;  H := _Height;  N := 0;  T := 0;

     repeat
           SetLength( _Levels, N+1 );

           with _Levels[ N ] do
           begin
                Width  := W;
                Height := H;
                TilesX := ( W + LUXIMAGE_TILE - 1 ) shr LUXIMAGE_TILE_LOG;
                TilesY := ( H + LUXIMAGE_TILE - 1 ) shr LUXIMAGE_TILE_LOG;

                SetLength( Tiles, TilesX * TilesY );

                Inc( T, Int64( TilesX ) * TilesY * LUXIMAGE_TILE * LUXIMAGE_TILE * PixelSize );
           end;

           if ( W = 1 ) and ( H = 1 ) then Break;

           W := ( W + 1 ) div 2;
           H := ( H + 1 ) div 2;

           Inc( N );
     until False;

     ///// タイルの実体（並列に確保する。動的配列は 0 で初期化される）

     M := '';

     try
          F := LuxFreeMemory;

          if ( F >= 0 ) and ( T > F ) then
          begin
               M := Format( '（空き %.1f GB）', [ F / ( 1024 * 1024 * 1024 ) ] );  Abort;
          end;

          Z := Int64( LUXIMAGE_TILE ) * LUXIMAGE_TILE * PixelSize;

          for L := 0 to LevelsN-1 do
          begin
               LL := L;  // 無名メソッドは for の制御変数を捕捉できない

               TParallel.For( 0, High( _Levels[ L ].Tiles ), procedure( I:Integer )
                                                             begin
                                                                  SetLength( _Levels[ LL ].Tiles[ I ].Data, Z );
                                                             end );
          end;
     except
          W := _Width;  H := _Height;

          _Levels := nil;  _Width := 0;  _Height := 0;

          raise EOutOfMemory.CreateFmt( '画像 %d × %d（%s、%.1f GB）のメモリを確保できない%s',
                                        [ W, H, ClassName, T / ( 1024 * 1024 * 1024 ), M ] );
     end;
end;

///// 全段のタイルを 0 で埋め、Stamp を進める。

procedure TLuxImage.FillLevels;
var
   L, LL :Integer;
begin
     for L := 0 to LevelsN-1 do
     begin
          LL := L;  // 無名メソッドは for の制御変数を捕捉できない

          TParallel.For( 0, High( _Levels[ L ].Tiles ), procedure( I:Integer )
                                                        begin
                                                             with _Levels[ LL ].Tiles[ I ] do
                                                             begin
                                                                  FillChar( Data[ 0 ], Length( Data ), 0 );

                                                                  Inc( Stamp );  Dirty := 0;
                                                             end;
                                                        end );
     end;
end;

//------------------------------------------------------------------------------

procedure TLuxImage.StartAsync( const Work_:TProc; const Saving_:Boolean );
begin
     if _Busy then raise EInvalidOpException.Create( '前の非同期処理がまだ終わっていない' );

     _Busy     := True;
     _Progress := 0;
     _Fired    := -1;

     ProgRange( 0, 1 );

     _Task := TTask.Run( procedure
                         var
                            M :String;
                         begin
                              M := '';

                              try
                                   Work_;
                              except
                                   on X:Exception do M := X.ClassName + ' ： ' + X.Message;
                              end;

                              TThread.Queue( nil, procedure
                                                  begin
                                                       _Busy     := False;
                                                       _Progress := 1;

                                                       if _Closing then Exit;  // 破棄中なら何も通知しない

                                                       if M <> '' then raise EInOutError.Create( M );

                                                       if not Saving_ then Notify;  // 段は作業スレッドで反映し終えている

                                                       if Saving_ then _OnSaved .Run( Self )
                                                                  else _OnLoaded.Run( Self );
                                                  end );
                         end );
end;

//------------------------------------------------------------------------------

procedure TLuxImage.ProgRange( const A_,B_:Single );
begin
     _ProgA := A_;
     _ProgB := B_;
end;

//------------------------------------------------------------------------------

///// 段 L_ の矩形 [X_,X_+W_)×[Y_,Y_+H_) を、段 L_-1 の対応する 2 倍の矩形の平均で作る。
///// R0_ / R1_ は 2W_ 画素、D_ は W_ 画素ぶんの作業領域。

procedure TLuxImage.MakeBlock( const L_,X_,Y_,W_,H_:Integer; const R0_,R1_,D_:Pointer );
var
   Z, SW, SH, N, J, SY :Integer;
   TX, TY, TX0, TX1, TY0, TY1 :Integer;
begin
     Z := PixelSize;

     SW := _Levels[ L_-1 ].Width;
     SH := _Levels[ L_-1 ].Height;

     N := Min( 2 * W_, SW - 2 * X_ );  // 元の段で読める画素数（奇数幅の端では 2W_-1 になる）

     for J := 0 to H_-1 do
     begin
          SY := 2 * ( Y_ + J );

          GetRaws( L_-1, 2 * X_, SY, N, R0_ );

          if SY + 1 < SH then GetRaws( L_-1, 2 * X_, SY+1, N, R1_ )
                         else Move( R0_^, R1_^, N * Z );

          if N < 2 * W_ then  // 端の画素を複製して偶数個にそろえる
          begin
               Move( ( PByte( R0_ ) + ( N - 1 ) * Z )^, ( PByte( R0_ ) + N * Z )^, Z );
               Move( ( PByte( R1_ ) + ( N - 1 ) * Z )^, ( PByte( R1_ ) + N * Z )^, Z );
          end;

          MipRow( R0_, R1_, D_, W_ );

          SetRaws( L_, X_, Y_ + J, W_, D_ );
     end;

     ///// 触ったタイルの Stamp を進める（同じタイルへ複数スレッドから来るので不可分に）

     TX0 :=   X_            shr LUXIMAGE_TILE_LOG;
     TX1 := ( X_ + W_ - 1 ) shr LUXIMAGE_TILE_LOG;
     TY0 :=   Y_            shr LUXIMAGE_TILE_LOG;
     TY1 := ( Y_ + H_ - 1 ) shr LUXIMAGE_TILE_LOG;

     for TY := TY0 to TY1 do
     for TX := TX0 to TX1 do AtomicIncrement( _Levels[ L_ ].Tiles[ TY * _Levels[ L_ ].TilesX + TX ].Stamp );
end;

///// 段 0 のタイル (TX_,TY_) の足跡を、段 1〜LUXIMAGE_TILE_LOG へ順に反映する。
///// 段 L での足跡は ( LUXIMAGE_TILE shr L ) 角の矩形で、段 L-1 の足跡だけから作れるので、
///// タイルごとの連鎖は互いに独立（並列に実行できる）。

procedure TLuxImage.MakeChain( const TX_,TY_:Integer; const R0_,R1_,D_:Pointer );
var
   L, S, X, Y, W, H :Integer;
begin
     for L := 1 to Min( LUXIMAGE_TILE_LOG, LevelsN-1 ) do
     begin
          S := LUXIMAGE_TILE shr L;

          X := TX_ * S;
          Y := TY_ * S;
          W := Min( S, _Levels[ L ].Width  - X );
          H := Min( S, _Levels[ L ].Height - Y );

          MakeBlock( L, X, Y, W, H, R0_, R1_, D_ );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TLuxImage.Create;
begin
     inherited;

     _Width    := 0;
     _Height   := 0;
     _Version  := 0;
     _Busy     := False;
     _Closing  := False;
     _Progress := 0;
     _Fired    := -1;
     _ProgA    := 0;
     _ProgB    := 1;
end;

constructor TLuxImage.Create( const W_,H_:Integer );
begin
     Create;

     SetSize( W_, H_ );
end;

destructor TLuxImage.Destroy;
begin
     _Closing := True;

     WaitFor;

     inherited;
end;

//////////////////////////////////////////////////////////////////////// C L A S S

class function TLuxImage.IsFloat :Boolean;
begin
     Result := False;
end;

class function TLuxImage.DefaultGamma :Single;
begin
     Result := 1;  // 整数形式は既に表示用に符号化されているとみなす
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImage.SetSize( const W_,H_:Integer );
begin
     if ( W_ < 0 ) or ( H_ < 0 ) then raise EArgumentException.Create( '画像サイズが負である' );

     if ( _Width = W_ ) and ( _Height = H_ ) then
     begin
          Clear;  Exit;
     end;

     _Width  := W_;
     _Height := H_;

     InitLevels;

     Inc( _Version );  Notify;
end;

procedure TLuxImage.Clear;
begin
     FillLevels;

     Inc( _Version );  Notify;
end;

//------------------------------------------------------------------------------

procedure TLuxImage.Changed;
var
   I :Integer;
begin
     if LevelsN > 0 then
     begin
          with _Levels[ 0 ] do for I := 0 to High( Tiles ) do Tiles[ I ].Dirty := 1;
     end;

     Inc( _Version );  Notify;
end;

procedure TLuxImage.TileChanged( const TX_,TY_:Integer );
begin
     with _Levels[ 0 ].Tiles[ TY_ * _Levels[ 0 ].TilesX + TX_ ] do
     begin
          AtomicIncrement( Stamp );
          AtomicExchange( Dirty, 1 );  // 画素の書き込みが Dirty より先に見えるように（不可分操作は全域の障壁）
     end;
end;

procedure TLuxImage.Notify;
begin
     if TThread.CurrentThread.ThreadID = MainThreadID then _OnChange.Run( Self )
     else TThread.Queue( nil, procedure
                              begin
                                   if not _Closing then _OnChange.Run( Self );
                              end );
end;

///// Dirty な段 0 タイルを集め、その足跡を段 1 以上へ反映する。
///// ・段 1〜LUXIMAGE_TILE_LOG ：タイルごとの連鎖が独立なので、タイル単位で並列に。
///// ・それより上の段 ：足跡が 1 画素未満で隣のタイルと混ざるので、段ごと作り直す（画素数はごく僅か）。

procedure TLuxImage.UpdateLevels;
var
   Dirts                        :TArray<Integer>;
   N, I, I0, I1, L, NX, Z       :Integer;
   LL, LX, LW, LH               :Integer;   // 無名メソッドは for の制御変数を捕捉できないので写す
begin
     if LevelsN < 2 then Exit;

     TMonitor.Enter( Self );
     try
          ///// Dirty を降ろしながら集める（降ろしてから読むので、以後の書き込みは取りこぼさない）

          N := 0;

          with _Levels[ 0 ] do
          begin
               SetLength( Dirts, Length( Tiles ) );

               for I := 0 to High( Tiles ) do
               begin
                    if AtomicExchange( Tiles[ I ].Dirty, 0 ) <> 0 then
                    begin
                         Dirts[ N ] := I;  Inc( N );
                    end;
               end;
          end;

          if N = 0 then Exit;

          Z  := PixelSize;
          NX := _Levels[ 0 ].TilesX;

          ///// 段 1〜LUXIMAGE_TILE_LOG ：タイルごとの連鎖を並列に

          I0 := 0;

          while I0 < N do
          begin
               I1 := Min( I0 + UPDATE_CHUNK, N ) - 1;

               TParallel.For( I0, I1, procedure( I:Integer )
                                      var
                                         R0, R1, D :TArray<Byte>;
                                      begin
                                           SetLength( R0, LUXIMAGE_TILE * Z );
                                           SetLength( R1, LUXIMAGE_TILE * Z );
                                           SetLength( D , LUXIMAGE_TILE * Z );

                                           MakeChain( Dirts[ I ] mod NX, Dirts[ I ] div NX, @R0[ 0 ], @R1[ 0 ], @D[ 0 ] );
                                      end );

               I0 := I1 + 1;

               if _Busy then DoProgress( I0 / N );  // 非同期処理中のみ（描画中の再入を避ける）
          end;

          ///// それより上の段 ：段ごと作り直す

          for L := LUXIMAGE_TILE_LOG+1 to LevelsN-1 do  // 段は下から順に（各段は直下の段だけに依存する）
          begin
               LL := L;
               LX := _Levels[ L ].TilesX;
               LW := _Levels[ L ].Width;
               LH := _Levels[ L ].Height;

               TParallel.For( 0, High( _Levels[ L ].Tiles ), procedure( I:Integer )
                                                             var
                                                                R0, R1, D :TArray<Byte>;
                                                                X, Y      :Integer;
                                                             begin
                                                                  SetLength( R0, LUXIMAGE_TILE * 2 * Z );
                                                                  SetLength( R1, LUXIMAGE_TILE * 2 * Z );
                                                                  SetLength( D , LUXIMAGE_TILE     * Z );

                                                                  X := ( I mod LX ) shl LUXIMAGE_TILE_LOG;
                                                                  Y := ( I div LX ) shl LUXIMAGE_TILE_LOG;

                                                                  MakeBlock( LL, X, Y, Min( LUXIMAGE_TILE, LW - X ),
                                                                                       Min( LUXIMAGE_TILE, LH - Y ), @R0[ 0 ], @R1[ 0 ], @D[ 0 ] );
                                                             end );
          end;
     finally
          TMonitor.Exit( Self );
     end;
end;

//------------------------------------------------------------------------------

function TLuxImage.LevelWidth( const L_:Integer ) :Integer;
begin
     Result := _Levels[ L_ ].Width;
end;

function TLuxImage.LevelHeight( const L_:Integer ) :Integer;
begin
     Result := _Levels[ L_ ].Height;
end;

function TLuxImage.LevelTilesX( const L_:Integer ) :Integer;
begin
     Result := _Levels[ L_ ].TilesX;
end;

function TLuxImage.LevelTilesY( const L_:Integer ) :Integer;
begin
     Result := _Levels[ L_ ].TilesY;
end;

function TLuxImage.TileWidth( const L_,TX_:Integer ) :Integer;
begin
     Result := Min( LUXIMAGE_TILE, _Levels[ L_ ].Width - TX_ * LUXIMAGE_TILE );
end;

function TLuxImage.TileHeight( const L_,TY_:Integer ) :Integer;
begin
     Result := Min( LUXIMAGE_TILE, _Levels[ L_ ].Height - TY_ * LUXIMAGE_TILE );
end;

//------------------------------------------------------------------------------

function TLuxImage.TileData( const L_,TX_,TY_:Integer ) :Pointer;
begin
     with _Levels[ L_ ] do Result := @Tiles[ TY_ * TilesX + TX_ ].Data[ 0 ];
end;

function TLuxImage.TileStamp( const L_,TX_,TY_:Integer ) :Cardinal;
begin
     with _Levels[ L_ ] do Result := Tiles[ TY_ * TilesX + TX_ ].Stamp;
end;

//------------------------------------------------------------------------------

procedure TLuxImage.GetRaws( const L_,X_,Y_,N_:Integer; const Dst_:Pointer );
var
   Z, I, C, TX, PX, TY, PY :Integer;
   D                       :PByte;
begin
     Z := PixelSize;
     D := Dst_;

     TY := Y_ shr LUXIMAGE_TILE_LOG;
     PY := Y_ and ( LUXIMAGE_TILE - 1 );

     I := 0;

     while I < N_ do
     begin
          TX := ( X_ + I ) shr LUXIMAGE_TILE_LOG;
          PX := ( X_ + I ) and ( LUXIMAGE_TILE - 1 );

          C := Min( LUXIMAGE_TILE - PX, N_ - I );

          Move( ( PByte( TileData( L_, TX, TY ) ) + ( PY * LUXIMAGE_TILE + PX ) * Z )^, D^, C * Z );

          Inc( D, C * Z );
          Inc( I, C );
     end;
end;

procedure TLuxImage.SetRaws( const L_,X_,Y_,N_:Integer; const Src_:Pointer );
var
   Z, I, C, TX, PX, TY, PY :Integer;
   S                       :PByte;
begin
     Z := PixelSize;
     S := Src_;

     TY := Y_ shr LUXIMAGE_TILE_LOG;
     PY := Y_ and ( LUXIMAGE_TILE - 1 );

     I := 0;

     while I < N_ do
     begin
          TX := ( X_ + I ) shr LUXIMAGE_TILE_LOG;
          PX := ( X_ + I ) and ( LUXIMAGE_TILE - 1 );

          C := Min( LUXIMAGE_TILE - PX, N_ - I );

          Move( S^, ( PByte( TileData( L_, TX, TY ) ) + ( PY * LUXIMAGE_TILE + PX ) * Z )^, C * Z );

          Inc( S, C * Z );
          Inc( I, C );
     end;
end;

//------------------------------------------------------------------------------

procedure TLuxImage.GetRow( const L_,X_,Y_,N_:Integer; const Dst_:PSingleRGBA );
var
   Z, I, C, TX, PX, TY, PY :Integer;
   D                       :PSingleRGBA;
begin
     Z := PixelSize;
     D := Dst_;

     TY := Y_ shr LUXIMAGE_TILE_LOG;
     PY := Y_ and ( LUXIMAGE_TILE - 1 );

     I := 0;

     while I < N_ do
     begin
          TX := ( X_ + I ) shr LUXIMAGE_TILE_LOG;
          PX := ( X_ + I ) and ( LUXIMAGE_TILE - 1 );

          C := Min( LUXIMAGE_TILE - PX, N_ - I );

          RowIn( PByte( TileData( L_, TX, TY ) ) + ( PY * LUXIMAGE_TILE + PX ) * Z, D, C );

          Inc( D, C );
          Inc( I, C );
     end;
end;

procedure TLuxImage.SetRow( const L_,X_,Y_,N_:Integer; const Src_:PSingleRGBA );
var
   Z, I, C, TX, PX, TY, PY :Integer;
   S                       :PSingleRGBA;
begin
     Z := PixelSize;
     S := Src_;

     TY := Y_ shr LUXIMAGE_TILE_LOG;
     PY := Y_ and ( LUXIMAGE_TILE - 1 );

     I := 0;

     while I < N_ do
     begin
          TX := ( X_ + I ) shr LUXIMAGE_TILE_LOG;
          PX := ( X_ + I ) and ( LUXIMAGE_TILE - 1 );

          C := Min( LUXIMAGE_TILE - PX, N_ - I );

          RowOut( S, PByte( TileData( L_, TX, TY ) ) + ( PY * LUXIMAGE_TILE + PX ) * Z, C );

          Inc( S, C );
          Inc( I, C );
     end;
end;

//------------------------------------------------------------------------------

procedure TLuxImage.LoadFromFile( const FileName_:String );
begin
     _Progress := 0;  _Fired := -1;

     TLuxImageFiler.LoadFromFile( Self, FileName_ );

     UpdateLevels;

     DoProgress( 1 );
end;

procedure TLuxImage.SaveToFile( const FileName_:String; const Quality_:Integer = 90 );
begin
     _Progress := 0;  _Fired := -1;

     TLuxImageFiler.SaveToFile( Self, FileName_, Quality_ );

     DoProgress( 1 );
end;

//------------------------------------------------------------------------------

procedure TLuxImage.LoadFromFileAsync( const FileName_:String );
var
   F :String;
begin
     F := FileName_;

     StartAsync( procedure
                 begin
                      ProgRange( 0, 0.75 );  TLuxImageFiler.LoadFromFile( Self, F );

                      ///// 表示に要る縮小段も、ここで作り終えてしまう。
                      ///// 最初の描画時に作ると、その分だけ UI が止まってしまうため。

                      ProgRange( 0.75, 1 );  UpdateLevels;

                      ProgRange( 0, 1 );
                 end, False );
end;

procedure TLuxImage.SaveToFileAsync( const FileName_:String; const Quality_:Integer = 90 );
var
   F :String;
   Q :Integer;
begin
     F := FileName_;  Q := Quality_;

     StartAsync( procedure
                 begin
                      TLuxImageFiler.SaveToFile( Self, F, Q );
                 end, True );
end;

procedure TLuxImage.WaitFor;
begin
     if Assigned( _Task ) then
     begin
          _Task.Wait;  _Task := nil;
     end;

     ///// 保留中の通知を、まだ自分が生きているうちに流し切る

     if TThread.CurrentThread.ThreadID = MainThreadID then CheckSynchronize;
end;

procedure TLuxImage.DoProgress( const Ratio_:Single );
begin
     _Progress := _ProgA + ( _ProgB - _ProgA ) * Clamp( Ratio_, 0, 1 );

     if Abs( _Progress - _Fired ) < 0.01 then Exit;  // 1% 刻みに間引く

     _Fired := _Progress;

     if TThread.CurrentThread.ThreadID = MainThreadID then _OnProgress.Run( Self )
     else TThread.Queue( nil, procedure
                              begin
                                   if not _Closing then _OnProgress.Run( Self );
                              end );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageUInt08

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TLuxImageUInt08.GetPixels( const X_,Y_:Integer ) :TByteRGBA;
begin
     GetRaws( 0, X_, Y_, 1, @Result );
end;

procedure TLuxImageUInt08.SetPixels( const X_,Y_:Integer; const P_:TByteRGBA );
begin
     SetRaws( 0, X_, Y_, 1, @P_ );

     TileChanged( X_ shr LUXIMAGE_TILE_LOG, Y_ shr LUXIMAGE_TILE_LOG );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageUInt08.RowIn( const Src_:Pointer; const Dst_:PSingleRGBA; const N_:Integer );
var
   S :PByteRGBA;
   D :PSingleRGBA;
   I :Integer;
begin
     S := Src_;  D := Dst_;

     for I := 1 to N_ do
     begin
          D^ := S^;  Inc( S );  Inc( D );
     end;
end;

procedure TLuxImageUInt08.RowOut( const Src_:PSingleRGBA; const Dst_:Pointer; const N_:Integer );
var
   S :PSingleRGBA;
   D :PByteRGBA;
   I :Integer;
begin
     S := Src_;  D := Dst_;

     for I := 1 to N_ do
     begin
          D^ := TByteRGBA( S^ );  Inc( S );  Inc( D );
     end;
end;

procedure TLuxImageUInt08.MipRow( const Src0_,Src1_,Dst_:Pointer; const N_:Integer );
var
   S0, S1 :PByteRGBA;
   D      :PByteRGBA;
   I      :Integer;
begin
     S0 := Src0_;  S1 := Src1_;  D := Dst_;

     for I := 1 to N_ do
     begin
          with D^ do
          begin
               R := ( S0[0].R + S0[1].R + S1[0].R + S1[1].R + 2 ) div 4;
               G := ( S0[0].G + S0[1].G + S1[0].G + S1[1].G + 2 ) div 4;
               B := ( S0[0].B + S0[1].B + S1[0].B + S1[1].B + 2 ) div 4;
               A := ( S0[0].A + S0[1].A + S1[0].A + S1[1].A + 2 ) div 4;
          end;

          Inc( S0, 2 );  Inc( S1, 2 );  Inc( D );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////////// C L A S S

class function TLuxImageUInt08.PixelKind :TLuxPixel;
begin
     Result := bpUInt08;
end;

class function TLuxImageUInt08.PixelSize :Integer;
begin
     Result := SizeOf( TByteRGBA );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageUInt16

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TLuxImageUInt16.GetPixels( const X_,Y_:Integer ) :TWordRGBA;
begin
     GetRaws( 0, X_, Y_, 1, @Result );
end;

procedure TLuxImageUInt16.SetPixels( const X_,Y_:Integer; const P_:TWordRGBA );
begin
     SetRaws( 0, X_, Y_, 1, @P_ );

     TileChanged( X_ shr LUXIMAGE_TILE_LOG, Y_ shr LUXIMAGE_TILE_LOG );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageUInt16.RowIn( const Src_:Pointer; const Dst_:PSingleRGBA; const N_:Integer );
var
   S :PWordRGBA;
   D :PSingleRGBA;
   I :Integer;
begin
     S := Src_;  D := Dst_;

     for I := 1 to N_ do
     begin
          D^ := S^;  Inc( S );  Inc( D );
     end;
end;

procedure TLuxImageUInt16.RowOut( const Src_:PSingleRGBA; const Dst_:Pointer; const N_:Integer );
var
   S :PSingleRGBA;
   D :PWordRGBA;
   I :Integer;
begin
     S := Src_;  D := Dst_;

     for I := 1 to N_ do
     begin
          D^ := S^;  Inc( S );  Inc( D );
     end;
end;

procedure TLuxImageUInt16.MipRow( const Src0_,Src1_,Dst_:Pointer; const N_:Integer );
var
   S0, S1 :PWordRGBA;
   D      :PWordRGBA;
   I      :Integer;
begin
     S0 := Src0_;  S1 := Src1_;  D := Dst_;

     for I := 1 to N_ do
     begin
          with D^ do
          begin
               R := ( Cardinal( S0[0].R ) + S0[1].R + S1[0].R + S1[1].R + 2 ) div 4;
               G := ( Cardinal( S0[0].G ) + S0[1].G + S1[0].G + S1[1].G + 2 ) div 4;
               B := ( Cardinal( S0[0].B ) + S0[1].B + S1[0].B + S1[1].B + 2 ) div 4;
               A := ( Cardinal( S0[0].A ) + S0[1].A + S1[0].A + S1[1].A + 2 ) div 4;
          end;

          Inc( S0, 2 );  Inc( S1, 2 );  Inc( D );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////////// C L A S S

class function TLuxImageUInt16.PixelKind :TLuxPixel;
begin
     Result := bpUInt16;
end;

class function TLuxImageUInt16.PixelSize :Integer;
begin
     Result := SizeOf( TWordRGBA );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageSFlo16

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TLuxImageSFlo16.GetPixels( const X_,Y_:Integer ) :THalfRGBA;
begin
     GetRaws( 0, X_, Y_, 1, @Result );
end;

procedure TLuxImageSFlo16.SetPixels( const X_,Y_:Integer; const P_:THalfRGBA );
begin
     SetRaws( 0, X_, Y_, 1, @P_ );

     TileChanged( X_ shr LUXIMAGE_TILE_LOG, Y_ shr LUXIMAGE_TILE_LOG );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageSFlo16.RowIn( const Src_:Pointer; const Dst_:PSingleRGBA; const N_:Integer );
var
   S :PHalfRGBA;
   D :PSingleRGBA;
   I :Integer;
begin
     S := Src_;  D := Dst_;

     for I := 1 to N_ do
     begin
          D^ := S^;  Inc( S );  Inc( D );
     end;
end;

procedure TLuxImageSFlo16.RowOut( const Src_:PSingleRGBA; const Dst_:Pointer; const N_:Integer );
var
   S :PSingleRGBA;
   D :PHalfRGBA;
   I :Integer;
begin
     S := Src_;  D := Dst_;

     for I := 1 to N_ do
     begin
          D^ := S^;  Inc( S );  Inc( D );
     end;
end;

procedure TLuxImageSFlo16.MipRow( const Src0_,Src1_,Dst_:Pointer; const N_:Integer );
var
   S0, S1 :PHalfRGBA;
   D      :PHalfRGBA;
   I      :Integer;
begin
     S0 := Src0_;  S1 := Src1_;  D := Dst_;

     for I := 1 to N_ do
     begin
          with D^ do
          begin
               R := ( Single( S0[0].R ) + Single( S0[1].R ) + Single( S1[0].R ) + Single( S1[1].R ) ) / 4;
               G := ( Single( S0[0].G ) + Single( S0[1].G ) + Single( S1[0].G ) + Single( S1[1].G ) ) / 4;
               B := ( Single( S0[0].B ) + Single( S0[1].B ) + Single( S1[0].B ) + Single( S1[1].B ) ) / 4;
               A := ( Single( S0[0].A ) + Single( S0[1].A ) + Single( S1[0].A ) + Single( S1[1].A ) ) / 4;
          end;

          Inc( S0, 2 );  Inc( S1, 2 );  Inc( D );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////////// C L A S S

class function TLuxImageSFlo16.PixelKind :TLuxPixel;
begin
     Result := bpSFlo16;
end;

class function TLuxImageSFlo16.PixelSize :Integer;
begin
     Result := SizeOf( THalfRGBA );
end;

class function TLuxImageSFlo16.IsFloat :Boolean;
begin
     Result := True;
end;

class function TLuxImageSFlo16.DefaultGamma :Single;
begin
     Result := 2.2;  // 浮動小数形式はリニアとみなす
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TLuxImageSFlo32

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TLuxImageSFlo32.GetPixels( const X_,Y_:Integer ) :TSingleRGBA;
begin
     GetRaws( 0, X_, Y_, 1, @Result );
end;

procedure TLuxImageSFlo32.SetPixels( const X_,Y_:Integer; const P_:TSingleRGBA );
begin
     SetRaws( 0, X_, Y_, 1, @P_ );

     TileChanged( X_ shr LUXIMAGE_TILE_LOG, Y_ shr LUXIMAGE_TILE_LOG );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TLuxImageSFlo32.RowIn( const Src_:Pointer; const Dst_:PSingleRGBA; const N_:Integer );
begin
     Move( Src_^, Dst_^, N_ * SizeOf( TSingleRGBA ) );  // 記憶形式そのもの
end;

procedure TLuxImageSFlo32.RowOut( const Src_:PSingleRGBA; const Dst_:Pointer; const N_:Integer );
begin
     Move( Src_^, Dst_^, N_ * SizeOf( TSingleRGBA ) );  // 記憶形式そのもの
end;

procedure TLuxImageSFlo32.MipRow( const Src0_,Src1_,Dst_:Pointer; const N_:Integer );
var
   S0, S1 :PSingleRGBA;
   D      :PSingleRGBA;
   I      :Integer;
begin
     S0 := Src0_;  S1 := Src1_;  D := Dst_;

     for I := 1 to N_ do
     begin
          D^ := ( S0[0] + S0[1] + S1[0] + S1[1] ) / 4;

          Inc( S0, 2 );  Inc( S1, 2 );  Inc( D );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////////// C L A S S

class function TLuxImageSFlo32.PixelKind :TLuxPixel;
begin
     Result := bpSFlo32;
end;

class function TLuxImageSFlo32.PixelSize :Integer;
begin
     Result := SizeOf( TSingleRGBA );
end;

class function TLuxImageSFlo32.IsFloat :Boolean;
begin
     Result := True;
end;

class function TLuxImageSFlo32.DefaultGamma :Single;
begin
     Result := 2.2;  // 浮動小数形式はリニアとみなす
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% LuxImageClass

function LuxImageClass( const Kind_:TLuxPixel ) :TLuxImageClass;
begin
     case Kind_ of
       bpUInt08: Result := TLuxImageUInt08;
       bpUInt16: Result := TLuxImageUInt16;
       bpSFlo16: Result := TLuxImageSFlo16;
       bpSFlo32: Result := TLuxImageSFlo32;
     else        Result := nil;
     end;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% LuxFreeMemory

function LuxFreeMemory :Int64;
{$IFDEF MSWINDOWS}
var
   S :TMemoryStatusEx;
begin
     S.dwLength := SizeOf( S );

     if GlobalMemoryStatusEx( S ) then Result := S.ullAvailPhys
                                  else Result := -1;
end;
{$ELSE}
begin
     Result := -1;
end;
{$ENDIF}

end. //######################################################################### ■
