# LUX.Complex.CP1

[English](README.md) | [日本語](ja/README.md)

`LUX.Complex.CP1` provides `TSingleCP1` / `TDoubleCP1` for homogeneous complex coordinates `[Z:W]`, representing `Z / W`; a nonzero `Z` with `W = 0` represents infinity. Add the LUX root, `Complex`, and `Complex/CP1` directories to the unit search path and use `LUX.Complex.CP1`. For example, `Z := Pow2( Z ) + C` evaluates a quadratic recurrence with CP1 operands. The unit depends on `LUX.Complex` and the RTL, without a rendering dependency.

Normalization scales all four components by a power of two. These are floating-point records: rounding and underflow remain, and values assigned to indeterminate expressions are implementation conventions. `Re` / `Im` extract ordinary components; application-specific observation and color formulas belong in the application. Currently, `Abs2` uses conservative overflow thresholds and `Abso` computes `Sqrt(Abs2)`, so the modulus can become infinite even when the modulus itself is representable.
