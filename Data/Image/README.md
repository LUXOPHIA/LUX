# LUX.Data.Image
[English](README.md) | [日本語](ja/README.md)

An ultra-high-resolution image library for Delphi / FireMonkey. `TLuxImage` keeps every pixel in CPU memory as a tiled mip pyramid, so the usable size is not bounded by the GPU's texture limit — it is unlimited as far as RAM allows — and the accompanying viewer displays an image in real time at a cost that depends on the size of the window rather than the size of the image. Tiles track their own changes, so many threads can render into an image at once and watch it appear on screen block by block.

## 1. Overview

FireMonkey's `TBitmap` shares its storage with the GPU and therefore inherits the GPU's texture size limit, which in practice caps it at about 8,192 × 8,192 pixels. `TLuxImage` does not: pixels live in ordinary heap blocks, divided into 256 × 256 tiles, and no part of the image needs to be resident on the GPU at once.

### 1.1 Features

- **No GPU size limit.** Pixels live in CPU memory, in 256 × 256 tiles.
- **All memory allocated up front.** `SetSize` allocates every tile of every level; if the image does not fit it fails there and then with `EOutOfMemory`, and never later.
- **Four pixel formats**, each mapping one-to-one onto a native Skia colour type: 8-bit and 16-bit unsigned integer, 16-bit and 32-bit floating point, all RGBA.
- **Built-in mip pyramid**, so a zoomed-out view costs the same as a zoomed-in one, and **per-tile change tracking**, so a change to one tile propagates up the pyramid at a cost of one third of a tile, not one third of the image.
- **Lock-free concurrent writing.** Any number of threads may write disjoint regions at once and report each finished tile with `TileChanged`; the viewer picks the changes up in real time.
- **`TLuxImageWorker`**, a block scheduler that runs an arbitrary per-block procedure over the whole image on all cores, handing out blocks one at a time so that wildly uneven per-pixel cost — ray tracing, fractals — still balances.
- **Real-time viewer** with smooth wheel zoom and drag scrolling, GPU tone mapping and gamma correction, which shows a rendering in progress block by block.
- **Colour management.** An image may carry a `ColorSpace` — sRGB, Display P3, Adobe RGB, Rec.2020, ProPhoto, ACEScg, their linear forms, or any space of your own — which is embedded in PNG (`sRGB` / `iCCP` + `gAMA` + `cHRM`) and JPEG (APP2 `ICC_PROFILE`) on save, recovered on load, and honoured by the viewer, which converts on the GPU to the monitor's own profile. `nil` means no colour management, and pixel values are never altered.
- **Asynchronous file I/O** with progress reporting and completion events.
- Depends only on the RTL, FireMonkey and Skia, all of which ship with RAD Studio.

### 1.2 Requirements

- RAD Studio 12 or later (developed and tested on RAD Studio 13 / Delphi 37.0)
- Windows 64-bit
- Skia (bundled with RAD Studio); `sk4d.dll` must be deployed alongside the executable

## 2. Technical Background

### 2.1 Tiled storage and the mip pyramid

Pixels are held in tiles of `LUXIMAGE_TILE` (256) square, each tile a separate heap block. This avoids a single huge contiguous allocation and keeps a write, a read or a bilinear sample within one tile in the common case. Tiles carry no padding: a tile is a plain `256 × 256 × PixelSize` block whose row pitch is 256 pixels.

Every tile of every level is allocated by `SetSize`. Nothing is allocated lazily, so a pointer returned by `TileData` is always valid, two threads writing disjoint regions never race on an allocation, and an image that does not fit in memory is refused at `SetSize` rather than part-way through a load or a render. Before allocating, `SetSize` compares the total requirement against the free physical memory and refuses without allocating if it exceeds it — the library assumes RAM, not the page file, is the bound.

Every image owns a pyramid of half-size levels. Level 0 is the original; each subsequent level halves both dimensions, rounding up, down to 1 × 1:

```math
W_{\ell+1} = \max\!\left( 1, \left\lceil \frac{W_\ell}{2} \right\rceil \right), \qquad H_{\ell+1} = \max\!\left( 1, \left\lceil \frac{H_\ell}{2} \right\rceil \right) \qquad \text{(2.1)}
```

With $T$ = `LUXIMAGE_TILE`, level $\ell$ therefore holds

