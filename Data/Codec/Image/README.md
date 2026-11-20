# LUX.Data.Codec.Image
[English](README.md) | [日本語](ja/README.md)

Image codecs for Delphi: PNG, JPEG and Radiance HDR. A codec converts between a stream and runs of pixels and knows nothing of the container the pixels live in, so the same codec fills a tiled image, a bitmap, a plain array or a GPU image.

## 1. Overview

| Unit | Main types | Role |
|---|---|---|
| `LUX.Data.Codec.Image` | `TImageHeader`, `TImageRaster`, `TImageCodec`, `EImageCodec` | the shape of an image, the door to a container, the base class of a format and its registry |
| `LUX.Data.Codec.Image.Png` | `TImageCodecPng`, `TImagePngLevel` | PNG, written directly on `System.ZLib` |
| `LUX.Data.Codec.Image.Jpg` | `TImageCodecJpg` | JPEG, through the Skia codec bundled with RAD Studio |
| `LUX.Data.Codec.Image.Hdr` | `TImageCodecHdr` | Radiance HDR ( `.hdr`, `.pic` ) |

### 1.1 Features

- **Container-independent.** A codec sees a container only through `TImageRaster`. A new container needs one raster class; a new format needs one codec class; neither touches the other.
- **One currency.** Pixels are exchanged as `TSingleRGBA`. A 32-bit float represents 8-bit and 16-bit integer samples and RGBE values exactly.
- **No whole-image buffer for reordering.** Pixels travel as runs with a start and a step, so interlace passes and scanlines of any orientation are delivered as they are decoded.
- **Settings are properties.** PNG has `Alpha` and `Level`, JPEG has `Quality`; no method carries an option of another format.
- **Stateless.** A codec holds settings and nothing else, so a `Clone` may run on another thread.
- **Recognised by content.** When reading, the format is found from the first bytes of the stream, so a file opens whatever its extension says, or without one. When writing, the format is chosen by the file extension, and the registry also builds the filter string of a save dialog.
- **Colour spaces** are read from and written to each format's own metadata.

### 1.2 Requirements

- RAD Studio 12 or later (developed and tested on RAD Studio 13 / Delphi 37.0)
- `LUX.Data.Codec.Image.Jpg` needs Skia (bundled with RAD Studio); `sk4d.dll` must be deployed alongside the executable. The other units depend on the RTL only.

## 2. Technical Background

### 2.1 Runs of pixels

A codec and a container exchange pixels as *runs*. A run is a start $(x, y)$, a step $(d_x, d_y)$ and a count $n$; its $i$-th pixel lies at

$$( x + i d_x , \quad y + i d_y ) \qquad i = 0, \dots, n-1 \qquad \text{(2.1)}$$

with the origin at the top left, $x$ to the right and $y$ downwards. An ordinary row is the run with step $(1, 0)$. The other cases a codec meets are the same thing with another step:

| Source | Start | Step |
|---|---|---|
| row $y$ of a non-interlaced image | $(0, y)$ | $(1, 0)$ |
| row $j$ of an Adam7 pass with origin $(x_0, y_0)$ and spacing $(s_x, s_y)$ | $(x_0, \ y_0 + j s_y)$ | $(s_x, 0)$ |
| a Radiance scanline stored right to left | $(w - 1, \ y)$ | $(-1, 0)$ |
| a Radiance scanline that is a column | $(x, 0)$ or $(x, \ h - 1)$ | $(0, 1)$ or $(0, -1)$ |

Because the step is part of the run, a decoder hands over each scanline the moment it is decoded and never keeps a whole image to put the pixels in order.

Decoding writes `Raster.Header` first — the container takes its size and colour space there — and then delivers every pixel exactly once. Encoding reads `Raster.Header` and takes the runs it needs.

### 2.2 PNG

The reader covers the whole of the format as specified in [1], whose compressed data stream is DEFLATE [2]:

| | supported |
|---|---|
| Bit depths | 1, 2, 4, 8, 16 |
| Colour types | 0 grayscale, 2 truecolour, 3 palette, 4 grayscale + alpha, 6 truecolour + alpha |
| Transparency | `tRNS` in all three of its forms — palette alpha, grayscale colour key, RGB colour key |
| Interlacing | none, and Adam7 |

The writer produces truecolour with alpha, or without it when `Alpha` is `False`, at 8 bit when the raster's `Depth` is 8 or less and at 16 bit otherwise, filtering every scanline with the Paeth predictor. Samples are clamped to 0…1.

