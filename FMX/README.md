# LUX.FMX
[English](README.md) | [日本語](ja/README.md)

Parts that a FireMonkey application on Windows needs regardless of what it does: a main form that behaves like an ordinary top-level window, a window surface primed with the background colour before the first paint, one light / dark custom style with its switcher, repainting that keeps up while messages keep arriving, and a probe that measures how smoothly the user interface follows an operation.

## 1. Overview

| Unit | Main types | Role |
|---|---|---|
| `LUX.FMX.Window` | `TMainWindow` | makes the main form's window the application window; `Present` / `Conceal`; `OnEnding` |
| `LUX.FMX.Primer` | `TPrimer` | fills a newly shown window with the form's `Fill` colour until FMX paints it |
| `LUX.FMX.Style` | `TFmxStyle` | applies the style resources and returns colours, fonts and sizes by role name |
| `LUX.FMX.Scheme` | `TFmxScheme`, `TSchemeChangedMessage` | selects light or dark ( automatic / light / dark ) and decorates every form |
| `LUX.FMX.Redraw` | `TRedraw`, `TRedrawingMessage` | paints an invalidated form before the next posted message is handled |
| `LUX.FMX.Motion` | `TMotionProbe`, `TMotionCost`, `TMotionLock` | measures update intervals, hitch ratio and intermediate frames for UI tests |

`LUX.FMX.Light.style` and `LUX.FMX.Dark.style` are the two style files that `TFmxStyle` loads. All units are for Windows and use only the public surface of FMX and documented Windows APIs, with one stated exception in `LUX.FMX.Primer`. `LUX.FMX.Redraw` and `LUX.FMX.Motion` use [`LUX.Windows`](../Windows/README.md) ( `LUX.Windows.Monitor`, `LUX.Windows.Load` ), so both folders must be on the search path.

## 2. Technical Background

### 2.1 The application window ( `LUX.FMX.Window` )

FMX creates a hidden, zero-sized application window that owns the taskbar button, and creates each form's window as an owned window of it. Consequently a form has no taskbar button of its own, minimising hides the form without animation, the taskbar button stays on the display of the hidden window, and the window surface is discarded while minimised, so a restored dark window flashes white.

`TMainWindow` removes the owner from the main form's window, registers that window as the application window through `RegisterApplicationHWNDProc`, and destroys the hidden one. Windows then minimises and restores the form's window itself. What FMX did on the hidden window is taken over: on `WM_ENDSESSION` the application is ended ( through `OnEnding` when assigned, otherwise by closing the main form ), and `TApplication.MainForm` is cleared while running so that child windows shown during minimisation are not shrunk, then set back when the form really closes.

### 2.2 Priming the surface ( `LUX.FMX.Primer` )

When a window becomes visible, Windows sends `WM_ERASEBKGND`, and an ordinary application paints its background there. The FMX window procedure answers "erased" without painting and has no class brush, so the new surface stays white until `WM_PAINT` is reached. FMX offers no public extension point for this message; `TPrimer` therefore replaces the window procedure of each form's window ( `GWLP_WNDPROC` ) and paints the form's `Fill` colour between the moment the window is shown and its first paint. Only solid-filled, non-transparent, non-3D forms are handled.

### 2.3 Style and scheme ( `LUX.FMX.Style`, `LUX.FMX.Scheme` )

The style is the single source of colours. Inside each style file, a colour is a `TBrushObject` named `color.<role>`, a font is a `TFontObject` named `font.<role>`, and a size is a `TStyleTag` named `span.<role>`; `TFmxStyle` looks them up on every call, so values are never kept across a light / dark change. `TFmxStyle.Ground` returns the colour that a style definition ( a `StyleLookup` name ) paints, which lets the form's `Fill` — and therefore the primed surface — match the styled background.

`TFmxScheme` listens to `TSystemAppearanceChangedMessage`, sets `TFmxStyle.Dark`, and, for every form just before it is shown and whenever the scheme changes, sets `Fill` from the form's background definition and switches the title bar with `DWMWA_USE_IMMERSIVE_DARK_MODE`. Controls need not be recreated.

### 2.4 Prompt repainting ( `LUX.FMX.Redraw` )

FMX requests a repaint with `InvalidateRect`, and Windows generates `WM_PAINT` only when no posted message remains. While messages arrive without a gap, the window changes but is not painted. `TRedraw` installs thread hooks ( `WH_GETMESSAGE`, `WH_CALLWNDPROCRET` ) and, each time a message is fetched, calls `UpdateWindow` on any FMX form that has an invalid region and whose due time has passed. Due times are spaced by the refresh period of the monitor the window is on and aligned to the vertical blank reported by `DwmGetCompositionTimingInfo`. After `WM_WINDOWPOSCHANGED` the form is painted at once. Immediately before any paint, `TRedrawingMessage` is sent with the form as sender, so that content drawn outside FMX can be repositioned within the same update.

### 2.5 Measuring smoothness ( `LUX.FMX.Motion` )

`TMotionProbe` repeats a caller-supplied step as queued calls one millisecond apart — the same starvation pattern as continuous mouse input — and records the time of every `OnPaint` of the form. With refresh period $T$ , a paint finished at time $t$ is displayed on tick $\lceil t / T \rceil$ ( the phase of the ticks is taken as the one most favourable to the measured form ). When consecutive paints advance by $k \ge 2$ ticks, $(k - 1) T$ is added to the hitch time, and