```math
\mathrm{TilesX}_\ell = \left\lceil \frac{W_\ell}{T} \right\rceil, \qquad \mathrm{TilesY}_\ell = \left\lceil \frac{H_\ell}{T} \right\rceil \qquad \text{(2.2)}
```

tiles, of which the ones on the right and bottom edges are partially filled.

The pyramid costs a bounded fraction of the base level, because each level holds a quarter of the pixels of the one below it:

```math
\sum_{\ell=1}^{\infty} \frac{1}{4^{\ell}} = \frac{1}{3} \qquad \text{(2.3)}
```

so the pyramid adds roughly 33 % to the memory of level 0, and the total allocated by `SetSize` is about $\tfrac{4}{3}\,W H \cdot$ `PixelSize`.

### 2.2 Change tracking and incremental pyramid update

Each level-0 tile carries a *dirty* flag and every tile of every level carries a *stamp*, a counter advanced whenever the tile's content changes. `TileChanged` sets the flag and advances the stamp; it is a pair of atomic operations, so any thread may call it without a lock.

`UpdateLevels` collects the dirty tiles and rebuilds only their *footprints* in the levels above. The footprint of level-0 tile $(t_x, t_y)$ in level $\ell$ is the square

```math
\left[\, t_x \frac{T}{2^{\ell}},\; (t_x + 1) \frac{T}{2^{\ell}} \right) \times \left[\, t_y \frac{T}{2^{\ell}},\; (t_y + 1) \frac{T}{2^{\ell}} \right) \qquad \text{(2.4)}
```

which, for $\ell \le \log_2 T = 8$, is at least one pixel and is computed solely from the same tile's footprint in level $\ell - 1$. The chains of different tiles are therefore independent up to level 8 and are run in parallel, one chain per dirty tile. Above level 8 a footprint is smaller than a pixel and mixes with its neighbours, so those levels are rebuilt whole — they hold at most $W H / 4^{9}$ pixels, which is negligible.

The work of one chain is a quarter, a sixteenth, … of a tile:

```math
\sum_{\ell=1}^{8} \frac{1}{4^{\ell}} \approx \frac{1}{3} \qquad \text{(2.5)}
```

so propagating a change costs about a third of the tile that changed. A whole-image change (`Changed`, or a file load) goes through the very same path with every tile dirty, and costs the same third of the image that a full pyramid build always did.

The viewer validates its per-tile GPU cache against the stamps — a tile's own and its eight neighbours', because the cached image carries a one-pixel apron of them — and calls `UpdateLevels` before every frame. A renderer that writes tiles from many threads therefore appears on screen block by block, without any coupling between the renderer and the viewer beyond `TileChanged` and `Notify`.

### 2.3 Parallel block scheduling

`TLuxImageWorker` cuts level 0 into square blocks that never cross a tile, numbers them in raster order and hands them to $N$ worker threads through a single atomic counter, one block at a time. No range is assigned statically, so the imbalance at the end of the run is at most one block, whatever the distribution of per-pixel cost — a property that matters for ray tracing, where adjacent pixels can differ by orders of magnitude. Because all tiles are allocated and blocks are disjoint, the workers need no lock; each reports its finished block with `TileChanged` and, throttled to about 30 Hz, asks the image to `Notify` and raises `OnProgress` on the main thread.

### 2.4 Level selection

For a display scale $s$ in screen pixels per image pixel, the viewer draws from level

```math
\ell = \min\!\left( \max\!\left( 0, \left\lceil -\log_2 s \right\rceil \right), \; \mathrm{LevelsN} - 1 \right) \qquad \text{(2.6)}
```

whose effective per-pixel scale is

```math
S = s \cdot 2^{\ell} \in [\,1, 2\,) \qquad \text{(2.7)}
```

Because $S \ge 1$ always, minification never occurs inside a level, and minification aliasing cannot arise. The number of visible tiles is then bounded by the window, not by the image:

```math
N_{\text{tiles}} \le \left( \left\lceil \frac{W_{\text{view}}}{S \cdot T} \right\rceil + 1 \right) \left( \left\lceil \frac{H_{\text{view}}}{S \cdot T} \right\rceil + 1 \right) \qquad \text{(2.8)}
```

For a 1920 × 1080 window this is at most about 9 × 6 = 54 tiles, whatever the size of the image.

