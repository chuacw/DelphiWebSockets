unit IdWebSocketServer;
interface

uses
  System.Classes, IdStreamVCL, IdGlobal, IdWinsock2, IdHTTPServer, IdContext,
  IdCustomHTTPServer, IdHTTPWebBrokerBridge, IdIOHandlerWebSocket,
  IdServerIOHandlerWebSocket, IdServerWebSocketContext,
  IdServerWebSocketHandling, IdServerSocketIOHandling, IdWebSocketTypes,
  IdIIOHandlerWebSocket;

type
  TWebSocketMessageText = procedure(const AContext: TIdServerWSContext;
    const aText: string; const AResponse: TStream)  of object;
  TWebSocketMessageBin  = procedure(const AContext: TIdServerWSContext;
    const aData: TStream; const AResponse: TStream) of object;

  {$IFDEF WEBSOCKETBRIDGE}
  TMyIdHttpWebBrokerBridge = class(TidHttpWebBrokerBridge)
  published
    property OnCreatePostStream;
    property OnDoneWithPostStream;
    property OnCommandGet;
  end;
  {$ENDIF}

  {$IFDEF WEBSOCKETBRIDGE}
  TIdWebSocketServer = class(TMyIdHttpWebBrokerBridge)
  {$ELSE}
  TIdWebSocketServer = class(TIdHTTPServer)
  {$ENDIF}
  private
    FSocketIO: TIdServerSocketIOHandling_Ext;
    FOnMessageText: TWebSocketMessageText;
    FOnMessageBin: TWebSocketMessageBin;
    FOnWebSocketClosing: TOnWebSocketClosing;
    FWriteTimeout: Integer;
    FConnectionEvents: TWebSocketConnectionEvents;

    function GetSocketIO: TIdServerSocketIOHandling;
    procedure SetWriteTimeout(const Value: Integer);
  protected
    function WebSocketCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean;
    procedure DoCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo); override;
    procedure ContextCreated(AContext: TIdContext); override;
    procedure ContextDisconnected(AContext: TIdContext); override;

    procedure InternalDisconnect(const AHandler: IIOHandlerWebsocket;
      ANotifyPeer: Boolean; const AReason: string='');

    procedure WebSocketUpgradeRequest(const AContext: TIdServerWSContext;
      const ARequestInfo: TIdHTTPRequestInfo; var Accept: Boolean); virtual;
    procedure WebSocketChannelRequest(const AContext: TIdServerWSContext;
      var aType:TWSDataType; const aStrmRequest, aStrmResponse: TMemoryStream); virtual;

    procedure SetOnWebSocketClosing(const AValue: TOnWebSocketClosing);

    // Fix for AV when changing Active from True to False;
    procedure DoTerminateContext(AContext: TIdContext); override;

  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;

    procedure DisconnectAll(const AReason: string='');
    procedure DisconnectWithReason(const AHandler: IIOHandlerWebSocket;
      const AReason: string; ANotifyPeer: Boolean = True);
    procedure SendMessageToAll(const aBinStream: TStream); overload;
    /// <summary> Sends the indicated message to all users except the AExceptTarget </summary>
    procedure SendMessageToAll(const AText: string;
      const AExceptTarget: TIdServerWSContext=nil); overload;

    property OnConnected: TWebSocketConnected read FConnectionEvents.ConnectedEvent
      write FConnectionEvents.ConnectedEvent;
    property OnDisconnected: TWebSocketDisconnected read FConnectionEvents.DisconnectedEvent
      write FConnectionEvents.DisconnectedEvent;
    property OnMessageText: TWebSocketMessageText read FOnMessageText write FOnMessageText;
    property OnMessageBin : TWebSocketMessageBin  read FOnMessageBin  write FOnMessageBin;
    property OnWebSocketClosing: TOnWebSocketClosing read FOnWebSocketClosing write SetOnWebSocketClosing;

    property SocketIO: TIdServerSocketIOHandling read GetSocketIO;
  published
    property WriteTimeout: Integer read FWriteTimeout write SetWriteTimeout default 2000;
  end;

implementation

uses
  System.SysUtils, WSDebugger, IdHTTPWebSocketClient;