$$\text{hitch ratio} = \frac{\sum (k - 1) T}{\text{elapsed time}} \quad [\text{ms/s}] \qquad \text{(2.1)}$$

must stay below `TMotionPace.HITCH_LIMIT` ( 5 ms/s ). Machine load is recorded during the measurement by `TLoad`; a measurement that overlaps a heavy interval is marked invalid rather than judged. `TMotionCost` measures, without showing a window, the time of one update ( step, realign, paint to an off-screen bitmap ) against a budget of half the shortest refresh period.

## 3. Architecture

```
・LUX.FMX.Window
  ┗・TMainWindow              ･･･ one per application, for the main form
     ┣・OnEnding :TProc       ･･･ entry called at session end
     ┣・Present               ･･･ show, restore and bring to front
     ┗・Conceal               ･･･ hide, taskbar button included
・LUX.FMX.Primer
  ┗・TPrimer                  ･･･ one per application, all forms
・LUX.FMX.Style
  ┗・TFmxStyle                ･･･ class members only
     ┣・Dark :Boolean         ･･･ setting it reapplies the style
     ┣・Apply                 ･･･ apply the style of the current scheme
     ┣・Color( Role_ )        ･･･ color.<role>
     ┣・Font( Role_ )         ･･･ font.<role>
     ┣・Span( Role_ )         ･･･ span.<role>
     ┗・Ground( Lookup_ )     ･･･ colour painted by a definition
・LUX.FMX.Scheme
  ┣・TSchemeMode              ･･･ smAuto / smLight / smDark
  ┣・TFmxScheme               ･･･ one per application
  ┃  ┗・Mode :TSchemeMode    ･･･ changing it reapplies and redecorates
  ┗・TSchemeChangedMessage    ･･･ sent after the scheme has changed
・LUX.FMX.Redraw
  ┣・TRedraw                  ･･･ one per application, main thread
  ┗・TRedrawingMessage        ･･･ sent just before a form is painted
・LUX.FMX.Motion
  ┣・TMotionProbe             ･･･ measures a shown form
  ┃  ┣・Pace / PaceFor       ･･･ update intervals → TMotionPace
  ┃  ┣・Drift                ･･･ the same, stepped by a timer
  ┃  ┣・Shots / ShotsFor     ･･･ frames captured from screen → TMotionShots
  ┃  ┣・Versus / ShotsVersus ･･･ application form against a bare form
  ┃  ┗・Settle               ･･･ wait for calm load, measure, retry
  ┣・TMotionCost              ･･･ time of one update, no window shown
  ┣・TMotionCostVersus        ･･･ the same against a bare form
  ┗・TMotionLock              ･･･ named mutex: one windowed test at a time
```

Unit dependencies inside the library:

```
・LUX.FMX.Scheme
  ┗・LUX.FMX.Style
・LUX.FMX.Redraw
  ┗・LUX.Windows.Monitor
・LUX.FMX.Motion
  ┣・LUX.Windows.Load
  ┗・LUX.Windows.Monitor
```

## 4. Usage

Link the two style files into the executable as `RCDATA` resources under the names `TFmxStyle` expects:

```
LUX_FMX_LIGHT RCDATA "LUX.FMX.Light.style"
LUX_FMX_DARK  RCDATA "LUX.FMX.Dark.style"
```

Apply the style in the project file, before any form is created:

```pascal
uses FMX.Forms, LUX.FMX.Scheme;

var
   S :TFmxScheme;
begin
     Application.Initialize;

     S := TFmxScheme.Create( smAuto );           // applies the style and follows Windows
     try
          Application.CreateForm( TForm1, Form1 );
          Application.Run;
     finally
          S.Free;
     end;
end.
```

Create the remaining parts in the main form's `OnCreate` and free them in `OnDestroy`:

```pascal
uses LUX.FMX.Primer, LUX.FMX.Window, LUX.FMX.Redraw;

procedure TForm1.FormCreate(Sender: TObject);
begin
     _Primer := TPrimer.Create;                  // before the first form is shown
     _Window := TMainWindow.Create( Self );      // before any other window exists
     _Redraw := TRedraw.Create;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
     _Redraw.Free;
     _Window.Free;
     _Primer.Free;
end;
```

A control that paints by itself asks the style each time:

```pascal
Canvas.Fill.Color := TFmxStyle.Color( 'accent' );
Canvas.Font.Assign( TFmxStyle.Font( 'body' ) );
```

A quick check of one update, suitable for running on every change:

```pascal
uses LUX.FMX.Motion;

var
   C :TMotionCost;
begin
     C := TMotionCost.Measure( F, 100, procedure( const Step_:Integer )   // F : a form that is not shown
     begin
          F.Width := 640 + Step_;
     end );

     Assert( C.Passed );                         // C.Mean <= C.Budget
end;
```

## 💖 [Embarcadero](https://www.embarcadero.com/) [**Delphi**](https://www.embarcadero.com/products/delphi)
Integrated Development Environment (IDE) for Creating Native Cross-Platform Apps.
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/products/delphi/starter)
