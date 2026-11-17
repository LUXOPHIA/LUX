# LUX.Windows
[English](README.md) | [日本語](ja/README.md)

Windows-specific parts for the start-up, residence and installation of a desktop application, and for reading the state of the machine. They call the Windows API directly and depend on no user-interface framework, so they serve FireMonkey and VCL applications alike.

## 1. Overview

| Unit | Main types | Role |
|---|---|---|
| `LUX.Windows.Single` | `TWinSingle`, `TWinRequest` | keeps one process per name and hands the command-line arguments of a second one to the first |
| `LUX.Windows.Notify` | `TWinNotify` | notification-area icon with a context menu and balloon notifications |
| `LUX.Windows.Startup` | `TWinStartup` | start at sign-in, registered under the current user's `Run` key |
| `LUX.Windows.Install` | `TWinInstaller` | install, update and uninstall with the executable itself |
| `LUX.Windows.Monitor` | `TWinMonitor` | the monitor a window is on and its refresh period |
| `LUX.Windows.Load` | `TLoad`, `TLoadTrace`, `TLoadSpan` | machine-wide load sampled on a dedicated thread |

`LUX.Windows.Install` uses `LUX.Windows.Startup`; the other units are independent of each other.

## 2. Technical Background

### 2.1 Single instance ( `LUX.Windows.Single` )

The first process to create a `TWinSingle` with a given name in a Windows session is the first instance ( `First` is true ). A request is the argument list itself, sent as one message over a message-type named pipe, so a partially written request is never read and concurrent requesters are queued by the operating system. The first instance creates the pipe while still holding the mutex that identifies it, so a second instance never observes a half-prepared state and no timed waiting is involved. The requester obtains the server's process identifier from the connected pipe ( `GetNamedPipeServerProcessId` ), grants it the right to come to the foreground, and may wait for it to end. The result is one of `trAbsent`, `trEnded`, `trAlive` and `trFailed`.

### 2.2 Notification area ( `LUX.Windows.Notify` )

`TWinNotify` owns a hidden window ( `AllocateHWnd` ) and registers the executable's `MAINICON` with `Shell_NotifyIcon`. A left click and a double click each call `OnOpen` exactly once, on the first button release, without waiting to tell them apart. The icon is registered again when Explorer restarts ( `TaskbarCreated` ), which also covers a start before the taskbar exists.

### 2.3 Start at sign-in ( `LUX.Windows.Startup` )

`TWinStartup` writes the value `"<executable>" /tray` under `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`. `/tray` is the argument by which the application starts resident without showing its window. `Enabled` reads true only when the registration points at this executable in this form.

### 2.4 Installation ( `LUX.Windows.Install` )

`TWinInstaller` installs the running executable, files beside it and an optional embedded zip resource into `Program Files\LUXOPHIA\<App>` by default. The steps are separate methods so that the caller decides their order and which run elevated: `Place`, `Register` ( the Windows list of installed apps, under `HKEY_LOCAL_MACHINE` ), `Grant` ( lets the user update later without elevation ), `Sweep` and `Enroll` ( Start-menu shortcut ). Uninstalling copies the executable to a temporary location and continues from there, because a running executable cannot delete itself; files still in use are removed at the next restart with `MoveFileEx`.

### 2.5 Monitor refresh period ( `LUX.Windows.Monitor` )

Since Windows 8.1 `DwmGetCompositionTimingInfo` accepts no window, so it cannot give a per-monitor period. `TWinMonitor` takes the monitor from `MonitorFromWindow`, its device name from `GetMonitorInfo`, and the refresh rate from `EnumDisplaySettings` ( `dmDisplayFrequency` ). The period is 0 when the rate is unknown. Because the rate is an integer number of hertz, the period can be off by less than 2 % on fractional rates.

### 2.6 Machine load ( `LUX.Windows.Load` )

`TLoad` samples through PDH on its own thread every 16 ms — not shorter than the clock interrupt interval, below which occupancy figures are meaningless — and stores each value as a time span:

| `TLoadKind` | Value |
|---|---|
| `lkCPU` | processor occupancy ( % ), from the raw user and privileged time counters |
| `lkGPU3D`, `lkGPUCopy`, `lkGPUEtc` | busiest GPU engine of each type ( % ), excluding this process |
| `lkPaging` | pages written out to free physical memory ( pages / s ) |
| `lkDisk` | busiest physical disk ( % ) |

