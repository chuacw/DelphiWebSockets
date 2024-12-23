unit WSMultiReadThread;

interface

uses
  System.Classes, IdStackConsts,
  {$IF DEFINED(MSWINDOWS)}IdWinsock2,{$ENDIF}
  IdHTTPWebSocketClient, System.Generics.Collections,
  IdWebSocketTypes;

type

  TWSThreadList<T> = class(TThreadList<T>) // System
  public
    function Count: Integer;
  end;

  TIdWebSocketMultiReadThread = class(TThread)
  private
    class var FInstance: TIdWebSocketMultiReadThread;
  protected
    FReadTimeout: Integer;
    FTempHandle: TIdStackSocketHandle;
    FPendingBreak: Boolean;
{$IF DEFINED(MSWINDOWS)}
    FReadSet, FExceptionSet: IdWinsock2.TFDSet;
    Finterval: TTimeVal;
{$ENDIF}
    FChannels: TThreadList<TIdHTTPWebSocketClient>;
    FReconnectList: TWSThreadList<TIdHTTPWebSocketClient>;
    FReconnectThread: TIdWebSocketQueueThread;

    procedure InitComponents; virtual;
    procedure FreeComponents; virtual;

    procedure BreakSelectWait; virtual;
    procedure CloseSpecialEventSocket; virtual;
    procedure InitSpecialEventSocket; virtual;
    procedure ResetSpecialEventSocket;

    procedure PingAllChannels;
    procedure ReadFromAllChannels; virtual;

    procedure EnsureReconnectList;

    procedure Execute; override;
    function GetCount: Integer;
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;

    procedure Lock;
    procedure Unlock;
    procedure Terminate;

    procedure AddClient   (AChannel: TIdHTTPWebSocketClient);
    procedure RemoveClient(AChannel: TIdHTTPWebSocketClient);

    property Count: Integer read GetCount;
    property ReadTimeout: Integer read FReadTimeout write FReadTimeout default 5000;

    class function  Instance: TIdWebSocketMultiReadThread;
    class procedure RemoveInstance(AForced: Boolean = false);
  type
    TMultiReadClass = type of TIdWebSocketMultiReadThread;
  class var
    GMultiReadClass: TMultiReadClass;
  end;

implementation

uses
  IdStack, IdStackBSDBase, IdGlobal, System.SysUtils,
  IdIIOHandlerWebSocket, System.DateUtils,
{$IF DEFINED(MSWINDOWS)}
  Winapi.Windows,
{$ELSE}
  FMX.Platform,
{$ENDIF}
  WSDebugger;

var
  GUnitFinalized: Boolean = false;

{ TIdWebSocketMultiReadThread }

procedure TIdWebSocketMultiReadThread.AddClient(
  AChannel: TIdHTTPWebSocketClient);
var
  LList: TList<TIdHTTPWebSocketClient>;
begin
  // Assert( (aChannel.IOHandler as TIdIOHandlerWebSocket).IsWebSocket, 'Channel is not a WebSocket');
  if (Self = nil) or Terminated then
    Exit;

  LList := FChannels.LockList;
  try
    // already exists?
    if LList.IndexOf(AChannel) >= 0 then
      Exit;

    Assert(LList.Count < 64, 'Max 64 connections can be handled by one read thread!');  // due to restrictions of the "select" API
    LList.Add(AChannel);

    // trigger the "select" wait
    BreakSelectWait;
  finally
    FChannels.UnlockList;
  end;
end;

procedure TIdWebSocketMultiReadThread.AfterConstruction;
begin
  inherited;
  TIdStack.IncUsage;

  ReadTimeout := 5000;

  FChannels := TThreadList<TIdHTTPWebSocketClient>.Create;
  InitComponents;
  InitSpecialEventSocket;
end;

procedure TIdWebSocketMultiReadThread.InitComponents;
begin
{$IF DEFINED(MSWINDOWS)}
  FillChar(FReadSet, SizeOf(FReadSet), 0);
  FillChar(FExceptionSet, SizeOf(FExceptionSet), 0);
{$ENDIF}
end;

procedure TIdWebSocketMultiReadThread.FreeComponents;
begin
end;

