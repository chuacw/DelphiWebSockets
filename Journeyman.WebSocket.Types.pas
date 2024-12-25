unit Journeyman.WebSocket.Types;

interface

uses
  System.Classes, System.SyncObjs, System.Generics.Collections, IdException;

type
  TWSDataType      = (wdtText, wdtBinary);
  TWSDataCode      = (wdcNone, wdcContinuation, wdcText, wdcBinary, wdcClose,
    wdcPing, wdcPong);
  TWSExtensionBit  = (webBit1, webBit2, webBit3);
  TWSExtensionBits = set of TWSExtensionBit;
  TIdWebSocketRequestType = (wsrtGet, wsrtPost);

  TIOWSPayloadInfo = record
    PayloadLength: Cardinal;
    DataCode: TWSDataCode;
    procedure Initialize(ATextMode: Boolean; APayloadLength: Cardinal);
    function DecLength(AValue: Cardinal): Boolean;
    procedure Clear;
  end;

  TOnWebSocketClosing = procedure (const AReason: string) of object;

   TWSCriticalSection = System.SyncObjs.TCriticalSection;
//  TWSCriticalSection = class
//  public
//    constructor Create;
//    procedure Enter;
//    procedure Leave;
//    function TryEnter: Boolean;
//  end;

  TThreadID = NativeUInt;

  TIdWebSocketQueueThread = class(TThread)
  private
    function GetThreadID: TThreadID;
  protected
    FLock: TWSCriticalSection;
    FTempThread: Integer;
    FEvent: TEvent;
    FEvents, FProcessing: TList<TThreadProcedure>;
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;

    procedure Lock;
    procedure Unlock;

    procedure ProcessQueue;
    procedure Execute; override;

    property ThreadID: TThreadID read GetThreadID;

    procedure Terminate;
    procedure QueueEvent(const aEvent: TThreadProcedure);
  end;

  // http://tangentsoft.net/wskfaq/intermediate.html
  // Winsock is not threadsafe, use a single/separate write thread and separate read thread
  // (do not write in 2 different thread or read in 2 different threads)
  TIdWebSocketWriteThread = class(TIdWebSocketQueueThread)
  protected
    class var FInstance: TIdWebSocketWriteThread;
  public
    class function  Instance: TIdWebSocketWriteThread;
    class procedure RemoveInstance;
    procedure Terminate;
  end;

  // async process data
  TIdWebSocketDispatchThread = class(TIdWebSocketQueueThread)
  protected
    class var FInstance: TIdWebSocketDispatchThread;
  public
    class function  Instance: TIdWebSocketDispatchThread;
    class procedure RemoveInstance(aForced: Boolean = False);
  end;

  TIdServerBaseHandling = class
  end;

implementation

uses
{$IF DEFINED(MSWINOWS)}
  Winapi.Windows,
{$ENDIF}
  System.SysUtils, Journeyman.WebSocket.DebugUtils;

var
  GUnitFinalized: Boolean = False;

{ TIOWSPayloadInfo }

procedure TIOWSPayloadInfo.Initialize(ATextMode: Boolean; APayloadLength: Cardinal);
begin
  PayloadLength := APayloadLength;
  if ATextMode then
    DataCode := wdcText else
    DataCode := wdcBinary;
end;

procedure TIOWSPayloadInfo.Clear;
begin
  PayloadLength := 0;
  DataCode := wdcBinary;
end;

function TIOWSPayloadInfo.DecLength(AValue: Cardinal): Boolean;
begin
  if PayloadLength >= AValue then
   begin
     PayloadLength := PayloadLength - AValue;
   end
   else PayloadLength := 0;
  DataCode := wdcContinuation;
  Result := PayloadLength = 0;
end;

{ TIdWebSocketQueueThread }

procedure TIdWebSocketQueueThread.AfterConstruction;
begin
  inherited;
  FLock       := TWSCriticalSection.Create;
  FEvents     := TList<TThreadProcedure>.Create;
  FProcessing := TList<TThreadProcedure>.Create;
  FEvent      := TEvent.Create;
end;

destructor TIdWebSocketQueueThread.Destroy;
begin
  Terminate;
  Lock;
  FEvents.Clear;
  FProcessing.Free;

  FEvent.Free;
  Unlock;
  FEvents.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TIdWebSocketQueueThread.Execute;
