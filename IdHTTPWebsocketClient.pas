unit IdHTTPWebSocketClient;
interface

uses
  System.Classes,
  IdHTTP,
  System.Types,
  IdHashSHA,                     // XE3 etc
  IdIOHandler,
  IdIOHandlerWebSocket,
  System.Net.Socket,
{$IF DEFINED(MSWINDOWS)}
  IdWinsock2,
{$ENDIF}
  System.Generics.Collections, System.SyncObjs, IdStack, IdSocketIOHandling,
  IdIIOHandlerWebSocket, System.SysUtils, IdWebSocketTypes, IdComponent,
  IdSSLOpenSSLHeaders, IdCTypes;

type
  TIdHTTPWebSocketClient = class;
  TWebSocketMsgBin  = reference to procedure(const AClient: TIdHTTPWebSocketClient;
    const AData: TStream);
  TWebSocketMsgText = reference to procedure(const AClient: TIdHTTPWebSocketClient;
    const AData: string);

  TSocketIOMsg = procedure(const AClient: TIdHTTPWebSocketClient;
    const aText: string; aMsgNr: Integer) of object;

  TIdSocketIOHandling_Ext = class(TIdSocketIOHandling)
  end;

  TIdHTTPWebSocketClient = class(TIdHTTP)
  private
    FPeerHost: string;
    FPeerPort: Word;
    FWSResourceName: string;
    FHash: TIdHashSHA1;
    FOnMessageBin: TWebSocketMsgBin;
    FOnMessageText: TWebSocketMsgText;
    FOnWebSocketClosing: TOnWebSocketClosing;
    FNoAsyncRead: Boolean;
    FWriteTimeout: Integer;

    /// <summary>Sets the write timeout. Call only when socket is connected. </summary>
    procedure InternalSetWriteTimeout(const AValue: Integer);

    function  GetIOHandlerWS: IIOHandlerWebSocket;
    procedure SetIOHandlerWS(const AValue: IIOHandlerWebSocket);
    procedure SetOnData(const AValue: TWebSocketMsgBin);
    procedure SetOnTextData(const AValue: TWebSocketMsgText);
    procedure SetOnWebSocketClosing(const AValue: TOnWebSocketClosing);
    procedure SetWriteTimeout(const AValue: Integer);
    procedure SetUseSSL(const AValue: Boolean);
  protected
    FCS: System.SyncObjs.TCriticalSection;
    FSocketIOCompatible: Boolean;
    FSocketIOHandshakeResponse: string;
    FSocketIO: TIdSocketIOHandling_Ext;
    FSocketIOContext: ISocketIOContext;
    FSocketIOConnectBusy: Boolean;
    FUseSSL: Boolean;
    /// <summary>Assign a TProc to FCustomHeadersProc in order to inject headers
    /// before sending a response to a web socket's initial setup request.</summary>
    FCustomHeadersProc: TProc;
    FRequestType: TIdWebSocketRequestType;

    // FHeartBeat: TTimer;
    // procedure HeartBeatTimer(Sender: TObject);
    function  GetSocketIO: TIdSocketIOHandling;
  protected
    /// <summary>Provides an opportunity for overriding custom headers if FCustomHeadersProc is
    /// assigned a value, by calling it.</summary>
    procedure DoCustomHeaders; virtual;
    procedure DoServerClosing(const AReason: string);
    function GetPeerHost: string;
    function GetPeerPort: Word;
    procedure InternalDisconnect(ANotifyPeer: Boolean; const AReason: string='');
    procedure InternalUpgradeToWebSocket(ARaiseException: Boolean;
      out AFailedReason: string); virtual;
    procedure InternalWrite(const AStream: TStream);
    function  MakeImplicitClientHandler: TIdIOHandler; override;
    procedure SSLStatus(ASender: TObject; const AStatus: TIdStatus;
     const AStatusText: string);
     procedure SSLStatusInfoEx(ASender : TObject; const AsslSocket: PSSL;
      const AWhere, Aret: TIdC_INT; const AType, AMsg : String );
  public
    procedure AsyncDispatchEvent(const AEvent: TStream); overload; virtual;
    procedure AsyncDispatchEvent(const AEvent: string); overload; virtual;
    procedure ResetChannel;
    /// <summary>Provides an opportunity for sending custom headers by adding a TProc
    /// which will be called before the initial WebSocket is setup.</summary>
    procedure AddCustomHeadersProc(const AProc: TProc);
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;

    function  TryUpgradeToWebSocket: Boolean;
    procedure UpgradeToWebSocket;

    function  TryLock: Boolean;
    procedure Lock;
    procedure Unlock;

    procedure CloseWebSocket(const AReason: string);
    procedure Connect; override;
    procedure ConnectAsync; virtual;
    procedure ConnectWebSocket(const AURL: string);
    function  TryConnect: Boolean;
    procedure Disconnect(ANotifyPeer: Boolean); override;
    procedure DisconnectWithReason(const AReason: string;
      ANotifyPeer: Boolean = True);

    function  CheckConnection: Boolean;
    procedure Ping;
    procedure ReadAndProcessData;

    procedure Post; overload;
    procedure Post(const AURL: string; AResponseContent: TStream; AIgnoreReplies: TArray<Int16>); overload;

    /// <summary>Write sends AMessage as a string to the target.</summary>
    /// <param name="AMessage">The UTF8 string to send to the target.</param>
    procedure Write(const AMessage: string); overload;
    /// <summary>Write sends the contents of AStream as binary to the target.</summary>
    /// <param name="AStream">The binary to send to the target</param>
    procedure Write(const AStream: TStream); overload;
    /// <summary>Write sends ABytes as a binary blob to the target.</summary>
    /// <param name="ABytes">The binary blob to send to the target</param>
    procedure Write(const ABytes: TArray<Byte>); overload;

    property  IOHandler: IIOHandlerWebSocket read GetIOHandlerWS write SetIOHandlerWS;

    // websockets
    property  OnMessageBin : TWebSocketMsgBin read FOnMessageBin write SetOnData;
    property  OnMessageText: TWebSocketMsgText read FOnMessageText write SetOnTextData;
    property  OnWebSocketClosing: TOnWebSocketClosing read FOnWebSocketClosing
      write SetOnWebSocketClosing;

    property  NoAsyncRead: Boolean read FNoAsyncRead write FNoAsyncRead;

    property  PeerHost: string read GetPeerHost;
    property  PeerPort: Word read GetPeerPort;

    // https://github.com/LearnBoost/socket.io-spec
    property  SocketIOCompatible: Boolean read FSocketIOCompatible write FSocketIOCompatible;
    property  SocketIO: TIdSocketIOHandling read GetSocketIO;
  published
    property  Host;
    property  Port;
    property  UseSSL: Boolean read FUseSSL write SetUseSSL;
    property  WSResourceName: string read FWSResourceName write FWSResourceName;

    property  WriteTimeout: Integer read FWriteTimeout write SetWriteTimeout default 2000;
  end;