procedure TIdWebSocketMultiReadThread.BreakSelectWait;
{$IF DEFINED(MSWINDOWS)}
var
  LAddr: TSockAddrIn6;
{$ENDIF}
begin
{$IF DEFINED(MSWINDOWS)}
  if FTempHandle = 0 then
    Exit;

  FillChar(LAddr, SizeOf(LAddr), 0);
  // Id_IPv4
  with PSOCKADDR(@LAddr)^ do
  begin
    sin_family := Id_PF_INET4;
    // dummy address and port
    (GStack as TIdStackBSDBase).TranslateStringToTInAddr('0.0.0.0', sin_addr, Id_IPv4);
    sin_port := htons(1); // port 1
  end;

  FPendingBreak := True;

  {$IF DEFINED(DEBUG_WS)}
  WSDebugger.OutputDebugString('Windows Breaking SelectWait');
  {$ENDIF}
//  connect to non-existing address to stop "select" from waiting
//  Note: this is some kind of "hack" because there is no nice way to stop it
//  The only(?) other possibility is to make a "socket pair" and send a byte to it,
//  but this requires a dynamic server socket (which can trigger a firewall
//  exception/question popup in WindowsXP+)

//  https://docs.microsoft.com/en-us/windows/desktop/api/winsock2/nf-winsock2-select
//  If a socket is processing a connect call (nonblocking), failure of the
//  connect attempt is indicated in exceptfds (application must then call
//  getsockopt SO_ERROR to determine the error value to describe why the
//  failure occurred). This document does not define which other
//  errors will be included.

  IdWinsock2.connect(FTempHandle, PSOCKADDR(@LAddr), SIZE_TSOCKADDRIN);
//  non blocking socket, so will always result in "would block"!
//  if (iResult <> Id_SOCKET_ERROR) or
//     ( (GStack <> nil) and (GStack.WSGetLastError <> WSAEWOULDBLOCK) )
//  then
//    GStack.CheckForSocketError(iResult);

{$ENDIF}
end;

procedure TIdWebSocketMultiReadThread.CloseSpecialEventSocket;
begin
  GStack.Disconnect(FTempHandle);
  FTempHandle := 0;
end;

destructor TIdWebSocketMultiReadThread.Destroy;
begin
  if FInstance = Self then
    FInstance := nil;

  Terminate;

  if FReconnectThread <> nil then
  begin
    FReconnectThread.Terminate;
    FReconnectThread.WaitFor;
    FReconnectThread.Free;
  end;

  if FReconnectList <> nil then
    FReconnectList.Free;

  CloseSpecialEventSocket;

  FreeComponents; // for descendants to work their magic

  FTempHandle := 0;
  FChannels.Free;
  TIdStack.DecUsage;
  inherited;
end;

procedure TIdWebSocketMultiReadThread.EnsureReconnectList;
begin
  if FReconnectList = nil then
    FReconnectList := TWSThreadList<TIdHTTPWebSocketClient>.Create;
end;

function TIdWebSocketMultiReadThread.GetCount: Integer;
var
  LList: TList<TIdHTTPWebSocketClient>;
begin
  LList := FChannels.LockList;
  Result := LList.Count;
  FChannels.UnlockList;
end;

procedure TIdWebSocketMultiReadThread.Execute;
var
  EM: string;
begin
  NameThreadForDebugging('WebSocket Multi Read Thread');

  while not Terminated do
  begin
    try
      while not Terminated do
      begin
        ReadFromAllChannels;
        PingAllChannels;
      end;
    except
      // continue
      on E: Exception do
        EM := E.Message;
    end;
  end;
end;

procedure TIdWebSocketMultiReadThread.InitSpecialEventSocket;
// FIONBIO is $8004667E
const
//{$IF DEFINED(PORTABLE)}
  PortableIOC_IN       = $80000000;
  PortableIOCPARM_MASK = $7F;
  PortableFIONBIO = PortableIOC_IN  or ((SizeOf(Longint) and PortableIOCPARM_MASK) shl 16)
    or (Ord('f') shl 8) or 126;    {Do not Localize}
