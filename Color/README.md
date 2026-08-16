# LUX.Color
[English](README.md) | [日本語](ja/README.md)

`LUX.Color` defines colour types as Delphi value records: linear floating-point colours with the transfer functions a display needs, and integer pixel formats that cast implicitly to and from them. `LUX.Color.Half` adds `binary16` variants laid out to match GPU textures. `LUX.Color.Space` defines RGB colour spaces — primaries, white point and transfer function — with presets from sRGB to ACEScg, conversion matrices between them, and ICC profile writing and reading.

## 1. Overview

Every colour is a plain `record` with constructors, operators and implicit casts, so colours are stack-allocated and copied by value. The floating-point records `TSingleRGB` / `TSingleRGBA` are the computational centre: they carry linear radiance, support arithmetic (including channel-wise multiplication), and expose the `Gamma` and `ToneMap` methods. Around them sit the storage formats:

| Record | Channels | Purpose |
|---|---|---|
| `TByteRGB` / `TByteRGBA` | `Byte` | 8-bit pixels, bit-compatible with `TAlphaColor` |
| `TWordRGB` / `TWordRGBA` | `Word` | 16-bit pixels, stored R,G,B(,A) to match Skia `RGBA16161616` |
| `TUInt32xRGB` / `TUInt32xRGBA` | `UInt32` | wide accumulators for summing many 8-bit samples |
| `TByteRGBE` | `Byte` ×4 | shared-exponent HDR encoding |
| `THalfRGB` / `THalfRGBA` | `THalf` | `binary16`, stored R,G,B(,A) to match Skia `RGBAF16` |

On little-endian targets `TByteRGB` declares its fields in B,G,R order (A on top for `TByteRGBA`), so the 32-bit pattern coincides with FireMonkey's `TAlphaColor` and both cast implicitly in either direction. `TSingleRGBA` likewise casts to and from `TAlphaColorF`. Alpha is straight (non-premultiplied) and defaults to opaque in every constructor and cast.

## 2. Mathematical Background

### 2.1 Display gamma

`Gamma` encodes a linear channel for a display of exponent $\gamma$ (default $2.2$), per channel; `TSingleRGBA.Gamma` leaves the alpha untouched:

```math
C' = C^{\,1/\gamma} \qquad \text{(2.1)}
```

### 2.2 Tone mapping

`ToneMap` applies the extended Reinhard operator [1] per channel, where $L_w$ is the white point (parameter `W_`, default $1$) — the luminance that maps to pure white:

```math
C' = \operatorname{clamp}\!\left( \frac{C \left( 1 + C / L_w^{\,2} \right)}{1 + C},\; 0,\; 1 \right) \qquad \text{(2.2)}
```

### 2.3 Shared-exponent encoding

`TByteRGBE` stores three 8-bit mantissas `R`,`G`,`B` and one biased exponent `E` shared by all channels, in the manner of the Radiance picture format [2]. Decoding a channel of mantissa $M$ gives

```math
C = 2^{\,E-128} \, \frac{M}{255} \qquad \text{(2.3)}
```

Encoding from `TSingleRGB` takes $E = 128 + \lceil \log_2 \max( R, G, B ) \rceil$ and $M = \mathrm{round}( 2^{-(E-128)} \, 255 \, C )$, so the brightest channel determines the scale and the dynamic range far exceeds what 8-bit gamma pixels can hold.

### 2.4 Bit-depth conversion

The casts convert exactly at the ends of the range: `Byte` → `Word` multiplies by $257$ (so `$FF` → `$FFFF`), `Word` → `Byte` takes the high byte; `Byte` → `Single` divides by $255$, and `Single` → `Byte` / `Word` rounds after clamping to $[0,1]$. `THalf` channels convert through `Single` bit-exactly within `binary16` precision [3].

### 2.5 Colour spaces

An RGB colour space is defined by the CIE chromaticities $(x, y)$ of its three primaries and its white point, and by a transfer function. From the primaries the matrix taking linear RGB to CIE XYZ follows by requiring that $(1,1,1)$ map to the white point at $Y = 1$:

```math
\mathbf{M} = \begin{pmatrix} X_r & X_g & X_b \\ 1 & 1 & 1 \\ Z_r & Z_g & Z_b \end{pmatrix} \operatorname{diag}(\mathbf{S}), \qquad \mathbf{S} = \begin{pmatrix} X_r & X_g & X_b \\ 1 & 1 & 1 \\ Z_r & Z_g & Z_b \end{pmatrix}^{-1} \begin{pmatrix} X_w \\ 1 \\ Z_w \end{pmatrix} \qquad \text{(2.4)}
```

where $X = x/y$ and $Z = (1 - x - y)/y$ for each chromaticity. Two spaces with different white points are joined through a Bradford chromatic adaptation [8], and ICC profiles [4] store colorants adapted to D50 in the same way.

