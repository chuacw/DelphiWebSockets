unit Journeyman.Portable.WSMultiReadThread;

interface

uses
  Journeyman.WebSocket.MultiReadThread, IdStack, IdStackConsts;

type

  TPortableMultiReadThread = class(TIdWebSocketMultiReadThread)
  protected
    FReadSet, FExceptionSet: TIdSocketList;
    FInterval: Integer;

{$IF DEFINED(ANDROID)}
    FConnectIP: string;
    FConnectHandle, FListenHandle: TIdStackSocketHandle;

    procedure Disconnect(var AHandle: TIdStackSocketHandle); inline;
{$ENDIF}
    procedure BreakSelectWait; override;
    procedure CloseSpecialEventSocket; override;
    procedure InitSpecialEventSocket; override;

    procedure InitComponents; override;
    procedure FreeComponents; override;

    procedure ReadFromAllChannels; override;
  end;

implementation

{$WARN UNIT_PLATFORM OFF}
uses
  IdStackBSDBase, IdGlobal, System.SysUtils,
  Journeyman.WebSocket.Interfaces,
  System.DateUtils, Journeyman.WebSocket.Consts,
  {$IF DEFINED(MSWINDOWS)}
    Winapi.Windows,
  {$ELSEIF DEFINED(POSIX)}
    Posix.Fcntl, Posix.Unistd, Posix.StrOpts,
  {$ENDIF}
  System.Generics.Collections, Journeyman.WebSocket.Client, Journeyman.WebSocket.Types,
  Journeyman.WebSocket.Debugger;

{$IF DEFINED(ANDROID)}
type
  TIdStackAndroid = class helper for TIdStackBSDBase
  public
    function SendTo(ASocket: TIdStackSocketHandle; const ABuffer: TIdBytes;
      const AOffset: Integer = 0; const ASize: Integer = -1; Flags: Integer = 0): Integer; overload; inline;
    function SendTo(ASocket: TIdStackSocketHandle; const ABuffer: TArray<Byte>;
      const AOffset: Integer = 0; const ASize: Integer = -1; Flags: Integer = 0): Integer; overload; inline;
  end;

function  TIdStackAndroid.SendTo(ASocket: TIdStackSocketHandle;
  const ABuffer: TIdBytes; const AOffset: Integer = 0;
  const ASize: Integer = -1; Flags: Integer = 0): Integer;
begin
  Result := WSSend(ASocket, ABuffer[AOffset], Length(ABuffer), Flags);
end;

function  TIdStackAndroid.SendTo(ASocket: TIdStackSocketHandle;
  const ABuffer: TArray<Byte>; const AOffset: Integer = 0;
  const ASize: Integer = -1; Flags: Integer = 0): Integer;
begin
  Result := WSSend(ASocket, ABuffer[AOffset], Length(ABuffer), Flags);
end;

procedure TPortableMultiReadThread.Disconnect(var AHandle: TIdStackSocketHandle);
begin
  if AHandle <> 0 then
    begin
      GStack.Disconnect(AHandle);
      AHandle := 0;
    end;
end;
{$ENDIF}

procedure TPortableMultiReadThread.BreakSelectWait;
begin
  if FTempHandle = 0 then
    Exit;

  FPendingBreak := True;
{$IF DECLARED(TIdStackAndroid)}

  var LBuffer: TIdBytes := [$99]; // send any data... this value arbitrary.
// Send an OOB message, necessary to cause Select to exit immediately
// on the Exception set.
  GBSDStack.SendTo(FConnectHandle, LBuffer, 0, Length(LBuffer),
    MSG_OOB);

  {$IF DEFINED(DEBUG_WS)}
  WSDebugger.OutputDebugString('Socket', 'OOB data, no disconnection');
  {$ENDIF}

{$ELSEIF DEFINED(POSIX)}
  // pipe approach, which works by writing to the write part of the pipe
  // which then causes data to be available in the read part of the pipe
  var nRead: Integer := 0;
  var Dummy: Byte := 0;
  var LIOCtlResult := ioctl(FTempHandle, FIONREAD, @nRead);
  if (LIOCtlResult = 0) and (nRead = 0) then
    begin
      // Writes to the write pipe
      FileWrite(FPosixWritePipe, @Dummy, SizeOf(Dummy));
    end;
{$ELSE}

//   connect to non-existing address to stop "select" from waiting
//   Note: this is some kind of "hack" because there is no nice way to stop it
//   The only(?) other possibility is to make a "socket pair" and send a byte to it,
//   but this requires a dynamic server socket (which can trigger a firewall
//   exception/question popup in WindowsXP+)