//{$ENDIF}
var
  LIOResult: Integer;
  LFlags: Cardinal;
  LTempHandle: THandle;
begin
  if GStack = nil then
    Exit; // finalized?

  // alloc socket
  LTempHandle := GStack.NewSocketHandle(Id_SOCK_STREAM, Id_IPPROTO_IP, Id_IPv4, False);
  FTempHandle := LTempHandle;
  Assert(LTempHandle <> THandle(Id_INVALID_SOCKET));
  LFlags    := 1; // enable NON blocking mode
  LIOResult := GStack.IOControl(LTempHandle, PortableFIONBIO, LFlags);
  GStack.CheckForSocketError(LIOResult);
end;

class function TIdWebSocketMultiReadThread.Instance: TIdWebSocketMultiReadThread;
begin
  if (FInstance = nil) then
  begin
    if GUnitFinalized then
      Exit(nil);

    GlobalNameSpace.BeginWrite;
    try
      if FInstance = nil then
        begin
          FInstance := TIdWebSocketMultiReadThread.GMultiReadClass.Create(True);
          FInstance.Start;
        end;
    finally
      GlobalNameSpace.EndWrite;
    end;
  end;
  Result := FInstance;
end;

procedure TIdWebSocketMultiReadThread.PingAllChannels;
var
  LList: TList<TIdHTTPWebSocketClient>;
  chn: TIdHTTPWebSocketClient;
  ws: IIOHandlerWebSocket;
  i: Integer;
  EM: string;
begin
  {$IF DEFINED(DEBUG_WS)}
  WSDebugger.OutputDebugString('PingAllChannels');
  {$ENDIF}
  if Terminated then
    Exit;

  LList := FChannels.LockList;
  try
    {$IF DEFINED(DEBUG_WS)}
    WSDebugger.OutputDebugString('Ping', 'Channels count: '+LList.Count.ToString);
    {$ENDIF}
    for i := 0 to LList.Count - 1 do
    begin
      chn := LList.Items[i];
      if chn.NoAsyncRead then
        Continue;

      ws := chn.IOHandler;
      // valid?
      if (ws <> nil) and (ws.IsWebSocket) and (chn.Socket <> nil) and
         (chn.Socket.Binding <> nil) and (chn.Socket.Binding.Handle > 0) and
         (chn.Socket.Binding.Handle <> INVALID_SOCKET) then
        begin
          // more than 10s nothing done? then send ping
          if SecondsBetween(Now, ws.LastPingTime) > 10 then
            if chn.CheckConnection then
              try
                chn.Ping;
              except
                on E: Exception do
                  EM := E.Message;
                // retry connect the next time?
              end;
        end else
      if not chn.Connected then
        begin
          if (ws <> nil) and (SecondsBetween(Now, ws.LastActivityTime) < 5) then
            Continue;

          if chn.TryLock then
            begin
              try
                EnsureReconnectList;
                FReconnectList.Add(chn);
              finally
                chn.Unlock;
              end;
            end;
        end;
    end;
  finally
    FChannels.UnlockList;
  end;

  if Terminated then
    Exit;

  // reconnect needed? (in background)
  if FReconnectList <> nil then
    if FReconnectList.Count > 0 then
      begin
        if FReconnectThread = nil then
          begin
            FReconnectThread := TIdWebSocketQueueThread.Create(False{direct start});
            TThread.NameThreadForDebugging('Reconnect Thread', FReconnectThread.ThreadID);
          end;

        FReconnectThread.QueueEvent(
          procedure
          var
            LListX: TList<TIdHTTPWebSocketClient>;
            chn: TIdHTTPWebSocketClient;
          begin
            while FReconnectList.Count > 0 do
              begin
                chn := nil;
                try
                  // get first one
                  LListX := FReconnectList.LockList;
                  try
                    if LListX.Count <= 0 then
                      Exit;

                    chn := TObject(LListX.Items[0]) as TIdHTTPWebSocketClient;
                    if not chn.TryLock then
                    begin
                      LListX.Delete(0);
                      chn := nil;
                      Continue;
                    end;
                  finally
                    FReconnectList.UnlockList;
                  end;

                  // try reconnect
                  ws := chn.IOHandler as IIOHandlerWebSocket;
                  if ( (ws = nil) or
                       (SecondsBetween(Now, ws.LastActivityTime) >= 5) ) then
                    begin
                      try
                        if not chn.Connected then
                        begin
                          if ws <> nil then
                            ws.LastActivityTime := Now;
                          // chn.ConnectTimeout  := 1000;
                          if (chn.Host <> '') and (chn.Port > 0) then
                            chn.TryUpgradeToWebSocket;
                        end;
                      except
                        // just try
                      end;
                    end;

                  LListX := FReconnectList.LockList;
                  try
                    if LListX.Count > 0 then
                      LListX.Delete(0);
                  finally
                    FReconnectList.UnlockList;
                  end;
                finally
                  if chn <> nil then
                    chn.Unlock;
                end;
              end;
          end);
      end;