The transfer function — encoded value $V$ to linear $L$ — is held in the seven-coefficient form of the ICC `parametricCurveType` (function type 4), which also covers every simpler type:

```math
L = \begin{cases} (a V + b)^{g} + e & V \ge d \\ c V + f & V < d \end{cases} \qquad \text{(2.5)}
```

sRGB [5] is $g = 2.4,\ a = 1/1.055,\ b = 0.055/1.055,\ c = 1/12.92,\ d = 0.04045$; Rec. 709 / 2020 [6] and ROMM [7] are of the same shape with their own constants; a pure gamma is $a = 1,\ b = c = d = 0$; linear is $g = 1$. Negative inputs, which floating-point images can carry, are handled by sign and magnitude.

The presets:

| Class | Primaries (R, G, B) | White | Transfer |
|---|---|---|---|
| `TLuxColorSpaceSRGB` / `…LinearSRGB` | (0.64, 0.33) (0.30, 0.60) (0.15, 0.06) | D65 | sRGB / linear |
| `TLuxColorSpaceDisplayP3` / `…LinearDisplayP3` | (0.680, 0.320) (0.265, 0.690) (0.150, 0.060) | D65 | sRGB / linear |
| `TLuxColorSpaceAdobeRGB` / `…LinearAdobeRGB` | (0.64, 0.33) (0.21, 0.71) (0.15, 0.06) | D65 | γ = 563/256 / linear |
| `TLuxColorSpaceRec2020` / `…LinearRec2020` | (0.708, 0.292) (0.170, 0.797) (0.131, 0.046) | D65 | Rec. 709 curve / linear |
| `TLuxColorSpaceProPhotoRGB` | (0.7347, 0.2653) (0.1596, 0.8404) (0.0366, 0.0001) | D50 | ROMM (γ 1.8, linear toe) |
| `TLuxColorSpaceACEScg` | (0.713, 0.293) (0.165, 0.830) (0.128, 0.044) | ACES (0.32168, 0.33767) | linear |

## 3. Architecture

### 3.1 Types

```
・TByteRGB         ･･･ R,G,B :Byte, stored B,G,R, ⇄ TAlphaColor
  ┗・TByteRGBA    ･･･ C :TByteRGB, A :Byte, bit-compatible with TAlphaColor

・TWordRGB         ･･･ R,G,B :Word, stored R,G,B ( Skia RGBA16161616 )
  ┗・TWordRGBA    ･･･ C :TWordRGB, A :Word

・TSingleRGB       ･･･ R,G,B :Single, linear; Gamma / ToneMap
  ┗・TSingleRGBA  ･･･ C :TSingleRGB, A :Single, ⇄ TAlphaColorF

・TUInt32xRGB      ･･･ R,G,B :UInt32, overflow-free accumulator
  ┗・TUInt32xRGBA ･･･ C :TUInt32xRGB, A :UInt32

・TByteRGBE        ･･･ C :TByteRGB, E :Byte, shared-exponent HDR

・THalfRGB         ･･･ R,G,B :THalf, stored R,G,B ( Skia RGBAF16 )
  ┗・THalfRGBA    ･･･ C :THalfRGB, A :THalf

・TLuxTransfer     ･･･ g a b c d e f, Decode / Encode, Linear / Gamma / sRGB / Rec709 / ROMM

・TLuxColorSpace   ･･･ Name, RedXY GreenXY BlueXY WhiteXY, Transfer, ToXYZ / FromXYZ / ToXYZD50, ToSpace, IccProfile, FromIcc
  ┣・TLuxColorSpaceSRGB           ┣・TLuxColorSpaceLinearSRGB
  ┣・TLuxColorSpaceDisplayP3      ┣・TLuxColorSpaceLinearDisplayP3
  ┣・TLuxColorSpaceAdobeRGB       ┣・TLuxColorSpaceLinearAdobeRGB
  ┣・TLuxColorSpaceRec2020        ┣・TLuxColorSpaceLinearRec2020
  ┣・TLuxColorSpaceProPhotoRGB    ┗・TLuxColorSpaceACEScg
  ┗・( your own subclass, or Create( name, xy × 4, transfer ) )

・TLuxColorSpaces  ･･･ shared instances of the presets, Find / Intern / FromIcc / ByName
```

The `…RGBA` records nest the corresponding `…RGB` as their field `C` and re-expose `R`,`G`,`B` as properties, so pointer casts between a colour and its alpha-carrying form are layout-safe.

A `TLuxColorSpace` is immutable once constructed and is meant to be *referenced*, not owned: `TLuxColorSpaces` holds one shared instance of each preset for the life of the program, and `Intern` files away any other instance by content, returning the existing one when an equal space (primaries, white and curve within tolerance) is already known. `FromIcc` parses a matrix/TRC ICC profile — `para` curves of every type and `curv` curves, the latter matched to the nearest known curve — and refuses LUT-based profiles.

### 3.2 Files