### 2.5 Display transfer functions

The viewer applies gamma correction

```math
C' = C^{\,1/\gamma} \qquad \text{(2.9)}
```

and, optionally, the extended Reinhard tone-mapping operator [4] with white point $L_w$ (the `White` property, default 1):

```math
C' = \operatorname{clamp}\!\left( \frac{C \left( 1 + C / L_w^{\,2} \right)}{1 + C}, \; 0, \; 1 \right) \qquad \text{(2.10)}
```

Both are evaluated by an SkSL runtime colour filter on the GPU, so changing `Gamma`, `ToneMap` or `White` costs nothing and does not invalidate the tile cache.

## 3. Architecture

### 3.1 Module and class structure

```
[ units and what they declare ]

・LUX.Data.Image                      ･･･ RTL only
  ┣・TLuxPixel                       ･･･ ( bpUInt08 … bpSFlo32 )
  ┣・TLuxTile                        ･･･ ( Data, Stamp, Dirty )
  ┣・TLuxLevel                       ･･･ ( Width, Height, Tiles* )
  ┣・TLuxImage                       ･･･ ( see the class hierarchy below )
  ┣・LUX.Data.Image.Files            ･･･ [ Skia ]
  ┃  ┣・TLuxImageFiler
  ┃  ┃  ┣・LoadFromPng / SaveToPng ･･･ System.ZLib, streaming
  ┃  ┃  ┗・LoadFromJpg / SaveToJpg ･･･ Skia codec
  ┃  ┣・LuxSkColorType
  ┃  ┗・LuxImageSize
  ┣・LUX.Data.Image.Worker           ･･･ RTL only
  ┃  ┣・TLuxBlockProc                ･･･ procedure( ThreadI_, X_,Y_,W_,H_ )
  ┃  ┗・TLuxImageWorker              ･･･ block scheduler on N threads
  ┗・LUX.Data.Image.Viewer           ･･･ [ FireMonkey + Skia ]
     ┗・TLuxImageViewer              ･･･ ( TFrame )
        ┣・TTileKey  TTileImg
        ┣・ISkImage cache + apron    ･･･ validated by tile stamps
        ┣・SkSL colour filter
        ┗・wheel zoom / drag scroll

[ class hierarchy ]

・TLuxImage
  ┣・TLuxImageUInt08                 ･･･ TByteRGBA
  ┣・TLuxImageUInt16                 ･･･ TWordRGBA
  ┣・TLuxImageSFlo16                 ･･･ THalfRGBA
  ┗・TLuxImageSFlo32                 ･･･ TSingleRGBA

[ pixel path ]  tiles → mip pyramid → Skia

・TLuxImage
  ┗・level 0                         ･･･ original pixels, 256 × 256 tiles, Dirty + Stamp
     ┗・mip pyramid                  ･･･ level ℓ+1 = half of ℓ ( UpdateLevels, footprints of dirty tiles )
        ┗・level chosen by (2.6)     ･･･ effective scale S ∈ [ 1, 2 )
           ┗・visible tiles of it    ･･･ bounded by (2.8), not by the image
              ┗・ISkImage + apron    ･･･ cached as TTileImg under TTileKey, rebuilt when a stamp moves
                 ┗・DrawImageRect    ･･･ SkSL colour filter: tone map + gamma

[ writer path ]  any thread → tiles → viewer

・TLuxImageWorker ( or your own threads )
  ┗・block                           ･･･ SetRow / SetRaws / TileData, disjoint per block
     ┗・TileChanged                  ･･･ Dirty := 1, Stamp++  ( atomic, no lock )
        ┗・Notify  ( ≤ 30 Hz )       ･･･ OnChange on the main thread
           ┗・viewer frame           ･･･ UpdateLevels, then draw

[ supporting units of the LUX standard library ]

・LUX                                 ･･･ base declarations, TDelegates
  ┣・LUX.Color                       ･･･ TByteRGBA  TWordRGBA  TSingleRGBA
  ┃  ┣・LUX.Color.Half              ･･･ THalfRGB  THalfRGBA
  ┃  ┗・LUX.Color.Space             ･･･ TLuxColorSpace, presets, TLuxColorSpaces, ICC read / write
  ┣・LUX.D2  LUX.D3  LUX.D3x3        ･･･ chromaticities, XYZ, 3 × 3 matrices
  ┗・LUX.D1.Half                     ･･･ THalf, the half-precision scalar
     ┗・LUX.D1.Half.DIff             ･･･ TdHalf, automatic differentiation
```