end;

procedure TIdWebSocketMultiReadThread.ReadFromAllChannels;
var
  LList: TList<TIdHTTPWebSocketClient>;
  chn: TIdHTTPWebSocketClient;
{$IF DEFINED(MSWINDOWS)}
  iCount: Integer;
  // LStart, LStopped: TDateTime;
{$ENDIF}
  i: Integer;
  iResult: NativeInt;
  ws: IIOHandlerWebSocket;
begin
  {$IF DEFINED(DEBUG_WS)}
  WSDebugger.OutputDebugString('ReadFromAllChannels');
  {$ENDIF}
  LList := FChannels.LockList;
  try
    WSDebugger.OutputDebugString('ReadFromAllChannels, channel count: '+ LList.Count.ToString);
    iResult := 0;
{$IF DEFINED(MSWINDOWS)}
    iCount  := 0;
    Freadset.fd_count := iCount;
{$ENDIF}

    for i := 0 to LList.Count - 1 do
    begin
      chn := TIdHTTPWebSocketClient(LList.Items[i]);
      if chn.NoAsyncRead then
        Continue;

      // valid?
      if // not chn.Busy and    also take busy channels (will be ignored later), otherwise we have to break/reset for each RO function execution
         (chn.IOHandler <> nil) and
         (chn.IOHandler.IsWebSocket) and
         (chn.Socket <> nil) and
         (chn.Socket.Binding <> nil) and
         (chn.Socket.Binding.Handle > 0) and
         (chn.Socket.Binding.Handle <> INVALID_SOCKET) then
      begin
        if chn.IOHandler.HasData then
        begin
          Inc(iResult);
          Break;
        end;

{$IF DEFINED(MSWINDOWS)}
        Freadset.fd_count         := iCount+1;
        Freadset.fd_array[iCount] := chn.Socket.Binding.Handle;
        Inc(iCount);
{$ENDIF}
      end;
    end;

    if FPendingBreak then
      ResetSpecialEventSocket;
  finally
    FChannels.UnlockList;
  end;

{$IF DEFINED(MSWINDOWS)}

  // nothing to wait for? then sleep some time to prevent 100% CPU
  if iResult = 0 then
  begin
    // special helper socket to be able to stop "select" from waiting
    FExceptionSet.fd_count    := 1;
    FExceptionSet.fd_array[0] := FTempHandle;

    // wait 15s till some data
    FInterval.tv_sec  := Self.ReadTimeout div 1000; // 5s
    FInterval.tv_usec := Self.ReadTimeout mod 1000;

    {$IF DEFINED(DEBUG_WS)}
    var LStart := Now;
    {$ENDIF}

    if iCount = 0 then
      begin
        iResult := IdWinsock2.select(0, nil, nil, @Fexceptionset, @Finterval);
        if iResult = SOCKET_ERROR then
          iResult := 1;  // ignore errors
      end else
      begin
      // wait till a socket has some data (or a signal via exceptionset is fired)
        iResult := IdWinsock2.select(0, @Freadset, nil, @Fexceptionset, @Finterval);
      end;

    {$IF DEFINED(DEBUG_WS)}
    var LStopped := Now;
    if MilliSecondsBetween(LStopped, LStart) < ReadTimeout then
      begin
        WSDebugger.OutputDebugString('Select Broken before Timeout');
      end else
      begin
        WSDebugger.OutputDebugString('Select Broken ON Timeout');
      end;
    {$ENDIF}

    if iResult = SOCKET_ERROR then
      // raise EIdWinsockStubError.Build(WSAGetLastError, '', []);
      // ignore error during wait: socket disconnected etc
      Exit;
  end;