{ TIdWebSocketServer }

procedure TIdWebSocketServer.AfterConstruction;
begin
  inherited;

  FSocketIO := TIdServerSocketIOHandling_Ext.Create;

  ContextClass := TIdServerWSContext;
  if IOHandler = nil then
    IOHandler := TIdServerIOHandlerWebSocket.Create(Self);

  FWriteTimeout := 2 * 1000;  //2s
end;

procedure TIdWebSocketServer.ContextCreated(AContext: TIdContext);
begin
  inherited ContextCreated(AContext);
  (AContext as TIdServerWSContext).OnCustomChannelExecute := Self.WebSocketChannelRequest;

  // default 2s write timeout
  // http://msdn.microsoft.com/en-us/library/windows/desktop/ms740532(v=vs.85).aspx
  try
    AContext.Connection.Socket.Binding.SetSockOpt(SOL_SOCKET, SO_SNDTIMEO, WriteTimeout);
  except
    // Some Lunux, eg Ubuntu, can't accept setting of WriteTimeout
  end;
end;

procedure TIdWebSocketServer.ContextDisconnected(AContext: TIdContext);
begin
  FSocketIO.FreeConnection(AContext);
  inherited;
end;

destructor TIdWebSocketServer.Destroy;
begin
  FSocketIO.Free;
  inherited;
end;

procedure TIdWebSocketServer.DisconnectAll(const AReason: string);
var
  LList: TList;
  LContext: TIdServerWSContext;
  I: Integer;
  LHandler: IIOHandlerWebSocket;
begin
  LList := Self.Contexts.LockList;
  try
    for I := LList.Count - 1 downto 0 do
    begin
      LContext := TIdServerWSContext(LList[I]);
      Assert(LContext is TIdServerWSContext);
      LHandler := LContext.IOHandler;
      try
        if LHandler.IsWebSocket and not LContext.IsSocketIO then
          begin
            DisconnectWithReason(LHandler, AReason);
  //          LHandler.Close;
          end;
      except
        {$IF DEFINED(DEBUG_WS)}
        on E: Exception do
          WSDebugger.OutputDebugString('Disconnect All: '+E.Message);
        {$ENDIF}
      end;
    end;
  finally
    Self.Contexts.UnlockList;
  end;
end;

procedure TIdWebSocketServer.DisconnectWithReason(
  const AHandler: IIOHandlerWebSocket; const AReason: string;
  ANotifyPeer: Boolean);
begin
  InternalDisconnect(AHandler, ANotifyPeer, AReason);
end;

function TIdWebSocketServer.WebSocketCommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean;
var
  LHandler: IIOHandlerWebSocket;
  LServerContext: TIdServerWSContext absolute AContext;
begin
  LServerContext.OnWebSocketUpgrade := Self.WebSocketUpgradeRequest;
  LServerContext.OnCustomChannelExecute := Self.WebSocketChannelRequest;
  LServerContext.SocketIO               := FSocketIO;

  Result := True;
  try // try to see if server becomes non-responsive by removing the try-except
    LHandler := LServerContext.IOHandler;
    LHandler.OnNotifyClosed := procedure begin
      LHandler.ClosedGracefully := True;
    end;
    Result := TIdServerWebSocketHandling.ProcessServerCommandGet(
      AContext as TIdServerWSContext, FConnectionEvents,
      ARequestInfo, AResponseInfo);
    {$IF DEFINED(DEBUG_WS)}
    WSDebugger.OutputDebugString('Completed ProcessServerCommandGet');
    {$ENDIF}
  except
  // chuacw fix, CloseConnection when return????
    on E: Exception do
      begin
        {$IF DEFINED(DEBUG_WS)}
        WSDebugger.OutputDebugString('Exception in ProcessServerCommandGet: '+E.Message);
        {$ENDIF}
        SetIOHandler(nil);
      end;
  end;

end;

procedure TIdWebSocketServer.DoCommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  if not WebSocketCommandGet(AContext,ARequestInfo,AResponseInfo) then
    inherited DoCommandGet(AContext, ARequestInfo, AResponseInfo);
end;

