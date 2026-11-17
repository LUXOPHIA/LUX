# LUX.Process
[English](README.md) | [日本語](ja/README.md)

Parts that concern the process as a whole. `LUX.Process.Deadline` sets a deadline on the termination of the current process, so that a shutdown that stalls does not leave the process behind.

## 1. Overview

| Unit | Main types | Role |
|---|---|---|
| `LUX.Process.Deadline` | `TProcessDeadline` | ends the process if it is still running after a given time |

The unit is for Windows and depends on no user-interface framework.

## 2. Technical Background

A shutdown sequence can stall anywhere — on the main thread or in a component that does not stop — and a process that never ends competes with its next start for the same resources. `TProcessDeadline.Arm` is called when the sequence begins.

* The deadline is awaited on a dedicated thread, so it takes effect even when the main thread is blocked.
* If the process ends normally before the deadline, the waiting thread disappears with it. This thread exists to outlive its creator, so nothing waits for it.
* When the deadline arrives, the process is ended on the spot with `TerminateProcess` and the given exit code, without clean-up: the clean-up is what has stalled.

## 3. Architecture

```
・TProcessDeadline      ･･･ record of stateless class methods
  ┗・Arm( Ms_, Code_ ) ･･･ end the process after Ms_ milliseconds
```

## 4. Usage

```pascal
uses LUX.Process.Deadline;

procedure TForm1.Quit;
begin
     TProcessDeadline.Arm( 5000, 1 );            // at most five more seconds

     // ... stop workers, close windows ...

     Close;
end;
```

## 💖 [Embarcadero](https://www.embarcadero.com/) [**Delphi**](https://www.embarcadero.com/products/delphi)
Integrated Development Environment (IDE) for Creating Native Cross-Platform Apps.
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/products/delphi/starter)