implementation

uses
  IdCoderMIME, System.Math, IdException, IdStackConsts,
  IdStackBSDBase, IdGlobal,
{$IF DEFINED(MSWINDOWS)}
  Winapi.Windows,
{$ELSEIF DEFINED(POSIX)}
  Posix.SysSocket, Posix.Fcntl, FMX.Platform,
{$ENDIF}
  System.StrUtils, System.DateUtils,
  IdWebSocketConsts, IdURI, IdIOHandlerWebSocketSSL, IdIPAddress,
  WSDebugger, System.Diagnostics, WSMultiReadThread, IdSSLOpenSSL;

{ TIdHTTPWebSocketClient }

procedure TIdHTTPWebSocketClient.AddCustomHeadersProc(const AProc: TProc);
begin
  FCustomHeadersProc := AProc;
end;

procedure TIdHTTPWebSocketClient.AfterConstruction;
begin
  inherited;
  FCS := System.SyncObjs.TCriticalSection.Create;
  FHash := TIdHashSHA1.Create;

  var LHandler := MakeImplicitClientHandler as TIdIOHandlerWebSocketSSL;
  LHandler.UseNagle := False;
  IOHandler := LHandler;
  ManagedIOHandler := True;

  FSocketIO  := TIdSocketIOHandling_Ext.Create;
//  FHeartBeat := TTimer.Create(nil);
//  FHeartBeat.Enabled := False;
//  FHeartBeat.OnTimer := HeartBeatTimer;

  FWriteTimeout  := 2 * 1000;
  ConnectTimeout := 30000;
end;

procedure TIdHTTPWebSocketClient.AsyncDispatchEvent(const AEvent: TStream);
begin
  if not Assigned(OnMessageBin) then
    Exit;

  var LStreamEvent := TMemoryStream.Create;
  LStreamEvent.CopyFrom(aEvent, aEvent.Size);

  // events during dispatch? channel is busy so offload event dispatching to different thread!
  TIdWebSocketDispatchThread.Instance.QueueEvent(
    procedure
    begin
      if Assigned(OnMessageBin) then
        OnMessageBin(Self, LStreamEvent);
      LStreamEvent.Free;
    end);
end;

procedure TIdHTTPWebSocketClient.AsyncDispatchEvent(const AEvent: string);
begin
  {$IFDEF DEBUG_WS}
  if DebugHook <> 0 then
    OutputDebugString(PChar('AsyncDispatchEvent: ' + AEvent) );
  {$ENDIF}

  // if not Assigned(OnTextData) then Exit;
  // events during dispatch? channel is busy so offload event dispatching to different thread!
  TIdWebSocketDispatchThread.Instance.QueueEvent(
    procedure
    begin
      if FSocketIOCompatible then
        FSocketIO.ProcessSocketIORequest(FSocketIOContext as TSocketIOContext, AEvent)
      else if Assigned(OnMessageText) then
        OnMessageText(Self, AEvent);
    end);
end;

function TIdHTTPWebSocketClient.CheckConnection: Boolean;
begin
  Result := False;
  try
    if (IOHandler <> nil) and
       not IOHandler.ClosedGracefully and
      IOHandler.Connected then
    begin
      IOHandler.CheckForDisconnect(True{error}, True{ignore buffer, check real connection});
      Result := True;  // ok if we reach here
    end;
  except
    on E: Exception do
    begin
      // clear inputbuffer, otherwise it stays connected :(
