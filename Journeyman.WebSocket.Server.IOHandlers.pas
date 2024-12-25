unit Journeyman.WebSocket.Server.IOHandlers;
interface

uses
  System.Classes, System.StrUtils, System.SysUtils, System.DateUtils,
  IdCoderMIME, IdThread, IdContext, IdCustomHTTPServer,
  {$IF CompilerVersion <= 21.0}  // D2010
  IdHashSHA1,
  {$ELSE}
  IdHashSHA,                     // XE3 etc
  {$ENDIF}
  IdServerIOHandlerSocket,
  Journeyman.WebSocket.Server.Contexts,
  Journeyman.WebSocket.IOHandlers,
  Journeyman.WebSocket.Types,
  Journeyman.WebSocket.Interfaces,
  IdServerIOHandlerStack, IdIOHandlerStack, IdGlobal,
  IdIOHandler, IdYarn, IdSocketHandle;

type
//  TIdServerSocketIOHandling_Ext = class(TIdServerSocketIOHandling)
//  end;

  TIdServerWebSocketHandling = class(TIdServerBaseHandling)
  protected
    class var FExitConnectedCheck: Boolean;
    class var FSupportsPerMessageDeflate: Boolean;
    FMaxWindowBits: Integer;
    class procedure DoWSExecute(AThread: TIdContext); virtual;
    class procedure HandleWSMessage(AContext: TIdServerWSContext;
      var AWSType: TWSDataType; ARequestStream, AResponseStream: TMemoryStream); virtual;
    class procedure DoPingReceived(const ANow, ALastPingReceived: TDateTime); static;
    class procedure DoPongReceived(const ANow, ALastPongReceived: TDateTime); static;
    class procedure SetMaxWindowBits(const Value: Integer); static;
    class procedure SetSupportsPerMessageDeflate(const Value: Boolean); static;
  public
  type
    TOnPingReceived = reference to procedure(const ANow, ALastPingReceived: TDateTime);
    TOnPongReceived = reference to procedure(const ANow, ALastPongReceived: TDateTime);
  class var
    FOnPingReceived: TOnPingReceived;
    FOnPongReceived: TOnPongReceived;
    FPingInterval: Integer;
  public
    class constructor Create;
    class destructor Destroy;
    class function ProcessServerCommandGet(AThread: TIdServerWSContext;
      const AConnectionEvents: TWebSocketConnectionEvents;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean; static;

//    class function CurrentSocket: ISocketIOContext;
    class property ExitConnectedCheck: Boolean read FExitConnectedCheck
      write FExitConnectedCheck;
    class property OnPingReceived: TOnPingReceived read FOnPingReceived write FOnPingReceived;
    class property OnPongReceived: TOnPongReceived read FOnPongReceived write FOnPongReceived;
    class property PingInterval: Integer read FPingInterval write FPingInterval;
    class property SupportsPerMessageDeflate: Boolean read FSupportsPerMessageDeflate write SetSupportsPerMessageDeflate;
    class property MaxWindowBits: Integer read FMaxWindowBits write SetMaxWindowBits;
  end;

  TIdServerIOHandlerStack = class(TIdServerIOHandlerSocket)
  protected
    procedure InitComponent; override;
  public
    function MakeClientIOHandler(ATheThread:TIdYarn ): TIdIOHandler; override;
  end;
  TIdServerIOHandlerWebSocket = class(TIdServerIOHandlerStack, ISetWebSocketClosing)
  protected
    FOnWebSocketClosing: TOnWebSocketClosing;
    procedure InitComponent; override;
    procedure SetWebSocketClosing(const AValue: TOnWebSocketClosing);
  public
    function Accept(ASocket: TIdSocketHandle; AListenerThread: TIdThread;
      AYarn: TIdYarn): TIdIOHandler; override;
    function MakeClientIOHandler(ATheThread:TIdYarn): TIdIOHandler; override;
  end;
implementation

uses
  System.Math, // Min(x, y)... Max(x, y)
  Journeyman.WebSocket.ArrayUtils,
  Journeyman.WebSocket.Consts,
  Journeyman.WebSocket.DebugUtils,
  Journeyman.WebSocket.CompressUtils;

{ TIdServerWebSocketHandling }

class constructor TIdServerWebSocketHandling.Create;
begin
  FPingInterval := 5;
  FMaxWindowBits := TServerMaxWindowBits.MinValue;
  FSupportsPerMessageDeflate := True;
end;
//var
class destructor TIdServerWebSocketHandling.Destroy;
begin
  FOnPingReceived := nil;
  FOnPongReceived := nil;
end;
class procedure TIdServerWebSocketHandling.DoPingReceived(const ANow, ALastPingReceived: TDateTime);
begin
  if Assigned(FOnPingReceived) then
    FOnPingReceived(ANow, ALastPingReceived);
end;
//  if not (LThread.Task is TIdServerWSContext) then
class procedure TIdServerWebSocketHandling.DoPongReceived(const ANow, ALastPongReceived: TDateTime);
begin
  if Assigned(FOnPongReceived) then
    FOnPongReceived(ANow, ALastPongReceived);
end;

class procedure TIdServerWebSocketHandling.DoWSExecute(AThread: TIdContext);
var
  LStreamRequest, LStreamResponse: TMemoryStream;
  LWSCode: TWSDataCode;
  LWSType: TWSDataType;
  LContext: TIdServerWSContext;
  LLastPingReceived, LLastPingSent, LLastPongReceived, LLastPongSent: TDateTime;
  LHandler: IIOHandlerWebSocket;
begin
  LContext   := nil;
  try
    LContext := AThread as TIdServerWSContext;
    LHandler := LContext.IOHandler;
    // todo: make separate function + do it after first real write (not header!)
    if LHandler.BusyUpgrading then
    begin
      LHandler.IsWebSocket   := True;
      LHandler.BusyUpgrading := False;
    end;
    // initial connect
//    if LContext.IsSocketIO then
//    begin
//      Assert(ASocketIOHandler <> nil);
//      ASocketIOHandler.WriteConnect(LContext);
//    end;
    AThread.Connection.Socket.UseNagle := False;  // no 200ms delay!

    LLastPingSent := 0;
    LLastPongSent := 0;
    LLastPingReceived := 0;
    LLastPongReceived := 0;

    while LHandler.Connected and not LHandler.ClosedGracefully do
    begin
      if LHandler.HasData or
        (LHandler.InputBuffer.Size > 0) or
         LHandler.Readable(1 * 1000) then     // wait 5s, else ping the client(!)
      begin

        LStreamResponse := TMemoryStream.Create;
        LStreamRequest  := TMemoryStream.Create;
        try

          LStreamRequest.Position := 0;
          // first is the type: text or bin
          LWSCode := TWSDataCode(LHandler.ReadUInt32);
          // then the length + data = stream
          LHandler.ReadStream(LStreamRequest);
          LStreamRequest.Position := 0;

          if LWSCode = wdcClose then
            begin
              {$IF DEFINED(DEBUG_WS)}
              OutputDebugString('Closing server session');
              {$ENDIF}
              Break;
            end;

          // ignore ping/pong messages
          if LWSCode in [wdcPing, wdcPong] then
          begin
            case LWSCode of
              wdcPing: begin
                DoPingReceived(Now, LLastPingReceived);
                LLastPingReceived := Now;
                if SecondsBetween(Now, LLastPongSent) > FPingInterval then
                  begin
                    LHandler.WriteData(nil, wdcPong);
                    LLastPongSent := Now;
                  end;
              end;
              wdcPong: begin
                DoPongReceived(Now, LLastPongReceived);
                LLastPongReceived := Now;
              end;
            end;
            Continue;
          end;

          if LWSCode = wdcText then
            LWSType := wdtText else
            LWSType := wdtBinary;

          // Must check both client and server because it's possible for client not to support,
          // while server supports it...
          if (LContext.SupportsPerMessageDeflate) and
             (LContext.ClientMaxWindowBits <> TClientMaxWindowBits.Disabled) and
             (LContext.ServerMaxWindowBits <> TServerMaxWindowBits.Disabled) then
            begin
              var LLen := LStreamRequest.Size;
              var LBytes: TArray<Byte>;
              SetLength(LBytes, LLen);
              LStreamRequest.Read(LBytes, LLen);
              var LCompressedBytes := DecompressMessage(LBytes, LContext.ServerMaxWindowBits);
              LStreamRequest.Size := 0;
              LStreamRequest.Write(LCompressedBytes, Length(LCompressedBytes));
              LStreamRequest.Position := 0;
            end;

          HandleWSMessage(LContext, LWSType, LStreamRequest, LStreamResponse);

          // write result back (of the same type: text or bin)
          if LStreamResponse.Size > 0 then
          begin
            if LWSType = wdtText then
              LHandler.Write(LStreamResponse, wdtText) else
              LHandler.Write(LStreamResponse, wdtBinary)
          end else
          begin
            LHandler.WriteData(nil, wdcPing);
            LLastPingSent := Now;
          end;
        finally
          LStreamRequest.Free;
          LStreamResponse.Free;
        end;
      end
      // ping after 5s idle
      else if SecondsBetween(Now, LLastPingSent) > FPingInterval then
      begin
        // ping
        LHandler.WriteData(nil, wdcPing);
        LLastPingSent := Now;
      end;

    end;
  finally
    LContext.IOHandler.Clear;
    AThread.Data := nil;
  end;
end;

class procedure TIdServerWebSocketHandling.HandleWSMessage(
  AContext: TIdServerWSContext; var AWSType:TWSDataType;
  ARequestStream, AResponseStream: TMemoryStream);
begin
  if Assigned(AContext.OnCustomChannelExecute) then
    AContext.OnCustomChannelExecute(AContext, AWSType, ARequestStream, AResponseStream);
end;

class function TIdServerWebSocketHandling.ProcessServerCommandGet(
  AThread: TIdServerWSContext; const AConnectionEvents: TWebSocketConnectionEvents;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean;
var
  Accept, LWasWebSocket: Boolean;
  LAConnection, sValue, LSGuid: string;
  LConnection: TArray<string>;
  LContext: TIdServerWSContext;
  LHash: TIdHashSHA1;
  LGuid: TGUID;
begin
  (* GET /chat HTTP/1.1
     Host: server.example.com
     Upgrade: websocket
     Connection: Upgrade
     Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
     Origin: http://example.com
     Sec-WebSocket-Protocol: chat, superchat
     Sec-WebSocket-Version: 13 *)

  (* GET ws://echo.websocket.org/?encoding=text HTTP/1.1
     Origin: http://websocket.org
     Cookie: __utma=99as
     Connection: Upgrade
     Host: echo.websocket.org
     Sec-WebSocket-Key: uRovscZjNol/umbTt5uKmw==
     Upgrade: websocket
     Sec-WebSocket-Version: 13 *)

  // Connection: Upgrade
  LAConnection := ARequestInfo.Connection;
  LConnection := SplitString(LAConnection, ', ');
  {$IF DEFINED(DEBUG_WS)}
  OutputDebugString(Format('Connection string: "%s"', [LConnection]));
  {$ENDIF}
  if PosInStrArray(SUpgrade, LConnection, False) = -1 then   // Firefox uses "keep-alive, Upgrade"
  begin
    // initiele ondersteuning voor socket.io
    if SameText(ARequestInfo.Document , '/socket.io/1/') then
    begin
      {
      https://github.com/LearnBoost/socket.io-spec
      The client will perform an initial HTTP POST request like the following
      http://example.com/socket.io/1/
      200: The handshake was successful.
      The body of the response should contain the session id (sid) given to the client, followed by the heartbeat timeout, the connection closing timeout, and the list of supported transports separated by :
      The absence of a heartbeat timeout ('') is interpreted as the server and client not expecting heartbeats.
      For example 4d4f185e96a7b:15:10:websocket,xhr-polling.
      }
      AResponseInfo.ResponseNo   := 200;
      AResponseInfo.ResponseText := 'Socket.io connect OK';

      CreateGUID(LGuid);
      LSGuid := GUIDToString(LGuid);
      AResponseInfo.ContentText  := LSGuid + ':15:10:websocket,xhr-polling';
      AResponseInfo.CloseConnection := False;
      // (AThread.SocketIO as TIdServerSocketIOHandling_Ext).NewConnection(AThread);
      //(AThread.SocketIO as TIdServerSocketIOHandling_Ext).NewConnection(squid, AThread.Binding.PeerIP);

    //'/socket.io/1/xhr-polling/2129478544'

      Result := True;  //handled
    end else
    begin
      AResponseInfo.ContentText := 'Missing connection info';
      Exit(False);
    end;
  end else
  begin
//    Result  := True;  // commented out due to H2077 Value assigned never used...
    LContext := AThread as TIdServerWSContext;

    if Assigned(LContext.OnWebSocketUpgrade) then
     begin
        Accept := True;
        LContext.OnWebSocketUpgrade(LContext, ARequestInfo, Accept);
        if not Accept then
          begin
            AResponseInfo.ContentText := 'Failed upgrade.';
            AResponseInfo.ResponseNo  := CNoContent;
            Exit(False);
          end;
     end;

    // Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
    sValue := ARequestInfo.RawHeaders.Values[SWebSocketKey];
    // "The value of this header field MUST be a nonce consisting of a randomly
    // selected 16-byte value that has been base64-encoded"
    if (sValue <> '') then
    begin
      if (Length(TIdDecoderMIME.DecodeString(sValue)) = 16) then
        LContext.WebSocketKey := sValue else
        begin
          {$IF DEFINED(DEBUG_WS)}
          OutputDebugString('Server', 'Invalid length');
          {$ENDIF}
          AResponseInfo.ContentText := 'Invalid length';
          AResponseInfo.ResponseNo  := CNoContent;
          Exit(False); //invalid length
        end;
    end else
    begin
      // important: key must exists, otherwise stop!
      {$IF DEFINED(DEBUG_WS)}
      OutputDebugString('Server', 'Aborting connection');
      {$ENDIF}
      AResponseInfo.ContentText := 'Key doesn''t exist';
      AResponseInfo.ResponseNo  := CNoContent;
      Exit(False);
    end;

    (*
     ws-URI = "ws:" "//" host [ ":" port ] path [ "?" query ]
     wss-URI = "wss:" "//" host [ ":" port ] path [ "?" query ]
     2.   The method of the request MUST be GET, and the HTTP version MUST be at least 1.1.
          For example, if the WebSocket URI is "ws://example.com/chat",
          the first line sent should be "GET /chat HTTP/1.1".
     3.   The "Request-URI" part of the request MUST match the /resource
          name/ defined in Section 3 (a relative URI) or be an absolute
          http/https URI that, when parsed, has a /resource name/, /host/,
          and /port/ that match the corresponding ws/wss URI.
    *)
    LContext.ResourceName := ARequestInfo.Document;
    if ARequestInfo.UnparsedParams <> '' then
      LContext.ResourceName := LContext.ResourceName + '?' +
                              ARequestInfo.UnparsedParams;
    // separate parts
    LContext.Path         := ARequestInfo.Document;
    LContext.Query        := ARequestInfo.UnparsedParams;

    // Host: server.example.com
    LContext.Host   := ARequestInfo.RawHeaders.Values[SHTTPHostHeader];
    // Origin: http://example.com
    LContext.Origin := ARequestInfo.RawHeaders.Values[SHTTPOriginHeader];
    // Cookie: __utma=99as
    LContext.Cookie := ARequestInfo.RawHeaders.Values[SHTTPCookieHeader];

    // Sec-WebSocket-Version: 13
    // "The value of this header field MUST be 13"
    sValue := Trim(ARequestInfo.RawHeaders.Values[SWebSocketVersion]);
    if (sValue <> '') then
    begin
      LContext.WebSocketVersion := StrToIntDef(sValue, 0);

      if LContext.WebSocketVersion < 13 then
        begin
          {$IF DEFINED(DEBUG_WS)}
          OutputDebugString('Server', 'WebSocket version < 13');
          {$ENDIF}
          AResponseInfo.ContentText := 'Wrong version';
          Exit(False); // Abort;  //must be at least 13
        end;
    end else
    begin
      {$IF DEFINED(DEBUG_WS)}
      OutputDebugString('Server', 'WebSocket version missing');
      {$ENDIF}
      AResponseInfo.ContentText := 'Missing version';
      Exit(False); // Abort; //must exist
    end;

    LContext.WebSocketProtocol   := ARequestInfo.RawHeaders.Values[SWebSocketProtocol];
    LContext.WebSocketExtensions := ARequestInfo.RawHeaders.Values[SWebSocketExtensions];
    LContext.Encoding            := ARequestInfo.AcceptEncoding;
    if SupportsPerMessageDeflate then
      begin
        var LWebSocketExtensions: TArray<string> := SplitString(LContext.WebSocketExtensions, '; ');
        var LPerMessageDeflateIndex := PosInStrArray(SPerMessageDeflate, LWebSocketExtensions, False);
        if LPerMessageDeflateIndex <> -1 then
          begin
            var LClientMaxWindowBitsParam := '';
            RemoveEmptyElements(LWebSocketExtensions);
            for var I := Low(LWebSocketExtensions) to High(LWebSocketExtensions) do
              begin
                if LWebSocketExtensions[I].StartsWith(SClientMaxWindowBits, True) then
                  begin
                    LClientMaxWindowBitsParam := LWebSocketExtensions[I];
                    Break;
                  end;
              end;
            if LClientMaxWindowBitsParam <> '' then
              begin
                var LClientMaxWindowBits := SplitString(LClientMaxWindowBitsParam, '=');
                RemoveEmptyElements(LClientMaxWindowBits);
                var LClientMaxWindowBitsLen := Length(LClientMaxWindowBits);
                case LClientMaxWindowBitsLen of
                  0: begin
                    LContext.ClientMaxWindowBits := TClientMaxWindowBits.MinValue;
                    if SupportsPerMessageDeflate then
                      begin
                        LContext.ServerMaxWindowBits := System.Math.Min(LContext.ClientMaxWindowBits, MaxWindowBits);
                        LContext.SupportsPerMessageDeflate := True;
                      end;
                  end;
                  1: begin
                    LContext.ClientMaxWindowBits := TClientMaxWindowBits.MinValue;
                    if SupportsPerMessageDeflate then
                      begin
                        LContext.ServerMaxWindowBits := LContext.ClientMaxWindowBits;
                        LContext.SupportsPerMessageDeflate := True;
                      end;
                  end;
                  2: begin
                    LContext.ClientMaxWindowBits := StrToIntDef(LClientMaxWindowBits[1], TClientMaxWindowBits.MinValue);
                    if SupportsPerMessageDeflate then
                      begin
                        LContext.ServerMaxWindowBits := LContext.ClientMaxWindowBits;
                        LContext.SupportsPerMessageDeflate := True;
                      end;
                  end;
                end;
              end;
            if LContext.SupportsPerMessageDeflate and
               (LContext.ClientMaxWindowBits <> TClientMaxWindowBits.Disabled) and
               (LContext.ServerMaxWindowBits <> TServerMaxWindowBits.Disabled) then
              begin
                var LValue := Format('%s; %s=%d', [SPerMessageDeflate, SClientMaxWindowBits, LContext.ServerMaxWindowBits]);
                AResponseInfo.CustomHeaders.AddValue(SWebSocketExtensions, LValue);
              end;
          end; // if LPerMessageDeflateIndex <> -1
      end; // end check for per-message deflate

    // Response
    (* HTTP/1.1 101 Switching Protocols
       Upgrade: websocket
       Connection: Upgrade
       Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo= *)
    AResponseInfo.ResponseNo         := CSwitchingProtocols;
    AResponseInfo.ResponseText       := SSwitchingProtocols;
    AResponseInfo.CloseConnection    := False;
    // Connection: Upgrade
    AResponseInfo.Connection         := SUpgrade;
    // Upgrade: websocket
    AResponseInfo.CustomHeaders.Values[SUpgrade] := SWebSocket;
    if LContext.ServerSoftware <> '' then
      AResponseInfo.CustomHeaders.Values[SServer] := LContext.ServerSoftware;

    // Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
    sValue := Trim(LContext.WebSocketKey) +  // ... "minus any leading and trailing whitespace"
              SWebSocketGUID;                // special GUID
    LHash := TIdHashSHA1.Create;
    try
      sValue := TIdEncoderMIME.EncodeBytes(                   // Base64
                     LHash.HashString(sValue) );              // SHA1
    finally
      LHash.Free;
    end;
    AResponseInfo.CustomHeaders.Values[SWebSocketAccept] := sValue;

    // send same protocol back?
    AResponseInfo.CustomHeaders.Values[SWebSocketProtocol]   := LContext.WebSocketProtocol;
    // we do not support extensions yet (gzip deflate compression etc)
    // AResponseInfo.CustomHeaders.Values['Sec-WebSocket-Extensions'] := context.WebSocketExtensions;
    // http://www.lenholgate.com/blog/2011/07/websockets---the-deflate-stream-extension-is-broken-and-badly-designed.html
    // but is could be done using idZlib.pas and DecompressGZipStream etc

    // send response back
    LContext.IOHandler.InputBuffer.Clear;
    LContext.IOHandler.BusyUpgrading := True;
    if Assigned(AConnectionEvents.OnBeforeSendHeaders) then
      begin
        AConnectionEvents.OnBeforeSendHeaders(LContext, AResponseInfo);
      end;
    AResponseInfo.WriteHeader;

    // handle all WS communication in separate loop
    {$IF DEFINED(DEBUG_WS)}
    OutputDebugString('Server', 'Entering DoWSExecute');
    {$ENDIF}
    LWasWebSocket := False;
    try
// This needs to be protected, otherwise, the server will
// become unresponsive after 3 disconnections initiated by the client
      LWasWebSocket := True;
      if Assigned(AConnectionEvents.ConnectedEvent) then
        AConnectionEvents.ConnectedEvent(AThread);
      // WebSocket handling loop, runs forever until disconnection
      DoWSExecute(AThread);
    except
      {$IF DEFINED(DEBUG_WS)}
      on E: Exception do
        begin
          var LMsg := Format('DoWSExecute Thread: %.8x Exception: %s', [
            TThread.Current.ThreadID, E.Message]);
          OutputDebugString('Server', LMsg);
        end;
      {$ENDIF}
    end;
    if LWasWebSocket and Assigned(AConnectionEvents.DisconnectedEvent) then
      AConnectionEvents.DisconnectedEvent(AThread);
    AResponseInfo.CloseConnection := True;
    {$IF DEFINED(DEBUG_WS)}
    var LMsg := Format('DoWSExecute Thread: %.8x done', [TThread.Current.ThreadID]);
    OutputDebugString('Server', LMsg);
    {$ENDIF}
    Result := True;
  end;
end;
class procedure TIdServerWebSocketHandling.SetMaxWindowBits(const Value: Integer);
begin
  var LSupportsPerMessageDeflate := (Value >= TServerMaxWindowBits.MinValue) and (Value <= TServerMaxWindowBits.MaxValue);
  if LSupportsPerMessageDeflate then
    begin
      FSupportsPerMessageDeflate := True;
      FMaxWindowBits := Value;
    end else
    begin
      FSupportsPerMessageDeflate := False;
    end;
end;

class procedure TIdServerWebSocketHandling.SetSupportsPerMessageDeflate(const Value: Boolean);
begin
  if Value then
    FMaxWindowBits := TServerMaxWindowBits.MinValue else
    FMaxWindowBits := TServerMaxWindowBits.Disabled;
  FSupportsPerMessageDeflate := Value;
end;

procedure TIdServerIOHandlerStack.InitComponent;
begin
  inherited InitComponent;
  IOHandlerSocketClass := TIdIOHandlerStack;
end;
function TIdServerIOHandlerStack.MakeClientIOHandler(ATheThread:TIdYarn ): TIdIOHandler;
begin
  Result := IOHandlerSocketClass.Create(nil);
end;
function TIdServerIOHandlerWebSocket.Accept(ASocket: TIdSocketHandle;
  AListenerThread: TIdThread; AYarn: TIdYarn): TIdIOHandler;
begin
  Result := inherited Accept(ASocket, AListenerThread, AYarn);
  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebSocket).IsServerSide := True; // server must not mask, only client
    (Result as TIdIOHandlerWebSocket).UseNagle := False;
  end;
end;
procedure TIdServerIOHandlerWebSocket.InitComponent;
begin
  inherited InitComponent;
  IOHandlerSocketClass := TIdIOHandlerWebsocketServer;
end;
function TIdServerIOHandlerWebSocket.MakeClientIOHandler(
  ATheThread: TIdYarn): TIdIOHandler;
begin
  Result := inherited MakeClientIOHandler(ATheThread);
  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebSocket).IsServerSide := True; // server must not mask, only client
    (Result as TIdIOHandlerWebSocket).UseNagle := False;
  end;
end;
procedure TIdServerIOHandlerWebSocket.SetWebSocketClosing(
  const AValue: TOnWebSocketClosing);
begin
  FOnWebSocketClosing := AValue;
end;
end.
