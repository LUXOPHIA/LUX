program LUX.Tests;

// 共通の部品（LUX.Windows.Single・Notify・Startup・Install・Monitor・Load、LUX.Thread.Inbox、LUX.Process.Deadline と、LUX.FMX.Motion・Redraw の、窓を出さずに確かめられる所）の試験
//
// ・最初の引数が Tests.Peer の役の名前なら、試験ではなく相手役のプロセスとして動いて終わる。
// ・作って走らせる手順は、同じフォルダーの test.bat。失敗は、終了コード（1：試験の失敗・2：試験を動かせなかった）に出す。

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  LUX.Windows.Single in '..\Windows\LUX.Windows.Single.pas',
  LUX.Windows.Notify in '..\Windows\LUX.Windows.Notify.pas',
  LUX.Windows.Startup in '..\Windows\LUX.Windows.Startup.pas',
  LUX.Windows.Install in '..\Windows\LUX.Windows.Install.pas',
  LUX.Windows.Monitor in '..\Windows\LUX.Windows.Monitor.pas',
  LUX.Windows.Load in '..\Windows\LUX.Windows.Load.pas',
  LUX.FMX.Motion in '..\FMX\LUX.FMX.Motion.pas',
  LUX.FMX.Redraw in '..\FMX\LUX.FMX.Redraw.pas',
  LUX.Thread.Inbox in '..\Thread\LUX.Thread.Inbox.pas',
  LUX.Process.Deadline in '..\Process\LUX.Process.Deadline.pas',
  Tests.Peer in 'Tests.Peer.pas',
  Tests.Windows.Single in 'Tests.Windows.Single.pas',
  Tests.Windows.Notify in 'Tests.Windows.Notify.pas',
  Tests.Windows.Startup in 'Tests.Windows.Startup.pas',
  Tests.Windows.Install in 'Tests.Windows.Install.pas',
  Tests.Windows.Monitor in 'Tests.Windows.Monitor.pas',
  Tests.Windows.Load in 'Tests.Windows.Load.pas',
  Tests.FMX.Motion in 'Tests.FMX.Motion.pas',
  Tests.FMX.Redraw in 'Tests.FMX.Redraw.pas',
  Tests.Thread.Inbox in 'Tests.Thread.Inbox.pas',
  Tests.Process.Deadline in 'Tests.Process.Deadline.pas';

var
   Runner  :ITestRunner;
   Results :IRunResults;

begin
     ReportMemoryLeaksOnShutdown := True;

     if TTestPeer.Serve then Exit;

     SetConsoleOutputCP( CP_UTF8 );

     try
          TDUnitX.CheckCommandLine;

          Runner := TDUnitX.CreateRunner;
          Runner.UseRTTI := True;
          Runner.AddLogger( TDUnitXConsoleLogger.Create( True ) );
          Runner.FailsOnNoAsserts := False;

          Results := Runner.Execute;

          if not Results.AllPassed then ExitCode := 1;
     except
          on E:Exception do
          begin
               Writeln( E.ClassName, ': ', E.Message );

               ExitCode := 2;
          end;
     end;
end.