//      if (IOHandler <> nil) then
//        IOHandler.Clear;
      Disconnect(False);
      if Assigned(OnDisconnected) then
        OnDisconnected(Self);
    end;
  end;
end;

procedure TIdHTTPWebSocketClient.CloseWebSocket(const AReason: string);
begin
  var LHandler := IOHandler;
  if LHandler <> nil then
    begin
      // chuacw fix, remove self from reading thread
      TIdWebSocketMultiReadThread.Instance.RemoveClient(Self);
      DisconnectWithReason(AReason);
    end;
end;

procedure TIdHTTPWebSocketClient.Connect;
begin
  Lock;
  try
    if Connected then
    begin
      TryUpgradeToWebSocket;
      Exit;
    end;

    if SocketIOCompatible and
       not FSocketIOConnectBusy then
    begin
      TryUpgradeToWebSocket;
    end
    else
    begin
      // clear inputbuffer, otherwise it can't connect :(
      if (IOHandler <> nil) then IOHandler.Clear;
      inherited Connect;
    end;
  finally
    Unlock;
  end;
end;

procedure TIdHTTPWebSocketClient.ConnectAsync;
begin
  TIdWebSocketMultiReadThread.Instance.AddClient(Self);
end;

procedure TIdHTTPWebSocketClient.ConnectWebSocket(const AURL: string);
var
  LUri: TIdURI;
  LNewSSL: Boolean;
  LNewHost: string;
  LNewPort: Word;
begin
  LUri := TIdURI.Create(AURL);
  try

    LNewSSL := SameText(LUri.Protocol, 'wss');
    LNewHost := LUri.Host;
    LNewPort := 0;

    if (LUri.Port = '') and LNewSSL then
      LNewPort := 443;
    if LNewPort = 0 then
      LNewPort := StrToIntDef(LUri.Port, 80);

    UseSSL := LNewSSL;
    Host   := LNewHost;
    Port   := LNewPort;

    UpgradeToWebSocket;
  finally
    LUri.Free;
  end;
end;

destructor TIdHTTPWebSocketClient.Destroy;
begin
  try
    TThread.Current.NameThreadForDebugging('Locking instance for removal ' + TThread.Current.ThreadID.ToString);
    Lock;
    try
      TThread.Current.NameThreadForDebugging('Locking instance for removal ' + TThread.Current.ThreadID.ToString);
      TIdWebSocketMultiReadThread.Instance.Lock;
      TIdWebSocketMultiReadThread.Instance.RemoveClient(Self);
      var LHandler := IOHandler;
      if Assigned(LHandler) then
        begin
          TThread.Current.NameThreadForDebugging('LHandler.Lock in WebSocketClient ' + TThread.Current.ThreadID.ToString);
          LHandler.Lock; // No need to unlock later, we're exiting...
          LHandler.CloseReason := 'Closing client';
        end;
    finally
      Unlock;
    end;
    FSocketIO.Free;
    FHash.Free;
    TThread.Current.NameThreadForDebugging('Calling inherited on WebSocketClient ' + TThread.Current.ThreadID.ToString);
    inherited; // This will send the required closes
    FCS.Free;
  finally
    TIdWebSocketMultiReadThread.Instance.Unlock;
  end;
end;

procedure TIdHTTPWebSocketClient.Disconnect(ANotifyPeer: Boolean);
begin
  if not SocketIOCompatible and
     ( (IOHandler <> nil) and not IOHandler.IsWebSocket)
  then
    TIdWebSocketMultiReadThread.Instance.RemoveClient(Self);

  if ANotifyPeer and SocketIOCompatible then
    FSocketIO.WriteDisconnect(FSocketIOContext as TSocketIOContext)
  else
    FSocketIO.FreeConnection(FSocketIOContext as TSocketIOContext);

//  IInterface(FSocketIOContext)._Release;
  FSocketIOContext := nil;

  Lock;
  try
    if IOHandler <> nil then
    begin
      IOHandler.Lock;
      try
        IOHandler.IsWebSocket := False;

        inherited Disconnect(ANotifyPeer);
        // clear buffer, other still "connected"
        IOHandler.Clear;

      finally
        IOHandler.Unlock;
      end;
    end;
  finally
    Unlock;
  end;
end;

procedure TIdHTTPWebSocketClient.DisconnectWithReason(const AReason: string;
  ANotifyPeer: Boolean);
begin
  InternalDisconnect(ANotifyPeer, AReason);
end;

procedure TIdHTTPWebSocketClient.DoCustomHeaders;
begin
  if Assigned(FCustomHeadersProc) then
    FCustomHeadersProc();
end;

procedure TIdHTTPWebSocketClient.DoServerClosing(const AReason: string);
begin
  if not NoAsyncRead then
    TIdWebSocketMultiReadThread.Instance.RemoveClient(Self);
  if Assigned(FOnWebSocketClosing) then
    FOnWebSocketClosing(AReason);
end;

function TIdHTTPWebSocketClient.GetIOHandlerWS: IIOHandlerWebSocket;
begin
//  if inherited IOHandler is TIdIOHandlerWebSocket then
    Result := (inherited IOHandler) as IIOHandlerWebSocket