`LOAD_LINES` gives the line above which a span counts as heavy: 50 % for the occupancies and 0 for paging.

## 3. Architecture

```
・LUX.Windows.Single
  ┣・TWinRequest                   ･･･ trAbsent / trEnded / trAlive / trFailed
  ┗・TWinSingle
     ┣・First :Boolean             ･･･ this process is the first instance
     ┣・Listen( OnRequest_ )       ･･･ first instance: start receiving requests
     ┗・Request( Args_, Timeout_ ) ･･･ later instance: send its arguments
・LUX.Windows.Notify
  ┗・TWinNotify
     ┣・Tip :String                ･･･ text shown on hover
     ┣・OnOpen :TProc              ･･･ left click or double click
     ┣・AddItem / AddSeparator     ･･･ build the context menu
     ┣・Primary :Integer           ･･･ item shown in bold
     ┣・Enableds[ Item_ ] :Boolean ･･･ whether the item can be chosen
     ┗・Balloon( Title_, Text_ )   ･･･ show a notification
・LUX.Windows.Startup
  ┗・TWinStartup                   ･･･ record
     ┣・Command :String            ･･･ "<Exe>" /tray
     ┗・Enabled :Boolean           ･･･ read: registered; write: add / remove
・LUX.Windows.Install
  ┗・TWinInstaller                 ･･･ record
     ┣・Dest, Target :String       ･･･ destination folder and executable
     ┣・Installed :Boolean         ･･･ running from the destination
     ┣・Startup :TWinStartup       ･･･ start-at-sign-in registration
     ┣・Place / Register / Grant   ･･･ install steps that need elevation
     ┣・Sweep / Enroll             ･･･ install steps as the user
     ┣・Uninstall / Remove         ･･･ handlers of /uninstall and /remove
     ┗・Elevate( Args_ )           ･･･ restart itself as administrator
・LUX.Windows.Monitor
  ┗・TWinMonitor                   ･･･ record
     ┣・Period :Double             ･･･ refresh period in seconds, 0 if unknown
     ┗・MinPeriod :Double          ･･･ shortest period among all monitors
・LUX.Windows.Load
  ┣・TLoadSpan                     ･･･ one value over one time span
  ┣・TLoadTrace                    ･･･ spans in a time range, with a summary
  ┃  ┗・Heavy( Head_, Tail_ )     ･･･ any span above its line in the range
  ┗・TLoad                         ･･･ owns the sampling thread
     ┣・Now :Double                ･･･ current time in milliseconds
     ┣・Trace( Head_, Tail_ )      ･･･ cut out a range → TLoadTrace
     ┣・Await( Time_, Proc_ )      ･･･ call back once sampled up to Time_
     ┗・Calm( Proc_ )              ･･･ call back once all kinds are below line
```

## 4. Usage

A resident application that allows one instance and shows its window when started again:

```pascal
uses LUX.Windows.Single, LUX.Windows.Notify;

var
   S :TWinSingle;
begin
     S := TWinSingle.Create( 'Example.App' );

     if not S.First then
     begin
          S.Request( [], 0 );                    // ask the first instance to show itself

          Exit;
     end;

     S.Listen( procedure( Args_:TArray<String> )
     begin
          // called on a waiting thread: hand Args_ over to the main thread
     end );
end;
```

```pascal
     N := TWinNotify.Create( 'Example' );
     N.OnOpen  := ShowMain;
     N.Primary := N.AddItem( 'Open', ShowMain );
     N.AddSeparator;
     N.AddItem( 'Quit', Quit );
     N.Balloon( 'Example', 'Finished.' );
```

The refresh period of the monitor a window is on, and a load trace over a measured interval:

```pascal
uses LUX.Windows.Monitor, LUX.Windows.Load;

var
   L :TLoad;
   H :Double;
   T :TLoadTrace;
begin
     Writeln( TWinMonitor.Create( Wnd ).Period * 1000:0:2, ' ms' );

     L := TLoad.Create;
     try
          H := TLoad.Now;
          // ... the work to be measured ...
          T := L.Trace( H, TLoad.Now );

          if T.Heavy( 0, T.Elapse ) then Writeln( 'measured under heavy load' );
     finally
          L.Free;
     end;
end;
```

## 💖 [Embarcadero](https://www.embarcadero.com/) [**Delphi**](https://www.embarcadero.com/products/delphi)
Integrated Development Environment (IDE) for Creating Native Cross-Platform Apps.
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/products/delphi/starter)