`Level` selects the DEFLATE effort. PNG is lossless, so the level changes the size and the time and never the pixels. zlib defines levels 0…9, but the size changes appreciably at four of them only, which are the four values of `TImagePngLevel`.

| `Level` | zlib |
| --- | --- |
| `plNone` | 0 ( stored ) |
| `plFastest` | 1 |
| `plDefault` | 6 |
| `plMax` | 9 |

`plNone` writes DEFLATE *stored* blocks — an ordinary PNG that any decoder reads — and is the setting to choose when write speed matters more than size.

### 2.3 JPEG

JPEG passes through Skia [5], which works on a whole image in one contiguous buffer, so reading or writing temporarily needs `width × height × 4` bytes. The standard [3] limits each side to 65,535 pixels. JPEG is an 8-bit format without alpha: decoded pixels have alpha 1, and encoding clamps to 0…1 and discards alpha.

### 2.4 Radiance HDR

The format is that of the Radiance picture file [6], and the codec follows the reference implementation [7].

A pixel is four bytes: three mantissas and a shared exponent $e$. A mantissa $m$ stands for the centre of its interval,

$$v = \frac{m + 0.5}{256} \cdot 2^{ e - 128 } \qquad \text{(2.2)}$$

and $e = 0$ is black. In the other direction the largest component is split into a fraction in $[ 0.5, 1 )$ and an exponent, each component is scaled by the same power of two and truncated, so the largest mantissa is at least 128 and the round-trip error of every component is at most $1 / 256$ of the largest.

Each scanline is stored in one of three ways, all of which are read:

| Form | Layout |
|---|---|
| flat | the pixels, four bytes each |
| old run-length | a pixel `( 1, 1, 1, n )` repeats the previous pixel $n$ times; consecutive ones shift $n$ by a further 8 bits each |
| new run-length | starts with `( 2, 2, high, low )` giving the length; then each of the four components separately, as chunks that either repeat one byte ( a count byte above 128 ) or carry up to 128 bytes verbatim |

The resolution line `{+-}{XY} n {+-}{YX} m` names the axis along which scanlines follow one another, then the axis within a scanline. File coordinates have $y$ upwards, so a scanline order runs against image coordinates when the sign of X is `-` or the sign of Y is `+`. All eight combinations are read; each scanline is delivered as a run with the corresponding start and step.

`FORMAT=32-bit_rle_rgbe` and `FORMAT=32-bit_rle_xyze` are read ( a file without `FORMAT` is taken as RGBE ); XYZ pixels are converted to RGB in the file's colour space. Values are delivered as stored: `EXPOSURE` and `COLORCORR` are not applied.

The writer produces RGBE in the standard orientation `-Y h +X w`, using the new run-length form when the width is 17…32,767 and the flat form otherwise. The format has no alpha, and negative components become 0.

### 2.5 Colour spaces

`TImageHeader.ColorSpace` is a `TLuxColorSpace` of `LUX.Color.Space`, or `nil` when unknown. Spaces read from files are interned in `TLuxColorSpaces` by content, so a profile that describes a preset yields that preset and spaces may be compared by reference.

| Format | Write | Read |
|---|---|---|
| PNG | sRGB as the `sRGB` chunk with `gAMA` and `cHRM`; any other space as `iCCP` with `cHRM`, and `gAMA` when the curve is a pure gamma; nothing for `nil` | `iCCP`, then `sRGB`, then `gAMA` + `cHRM`; otherwise `nil` |
| JPEG | the ICC profile [4] as APP2 `ICC_PROFILE` segments; nothing for `nil` | those segments reassembled and parsed; otherwise `nil` |
| Radiance HDR | pixels converted to linear and the primaries as `PRIMARIES=`; pixels as they are and no `PRIMARIES=` for `nil` | the linear space with the primaries of `PRIMARIES=`, or with the format's default primaries |

## 3. Architecture

