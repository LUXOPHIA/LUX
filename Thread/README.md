# LUX.Thread
[English](README.md) | [日本語](ja/README.md)

Parts for passing work between threads. `LUX.Thread.Inbox` provides a single inbox through which items arriving on any thread are delivered, in order, to a handler on the main thread.

## 1. Overview

| Unit | Main types | Role |
|---|---|---|
| `LUX.Thread.Inbox` | `IInbox<TItem_>`, `TInbox<TItem_>` | a reference-counted inbox to the main thread |

The unit depends only on the Delphi RTL and on no user-interface framework.

## 2. Technical Background

An inbox fixes, in one place, how items reach the main thread and what happens to those that arrive after their receiver has gone.

* **Always deferred.** `Post` may be called from any thread. Delivery always happens later, when the main thread drains its queue. `TThread.Queue` executes immediately when called on the main thread, so the inbox queues with `TThread.ForceQueue`; a handler that destroys controls therefore never runs in the middle of the event that posted the item.
* **Held before a handler exists.** Items that arrive while `OnTake` is unassigned are kept and delivered in arrival order once it is assigned, so receiving can begin before the receiver is built.
* **Reference counted.** The inbox is held through `IInbox<TItem_>` from the moment it is created. The owner and every background job each hold a reference, and each queued delivery holds one until it is drained.
* **Closing.** The owner calls `Close` on the main thread before releasing its reference. `Close` releases the handler and the held items there; anything posted afterwards, or queued but not yet delivered, is discarded. A background job that posts late still holds a live inbox and never touches the owner that has been torn down.

Creating the inbox, assigning `OnTake` and calling `Close` belong to the main thread. `Post`, and taking or releasing a reference, are allowed on any thread.

## 3. Architecture

```
・IInbox<TItem_>
  ┣・OnTake :TProc<TItem_> ･･･ handler, called on the main thread
  ┣・Post( Item_ )         ･･･ hand over an item, from any thread
  ┗・Close                 ･･･ discard pending items, drop the handler
・TInbox<TItem_>            ･･･ TInterfacedObject, implements IInbox
```

## 4. Usage

```pascal
uses LUX.Thread.Inbox;

var
   _Inbox :IInbox<String>;

procedure TForm1.FormCreate(Sender: TObject);
begin
     _Inbox := TInbox<String>.Create;

     _Inbox.OnTake := procedure( Text_:String )
     begin
          Memo1.Lines.Add( Text_ );              // on the main thread
     end;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
     _Inbox.Close;                               // later posts are discarded

     _Inbox := nil;
end;
```

A background job captures the interface reference and posts through it:

```pascal
procedure Start( const Inbox_:IInbox<String> );
begin
     TThread.CreateAnonymousThread( procedure
     begin
          Inbox_.Post( 'done' );
     end ).Start;
end;
```

## 💖 [Embarcadero](https://www.embarcadero.com/) [**Delphi**](https://www.embarcadero.com/products/delphi)
Integrated Development Environment (IDE) for Creating Native Cross-Platform Apps.
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/products/delphi/starter)