//  else
//    Assert(False);
end;

function TIdHTTPWebSocketClient.GetPeerHost: string;
var
  LHandler: TIdIOHandlerWebSocketSSL;
begin
  LHandler := IOHandler as TIdIOHandlerWebSocketSSL;
  if Assigned(LHandler) and LHandler.BindingAllocated then
    Result := FPeerHost else
    Result := '';
end;

function TIdHTTPWebSocketClient.GetPeerPort: Word;
var
  LHandler: TIdIOHandlerWebSocketSSL;
begin
  LHandler := IOHandler as TIdIOHandlerWebSocketSSL;
  if Assigned(LHandler) and LHandler.BindingAllocated then
    Result := FPeerPort else
    Result := 0;
end;

function TIdHTTPWebSocketClient.GetSocketIO: TIdSocketIOHandling;
begin
  Result := FSocketIO;
end;

function TIdHTTPWebSocketClient.TryConnect: Boolean;
begin
  Lock;
  try
    try
      if Connected then
        Exit(True);

      Connect;
      Result := Connected;
    except
      Result := False;
    end
  finally
    Unlock;
  end;
end;

function TIdHTTPWebSocketClient.TryLock: Boolean;
begin
//  Result := System.TMonitor.TryEnter(Self);
  Result := FCS.TryEnter;
end;

function TIdHTTPWebSocketClient.TryUpgradeToWebSocket: Boolean;
var
  sError: string;
begin
  try
    FSocketIOConnectBusy := True;
    Lock;
    try
      if (IOHandler <> nil) and IOHandler.IsWebSocket then
        Exit(True);

      InternalUpgradeToWebSocket(False{no raise}, sError);
      Result := (sError = '');
    finally
      FSocketIOConnectBusy := False;
      Unlock;
    end;
  except
    Result := False;
  end;
end;

procedure TIdHTTPWebSocketClient.Unlock;
begin
  FCS.Leave;
//  System.TMonitor.Exit(Self);
end;

procedure TIdHTTPWebSocketClient.UpgradeToWebSocket;
var
  sError: string;
begin
  Lock;
  try
    if IOHandler = nil then
      Connect
    else if not IOHandler.IsWebSocket then
      InternalUpgradeToWebSocket(True{raise}, sError);
  finally
    Unlock;
  end;
end;

procedure TIdHTTPWebSocketClient.Write(const AMessage: string);
begin
  var LHandler := IOHandler;
  if LHandler.Connected then
    begin
      LHandler.Write(AMessage);
    end;
end;

procedure TIdHTTPWebSocketClient.Write(const AStream: TStream);
begin
  var LHandler := IOHandler;
  if LHandler.Connected then
    begin
      InternalWrite(AStream);
    end;
end;

procedure TIdHTTPWebSocketClient.Write(const ABytes: TArray<Byte>);
begin
  var LHandler := IOHandler;
  if LHandler.Connected then
    begin
      LHandler.WriteBin(ABytes);
    end;
end;

procedure TIdHTTPWebSocketClient.InternalDisconnect(ANotifyPeer: Boolean;
  const AReason: string);
begin
  var LHandler := IOHandler;

// See if we can get the reason from the server by using the read thread
//  if (not NoAsyncRead) or (not SocketIOCompatible and
//      ((LHandler <> nil) and not LHandler.IsWebSocket)) then
//    TIdWebSocketMultiReadThread.Instance.RemoveClient(Self);

  if LHandler <> nil then
    begin
      LHandler.Lock;
      try
        if AReason = '' then
          LHandler.Close else
          LHandler.CloseWithReason(AReason);
      finally
        LHandler.Unlock;
      end;
    end;

  if ANotifyPeer and SocketIOCompatible then
    FSocketIO.WriteDisconnect(FSocketIOContext as TSocketIOContext)
  else
    FSocketIO.FreeConnection(FSocketIOContext as TSocketIOContext);

//  IInterface(FSocketIOContext)._Release;
  FSocketIOContext := nil;

  Lock;
  try
    if LHandler <> nil then
    begin
      LHandler.Lock;
      try
        LHandler.IsWebSocket := False;

        inherited Disconnect(ANotifyPeer);
        // clear buffer, others still "connected"
        LHandler.Clear;

      finally
        LHandler.Unlock;
      end;
    end;
  finally
    Unlock;
  end;
end;

procedure TIdHTTPWebSocketClient.InternalUpgradeToWebSocket(
  ARaiseException: Boolean; out AFailedReason: string);

  function GenerateWebSocketKey: string;
  var
    I: Integer;
  begin
    Result := '';
    for I := 1 to 16 do
      Result := Result + Char(Random(127-32) + 32);
  end;

var
  LURL: string;
  strmResponse: TMemoryStream;
  LKey, LResponseKey, LUserAgent, LWSResourceName: string;
  LSocketioExtended: string;
  LLocked: boolean;
  LHandler: IIOHandlerWebSocket;