```
[ units and what they declare ]

・LUX.Data.Codec.Image                ･･･ RTL only
  ┣・TImageHeader                    ･･･ ( Width, Height, ColorSpace, Depth )
  ┣・TImageRaster                    ･･･ abstract: Header, GetLine, SetLine
  ┣・TImageCodec                     ･･･ Decode, Encode; abstract: DoDecode, DoEncode
  ┃  ┣・Extensions / Caption         ･･･ the extensions and the name of a format
  ┃  ┣・Matches / ClassOf            ･･･ the format of a stream, by its first bytes
  ┃  ┣・Regist / Codecs              ･･･ the registry of formats
  ┃  ┣・ClassFor / CreateFor         ･･･ the format of a file name
  ┃  ┣・DialogFilter                 ･･･ the Filter of a dialog
  ┃  ┗・Assign / Clone               ･･･ copying the settings
  ┣・EImageCodec                     ･･･ data that does not fit the format
  ┣・LUX.Data.Codec.Image.Png        ･･･ System.ZLib only
  ┃  ┣・TImagePngLevel               ･･･ ( plNone, plFastest, plDefault, plMax )
  ┃  ┗・TImageCodecPng               ･･･ Alpha, Level
  ┣・LUX.Data.Codec.Image.Jpg        ･･･ [ Skia ]
  ┃  ┗・TImageCodecJpg               ･･･ Quality
  ┗・LUX.Data.Codec.Image.Hdr        ･･･ RTL only
     ┗・TImageCodecHdr

[ class hierarchy ]

・TImageCodec
  ┣・TImageCodecPng
  ┣・TImageCodecJpg
  ┗・TImageCodecHdr

[ dependency ]  bridge → codec → colour

・a bridge                            ･･･ derives TImageRaster for one container
  ┗・LUX.Data.Codec.Image.*          ･･･ knows TImageRaster, no container
     ┗・LUX.Color  LUX.Color.Space   ･･･ TSingleRGBA, TByteRGBE, TLuxColorSpace
```

A bridge lives with its container. `LUX.Data.Image.Codec`, next to `TLuxImage`, is one: `TLuxImageRaster` presents an image as a raster, and `TLuxImageFiler` adds progress, the mip pyramid and asynchronous operation.

A new format is one new unit: derive from `TImageCodec`, implement `Extensions`, `Caption`, `Matches`, `DoDecode` and `DoEncode`, expose the format's settings as properties with `Assign` copying them, and `Regist` the class in the unit's `initialization`.

## 4. Usage

### 4.1 A raster of your own

```pascal
uses LUX.Color, LUX.Data.Codec.Image;

type
  TArrayRaster = class( TImageRaster )
  private
    _Header :TImageHeader;
    _Pixels :TArray<TSingleRGBA>;
  protected
    function GetHeader :TImageHeader; override;
    procedure SetHeader( const Header_:TImageHeader ); override;
  public
    procedure GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); override;
    procedure SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA ); override;
  end;

function TArrayRaster.GetHeader :TImageHeader;
begin
     Result := _Header;
end;

procedure TArrayRaster.SetHeader( const Header_:TImageHeader );
begin
     _Header := Header_;

     SetLength( _Pixels, Header_.Width * Header_.Height );
end;

procedure TArrayRaster.GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );
var
   I :Integer;
begin
     for I := 0 to N_-1 do Pixels_[ I ] := _Pixels[ ( Y_ + I * DY_ ) * _Header.Width + ( X_ + I * DX_ ) ];
end;

procedure TArrayRaster.SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );
var
   I :Integer;
begin
     for I := 0 to N_-1 do _Pixels[ ( Y_ + I * DY_ ) * _Header.Width + ( X_ + I * DX_ ) ] := Pixels_[ I ];
end;
```

### 4.2 Reading and writing

```pascal
uses System.Classes, LUX.Data.Codec.Image, LUX.Data.Codec.Image.Png, LUX.Data.Codec.Image.Jpg, LUX.Data.Codec.Image.Hdr;

Raster := TArrayRaster.Create;

Stream := TFileStream.Create( 'sky.hdr', fmOpenRead );
Codec  := TImageCodec.ClassOf( Stream ).Create;          // the content picks TImageCodecHdr
try
   Codec.Decode( Stream, Raster );                       // Raster.Header is now the size and the colour space
finally
   Stream.Free;
   Codec .Free;
end;

Png    := TImageCodecPng.Create;
Stream := TFileStream.Create( 'sky.png', fmCreate );
try
   Png.Level := plFastest;

   Png.Encode( Stream, Raster );
finally
   Stream.Free;
   Png   .Free;
end;
```

### 4.3 Dialogs

```pascal
OpenDialog1.Filter := TImageCodec.DialogFilter( 'Images' );   // 'Images (*.png;*.jpg;…)|…|PNG (*.png)|*.png|…'
SaveDialog1.Filter := TImageCodec.DialogFilter;               // one entry per format
```