//  https://docs.microsoft.com/en-us/windows/desktop/api/winsock2/nf-winsock2-select
//  If a socket is processing a connect call (nonblocking), failure of the
//  connect attempt is indicated in exceptfds (application must then call
//  getsockopt SO_ERROR to determine the error value to describe why the
//  failure occurred). This document does not define which other
//  errors will be included.
  try
    {$IF DEFINED(DEBUG_WS)}
    WSDebugger.OutputDebugString('WSChat', 'Portable Breaking SelectWait');
    {$ENDIF}
    // Hopefully nothing is listening on port 1
    GStack.Connect(FTempHandle, '0.0.0.0', 1, Id_IPv4);
  except
    on E: EIdSocketError do
      ; // do nothing
  else
    raise;
  end;
{$ENDIF}
end;

procedure TPortableMultiReadThread.CloseSpecialEventSocket;
begin
{$IF DEFINED(POSIX) OR DEFINED(ANDROID)}
  Disconnect(FListenHandle);
  Disconnect(FConnectHandle);
  Disconnect(FTempHandle);
//{$ELSEIF DEFINED(POSIX)}
//  FileClose(FTempHandle);
//  FTempHandle := 0;
//  FileClose(FPosixWritePipe);
//  FPosixWritePipe := 0;
{$ELSE}
  inherited;
{$ENDIF}
end;


procedure TPortableMultiReadThread.InitComponents;
begin
  FReadSet := TIdSocketList.CreateSocketList;
  FExceptionSet := TIdSocketList.CreateSocketList;
end;

procedure TPortableMultiReadThread.FreeComponents;
begin
  FExceptionSet.Free;
  FReadSet.Free;
end;

procedure TPortableMultiReadThread.InitSpecialEventSocket;
// FIONBIO is $8004667E
const
//{$IF DEFINED(PORTABLE)}
  PortableIOC_IN       = $80000000;
  PortableIOCPARM_MASK = $7F;
  PortableFIONBIO = PortableIOC_IN  or ((SizeOf(Longint) and PortableIOCPARM_MASK) shl 16)
    or (Ord('f') shl 8) or 126;    {Do not Localize}
//{$ENDIF}
var
  LTempHandle: THandle;
begin
  if GStack = nil then
    Exit; // finalized?

{$REGION 'Enable non-blocking mode'}
{$IF DEFINED(ANDROID) OR DEFINED(LINUX)}
  LTempHandle := GStack.NewSocketHandle(Id_SOCK_STREAM, Id_IPPROTO_IP,
    Id_IPv4, False);

//  FTempHandle := LTempHandle;
//
//  var LFlags := fcntl(LTempHandle, F_GETFL, 0);
//  LFlags := LFlags or O_NONBLOCK;
//  fcntl(LTempHandle, F_SETFL, LFlags);

  GStack.Bind(LTempHandle, '0.0.0.0', 0, Id_IPv4);
  var LIP: string; var LPort: Word;
  GStack.GetSocketName(LTempHandle, LIP, LPort);

// Can't connect to 0.0.0.0, so need to connect to a valid address...
  if LIP = '0.0.0.0' then
    FConnectIP := '127.0.0.1' else
    FConnectIP := LIP;

  GStack.Listen(LTempHandle, 1);
  FListenHandle := LTempHandle;

  FConnectHandle := GStack.NewSocketHandle(Id_SOCK_STREAM, Id_IPPROTO_IP, Id_IPv4, False);
  GStack.Connect(FConnectHandle, FConnectIP, LPort, Id_IPv4);

  var LAcceptedHandle := GStack.Accept(FListenHandle, FConnectIP, LPort);

  FTempHandle := LAcceptedHandle;

{$ELSEIF DEFINED(POSIX)}
//  LFlags := fcntl(LTempHandle, F_GETFL, 0);
//  LFlags := LFlags or O_NONBLOCK;
//  iResult := fcntl(LTempHandle, F_SETFL, LFlags);

  // pipe approach, which works by writing to the write part of the pipe
  // which then causes data to be available in the read part of the pipe
  var LSyncEvent: TPipeDescriptors;
  if pipe(LSyncEvent) >= 0 then
    begin
      FTempHandle := LSyncEvent.ReadDes;      // read pipe
      FPosixWritePipe := LSyncEvent.WriteDes; // write pipe
    end;
{$ELSE}
  // alloc socket
  LTempHandle := GStack.NewSocketHandle(Id_SOCK_STREAM, Id_IPPROTO_IP, Id_IPv4, False);
  FTempHandle := LTempHandle;
  Assert(LTempHandle <> THandle(Id_INVALID_SOCKET));
  var LFlags: Cardinal := 1; // enable NON blocking mode
  var iResult := GStack.IOControl(LTempHandle, PortableFIONBIO, LFlags);
  GStack.CheckForSocketError(iResult);
{$ENDIF}
{$ENDREGION}
end;

procedure TPortableMultiReadThread.ReadFromAllChannels;
var
  LList: TList<TIdHTTPWebSocketClient>;
  LClient: TIdHTTPWebSocketClient;
  /// <summary>Number of WebSockets with data.</summary>
  LWebSocketCount, I: Integer;
  LSelectorsHaveData: Boolean;
  LEnterSleep: Boolean;
  LHandler: IIOHandlerWebSocket;
