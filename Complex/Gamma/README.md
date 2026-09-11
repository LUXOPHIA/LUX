# LUX.C2.Gamma

[English](README.md) | [日本語](ja/README.md)

Complex gamma functions for Delphi, implemented with the Lanczos approximation and Takuya Ooura's `cdgamma` algorithm. Each method has a `.Diff` unit that propagates derivatives using dual numbers.

## 1. Functions and types

These units expose standalone functions; they define no classes and require no object construction. The ordinary units accept `TSingleC` and `TDoubleC`. The `.Diff` units accept `TdSingleC` and `TdDoubleC`, whose `o` and `d` properties hold the value and derivative components.

| Unit | Exported functions |
|---|---|
| `LUX.C2.Gamma.Lanczos` | `Gamma7`, `Gamma9`, `Gamma11`, `Gamma15`; `LnGamma7`, `LnGamma9`, `LnGamma11`, `LnGamma15` |
| `LUX.C2.Gamma.Lanczos.Diff` | The same names, overloaded for dual complex numbers |
| `LUX.C2.Gamma.Ooura` | `Gamma` |
| `LUX.C2.Gamma.Ooura.Diff` | `Gamma`, overloaded for dual complex numbers |

The suffix of each Lanczos function is the number of stored coefficients, including the constant term. It is not a number of guaranteed significant digits. The implementation pairs each coefficient set with a fixed parameter `g`:

| Functions | Coefficients `N` | `g` |
|---|---:|---:|
| `Gamma7` / `LnGamma7` | 7 | 5 |
| `Gamma9` / `LnGamma9` | 9 | 7 |
| `Gamma11` / `LnGamma11` | 11 | 9 |
| `Gamma15` / `LnGamma15` | 15 | 607/128 |

Both ordinary and dual Lanczos units contain their own coefficient definitions so that each implementation can be read in one source file. Ooura's implementation uses one fixed approximation and exposes no order parameter or complex log-gamma function.

## 2. Usage

Add the LUX root, `Complex`, and `Complex/Gamma` directories to the Delphi unit search path. The gamma units depend on the LUX numeric types; they do not depend on FireMonkey.

This console example evaluates the value and a derivative at the same complex argument. Unit-qualified calls make the choice between the ordinary and dual overloads explicit.

```pascal
program GammaExample;

{$APPTYPE CONSOLE}

uses
  LUX.Complex,
  LUX.Complex.Diff,
  LUX.C2.Gamma.Lanczos,
  LUX.C2.Gamma.Lanczos.Diff;

var
  Z, G :TDoubleC;
  D, F :TdDoubleC;
begin
  Z := TDoubleC.Create( 2.5, 1 );
  G := LUX.C2.Gamma.Lanczos.Gamma15( Z );

  D.o := Z;
  D.d := TDoubleC.Create( 1, 0 );
  F := LUX.C2.Gamma.Lanczos.Diff.Gamma15( D );

  Writeln( 'Gamma: ', G.R, ', ', G.I );
  Writeln( 'Value: ', F.o.R, ', ', F.o.I );
  Writeln( 'Derivative: ', F.d.R, ', ', F.d.I );
end.
```

Setting `D.d` to `1 + 0i` seeds differentiation in the real direction. Where the approximation is analytic, `F.d` approximates the complex derivative of gamma at `Z`. At regular inputs with finite intermediate values, a zero seed produces a zero derivative component. Automatic differentiation differentiates the implemented approximation and remains subject to approximation and floating-point errors.

To use Ooura's method, add `LUX.C2.Gamma.Ooura` or `LUX.C2.Gamma.Ooura.Diff` and call its `Gamma` function with the corresponding type. The two methods can be compared at the same input; agreement alone is not an accuracy guarantee.

## 3. Mathematical formulation

### 3.1. Lanczos approximation

For `Re(z) >= 1/2`, the implementation evaluates the finite Lanczos approximation [1, 2]:

```math
A(z)=c_0+\sum_{k=1}^{N-1}\frac{c_k}{z-1+k},
\qquad B=z+g-\frac12,
\qquad \Gamma(z)\approx\sqrt{2\pi}\,A(z)B^{z-1/2}e^{-B}.
```

`Gamma*` computes `A * Exp(Ln(B) * (z - 1/2) - B + Ln(2*pi)/2)`. `LnGamma*` evaluates the logarithmic expression term by term. Each `N` selects a complete coefficient set and its matching `g`; increasing `N` does not by itself guarantee a smaller floating-point error [2].

### 3.2. Reflection