begin
  TThread.NameThreadForDebugging(ClassName);

  while not Terminated do
  begin
    try
      if FEvent.WaitFor(3 * 1000) = wrSignaled then
      begin
        FEvent.ResetEvent;
        ProcessQueue;
      end;

      if FProcessing.Count > 0 then
        ProcessQueue;
    except
      // continue
    end;
  end;
end;

function TIdWebSocketQueueThread.GetThreadID: TThreadID;
begin
  if FTempThread > 0 then
    Result := FTempThread
  else
    Result := inherited ThreadID;
end;

procedure TIdWebSocketQueueThread.Lock;
begin
  // System.TMonitor.Enter(FEvents);
  // WSDebugger.OutputDebugString('FLock Lock', TThread.Current.ThreadID.ToString);
  FLock.Enter;
end;

procedure TIdWebSocketQueueThread.ProcessQueue;
var
  LProc: TThreadProcedure;
begin
  FTempThread := TThread.Current.ThreadID; // GetCurrentThreadId;

  Lock;
  try
    // copy
    while FEvents.Count > 0 do
    begin
      LProc := FEvents.Items[0];
      FProcessing.Add(LProc);
      FEvents.Delete(0);
    end;
  finally
    Unlock;
  end;

  while FProcessing.Count > 0 do
  begin
    LProc := FProcessing.Items[0];
    FProcessing.Delete(0);
    LProc();
  end;
end;

procedure TIdWebSocketQueueThread.QueueEvent(const aEvent: TThreadProcedure);
begin
  if Terminated then
    Exit;

  Lock;
  try
    FEvents.Add(aEvent);
  finally
    Unlock;
  end;
  FEvent.SetEvent;
end;

procedure TIdWebSocketQueueThread.Terminate;
begin
  inherited Terminate;
  FEvent.SetEvent;
end;

procedure TIdWebSocketQueueThread.Unlock;
begin
//  System.TMonitor.Exit(FEvents);
//  WSDebugger.OutputDebugString('FLock Leave', TThread.Current.ThreadID.ToString);
  FLock.Leave;
end;

{ TIdWebSocketWriteThread }

class function TIdWebSocketWriteThread.Instance: TIdWebSocketWriteThread;
begin
  if FInstance = nil then
  begin
    GlobalNameSpace.BeginWrite;
    try
      if FInstance = nil then
      begin
        FInstance := Create(True);
        TThread.NameThreadForDebugging('WebSocket Write Thread', FInstance.ThreadID);
        FInstance.Start;
      end;
    finally
      GlobalNameSpace.EndWrite;
    end;
  end;
  Result := FInstance;
end;

class procedure TIdWebSocketWriteThread.RemoveInstance;
begin
  if FInstance <> nil then
  begin
    FInstance.Terminate;
    FInstance.WaitFor;
    FreeAndNil(FInstance);
  end;
end;

procedure TIdWebSocketWriteThread.Terminate;
begin
  if FInstance = Self then
    FInstance := nil;
  inherited Terminate;
end;

{ TIdWebSocketDispatchThread }

class function TIdWebSocketDispatchThread.Instance: TIdWebSocketDispatchThread;
begin
  if FInstance = nil then
  begin
    if GUnitFinalized then
      Exit(nil);

    GlobalNameSpace.BeginWrite;
    try
      if FInstance = nil then
      begin
        FInstance := Create(True);
        FInstance.Start;
      end;
    finally
      GlobalNameSpace.EndWrite;
    end;
  end;
  Result := FInstance;
end;

class procedure TIdWebSocketDispatchThread.RemoveInstance;
var
  LDispatchThread: TIdWebSocketDispatchThread;
{$IF DEFINED(CHECKSPEED)}
  LStopwatch: TStopwatch;
{$ENDIF}
begin
  if FInstance <> nil then
  begin
    LDispatchThread := FInstance;
    LDispatchThread.Terminate;
    FInstance := nil;

    if aForced then
    begin
{$IF DEFINED(CHECKSPEED)}
      LStopwatch := TStopwatch.StartNew;
{$ENDIF}
      LDispatchThread.WaitFor;
      LDispatchThread.Terminate;
{$IF DEFINED(CHECKSPEED)}
      LStopwatch.Stop;
      OutputDebugString(10, LStopwatch.ElapsedMilliseconds);
{$ENDIF}
    end;
    LDispatchThread.WaitFor;
    FreeAndNil(LDispatchThread);
  end;
end;

end.

