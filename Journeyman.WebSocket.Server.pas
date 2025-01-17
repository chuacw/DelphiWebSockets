unit Journeyman.WebSocket.Server;
interface

uses
  System.Classes, IdStreamVCL, IdGlobal, IdWinsock2, IdHTTPServer, IdContext,
  IdCustomHTTPServer,
{$IFDEF WEBSOCKETBRIDGE}
  IdHTTPWebBrokerBridge,
{$ENDIF}
  Journeyman.WebSocket.IOHandlers,
  Journeyman.WebSocket.Server.SSLIOHandlers,
  Journeyman.WebSocket.Server.Contexts,
  Journeyman.WebSocket.Server.IOHandlers,
  Journeyman.WebSocket.Types,
  Journeyman.WebSocket.Interfaces;

type

  {$IFDEF WEBSOCKETBRIDGE}
  TMyIdHttpWebBrokerBridge = class(TidHttpWebBrokerBridge)
  published
    property OnCreatePostStream;
    property OnDoneWithPostStream;
    property OnCommandGet;
  end;
  {$ENDIF}
  TWebSocketMessageText = procedure(const AContext: TIdServerWSContext;
    const aText: string; const AResponse: TStream)  of object;
  TWebSocketMessageBin  = procedure(const AContext: TIdServerWSContext;
    const aData: TStream; const AResponse: TStream) of object;

  {$IFDEF WEBSOCKETBRIDGE}
  TIdWebSocketServer = class(TMyIdHttpWebBrokerBridge)
  {$ELSE}
  TIdWebSocketServer = class(TIdHTTPServer)
  {$ENDIF}
  protected
    FOnMessageText: TWebSocketMessageText;
    FOnMessageBin: TWebSocketMessageBin;
    FOnWebSocketClosing: TOnWebSocketClosing;
    FWriteTimeout: Integer;
    FConnectionEvents: TWebSocketConnectionEvents;

    procedure SetWriteTimeout(const Value: Integer);
    function WebSocketCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean; virtual;
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
  type
    TOnSentMessage = reference to procedure(var VBytes: TIdBytes);
  protected
    procedure DoOnSentMessage(const AOnSentMessage: TOnSentMessage; var VBytes: TIdBytes);
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;

    procedure DisconnectAll(const AReason: string='');
    procedure DisconnectWithReason(const AHandler: IIOHandlerWebSocket;
      const AReason: string; ANotifyPeer: Boolean = True);
    procedure SendMessageToAll(const ABinStream: TStream; const AOnSentMessage: TOnSentMessage = nil); overload;
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

    property OnBeforeSendHeaders: TOnBeforeSendHeaders read FConnectionEvents.OnBeforeSendHeaders
      write FConnectionEvents.OnBeforeSendHeaders;
  published
    property WriteTimeout: Integer read FWriteTimeout write SetWriteTimeout default 2000;
  end;

implementation

uses
  System.SysUtils, Journeyman.WebSocket.DebugUtils, Journeyman.WebSocket.Client,
  Journeyman.WebSocket.Consts;

{ TIdWebSocketServer }

procedure TIdWebSocketServer.AfterConstruction;
begin
  inherited;

  ContextClass := TIdServerWSContext;
  if IOHandler = nil then
    IOHandler := TIdServerIOHandlerWebSocket.Create(Self);

  FWriteTimeout := 2 * 1000;  // 2s
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
//  if Assigned(FSocketIO) then
//    FSocketIO.FreeConnection(AContext);
  inherited;
end;

destructor TIdWebSocketServer.Destroy;
begin
  DisconnectAll('Server shutdown.');
//  FSocketIO.Free;
//  FSocketIO := nil;
  inherited;
end;

procedure TIdWebSocketServer.DisconnectAll(const AReason: string);
var
  LList: TList;
  LContext: TIdServerWSContext;
  I: Integer;
  LHandler: IIOHandlerWebSocket;
begin
  LList := Contexts.LockList;
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
            OutputDebugString('Disconnect All: '+E.Message);
        {$ENDIF}
      end;
    end;
  finally
    Contexts.UnlockList;
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
  LServerContext.OnWebSocketUpgrade := WebSocketUpgradeRequest;
  LServerContext.OnCustomChannelExecute := WebSocketChannelRequest;
//  LServerContext.SocketIO               := FSocketIO;
  LServerContext.ServerSoftware := ServerSoftware;

  Result := True;
  try // try to see if server becomes non-responsive by removing the try-except
    LHandler := LServerContext.IOHandler;
    LHandler.OnNotifyClosed := procedure begin
      LHandler.ClosedGracefully := True;
    end;
    Result := TIdServerWebSocketHandling.ProcessServerCommandGet(
      LServerContext, FConnectionEvents, ARequestInfo, AResponseInfo);

    {$IF DEFINED(DEBUG_WS)}
    OutputDebugString('Completed ProcessServerCommandGet');
    {$ENDIF}
  except
  // chuacw fix, CloseConnection when return????
    on E: Exception do
      begin
        {$IF DEFINED(DEBUG_WS)}
        OutputDebugString('Exception in ProcessServerCommandGet: '+E.Message);
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

//function TIdWebSocketServer.GetSocketIO: TIdServerSocketIOHandling;
//begin
//  Result := FSocketIO;
//end;

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
    Contexts.UnlockList;
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
var
  LData: string;
begin
  if aType = wdtText then
  begin
    with TStreamReader.Create(aStrmRequest) do
    begin
      LData := ReadToEnd;
      Free;
    end;
    if Assigned(OnMessageText) then
      OnMessageText(AContext, LData, AStrmResponse)
  end
  else if Assigned(OnMessageBin) then
      OnMessageBin(AContext, aStrmRequest, aStrmResponse)
end;

procedure TIdWebSocketServer.DoOnSentMessage(const AOnSentMessage: TOnSentMessage; var VBytes: TIdBytes);
begin
  if Assigned(AOnSentMessage) then
    AOnSentMessage(VBytes);
end;
procedure TIdWebSocketServer.SendMessageToAll(const ABinStream: TStream; const AOnSentMessage: TOnSentMessage = nil);
var
  LList: TList;
  LContext: TIdServerWSContext;
  I: Integer;
  LBytes: TIdBytes;
begin
  LList := Contexts.LockList;
  try
    TIdStreamHelperVCL.ReadBytes(ABinStream, LBytes);

    for I := 0 to LList.Count - 1 do
    begin
      LContext := TIdServerWSContext(LList.Items[I]);
      Assert(LContext is TIdServerWSContext);
      if LContext.IOHandler.IsWebSocket and not LContext.IsSocketIO then
        begin
          LContext.IOHandler.Write(LBytes);
          DoOnSentMessage(AOnSentMessage, LBytes);
        end;
    end;
  finally
    Contexts.UnlockList;
  end;
end;

end.