For `Re(z) < 1/2`, the Lanczos functions use the reflection identity [3]:

```math
\Gamma(z)\Gamma(1-z)=\frac{\pi}{\sin(\pi z)},\qquad z\notin\mathbb Z.
```

`Gamma*` applies the identity directly. `LnGamma*` uses `Ln(pi / Sin(pi*z)) - LnGammaP(1-z)`. The helper evaluates the approximation in the reflected half-plane.

### 3.3. Ooura's algorithm

The Ooura units are Delphi ports of `cdgamma.c` from the author's `gamerf` package [4]. They evaluate a fixed rational-and-exponential approximation. Their reflection branch is selected at `Re(z) < 0`, rather than at the Lanczos threshold of `1/2`.

The dual version propagates derivatives through the real and imaginary components, including conjugation and squared modulus. These intermediate operations are not themselves holomorphic; their derivatives are handled as real operations on the two components.

## 4. Domain, branches, and accuracy

### 4.1. Poles

The non-positive integers `0, -1, -2, ...` are poles of gamma and are outside the supported input domain [3]. These implementations do not explicitly detect poles. At a pole they may return finite values, `INF`, or `NaN`, or raise a floating-point exception depending on the operations and exception mask. `INF`/`NaN` must not be used as a reliable pole detector.

For example, in a Delphi Win64 double-precision check with floating-point exceptions masked, all five gamma variants returned a finite real value of approximately `-2.5653e16` at `z = -1`, while `z = 0` produced `NaN`. The ordinary and dual variants showed the same value behavior. This illustrates the limitation; it is not a portable specification of the returned bits. In the reflection calculation, a floating-point evaluation of `Sin(pi*z)` need not be exactly zero at a negative integer.

### 4.2. Logarithm branches

`LnGamma*` combines principal complex logarithms. Its exponential represents the corresponding gamma approximation, subject to floating-point effects, but the result is not guaranteed to follow the analytic principal log-gamma branch. In particular, values can differ by multiples of `2*pi*i`, in addition to numerical error. The principal logarithm of `Gamma(z)` and the principal log-gamma function are distinct branch conventions; see the mpmath documentation for this distinction [5]. Do not assume branch continuity when using these routines along a complex path.

### 4.3. Numerical limits

The functions provide no configurable error tolerance or full-domain error bound. Accuracy depends on the coefficient set, input, numeric type, elementary functions, and rounding. Large arguments and intermediate expressions can overflow or underflow, and cancellation can reduce accuracy even away from poles. A logarithmic formulation does not eliminate every intermediate-range limitation.

No reproducible benchmark accompanying these units establishes a universal ranking or a guaranteed number of digits for the four Lanczos sets and Ooura's method. Validate the intended input range and derivative outputs against an independent high-precision reference when those guarantees are required.

## 5. Source layout

```text
Gamma/
├─ LUX.C2.Gamma.Lanczos.pas
├─ LUX.C2.Gamma.Lanczos.Diff.pas
├─ LUX.C2.Gamma.Ooura.pas
├─ LUX.C2.Gamma.Ooura.Diff.pas
├─ README.md
└─ ja/README.md
```

The complex types are defined in `LUX.Complex` and `LUX.Complex.Diff`. The separate [real-argument gamma units](../../D1/Gamma/README.md) live in `D1/Gamma` and have their own APIs and domain conventions.

## 6. References and attribution

1. C. Lanczos, [*A Precision Approximation of the Gamma Function*](https://doi.org/10.1137/0701008), 1964, pp. 86–96.
2. Boost.Math, [*The Lanczos Approximation*](https://www.boost.org/doc/libs/latest/libs/math/doc/html/math_toolkit/lanczos.html). Background on coefficient counts, parameter selection, and cancellation; not a measured accuracy specification for these Delphi routines.
3. NIST DLMF, [*Gamma Function: Definitions*](https://dlmf.nist.gov/5.2) and [*Functional Relations*](https://dlmf.nist.gov/5.5).
4. Takuya Ooura, [*Gamma / Error Functions*](https://www.kurims.kyoto-u.ac.jp/~ooura/gamerf.html), including `cdgamma.c` in `gamerf`.
5. mpmath, [*Factorials and gamma functions*](https://mpmath.org/doc/current/functions/gamma.html), especially `loggamma`.

The Ooura units retain the original attribution: Copyright(C) 1996 Takuya OOURA. See their source headers and the package's original notice.

## 💖 [Embarcadero](https://www.embarcadero.com/) [Delphi](https://www.embarcadero.com/products/delphi)

Integrated development environment for native cross-platform applications.