```
・Color/
  ┣・LUX.Color.pas       ･･･ integer, wide-integer and Single colour records
  ┣・LUX.Color.Half.pas  ･･･ THalfRGB / THalfRGBA  ( binary16 storage )
  ┗・LUX.Color.Space.pas ･･･ TLuxTransfer, TLuxColorSpace and presets, TLuxColorSpaces, ICC
```

`LUX.Color.Half` depends on `LUX.D1.Half` for the `THalf` scalar; `LUX.Color.Space` on `LUX.D2` / `LUX.D3` / `LUX.D3x3` for chromaticities, XYZ triples and 3 × 3 matrices.

## 4. Usage

```pascal
uses LUX.Color;

var
   C :TSingleRGB;
   E :TByteRGBE;
   B :TByteRGB;
   A :TAlphaColor;
begin
     C := TSingleRGB.Create( 4.0, 2.0, 1.0 );    // linear, above white
     E := C;                                     // RGBE keeps the range

     C := C.ToneMap( 1 ).Gamma( 2.2 );           // Reinhard, then display gamma
     B := C;                                     // clamped and rounded to 8 bit
     A := B;                                     // TAlphaColor for the UI
end;
```

Converting a colour from one space to another, and round-tripping a space through an ICC profile:

```pascal
uses LUX.Color, LUX.Color.Space, LUX.D3, LUX.D3x3;

var
   P3, S :TLuxColorSpace;
   M     :TDoubleM3;
   L     :TSingleRGB;
   V     :TDouble3D;
   Icc   :TBytes;
begin
     P3 := TLuxColorSpaces.DisplayP3;                        // shared preset

     L := P3.ToLinear( TSingleRGB.Create( 0.5, 0.25, 0 ) );  // decode with the P3 curve
     M := P3.ToSpace( TLuxColorSpaces.sRGB );                // linear P3 → linear sRGB ( same white, so no adaptation )
     V := M * TDouble3D.Create( L.R, L.G, L.B );
     L := TLuxColorSpaces.sRGB.ToEncoded( TSingleRGB.Create( V.X, V.Y, V.Z ) );

     Icc := P3.IccProfile;                                   // ICC v4 display profile, matrix + para curves
     S   := TLuxColorSpaces.FromIcc( Icc );                  // = P3 ( interned to the same instance )

     S := TLuxColorSpace.Create( 'My camera', TDouble2D.Create( 0.70, 0.30 ), TDouble2D.Create( 0.20, 0.75 ),
                                              TDouble2D.Create( 0.13, 0.05 ), LUX_WHITE_D65, TLuxTransfer.Gamma( 2.2 ) );
     S := TLuxColorSpaces.Intern( S );                       // keep it for the life of the program
end;
```

## 5. References

1. E. Reinhard, M. Stark, P. Shirley and J. Ferwerda, [*Photographic Tone Reproduction for Digital Images*](https://doi.org/10.1145/566570.566575), ACM Transactions on Graphics, vol. 21, no. 3, pp. 267–276, 2002.
2. G. Ward, [*Real Pixels*](https://www.realtimerendering.com/resources/GraphicsGems/), in Graphics Gems II, Academic Press, pp. 80–83, 1991.
3. IEEE, [*IEEE Standard for Floating-Point Arithmetic (IEEE Std 754-2019)*](https://doi.org/10.1109/IEEESTD.2019.8766229), IEEE, 2019.
4. International Color Consortium, [*Specification ICC.1:2022 — Image technology colour management — Architecture, profile format, and data structure*](https://www.color.org/specification/ICC.1-2022-05.pdf), ICC, 2022.
5. IEC, [*IEC 61966-2-1:1999 — Multimedia systems and equipment — Colour measurement and management — Part 2-1: Colour management — Default RGB colour space — sRGB*](https://webstore.iec.ch/publication/6169), IEC, 1999.
6. ITU-R, [*Recommendation BT.2020-2 — Parameter values for ultra-high definition television systems for production and international programme exchange*](https://www.itu.int/rec/R-REC-BT.2020), ITU, 2015.
7. ISO, [*ISO 22028-2:2013 — Photography and graphic technology — Extended colour encodings for digital image storage, manipulation and interchange — Part 2: Reference output medium metric RGB colour image encoding (ROMM RGB)*](https://www.iso.org/standard/56591.html), ISO, 2013.
8. K. M. Lam, *Metamerism and Colour Constancy*, Ph.D. thesis, University of Bradford, 1985 — the Bradford transform, as adopted in [4].
9. Academy of Motion Picture Arts and Sciences, [*ACEScg — A Working Space for CGI Render and Compositing (S-2014-004)*](https://docs.acescentral.com/specifications/acescg/), AMPAS, 2014.

## 💖 [Embarcadero](https://www.embarcadero.com/) [**Delphi**](https://www.embarcadero.com/products/delphi)
Integrated Development Environment (IDE) for Creating Native Cross-Platform Apps.
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/products/delphi/starter)