## 5. API Reference

### 5.1 TImageHeader

```pascal
Width      :Integer;         // pixels across, at least 1
Height     :Integer;         // pixels down, at least 1
ColorSpace :TLuxColorSpace;  // the space of the pixel values; nil if unknown; not owned
Depth      :Integer;         // bits of one sample; 32 for floating point
```

### 5.2 TImageRaster

```pascal
property Header :TImageHeader;   // read: the present shape    write: take this size and colour space
procedure GetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );  // read a run
procedure SetLine( const X_,Y_,DX_,DY_,N_:Integer; const Pixels_:PSingleRGBA );  // write a run
```

Writing `Header` discards the pixels the container held. A container whose sample precision is fixed need not follow `Depth`.

### 5.3 TImageCodec

```pascal
constructor Create; virtual;

///// the format
class function Extensions :TArray<String>;     // lower case, with the dot; the first is the default
class function Caption :String;
class function Handles( const FileName_:String ) :Boolean;
class function Matches( const Bytes_:TBytes ) :Boolean;              // are these the first bytes of this format?

///// the registry
class procedure Regist( const Codec_:TImageCodecClass );             // from the unit's initialization
class function Codecs :TArray<TImageCodecClass>;                     // in order of registration
class function ClassOf( const Stream_:TStream ) :TImageCodecClass;   // by content; nil if no format matches; the position is kept
class function ClassFor( const FileName_:String ) :TImageCodecClass; // by extension; nil if the extension is unknown
class function CreateFor( const FileName_:String ) :TImageCodec;     // nil if the extension is unknown
class function DialogFilter( const Caption_:String = '' ) :String;

///// settings
procedure Assign( const Codec_:TImageCodec );
function Clone :TImageCodec;

///// conversion
procedure Decode( const Stream_:TStream; const Raster_:TImageRaster );   // checks the first bytes, then DoDecode
procedure Encode( const Stream_:TStream; const Raster_:TImageRaster );   // checks the size, then DoEncode
```

```pascal
TImageCodecPng    property Alpha :Boolean;      // write alpha            ( default True )
                  property Level :TImagePngLevel;    // plNone … plMax         ( default plDefault )

TImageCodecJpg    property Quality :Integer;    // clamped to 1 … 100     ( default 90 )
```

Data that does not fit the format raises `EImageCodec`; a stream that ends early may raise the stream's own `EReadError` instead. `Encode` refuses an image without size before writing anything.

## 6. Limitations

- JPEG needs the whole image in one buffer and is limited to 65,535 pixels on a side.
- The PNG writer does not produce palette, grayscale or interlaced files.
- Radiance HDR: `EXPOSURE`, `COLORCORR`, `PIXASPECT` and `VIEW` are neither applied nor preserved; spectral pictures ( `Radiance_spectra` ) are not read; XYZE is not written.

## 7. References

1. W3C, [*Portable Network Graphics (PNG) Specification (Third Edition)*](https://www.w3.org/TR/png-3/), W3C Recommendation, 2025.
2. P. Deutsch, [*DEFLATE Compressed Data Format Specification version 1.3*](https://www.rfc-editor.org/rfc/rfc1951), RFC 1951, IETF, 1996.
3. ITU-T, [*Recommendation T.81: Digital compression and coding of continuous-tone still images — Requirements and guidelines*](https://www.itu.int/rec/T-REC-T.81), ITU-T, 1992.
4. International Color Consortium, [*Specification ICC.1:2022 — Image technology colour management — Architecture, profile format, and data structure*](https://www.color.org/specification/ICC.1-2022-05.pdf), ICC, 2022.
5. [*Skia Graphics Library*](https://skia.org/), Google.
6. G. Ward, [*Radiance File Formats*](https://radsite.lbl.gov/radiance/refer/filefmts.pdf), Lawrence Berkeley National Laboratory.
7. Lawrence Berkeley National Laboratory, [*Radiance*](https://github.com/LBNL-ETA/Radiance), source code ( `src/common/color.c`, `color.h`, `resolu.c`, `header.c` ).

## 💖 [Embarcadero](https://www.embarcadero.com/) [**Delphi**](https://www.embarcadero.com/products/delphi)
Integrated Development Environment (IDE) for Creating Native Cross-Platform Apps.
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/products/delphi/starter)