`LUX.Data.Image.pas` and `LUX.Data.Image.Worker.pas` use neither FireMonkey nor Skia; those dependencies are confined to the file and viewer units.

### 3.2 File layout

```
・Data/Image/
  ┣・LUX.Data.Image.pas        ･･･ TLuxImage and the 4 concrete classes
  ┣・LUX.Data.Image.Files.pas  ･･･ file reading and writing
  ┣・LUX.Data.Image.Worker.pas ･･･ TLuxImageWorker, parallel block scheduler
  ┗・LUX.Data.Image.Viewer.pas ･･･ TLuxImageViewer ( TFrame )
```

## 4. Usage

### 4.1 Project setup

Enable the Skia canvas in the project source file, and include `FMX.Skia.Canvas.Vulkan` so that the Vulkan backend registers itself:

```pascal
uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  FMX.Skia.Canvas.Vulkan,
  ...

begin
  GlobalUseSkia                    := True;
  GlobalUseSkiaRasterWhenAvailable := False;

  Application.Initialize;
  ...
```

With this in place the viewer draws straight into the window surface: there is no intermediate raster surface and no per-frame texture upload of the whole window. Without it the viewer still works — it renders through an intermediate raster bitmap instead — but that costs a full-window blit every frame.

### 4.2 Loading and displaying an image

```pascal
Image  := TLuxImageUInt08.Create;

Viewer        := TLuxImageViewer.Create( Self );
Viewer.Parent := Self;
Viewer.Align  := TAlignLayout.Client;
Viewer.Image  := Image;

Image.OnLoaded.Add( ImageLoaded );

Image.LoadFromFileAsync( 'huge.jpg' );
```

```pascal
procedure TForm1.ImageLoaded( Sender_:TObject );
begin
     Viewer.FitToWindow;
end;
```

### 4.3 Rendering into an image on all cores

`TLuxImageWorker` runs a procedure of your own over every block of the image. The procedure receives the worker index and the block rectangle in level-0 pixels; what it computes — a ray-traced scene, a fractal, a filter of another image — is entirely up to it. The viewer, if one is attached, shows the blocks as they finish.

```pascal
Image := TLuxImageSFlo32.Create( 16384, 16384 );  // all memory allocated here; EOutOfMemory if it does not fit

Viewer.Image := Image;
Viewer.FitToWindow;

Worker := TLuxImageWorker.Create( Image );

Worker.OnProgress.Add( WorkerProgress );  // about 30 Hz, main thread
Worker.OnFinished.Add( WorkerFinished );  // main thread, also after Cancel

Worker.Start( procedure( const ThreadI_,X_,Y_,W_,H_:Integer )
              var
                 Row  :TArray<TSingleRGBA>;
                 I, J :Integer;
              begin
                   SetLength( Row, W_ );

                   for J := Y_ to Y_+H_-1 do
                   begin
                        for I := 0 to W_-1 do Row[ I ] := Shade( X_+I, J );  // your computation

                        Image.SetRow( 0, X_, J, W_, @Row[ 0 ] );
                   end;
              end );
```

`Block` (default 64) is the side of a block and `ThreadsN` (default: the number of logical processors in every processor group) the number of threads. Set `Writing := False` for a pass that only reads the image, so that no tile is marked changed.

Threads of your own can do the same thing without the worker: write disjoint regions through `SetRow`, `SetRaws` or `TileData`, call `TileChanged` for each level-0 tile you finish, and call `Notify` — at a rate you throttle — whenever the display should catch up.

### 4.4 Colour spaces

```pascal
Image.ColorSpace := TLuxColorSpaces.LinearRec2020;   // "these pixels are linear Rec.2020" — the pixels themselves are untouched
Image.SaveToFile( 'render.png' );                     // iCCP + cHRM + gAMA are written
Image.SaveToFile( 'render.jpg', 95 );                 // APP2 ICC_PROFILE is written

Image.LoadFromFile( 'photo.jpg' );                    // an embedded Adobe RGB profile → Image.ColorSpace = TLuxColorSpaces.AdobeRGB
                                                      // an unknown profile → a new TLuxColorSpace, kept in TLuxColorSpaces
                                                      // no profile → nil

Viewer.ColorSpace := nil;                             // default: convert to the monitor's own profile
Viewer.ColorSpace := TLuxColorSpaces.sRGB;            // or force sRGB
```