{$ENDIF}

  if Terminated then
    Exit;

  // some data?
  if (iResult > 0) then
  begin
    // make sure the thread is created outside a lock
    TIdWebSocketDispatchThread.Instance;

    LList := FChannels.LockList;
    if LList = nil then
      Exit;
    try
      // check for data for all channels
      for i := 0 to LList.Count - 1 do
      begin
        if LList = nil then
          Exit;
        chn := TIdHTTPWebSocketClient(LList.Items[i]);
        if chn.NoAsyncRead then
          Continue;

        if chn.TryLock then
        try
          ws  := chn.IOHandler as IIOHandlerWebSocket;
          if (ws = nil) then
            Continue;

          if ws.TryLock then     // IOHandler.Readable cannot be done during pending action!
          try
            try
              chn.ReadAndProcessData;
            except
              on e:Exception do
              begin
                LList := nil;
                FChannels.UnlockList;
                chn.ResetChannel;
                // raise;
              end;
            end;
          finally
            ws.Unlock;
          end;
        finally
          chn.Unlock;
        end;
      end;

      if FPendingBreak then
        ResetSpecialEventSocket;
    finally
      if LList <> nil then
        FChannels.UnlockList;
      // strmEvent.Free;
    end;
  end;
end;

procedure TIdWebSocketMultiReadThread.RemoveClient(
  AChannel: TIdHTTPWebSocketClient);
begin
  if (Self = nil) or Terminated then
    Exit;

  AChannel.Lock;
  try
    EnsureReconnectList;
    FReconnectList.LockList;
    try
      FReconnectList.Remove(AChannel);
      FChannels.Remove(AChannel);
    finally
      FReconnectList.UnlockList;
    end;
  finally
    AChannel.Unlock;
  end;
  BreakSelectWait;
end;

class procedure TIdWebSocketMultiReadThread.RemoveInstance(AForced: Boolean);
var
  o: TIdWebSocketMultiReadThread;
begin
  if FInstance <> nil then
  begin
    if FInstance.Count > 0 then
      Exit;
    o := FInstance;
    o.Terminate;
    FInstance := nil;

    if AForced then
    begin
{$IF DEFINED(MSWINDOWS)}
      WaitForSingleObject(o.Handle, 2 * 1000);
      TerminateThread(o.Handle, MaxInt);
{$ENDIF}
    end else
      o.WaitFor;
    FreeAndNil(o);
  end;
end;

procedure TIdWebSocketMultiReadThread.ResetSpecialEventSocket;
begin
  Assert(FPendingBreak);
  FPendingBreak := False;

  CloseSpecialEventSocket;
  InitSpecialEventSocket;
end;

procedure TIdWebSocketMultiReadThread.Lock;
begin
  FChannels.LockList;
end;

procedure TIdWebSocketMultiReadThread.Unlock;
begin
  FChannels.UnlockList;
end;

procedure TIdWebSocketMultiReadThread.Terminate;
begin
  if FReconnectThread <> nil then
    FReconnectThread.Terminate;

  inherited Terminate;

  FChannels.LockList;
  try
    // fire a signal, so the "select" wait will quit and thread can stop
    BreakSelectWait;
  finally
    FChannels.UnlockList;
  end;
end;

{ TWSThreadList<T> }

function TWSThreadList<T>.Count: Integer;
var
  LList: TList<T>;
begin
  LList := LockList;
  Result := LList.Count;
  UnlockList;
end;

initialization
  TIdWebSocketMultiReadThread.GMultiReadClass := TIdWebSocketMultiReadThread;
finalization
  GUnitFinalized := True;
  TIdWebSocketMultiReadThread.RemoveInstance;
  TIdWebSocketDispatchThread.RemoveInstance;
end.
