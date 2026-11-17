unit Tests.Thread.Inbox;

// LUX.Thread.Inbox の試験
//
//【持ち方】
// ・受け口は、作った時点から、インターフェース（IInbox）で持つ。片付けるときは、Close してから、参照を手放す。

interface //#################################################################### ■

uses DUnitX.TestFramework;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TInboxTests

     [TestFixture]
     TInboxTests = class
     public
       [Test] procedure HeldUntilTaker;
       [Test] procedure LaterOnMainThread;
       [Test] procedure DroppedAfterRelease;
       [Test] procedure FromOtherThread;
       [Test] procedure DroppedAfterClose;
       [Test] procedure LateAfterOwnerGone;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.SysUtils, System.Classes, System.SyncObjs,
     LUX.Thread.Inbox;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TInboxTests

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 受け取り手が決まる前に届いたものは、ためておかれ、決まったときに、届いた順に渡る
procedure TInboxTests.HeldUntilTaker;
var
   B :IInbox<String>;
   G :String;
begin
     G := '';

     B := TInbox<String>.Create;
     try
          B.Post( 'a' );
          B.Post( 'b' );

          CheckSynchronize;  // 主スレッドに届いたが、受け取り手がまだ無いので、ためておかれる

          Assert.AreEqual( '', G );

          B.OnTake := procedure( S :String ) begin G := G + S end;

          Assert.AreEqual( 'ab', G );

          B.Post( 'c' );

          CheckSynchronize;

          Assert.AreEqual( 'abc', G );
     finally
          B.Close;
     end;
end;

// 主スレッドから渡したものも、その場では渡らず、主スレッドが順番待ちを汲んだときに渡る
procedure TInboxTests.LaterOnMainThread;
var
   B :IInbox<String>;
   G :String;
begin
     G := '';

     B := TInbox<String>.Create;
     try
          B.OnTake := procedure( S :String ) begin G := G + S end;

          B.Post( 'a' );

          Assert.AreEqual( '', G, '主スレッドから渡しても、その場では渡らない' );

          CheckSynchronize;

          Assert.AreEqual( 'a', G, '後で渡る' );

          // 主スレッドから積んで、汲まれる前に閉じたものは、捨てられる
          B.Post( 'b' );
          B.Close;

          CheckSynchronize;

          Assert.AreEqual( 'a', G, '閉じた後は、渡らない' );
     finally
          B.Close;
     end;
end;

// 積んで、汲まれる前に閉じて参照を手放したものは、捨てられる（積んだ手続きが、受け口を生かしておき、汲まれた後に壊れる）
procedure TInboxTests.DroppedAfterRelease;
var
   B :IInbox<String>;
   G :String;
begin
     G := '';

     B := TInbox<String>.Create;
     B.OnTake := procedure( S :String ) begin G := G + S end;

     B.Post( 'a' );
     B.Close;
     B := nil;

     CheckSynchronize;

     Assert.AreEqual( '', G );
end;

// ほかの実行スレッドから届いたものは、主スレッドで渡る
procedure TInboxTests.FromOtherThread;
var
   B :IInbox<Integer>;
   T :TThread;
   M :TThreadID;
   G :Integer;
begin
     G := 0;
     M := 0;

     B := TInbox<Integer>.Create;
     try
          B.OnTake := procedure( I :Integer )
                      begin
                           G := I;
                           M := TThread.CurrentThread.ThreadID;
                      end;

          T := TThread.CreateAnonymousThread( procedure begin B.Post( 7 ) end );
          T.FreeOnTerminate := False;
          T.Start;
          T.WaitFor;  // 主スレッドは、待つ間にも、回されたものを汲む
          T.Free;

          CheckSynchronize;

          Assert.AreEqual( 7, G );
          Assert.AreEqual( MainThreadID, M );
     finally
          B.Close;
     end;
end;

// 閉じた後に届いたもの・閉じる前に届いて、まだ渡っていないものは、捨てられる
procedure TInboxTests.DroppedAfterClose;
var
   B :IInbox<String>;
   T :TThread;
   E :TEvent;
   G :String;
begin
     G := '';

     E := TEvent.Create( nil, True, False, '' );
     B := TInbox<String>.Create;
     try
          B.OnTake := procedure( S :String ) begin G := G + S end;

          // ほかの実行スレッドが渡し終えたことを、合図で知る（合図を待つ間、主スレッドは、回されたものを汲まない）
          T := TThread.CreateAnonymousThread( procedure
                                              begin
                                                   B.Post( 'x' );

                                                   E.SetEvent;
                                              end );
          T.FreeOnTerminate := False;
          T.Start;

          Assert.AreEqual( wrSignaled, E.WaitFor( 10000 ) );

          B.Close;  // 'x' は、届いているが、まだ渡っていない

          T.WaitFor;
          T.Free;

          CheckSynchronize;

          B.Post( 'y' );

          CheckSynchronize;

          Assert.AreEqual( '', G );
     finally
          B.Close;
          E.Free;
     end;
end;

// 持ち主が閉じて参照を手放した後に、裏の仕事が、持っていた参照で渡しても、捨てられ、壊れた持ち主に触れない。
// 受け口は、裏の仕事が参照を手放し、積んだ手続きが汲まれた後に、壊れる（試験の後のリークの検査で、残らないことを見る）
procedure TInboxTests.LateAfterOwnerGone;
var
   B :IInbox<String>;
   G :String;
   E, F :TEvent;
   T :TThread;
begin
     G := '';

     E := TEvent.Create( nil, True, False, '' );
     F := TEvent.Create( nil, True, False, '' );
     try
          B := TInbox<String>.Create;
          B.OnTake := procedure( S :String ) begin G := G + S end;

          // 裏の仕事は、自分の参照を持ち、持ち主が片付けた後で渡す
          T := TThread.CreateAnonymousThread( procedure
                                              var
                                                 J :IInbox<String>;
                                              begin
                                                   J := B;

                                                   E.SetEvent;

                                                   F.WaitFor( INFINITE );

                                                   J.Post( 'late' );
                                              end );
          T.FreeOnTerminate := False;
          T.Start;

          Assert.AreEqual( wrSignaled, E.WaitFor( 10000 ), '裏の仕事が、参照を持った' );

          B.Close;
          B := nil;  // 持ち主が片付けた

          F.SetEvent;

          T.WaitFor;
          T.Free;

          CheckSynchronize;

          Assert.AreEqual( '', G, '閉じた後に届いたものは、渡らない' );
     finally
          F.Free;
          E.Free;
     end;
end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

     TDUnitX.RegisterTestFixture( TInboxTests );

end. //######################################################################### ■