`ColorSpace` is a reference, never owned by the image: the presets live in `TLuxColorSpaces` for the life of the program, and spaces read from files are interned there by content, so an image may be assigned any of them freely and compared by pointer.

## 5. Pixel Formats

| Class | Pixel record | Bytes / pixel | Skia colour type | Default display gamma |
|---|---|---|---|---|
| `TLuxImageUInt08` | `TByteRGBA` | 4 | `BGRA8888` | 1.0 |
| `TLuxImageUInt16` | `TWordRGBA` | 8 | `RGBA16161616` | 1.0 |
| `TLuxImageSFlo16` | `THalfRGBA` | 8 | `RGBAF16` | 2.2 |
| `TLuxImageSFlo32` | `TSingleRGBA` | 16 | `RGBAF32` | 2.2 |

Because each format matches a native Skia colour type, the viewer hands tiles to the GPU without any pixel-format conversion. The 16-bit floating-point format is IEEE 754 `binary16` [5].

Alpha is stored straight, that is, not premultiplied.

Integer formats are taken to hold display-encoded values — a JPEG is already sRGB — so their default display gamma is 1.0. Floating-point formats are taken to hold linear values, so their default gamma is 2.2 and tone mapping is enabled by default.

## 6. API Reference

### 6.1 TLuxImage

```pascal
///// size  ( SetSize allocates every tile of every level, or raises EOutOfMemory and leaves the image empty )
procedure SetSize( const W_,H_:Integer );
procedure Clear;                        // zero every level
property  Width  :Integer;
property  Height :Integer;

///// format
class function PixelKind :TLuxPixel;    // bpUInt08 / bpUInt16 / bpSFlo16 / bpSFlo32
class function PixelSize :Integer;      // bytes per pixel
class function IsFloat :Boolean;
class function DefaultGamma :Single;

///// pixel access, format independent
property Colors[ const X_,Y_:Integer ] :TSingleRGBA; default;
procedure GetRow( const L_,X_,Y_,N_:Integer; const Dst_:PSingleRGBA );
procedure SetRow( const L_,X_,Y_,N_:Integer; const Src_:PSingleRGBA );

///// pixel access, typed  ( declared on each concrete class )
property Pixels[ const X_,Y_:Integer ] :TByteRGBA;    // TLuxImageUInt08
property Pixels[ const X_,Y_:Integer ] :TWordRGBA;    // TLuxImageUInt16
property Pixels[ const X_,Y_:Integer ] :THalfRGBA;    // TLuxImageSFlo16
property Pixels[ const X_,Y_:Integer ] :TSingleRGBA;  // TLuxImageSFlo32

///// raw access, crossing tile boundaries transparently
procedure GetRaws( const L_,X_,Y_,N_:Integer; const Dst_:Pointer );
procedure SetRaws( const L_,X_,Y_,N_:Integer; const Src_:Pointer );

///// levels and tiles
property LevelsN :Integer;
function LevelWidth ( const L_:Integer ) :Integer;
function LevelHeight( const L_:Integer ) :Integer;
function LevelTilesX( const L_:Integer ) :Integer;
function LevelTilesY( const L_:Integer ) :Integer;
function TileWidth  ( const L_,TX_:Integer ) :Integer;
function TileHeight ( const L_,TY_:Integer ) :Integer;
function TileData ( const L_,TX_,TY_:Integer ) :Pointer;   // always valid; row pitch is LUXIMAGE_TILE pixels
function TileStamp( const L_,TX_,TY_:Integer ) :Cardinal;  // advanced whenever the tile's content changes

///// change tracking
procedure TileChanged( const TX_,TY_:Integer );  // level-0 tile written: mark dirty, advance stamp  ( any thread, no lock, no event )
procedure Notify;                                // raise OnChange on the main thread
procedure Changed;                               // whole image changed: every tile dirty, Version++, Notify
procedure UpdateLevels;                          // propagate dirty tiles to levels 1…  ( calls are serialised )

///// files, synchronous
procedure LoadFromFile( const FileName_:String );
procedure SaveToFile( const FileName_:String; const Quality_:Integer = 90; const Alpha_:Boolean = True );  // PNG: Alpha_=False writes RGB without alpha; ColorSpace, if any, is embedded

///// files, on a worker thread
procedure LoadFromFileAsync( const FileName_:String );
procedure SaveToFileAsync( const FileName_:String; const Quality_:Integer = 90; const Alpha_:Boolean = True );
procedure WaitFor;
property  Busy     :Boolean;
property  Progress :Single;      // 0 … 1

///// colour space  ( LUX.Color.Space; not owned; nil = no colour management )
property  ColorSpace :TLuxColorSpace;

///// notification
property  Version    :Cardinal;  // incremented by SetSize, Clear and Changed  ( the viewer drops its whole cache )
property  OnChange   :TDelegates;
property  OnProgress :TDelegates;
property  OnLoaded   :TDelegates;
property  OnSaved    :TDelegates;
```