function TIdWebSocketServer.GetSocketIO: TIdServerSocketIOHandling;
begin
  Result := FSocketIO;
end;

procedure TIdWebSocketServer.InternalDisconnect(
  const AHandler: IIOHandlerWebSocket; ANotifyPeer: Boolean;
  const AReason: string);
var
  LHandler: IIOHandlerWebSocket;
begin
  LHandler := AHandler;

// See if we can get the reason from the server by using the read thread

  if LHandler <> nil then
    begin
      if AReason = '' then
        LHandler.Close else
        LHandler.CloseWithReason(AReason);

      LHandler.Lock;
      try
        LHandler.IsWebSocket := False;

        LHandler.Clear;

      finally
        LHandler.Unlock;
      end;
    end;
end;

procedure TIdWebSocketServer.SendMessageToAll(const AText: string;
  const AExceptTarget: TIdServerWSContext=nil);
var
  LList: TList;
  LContext: TIdServerWSContext;
  I: Integer;
begin
  LList := Contexts.LockList;
  try
    for I := 0 to LList.Count - 1 do
      begin
        LContext := TIdServerWSContext(LList.Items[I]);
        Assert(LContext is TIdServerWSContext);
        if LContext = AExceptTarget then
          Continue; // skip sending to this target
        if LContext.IOHandler.IsWebSocket and not LContext.IsSocketIO then
          LContext.IOHandler.Write(AText);
      end;
  finally
    Self.Contexts.UnlockList;
  end;
end;

procedure TIdWebSocketServer.SetOnWebSocketClosing(
  const AValue: TOnWebSocketClosing);
var
  LList: TList;
  LContext: TIdServerWSContext;
  I: Integer;
  LHandler: IIOHandlerWebSocket;
  LSetWebSocketClosing: ISetWebSocketClosing;
begin
  FOnWebSocketClosing := AValue;

  LList := Contexts.LockList;
  try
    for I := LList.Count - 1 downto 0 do
    begin
      LContext := TIdServerWSContext(LList[I]);
      Assert(LContext is TIdServerWSContext);
      LHandler := LContext.IOHandler;
      if Supports(LHandler, ISetWebSocketClosing, LSetWebSocketClosing) then
        LSetWebSocketClosing.SetWebSocketClosing(AValue);
    end;
  finally
    Contexts.UnlockList;
  end;
end;

procedure TIdWebSocketServer.DoTerminateContext(AContext: TIdContext);
begin
  AContext.Binding.CloseSocket;
end;

procedure TIdWebSocketServer.SetWriteTimeout(const Value: Integer);
begin
  FWriteTimeout := Value;
end;

procedure TIdWebSocketServer.WebSocketUpgradeRequest(const AContext: TIdServerWSContext;
  const ARequestInfo: TIdHTTPRequestInfo; var Accept: Boolean);
begin
  Accept := True;
end;

procedure TIdWebSocketServer.WebSocketChannelRequest(
  const AContext: TIdServerWSContext; var aType: TWSDataType;
  const aStrmRequest, aStrmResponse: TMemoryStream);
var s: string;
begin
  if aType = wdtText then
  begin
    with TStreamReader.Create(aStrmRequest) do
    begin
      s := ReadToEnd;
      Free;
    end;
    if Assigned(OnMessageText) then
      OnMessageText(AContext, s, aStrmResponse)
  end
  else if Assigned(OnMessageBin) then
      OnMessageBin(AContext, aStrmRequest, aStrmResponse)
end;

procedure TIdWebSocketServer.SendMessageToAll(const aBinStream: TStream);
var
  LList: TList;
  LContext: TIdServerWSContext;
  I: Integer;
  bytes: TIdBytes;
begin
  LList := Contexts.LockList;
  try
    TIdStreamHelperVCL.ReadBytes(aBinStream, bytes);

    for I := 0 to LList.Count - 1 do
    begin
      LContext := TIdServerWSContext(LList.Items[I]);
      Assert(LContext is TIdServerWSContext);
      if LContext.IOHandler.IsWebSocket and not LContext.IsSocketIO then
        LContext.IOHandler.Write(bytes);
    end;
  finally
    Contexts.UnlockList;
  end;
end;

end.