begin
  Assert((IOHandler = nil) or not IOHandler.IsWebSocket);
  // remove from thread during connection handling
  TIdWebSocketMultiReadThread.Instance.RemoveClient(Self);

  LLocked := False;
  strmResponse := TMemoryStream.Create;
  Lock;
  try
    // reset pending data
    LHandler := IOHandler;
    if LHandler <> nil then
    begin
      LHandler.Lock;
      LLocked := True;
      if LHandler.IsWebSocket then
        Exit;
      LHandler.Clear;
    end;

    // special socket.io handling, see https://github.com/LearnBoost/socket.io-spec
    if SocketIOCompatible then
    begin
      Request.Clear;
      Request.Connection := 'keep-alive';
      LURL := Format('http%s://%s:%d/socket.io/1/', [IfThen(UseSSL, 's', ''), Host, Port]);
      strmResponse.Clear;

      ReadTimeout := 5 * 1000;
      // get initial handshake
      Post(LURL, strmResponse, strmResponse);
      if ResponseCode = 200 {OK} then
      begin
        // if not Connected then  //reconnect
        //  Self.Connect;
        strmResponse.Position := 0;
        // The body of the response should contain the session id (sid) given to the client,
        // followed by the heartbeat timeout, the connection closing timeout, and the list of supported transports separated by :
        // 4d4f185e96a7b:15:10:websocket,xhr-polling
        with TStreamReader.Create(strmResponse) do
        try
          FSocketIOHandshakeResponse := ReadToEnd;
        finally
          Free;
        end;
        LKey := Copy(FSocketIOHandshakeResponse, 1, Pos(':', FSocketIOHandshakeResponse)-1);
        LSocketioExtended := 'socket.io/1/websocket/' + LKey;
        WSResourceName := LSocketioExtended;
      end else
      begin
        AFailedReason := Format('Initial socket.io handshake failed: "%d: %s"',[ResponseCode, ResponseText]);
        if ARaiseException then
          raise EIdWebSocketHandleError.Create(AFailedReason);
      end;
    end;

    LUserAgent := Request.UserAgent;
    Request.Clear;
    Request.UserAgent := LUserAgent;
    Request.CustomHeaders.Clear;
    strmResponse.Clear;
    // http://www.websocket.org/aboutwebsocket.html
    (* GET ws://echo.websocket.org/?encoding=text HTTP/1.1
     Origin: http://websocket.org
     Cookie: __utma=99as
     Connection: Upgrade
     Host: echo.websocket.org
     Sec-WebSocket-Key: uRovscZjNol/umbTt5uKmw==
     Upgrade: websocket
     Sec-WebSocket-Version: 13 *)

    // Connection: Upgrade
    Request.CustomHeaders.AddValue(SConnection, SUpgrade);
    // Upgrade: websocket
    Request.CustomHeaders.AddValue(SUpgrade, SWebSocket);

    // Sec-WebSocket-Key
    LKey := GenerateWebSocketKey;

    // base64 encoded
    LKey := TIdEncoderMIME.EncodeString(LKey);
    Request.CustomHeaders.AddValue(SWebSocketKey, LKey);
    // Sec-WebSocket-Version: 13
    Request.CustomHeaders.AddValue(SWebSocketVersion, '13');

    FPeerHost := Host;
    FPeerPort := Port;
    Request.CacheControl := SNoCache;
    Request.Pragma := SNoCache;
    Request.Host := Format('Host: %s:%d', [Host, Port]);
    Request.CustomHeaders.AddValue(SHTTPOriginHeader,
      Format('http%s://%s:%d', [IfThen(UseSSL, 's', ''), Host, Port]));
    DoCustomHeaders;

    // ws://host:port/<resourcename>
    // about resourcename, see: http://dev.w3.org/html5/websockets/ "Parsing WebSocket URLs"
    // sURL := Format('ws://%s:%d/%s', [Host, Port, WSResourceName]);
    if WSResourceName.StartsWith('/') then
      LWSResourceName := WSResourceName.Substring(1) else
      LWSResourceName := WSResourceName;
    LURL := Format('http%s://%s:%d/%s', [IfThen(UseSSL, 's', ''), Host, Port, LWSResourceName]);
    ReadTimeout := Max(5 * 1000, ReadTimeout);

    { voorbeeld:
    GET http://localhost:9222/devtools/page/642D7227-148E-47C2-B97A-E00850E3AFA3 HTTP/1.1
    Upgrade: websocket
    Connection: Upgrade
    Host: localhost:9222
    Origin: http://localhost:9222
    Pragma: no-cache
    Cache-Control: no-cache
    Sec-WebSocket-Key: HIqoAdZkxnWWH9dnVPyW7w==
    Sec-WebSocket-Version: 13
    Sec-WebSocket-Extensions: x-webkit-deflate-frame
    User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/27.0.1453.116 Safari/537.36
    Cookie: __utma=1.2040118404.1366961318.1366961318.1366961318.1; __utmc=1; __utmz=1.1366961318.1.1.utmcsr=(direct)|utmccn=(direct)|utmcmd=(none); deviceorder=0123456789101112; MultiTouchEnabled=false; device=3; network_type=0
    }
    if SocketIOCompatible then
    begin
      // 1st, try to do socketio specific connection
      Response.Clear;
      Response.ResponseCode := 0;
      Request.URL    := LURL;
      Request.Method := Id_HTTPMethodGet;
      Request.Source := nil;
      Response.ContentStream := strmResponse;
      PrepareRequest(Request);

      // connect and upgrade
      ConnectToHost(Request, Response);

      // check upgrade succesful
      CheckForGracefulDisconnect(True);
      CheckConnected;
      Assert(Connected);

      if Response.ResponseCode = 0 then
        Response.ResponseText := Response.ResponseText else
      if Response.ResponseCode <> 200{ok} then
      begin
        AFailedReason := Format('Error while upgrading: "%d: %s"',[ResponseCode, ResponseText]);
        if ARaiseException then
          raise EIdWebSocketHandleError.Create(AFailedReason)
        else
          Exit;
      end;

      // 2nd, get websocket response
      Response.Clear;
      if LHandler.CheckForDataOnSource(ReadTimeout) then
      begin
        FHTTPProto.RetrieveHeaders(MaxHeaderLines);
        // Response.RawHeaders.Text := IOHandler.InputBufferAsString();
        Response.ResponseText := Response.RawHeaders.Text;
      end;
    end else
    begin
      case FRequestType of
        wsrtGet: Get(LURL, strmResponse, [101]);
        wsrtPost: begin
            Post(LURL, strmResponse, [101]);
        end;
      end;
    end;

    // http://www.websocket.org/aboutwebsocket.html
    (* HTTP/1.1 101 WebSocket Protocol Handshake
       Date: Fri, 10 Feb 2012 17:38:18 GMT
       Connection: Upgrade
       Server: Kaazing Gateway
       Upgrade: WebSocket
       Access-Control-Allow-Origin: http://websocket.org
       Access-Control-Allow-Credentials: true
       Sec-WebSocket-Accept: rLHCkw/SKsO9GAH/ZSFhBATDKrU=
       Access-Control-Allow-Headers: content-type *)

    // 'HTTP/1.1 101 Switching Protocols'
    if Response.ResponseCode <>  CSwitchingProtocols then
    begin
      AFailedReason := Format('Error while upgrading: "%d: %s"',[Response.ResponseCode, Response.ResponseText]);
      if ARaiseException then
        raise EIdWebSocketHandleError.Create(AFailedReason)
      else
        Exit;
    end;
    // connection: upgrade
    if not SameText(Response.Connection, SUpgrade) then
    begin
      AFailedReason := Format('Connection not upgraded: "%s"',[Response.Connection]);
      if ARaiseException then
        raise EIdWebSocketHandleError.Create(AFailedReason)
      else
        Exit;
    end;
    // upgrade: websocket
    if not SameText(Response.RawHeaders.Values[SUpgrade], SWebSocket) then
    begin
      AFailedReason := Format('Not upgraded to websocket: "%s"', [Response.RawHeaders.Values[SUpgrade]]);
      if ARaiseException then
        raise EIdWebSocketHandleError.Create(AFailedReason)
      else
        Exit;
    end;
    // check handshake key
    LResponseKey := Trim(LKey) +     // ... "minus any leading and trailing whitespace"
                    SWebSocketGUID;  // special GUID
    LResponseKey := TIdEncoderMIME.EncodeBytes(                          // Base64
                         FHash.HashString(LResponseKey) );               // SHA1
    if not SameText(Response.RawHeaders.Values[SWebSocketAccept], LResponseKey) then
    begin
      AFailedReason := 'Invalid key handshake';
      if ARaiseException then
        raise EIdWebSocketHandleError.Create(AFailedReason)
      else
        Exit;
    end;

    // upgrade succesful
    LHandler.IsWebSocket := True;
    AFailedReason := '';
    Assert(Connected);

    if SocketIOCompatible then
    begin
      FSocketIOContext := TSocketIOContext.Create(Self);
      (FSocketIOContext as TSocketIOContext).ConnectSend := True;  // connect already send via url? GET /socket.io/1/websocket/9elrbEFqiimV29QAM6T-
      FSocketIO.WriteConnect(FSocketIOContext as TSocketIOContext);
    end;

    // always read the data! (e.g. RO use override of AsyncDispatchEvent to process data)
    // if Assigned(OnBinData) or Assigned(OnTextData) then
  finally
    Request.Clear;
    Request.CustomHeaders.Clear;
    strmResponse.Free;

    if LLocked and (LHandler <> nil) then
      LHandler.Unlock;
    Unlock;

  end;

  // default 2s write timeout
  // http://msdn.microsoft.com/en-us/library/windows/desktop/ms740532(v=vs.85).aspx
  if Connected then
    begin
      // chuacw fix, add to thread after successful connection
      if not NoAsyncRead then
        TIdWebSocketMultiReadThread.Instance.AddClient(Self);

