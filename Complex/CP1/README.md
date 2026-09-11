# LUX.Complex.CP1

[English](README.md) | [日本語](ja/README.md)

`TSingleCP1` and `TDoubleCP1` represent a complex value as homogeneous coordinates `[Z:W]`, with value `Z / W`. A nonzero numerator with `W = 0` represents the single point at infinity. Add the LUX root, `Complex`, and `Complex/CP1` to the unit search path.

Both records provide the public features of the corresponding `TSingleC` / `TDoubleC` number records:

| Feature | CP1 API |
|---|---|
| Components | Writable `R` / `I`; `Re` / `Im` are aliases |
| Imaginary unit | `Imaginary` |
| Magnitude | `Abs2`; writable `Abso` |
| Direction | Writable `Unitor`; read-only `Angle` in radians |
| Conjugation | Writable `Conj` |
| Arithmetic | Unary signs, addition, subtraction, multiplication, division, scalar products and division |
| Random values | `RandG` with default/scalar, ordinary-complex, or CP1 component deviations; `RandBS1`, `RandBS2`, `RandBS4` |
| Conversion | Ordinary complex values to CP1 implicitly, CP1 to ordinary complex values explicitly, and conversions between precisions |
| Function types | `TSingleCP1Func`, `TDoubleCP1Func` |
| Elementary functions | `Pow`, `Roo2`, `Exp`, `Expi`, `Ln`, `Sin`, `Cos`, `Tan`, `ArcSin`, `ArcCos` |

CP1 additionally provides `Zero`, `Infinity`, `IsZero`, `IsInf`, equality operators, and `Pow2`. `Z := Pow2(Z) + C` evaluates a quadratic recurrence. The unit has no rendering dependency.

For finite nonzero values, setters follow the ordinary number records: `Abso := A` assigns `A * Unitor`, `Unitor := U` assigns `|Self| * U` without normalizing the argument, and `Conj := C` assigns the conjugate of `C`. Assigning a component preserves the other component. Unlike the ordinary records, `R` and `I` are properties, so they cannot be passed as `var` parameters. Normalization scales the four stored components by a power of two; rounding and underflow can still lose information.

`Abso` uses `Hypot` on numerator and denominator. `Abs2` separates mantissas and exponents before squaring, with overflow checked against the result type. Direction is obtained from normalized numerator and denominator directions. `Ln` uses the difference of logarithmic magnitudes, and `Roo2` uses the half-angle with square roots of the two magnitudes. `ArcCos` uses the same logarithmic expression as the ordinary complex implementation. Results at branch cuts remain subject to signed zero and floating-point rounding.

Infinity and indeterminate expressions follow implementation conventions, not unique mathematical values: the existing `0/0` and infinity/infinity convention is `Infinity`; consequently `Unitor` of zero or infinity returns `Infinity`. `Angle` is zero at zero and NaN at infinity. Component assignments to infinity leave it unchanged; conjugation preserves infinity. Reading its ordinary components returns positive infinity. Elementary-function conventions at infinity remain implementation-specific. A homogeneous pair `[0:0]` is not a valid CP1 point.

Random methods delegate to the ordinary number generators, retaining their distribution, parameter interpretation, and random-number consumption. They generate finite-plane samples, not a uniform distribution on the sphere. Observation and color formulas belong in the application.