Writing pixels — `SetRow`, `SetRaws`, or directly through `TileData` — does not by itself mark anything. Call `TileChanged` for each level-0 tile you have finished, or `Changed` once after touching the whole image; then `Notify` when the display should catch up. `Changed` notifies by itself. The single-pixel property setters call `TileChanged` for the tile they touch and do not notify.

`UpdateLevels` is what turns dirty tiles into up-to-date mip levels. The viewer calls it before every frame and the loader calls it once after a file is read; a program that reads the levels itself must call it too. It may be called from any thread; concurrent calls are serialised, and it is safe to call while other threads are still writing other tiles, because a tile is only read after its dirty flag has been taken down.

`Colors[]` and `Pixels[]` are convenient but slow for bulk work — one tile lookup per pixel — so loaders and renderers use the row calls.

Tiles carry no padding in storage. The viewer gathers the one-pixel apron it needs when it builds its render cache.

### 6.2 TLuxImageWorker

```pascal
constructor Create( const Image_:TLuxImage );

property Image     :TLuxImage;
property Block     :Integer;    // side of a block, default 64  ( 1 … LUXIMAGE_TILE )
property ThreadsN  :Integer;    // default: logical processors in every processor group
property Writing   :Boolean;    // default True: TileChanged after every block; False for read-only passes
property Busy      :Boolean;
property Cancelled :Boolean;
property Progress  :Single;     // finished blocks / total blocks

procedure Start( const Proc_:TLuxBlockProc );   // TLuxBlockProc = reference to procedure( const ThreadI_,X_,Y_,W_,H_:Integer )
procedure Cancel;                               // stops after the blocks in flight
procedure Wait;                                 // waits for every thread; from the main thread also drains OnFinished

property OnProgress :TDelegates;  // main thread, at most about 30 Hz
property OnFinished :TDelegates;  // main thread, once, whether finished or cancelled
```

Blocks lie within tiles and are handed out in raster order, one per atomic increment of a shared counter, so the tail of the run waits for at most one block. `ThreadI_` runs from 0 to `ThreadsN` − 1 and is meant to index per-thread state such as random-number generators or scratch buffers. The worker runs on threads of its own rather than on the RTL's shared pool, so that `UpdateLevels`, which parallelises through `TParallel.For`, is not starved while a render is running.

An exception raised by the procedure cancels the run and is re-raised on the main thread after `OnFinished`. The destructor cancels and waits, so a worker may be freed while it is running.

### 6.3 Asynchronous file I/O

`LoadFromFileAsync` and `SaveToFileAsync` run the ordinary loader on a `TTask` and deliver every notification to the main thread through `TThread.Queue`, so handlers may touch the UI directly.

`Busy` is raised before the task starts and lowered immediately before `OnLoaded` or `OnSaved` is raised. The viewer draws nothing while `Busy` is set, because a load begins with `SetSize`, which replaces the tile structure. The destructor waits for the task and drains any pending notification, so an image may be freed while a load is in flight.

Loading also builds the whole mip pyramid on the task's thread, through `UpdateLevels` with every tile dirty, using all available cores. Were it left to the first repaint, that work would block the UI instead.

`Progress` runs from 0 to 1 over the entire operation, including the pyramid. It is reported per row, so PNG advances smoothly; JPEG cannot, because Skia's decode is a single call with no callback, and progress therefore stands still until the decode completes.