{$IF DEFINED(MSWINDOWS)}
      try
        InternalSetWriteTimeout(WriteTimeout);
      except
        {$IF DEFINED(DEBUG_WS)}
        on E: Exception do
          WSDebugger.OutputDebugString('WriteTimeout not supported? error: ' + E.Message);
        {$ENDIF}
      end;
{$ELSEIF DEFINED(ANDROID)}
//      setting timeout may not be supported on some platforms
//      Timeout not supported on Android
      try
        InternalSetWriteTimeout(WriteTimeout);
      except
        {$IF DEFINED(DEBUG_WS)}
        on E: Exception do
          begin
            var LLine := Format('WriteTimeout not supported. Type: %s, error: %s',
              [E.ClassName, E.Message]);
            WSDebugger.OutputDebugString(LLine);
          end;
        {$ENDIF}
      end;
{$ELSE}
      try
        InternalSetWriteTimeout(WriteTimeout);
      except
        {$IF DEFINED(DEBUG_WS)}
        on E: Exception do
          begin
            var LLine := Format('WriteTimeout not supported. Type: %s, error: %s',
              [E.ClassName, E.Message]);
            WSDebugger.OutputDebugString(LLine);
          end;
        {$ENDIF}
      end;
{$ENDIF}
    end;
end;