begin
  {$IF DEFINED(DEBUG_WS)}
  WSDebugger.OutputDebugString('ReadFromAllChannels');
  {$ENDIF}
  LList := FChannels.LockList;
  try
    {$IF DEFINED(DEBUG_WS)}
    WSDebugger.OutputDebugString('ReadFromAllChannels, channel count: '+ LList.Count.ToString);
    {$ENDIF}
    LWebSocketCount  := 0;
    LSelectorsHaveData := False;
    FReadSet.Clear;

    for I := 0 to LList.Count - 1 do
    begin
      LClient := TIdHTTPWebSocketClient(LList.Items[I]);
      if LClient.NoAsyncRead then
        Continue;

      LHandler := LClient.IOHandler;

      // valid?
      if //not chn.Busy and    also take busy channels (will be ignored later),
      // otherwise we have to break/reset for each RO function execution
         (LHandler <> nil) and (LHandler.IsWebSocket) and
         (LClient.Socket <> nil) and (LClient.Socket.Binding <> nil) and
         (LClient.Socket.Binding.Handle > 0) and
         (LClient.Socket.Binding.Handle <> Id_INVALID_SOCKET) then
      begin
        if LHandler.HasData then
        begin
          LSelectorsHaveData := True;
          Break;
        end;

        FReadSet.Add(LClient.Socket.Binding.Handle);
        Inc(LWebSocketCount);
      end;
    end;

    if FPendingBreak then
      ResetSpecialEventSocket;
  finally
    FChannels.UnlockList;
  end;

  LEnterSleep := not LSelectorsHaveData;

  // nothing to wait for? then sleep some time to prevent 100% CPU
  if LEnterSleep then
  begin
    {$IF DEFINED(DEBUG_WS)}
    var LStart := Now;
    {$ENDIF}

    // special helper socket to be able to stop "select" from waiting
    FExceptionSet.Clear;
    FExceptionSet.Add(FTempHandle);
    FInterval := ReadTimeout;

    var LExceptionSet: TIdSocketList;

    if LWebSocketCount = 0 then
    begin
      try
        // Returns true if there's data
        // Returns false if timeout
        // Throws an exception if the exception handle has been connected
        LExceptionSet := FExceptionSet;
        LSelectorsHaveData := FReadSet.Select(nil, nil, LExceptionSet, FInterval);
      except
        LSelectorsHaveData := True;
      end;
    end else
    begin
      // wait till a socket has some data (or a signal via exceptionset is fired)
      try
        LSelectorsHaveData := FReadSet.Select(FReadSet, nil, FExceptionSet, FInterval);
      except
        // an error should be the equivalent of iResult = SOCKET_ERROR,
        // so set LSelectorsHaveData = false, so that it'll exit...
        LSelectorsHaveData := False;
      end;
    end;

    {$IF DEFINED(DEBUG_WS)}
    var LStopped := Now;
    if MilliSecondsBetween(LStopped, LStart) < ReadTimeout then
      begin
        WSDebugger.OutputDebugString('WSChat', 'Select Broken before Timeout');
      end else
      begin
        WSDebugger.OutputDebugString('WSChat', 'Select Broken ON Timeout');
      end;
    {$ENDIF}

    if not LSelectorsHaveData then
      Exit;

  end;

  if Terminated then
    Exit;

  // Is there some data?

  if LSelectorsHaveData then
  begin
    // make sure the thread is created outside a lock
    TIdWebSocketDispatchThread.Instance;

    LList := FChannels.LockList;
    {$REGION 'LOOP'}
    if LList = nil then
      Exit;
    try
      // check for data for all channels
      for I := 0 to LList.Count - 1 do
      begin
        if LList = nil then
          Exit;
        LClient := TIdHTTPWebSocketClient(LList.Items[I]);
        if LClient.NoAsyncRead then
          Continue;

        if LClient.TryLock then
        try
          LHandler  := LClient.IOHandler as IIOHandlerWebSocket;
          if (LHandler = nil) then
            Continue;

          if LHandler.TryLock then     // IOHandler.Readable cannot be done during pending action!
          try
            try
              // If the client got disconnecte, it won't be able to read any data
              // and the SSL connection will throw an exceptino
              // so need to protect it with a try except block
              LClient.ReadAndProcessData;
            except
              // usually an EAccessViolation from the SSL layer if it's disconnected
              on E: Exception do
              begin
                LList := nil;
                FChannels.UnlockList;
                LClient.ResetChannel;
                // raise;
              end;
            end;
          finally
            LHandler.Unlock;
          end;
        finally
          LClient.Unlock;
        end;
      end;

      if FPendingBreak then
        ResetSpecialEventSocket;
    finally
      if LList <> nil then
        FChannels.UnlockList;
      // strmEvent.Free;
    end;
    {$ENDREGION}
  end;
end;

initialization
  TIdWebSocketMultiReadThread.GMultiReadClass := TPortableMultiReadThread;
end.