### 6.4 File formats

| Format | Read | Write | Notes |
|---|---|---|---|
| PNG | ✔ | ✔ | Implemented directly on `System.ZLib`. Reads every variant the format defines; writes RGBA (or RGB without alpha when `Alpha_ = False`), 8 bit for `TLuxImageUInt08` and 16 bit otherwise. With a `ColorSpace`, sRGB is written as the `sRGB` chunk (plus `gAMA` and `cHRM`, as the specification recommends) and any other space as an `iCCP` profile plus `cHRM` (and `gAMA` when the curve is a pure gamma). On reading, `iCCP`, then `sRGB`, then `gAMA` + `cHRM` are honoured, in that order. |
| JPEG | ✔ | ✔ | Uses the Skia codec. With a `ColorSpace`, the ICC profile is embedded as APP2 `ICC_PROFILE` segments after the JFIF header; on reading, those segments are reassembled and parsed. |

The PNG reader covers the whole of the format as specified in [1], whose compressed data stream is DEFLATE [2]:

| | supported |
|---|---|
| Bit depths | 1, 2, 4, 8, 16 |
| Colour types | 0 grayscale, 2 truecolour, 3 palette, 4 grayscale + alpha, 6 truecolour + alpha |
| Transparency | `tRNS` in all three of its forms — palette alpha, grayscale colour key, RGB colour key |
| Interlacing | none, and Adam7 |

Non-interlaced images are decoded a row at a time and written straight into the tiles, so no whole-image temporary is ever allocated regardless of the size of the file. Adam7 images are decoded pass by pass and the pixels scattered to their final positions, which is slower but equally free of a full-size buffer.

JPEG passes through Skia [6], which requires the whole image in one contiguous buffer, so reading or writing a JPEG temporarily needs `width × height × 4` bytes in addition to the image itself. The JPEG standard [3] also caps dimensions at 65,535.

Saving a floating-point image to PNG clamps to 0…1 and quantises to 16 bit; saving to JPEG clamps to 0…1 and quantises to 8 bit. Tone mapping is not applied when saving, as it is a display setting.

`LUX.Data.Image.Files.pas` also exports:

```pascal
function LuxSkColorType( const Kind_:TLuxPixel ) :TSkColorType;
function LuxImageSize( const FileName_:String; out Width_,Height_:Integer ) :Boolean;
```

### 6.5 TLuxImageViewer

```pascal
property Image      :TLuxImage;
property Gamma      :Single;       // out = in^(1/Gamma)
property ToneMap    :Boolean;      // Reinhard 2002
property White      :Single;       // tone mapping white point, default 1
property Background :TAlphaColor;
property Scale      :Single;       // screen pixels per image pixel
property Origin     :TPointF;      // image coordinate at the top left of the view
property MinScale   :Single;       // default 1/4096
property MaxScale   :Single;       // default 256

property ColorSpace       :TLuxColorSpace;   // display colour space; nil = the monitor's own profile
property ActiveColorSpace :TLuxColorSpace;   // the display space actually in use

procedure FitToWindow;
procedure ZoomAt( const P_:TPointF; const Factor_:Single );
procedure ZoomWheel( const WheelDelta_:Integer );
function  ViewToImage( const P_:TPointF ) :TPointF;
function  ImageToView( const P_:TPointF ) :TPointF;
procedure Redraw;
```

Assigning `Image` resets `Gamma` and `ToneMap` to that class's defaults and fits the image to the window. When the image has a `ColorSpace`, the default `Gamma` is 1 — the transfer functions decide the display encoding — and `Gamma` acts as an additional adjustment; when the image's colour space changes, the default is re-applied.

`ColorSpace` is the *display* side of the conversion. Left `nil`, the viewer asks Windows for the ICC profile assigned to the monitor the window is on (the "Monitor RGB" of Photoshop) through `GetICMProfile`, parses it, and follows the window from monitor to monitor; a profile that cannot be parsed, or none, means sRGB. Assign a space to override — `TLuxColorSpaces.sRGB` forces sRGB, which is also the right choice under Windows HDR / Auto Color Management, where the compositor performs the display conversion itself. If the image has no colour space, nothing is converted regardless of this property.