procedure TIdHTTPWebSocketClient.InternalWrite(const AStream: TStream);
begin
  var LHandler := IOHandler;
  AStream.Position := 0;
  LHandler.Write(AStream, wdtBinary);
end;

procedure TIdHTTPWebSocketClient.Lock;
begin
  FCS.Enter;
//  System.TMonitor.Enter(Self);
end;

procedure TIdHTTPWebSocketClient.SSLStatus(ASender: TObject;
  const AStatus: TIdStatus; const AStatusText: string);
begin
{$IF DEFINED(DEBUG_WS)}
  WSDebugger.OutputDebugString('SSL', AStatusText);
{$ENDIF}
end;

procedure TIdHTTPWebSocketClient.SSLStatusInfoEx(ASender : TObject; const AsslSocket: PSSL;
    const AWhere, Aret: TIdC_INT; const AType, AMsg : String );
begin
{$IF DEFINED(DEBUG_WS)}
  var LLine := Format('AType: %s, AMsg: %s', [AType, AMsg]);
  WSDebugger.OutputDebugString('SSL', LLine);
{$ENDIF}
end;

function TIdHTTPWebSocketClient.MakeImplicitClientHandler: TIdIOHandler;
var
  LSSLHandler: TIdIOHandlerWebSocketSSL;
begin
  LSSLHandler := TIdIOHandlerWebSocketSSL.Create(Self);
  LSSLHandler.OnWebSocketClosing := FOnWebSocketClosing;
  LSSLHandler.RoleName := 'Client';
  LSSLHandler.PassThrough := not UseSSL;
  LSSLHandler.UseNagle := False;
  LSSLHandler.OnStatus := SSLStatus;
  LSSLHandler.OnStatusInfoEx := SSLStatusInfoEx;
  LSSLHandler.SSLOptions.Method := sslvSSLv23;
  LSSLHandler.SSLOptions.Mode := sslmClient;
  Result := LSSLHandler;
end;

procedure TIdHTTPWebSocketClient.Ping;
var
  ws: IIOHandlerWebSocket;
begin
  if TryLock then
  try
    ws  := IOHandler as IIOHandlerWebSocket;
    ws.LastPingTime := Now;

    // socket.io?
    if SocketIOCompatible and ws.IsWebSocket then
    begin
      FSocketIO.Lock;
      try
        if (FSocketIOContext <> nil) then
          FSocketIO.WritePing(FSocketIOContext as TSocketIOContext);  //heartbeat socket.io message
      finally
        FSocketIO.Unlock;
      end
    end
    // only websocket?
    else if not SocketIOCompatible and ws.IsWebSocket then
    begin
      if ws.TryLock then
      try
        ws.WriteData(nil, wdcPing);
      finally
        ws.Unlock;
      end;
    end;
  finally
    Unlock;
  end;
end;

procedure TIdHTTPWebSocketClient.ReadAndProcessData;
var
  LStreamEvent: TMemoryStream;
  LWSText: UTF8String;
  LWSCode: TWSDataCode;
begin
{$IF DEFINED(DEBUG_WS)}
  WSDebugger.OutputDebugString('WSChat', 'Entering ReadAndProcessData');
{$ENDIF}
  LStreamEvent := nil;
  var LHandler := IOHandler;
  LHandler.Lock;
  try
    // try to process all events
    while LHandler.HasData or (LHandler.Connected and LHandler.Readable(0)) do
    begin      // has some data
      if LStreamEvent = nil then
        LStreamEvent := TMemoryStream.Create;
      LStreamEvent.Clear;

      // first is the data type TWSDataType(text or bin), but is ignore/not needed
      LWSCode := TWSDataCode(IOHandler.ReadLongWord);
      if not (LWSCode in [wdcText, wdcBinary, wdcPing, wdcPong]) then
      begin
        // Sleep(0);
        Continue;
      end;

      // next the size + data = stream
      LHandler.ReadStream(LStreamEvent);

      // ignore ping/pong messages
      if LWSCode in [wdcPing, wdcPong] then
        Continue;

      // fire event
      // offload event dispatching to different thread! otherwise deadlocks possible? (do to synchronize)
      LStreamEvent.Position := 0;
      case LWSCode of
        wdcBinary:
          begin
            AsyncDispatchEvent(LStreamEvent);
          end;
        wdcText:
          begin
            SetLength(LWSText, LStreamEvent.Size);
            // Cross-platform indexing
            LStreamEvent.Read(LWSText[Low(LWSText)], LStreamEvent.Size);
            if LWSText <> '' then
              begin
                AsyncDispatchEvent(string(LWSText));
              end;
            {$IF DEFINED(DEBUG_WS)}
            WSDebugger.OutputDebugString('WSChat', 'Leaving wdcText');
            {$ENDIF}
          end;
      end;
    end;
  finally
    LHandler.Unlock;
    LStreamEvent.Free;
    {$IF DEFINED(DEBUG_WS)}
    WSDebugger.OutputDebugString('WSChat', 'Leaving ReadAndProcessData');
    {$ENDIF}
  end;