Setting `Scale` re-centres the image: the centre of the image is placed at the centre of the view. `ZoomAt` instead holds a given point of the view still, which is what the wheel uses to keep the pixel under the cursor in place.

Rolling the wheel towards you zooms in — the factor applied is $2^{-\Delta / 480}$, so four notches double the scale. Dragging with the left button scrolls.

### 6.6 How a frame is drawn

1. If `Version` has changed, the whole tile cache is dropped. Then `UpdateLevels` propagates any tiles that were changed since the last frame.
2. The level is chosen by (2.6) so that within it the image is always magnified by a factor in [1, 2). Minification never occurs inside a level, so minification aliasing cannot arise.
3. The visible tiles of that level are enumerated, at most the number bounded by (2.8).
4. Each tile becomes an `ISkImage` and is cached, keyed by `TTileKey` (level and tile indices) and validated by the sum of the stamps of the tile and its eight neighbours. The cached image carries a one-pixel apron gathered from the neighbouring tiles, so filtering at a tile boundary reads real neighbouring pixels instead of clamping, and no seams appear; including the neighbours in the validation is what keeps the apron current when a neighbour changes.
5. The tiles are drawn with `DrawImageRect`. At `Scale` ≥ 1 sampling is nearest neighbour, so magnifying past 1:1 shows pixels as squares; below 1:1 it is linear. Colour management, tone mapping and gamma are applied by one SkSL runtime colour filter on the GPU, so changing `Gamma`, `ToneMap`, `White` or either colour space costs nothing and does not invalidate the cache.

The colour filter, per pixel and after un-premultiplying, is: decode with the image's transfer function → tone map (optional, in linear light) → 3 × 3 matrix from the image's primaries to the display's, with Bradford adaptation if the white points differ → encode with the display's transfer function → `pow( 1/Gamma )` → re-premultiply. Without an image colour space only the tone map and the gamma remain, exactly as before. Both transfer functions are passed as the seven ICC coefficients (`LUX.Color.Space`, §2.5), so any curve the library can describe runs on the GPU unchanged.

Nothing is resampled on the CPU. The per-frame CPU work is the pyramid update for tiles that changed and the aprons of tiles that were rebuilt or newly exposed.

## 7. Limitations

- There is no paging to disk. `SetSize` refuses an image whose tiles would not fit in free physical memory.
- TIFF, OpenEXR and Radiance HDR are not implemented.
- Skia's codec converts reliably only to 8-bit, so a JPEG is always decoded as BGRA8888 and converted afterwards when the target class is wider. As JPEG is an 8-bit format, nothing is lost.
- `TLuxImageWorker` suits work that is independent per block. Algorithms with a scan-order or whole-image dependency (integral images, FFTs) need their own scheduling.

## 8. Demo

`LuxImage.dproj` in the repository root opens a PNG or JPEG in any of the four formats, or renders a Mandelbrot set of 4,096² to 65,536² pixels on all cores with `TLuxImageWorker`, showing the blocks as they finish; the result can be saved as PNG or JPEG.

## 9. References

1. W3C, [*Portable Network Graphics (PNG) Specification (Third Edition)*](https://www.w3.org/TR/png-3/), W3C Recommendation, 2025.
2. P. Deutsch, [*DEFLATE Compressed Data Format Specification version 1.3*](https://www.rfc-editor.org/rfc/rfc1951), RFC 1951, IETF, 1996.
3. ITU-T, [*Recommendation T.81: Digital compression and coding of continuous-tone still images — Requirements and guidelines*](https://www.itu.int/rec/T-REC-T.81), ITU-T, 1992.
4. E. Reinhard, M. Stark, P. Shirley and J. Ferwerda, [*Photographic Tone Reproduction for Digital Images*](https://doi.org/10.1145/566570.566575), ACM Transactions on Graphics, vol. 21, no. 3, pp. 267–276, 2002.
5. IEEE, [*IEEE Standard for Floating-Point Arithmetic (IEEE Std 754-2019)*](https://doi.org/10.1109/IEEESTD.2019.8766229), IEEE, 2019.
6. [*Skia Graphics Library*](https://skia.org/), Google.

## 💖 [Embarcadero](https://www.embarcadero.com/) [**Delphi**](https://www.embarcadero.com/products/delphi)
Integrated Development Environment (IDE) for Creating Native Cross-Platform Apps.
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/products/delphi/starter)