end;

procedure TIdHTTPWebSocketClient.ResetChannel;
begin
//  TIdWebSocketMultiReadThread.Instance.RemoveClient(Self); keep for reconnect
  var LHandler := IOHandler;
  if LHandler <> nil then
    begin
      LHandler.InputBuffer.Clear;
      LHandler.BusyUpgrading := False;
      LHandler.IsWebSocket   := False;
      // close/disconnect internal socket
      // ws := IndyClient.IOHandler as TIdIOHandlerWebSocket;
      // ws.Close;  done in disconnect below
    end;
  Disconnect(False);
end;

procedure TIdHTTPWebSocketClient.SetIOHandlerWS(
  const AValue: IIOHandlerWebSocket);
begin
  SetIOHandler(AValue as TIdIOHandler);
end;

procedure TIdHTTPWebSocketClient.SetOnData(const AValue: TWebSocketMsgBin);
begin
//  if not Assigned(Value) and not Assigned(FOnTextData) then
//    TIdWebSocketMultiReadThread.Instance.RemoveClient(Self);

  FOnMessageBin := AValue;

//  if Assigned(Value) and
//     (Self.IOHandler as TIdIOHandlerWebSocket).IsWebSocket
//  then
//    TIdWebSocketMultiReadThread.Instance.AddClient(Self);
end;

procedure TIdHTTPWebSocketClient.SetOnTextData(const AValue: TWebSocketMsgText);
begin
//  if not Assigned(Value) and not Assigned(FOnData) then
//    TIdWebSocketMultiReadThread.Instance.RemoveClient(Self);

  FOnMessageText := AValue;

//  if Assigned(Value) and
//     (Self.IOHandler as TIdIOHandlerWebSocket).IsWebSocket
//  then
//    TIdWebSocketMultiReadThread.Instance.AddClient(Self);
end;

procedure TIdHTTPWebSocketClient.SetOnWebSocketClosing(
  const AValue: TOnWebSocketClosing);
var
  LSetWebSocketClosing: ISetWebSocketClosing;
begin
  FOnWebSocketClosing := AValue;
  if Supports(IOHandler, ISetWebSocketClosing, LSetWebSocketClosing) then
    LSetWebSocketClosing.SetWebSocketClosing(DoServerClosing);
end;

procedure TIdHTTPWebSocketClient.SetUseSSL(const AValue: Boolean);
begin
  if FUseSSL <> AValue then
    begin
      FUseSSL := AValue;
      IOHandler := MakeImplicitClientHandler as IIOHandlerWebSocket;
    end;
end;

procedure TIdHTTPWebSocketClient.InternalSetWriteTimeout(const AValue: Integer);
begin
  var LHandler := IOHandler;
  LHandler.Binding.SetSockOpt(Id_SOL_SOCKET, Id_SO_SNDTIMEO, AValue);
end;

procedure TIdHTTPWebSocketClient.SetWriteTimeout(const AValue: Integer);
begin
  FWriteTimeout := AValue;
  if Connected then
    begin
      try
        InternalSetWriteTimeout(AValue);
      except // fails on Linux
      end;
    end;
end;

procedure TIdHTTPWebSocketClient.Post(const AURL: string;
  AResponseContent: TStream; AIgnoreReplies: TArray<Int16>);
var
  OldProtocol: TIdHTTPProtocolVersion;
begin
  // PLEASE READ CAREFULLY

  // Currently when issuing a POST, IdHTTP will automatically set the protocol
  // to version 1.0 independently of the value it had initially. This is because
  // there are some servers that don't respect the RFC to the full extent. In
  // particular, they don't respect sending/not sending the Expect: 100-Continue
  // header. Until we find an optimum solution that does NOT break the RFC, we
  // will restrict POSTS to version 1.0.
  OldProtocol := FProtocolVersion;
  try
    // If hoKeepOrigProtocol is SET, is possible to assume that the developer
    // is sure in operations of the server
    if not (hoKeepOrigProtocol in FOptions) then begin
      if Connected then begin
        Disconnect;
      end;
      FProtocolVersion := pv1_0;
    end;
    DoRequest(Id_HTTPMethodPost, AURL, nil, AResponseContent, AIgnoreReplies);
  finally
    FProtocolVersion := OldProtocol;
  end;
end;

procedure TIdHTTPWebSocketClient.Post;
var
  MS: TMemoryStream;
begin
  MS := TMemoryStream.Create;
  try
    inherited Post(WSResourceName, MS);
  finally
    MS.Free;
  end;
end;

end.
