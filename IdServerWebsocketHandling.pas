unit IdServerWebSocketHandling;
interface

uses
  System.Classes, System.StrUtils, System.SysUtils, System.DateUtils,
  IdCoderMIME, IdThread, IdContext, IdCustomHTTPServer,
  {$IF CompilerVersion <= 21.0}  // D2010
  IdHashSHA1,
  {$ELSE}
  IdHashSHA,                     // XE3 etc
  {$ENDIF}
  IdServerSocketIOHandling, IdSocketIOHandling, IdServerBaseHandling,
  IdServerWebSocketContext, IdIOHandlerWebSocket, IdWebSocketTypes;

type
  TIdServerSocketIOHandling_Ext = class(TIdServerSocketIOHandling)
  end;

  TIdServerWebSocketHandling = class(TIdServerBaseHandling)
  protected
    class var FExitConnectedCheck: Boolean;
    class procedure DoWSExecute(AThread: TIdContext;
      ASocketIOHandler: TIdServerSocketIOHandling_Ext); virtual;
    class procedure HandleWSMessage(AContext: TIdServerWSContext;
      var AWSType: TWSDataType; ARequestStream, AResponseStream: TMemoryStream;
      ASocketIOHandler: TIdServerSocketIOHandling_Ext); virtual;
  public
    class function ProcessServerCommandGet(AThread: TIdServerWSContext;
      const AConnectionEvents: TWebSocketConnectionEvents;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean;

    class function CurrentSocket: ISocketIOContext;
    class property ExitConnectedCheck: Boolean read FExitConnectedCheck
      write FExitConnectedCheck;
  end;

implementation

uses
  IdWebSocketConsts, IdIIOHandlerWebSocket, WSDebugger;

{ TIdServerWebSocketHandling }

class function TIdServerWebSocketHandling.CurrentSocket: ISocketIOContext;
var
  LThread: TIdThreadWithTask;
  LContext: TIdServerWSContext;
begin
  if not (TThread.Current is TIdThreadWithTask) then
    Exit(nil);
  LThread  := TThread.Current as TIdThreadWithTask;
  if not (LThread.Task is TIdServerWSContext) then
    Exit(nil);
  LContext := LThread.Task as TIdServerWSContext;
  Result  := LContext.SocketIO.GetSocketIOContext(LContext);
end;

class procedure TIdServerWebSocketHandling.DoWSExecute(AThread: TIdContext;
  ASocketIOHandler: TIdServerSocketIOHandling_Ext);
var
  LStreamRequest, LStreamResponse: TMemoryStream;
  LWSCode: TWSDataCode;
  LWSType: TWSDataType;
  LContext: TIdServerWSContext;
  LStart: TDateTime;
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
    if LContext.IsSocketIO then
    begin
      Assert(ASocketIOHandler <> nil);
      ASocketIOHandler.WriteConnect(LContext);
    end;
    AThread.Connection.Socket.UseNagle := False;  // no 200ms delay!

    LStart := Now;

    while LHandler.Connected and not LHandler.ClosedGracefully do
    begin
      if LHandler.HasData or
        (LHandler.InputBuffer.Size > 0) or
         LHandler.Readable(1 * 1000) then     // wait 5s, else ping the client(!)
      begin
        LStart := Now;

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
              WSDebugger.OutputDebugString('Closing server session');
              {$ENDIF}
              Break;
            end;

          // ignore ping/pong messages
          if LWSCode in [wdcPing, wdcPong] then
          begin
            if LWSCode = wdcPing then
              LHandler.WriteData(nil, wdcPong);
            Continue;
          end;

          if LWSCode = wdcText then
            LWSType := wdtText else
            LWSType := wdtBinary;

          HandleWSMessage(LContext, LWSType, LStreamRequest, LStreamResponse, ASocketIOHandler);

          // write result back (of the same type: text or bin)
          if LStreamResponse.Size > 0 then
          begin
            if LWSType = wdtText then
              LHandler.Write(LStreamResponse, wdtText) else
              LHandler.Write(LStreamResponse, wdtBinary)
          end else
          begin
            LHandler.WriteData(nil, wdcPing);
          end;
        finally
          LStreamRequest.Free;
          LStreamResponse.Free;
        end;
      end
      // ping after 5s idle
      else if SecondsBetween(Now, LStart) > 5 then
      begin
        LStart := Now;
        // ping
        if LContext.IsSocketIO then
        begin
          // context.SocketIOPingSend := True;
          Assert(ASocketIOHandler <> nil);
          ASocketIOHandler.WritePing(LContext);
        end else
        begin
          LHandler.WriteData(nil, wdcPing);
        end;
      end;

    end;
  finally
    if LContext.IsSocketIO then
    begin
      Assert(ASocketIOHandler <> nil);
      ASocketIOHandler.WriteDisconnect(LContext);
    end;
    LContext.IOHandler.Clear;
    AThread.Data := nil;
  end;
end;

class procedure TIdServerWebSocketHandling.HandleWSMessage(
  AContext: TIdServerWSContext; var AWSType:TWSDataType;
  ARequestStream, AResponseStream: TMemoryStream;
  ASocketIOHandler: TIdServerSocketIOHandling_Ext);
begin
  if AContext.IsSocketIO then
  begin
    ARequestStream.Position := 0;
    Assert(ASocketIOHandler <> nil);
    ASocketIOHandler.ProcessSocketIORequest(AContext, ARequestStream);
  end
  else if Assigned(AContext.OnCustomChannelExecute) then
    AContext.OnCustomChannelExecute(AContext, AWSType, ARequestStream, AResponseStream);
end;

class function TIdServerWebSocketHandling.ProcessServerCommandGet(
  AThread: TIdServerWSContext;
  const AConnectionEvents: TWebSocketConnectionEvents;
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo): Boolean;
var
  Accept, LWasWebSocket: Boolean;
  LConnection, sValue, LSGuid: string;
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
  LConnection := ARequestInfo.Connection;
  {$IF DEFINED(DEBUG_WS)}
  WSDebugger.OutputDebugString(Format('Connection string: "%s"', [LConnection]));
  {$ENDIF}
  if not ContainsText(LConnection, SUpgrade) then   //Firefox uses "keep-alive, Upgrade"
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
      (AThread.SocketIO as TIdServerSocketIOHandling_Ext).NewConnection(AThread);
      //(AThread.SocketIO as TIdServerSocketIOHandling_Ext).NewConnection(squid, AThread.Binding.PeerIP);

      Result := True;  //handled
    end
    //'/socket.io/1/xhr-polling/2129478544'
    else if StartsText('/socket.io/1/xhr-polling/', ARequestInfo.Document) then
    begin
      AResponseInfo.ContentStream   := TMemoryStream.Create;
      AResponseInfo.CloseConnection := False;

      LSGuid := Copy(ARequestInfo.Document, 1 + Length('/socket.io/1/xhr-polling/'),
        Length(ARequestInfo.Document));
      var LCommandType := ARequestInfo.CommandType;
      if LCommandType in [hcGET, hcPOST] then
        begin
          var LSocketIOHandlingExt := (AThread.SocketIO as TIdServerSocketIOHandling_Ext);
          var LPostStream := ARequestInfo.PostStream;
          case LCommandType of
            hcGET: LSocketIOHandlingExt.ProcessSocketIO_XHR(LSGuid, LPostStream,
              AResponseInfo.ContentStream);
            hcPOST: LSocketIOHandlingExt.ProcessSocketIO_XHR(LSGuid, LPostStream,
              nil);   //no response expected with POST!
          end;
        end;
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
          WSDebugger.OutputDebugString('Server', 'Invalid length');
          {$ENDIF}
          AResponseInfo.ContentText := 'Invalid length';
          Exit(False); //invalid length
        end;
    end else
    begin
      // important: key must exists, otherwise stop!
      {$IF DEFINED(DEBUG_WS)}
      WSDebugger.OutputDebugString('Server', 'Aborting connection');
      {$ENDIF}
      AResponseInfo.ContentText := 'Key doesn''t exist';
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
    sValue := ARequestInfo.RawHeaders.Values[SWebSocketVersion];
    if (sValue <> '') then
    begin
      LContext.WebSocketVersion := StrToIntDef(sValue, 0);

      if LContext.WebSocketVersion < 13 then
        begin
          {$IF DEFINED(DEBUG_WS)}
          WSDebugger.OutputDebugString('Server', 'WebSocket version < 13');
          {$ENDIF}
          AResponseInfo.ContentText := 'Wrong version';
          Exit(False); // Abort;  //must be at least 13
        end;
    end else
    begin
      {$IF DEFINED(DEBUG_WS)}
      WSDebugger.OutputDebugString('Server', 'WebSocket version missing');
      {$ENDIF}
      AResponseInfo.ContentText := 'Missing version';
      Exit(False); // Abort; //must exist
    end;

    LContext.WebSocketProtocol   := ARequestInfo.RawHeaders.Values[SWebSocketProtocol];
    LContext.WebSocketExtensions := ARequestInfo.RawHeaders.Values[SWebSocketExtensions];

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
    AResponseInfo.WriteHeader;

    // handle all WS communication in separate loop
    {$IF DEFINED(DEBUG_WS)}
    WSDebugger.OutputDebugString('Server', 'Entering DoWSExecute');
    {$ENDIF}
    LWasWebSocket := False;
    try
// This needs to be protected, otherwise, the server will
// become unresponsive after 3 disconnections initiated by the client
      LWasWebSocket := True;
      if Assigned(AConnectionEvents.ConnectedEvent) then
        AConnectionEvents.ConnectedEvent(AThread);
      DoWSExecute(AThread, (LContext.SocketIO as TIdServerSocketIOHandling_Ext));
    except
      {$IF DEFINED(DEBUG_WS)}
      on E: Exception do
        begin
          var LMsg := Format('DoWSExecute Thread: %.8x Exception: %s', [
            TThread.Current.ThreadID, E.Message]);
          WSDebugger.OutputDebugString('Server', LMsg);
        end;
      {$ENDIF}
    end;
    if LWasWebSocket and Assigned(AConnectionEvents.DisconnectedEvent) then
      AConnectionEvents.DisconnectedEvent(AThread);
    AResponseInfo.CloseConnection := True;
    {$IF DEFINED(DEBUG_WS)}
    var LMsg := Format('DoWSExecute Thread: %.8x done', [TThread.Current.ThreadID]);
    WSDebugger.OutputDebugString('Server', LMsg);
    {$ENDIF}
    Result := True;
  end;
end;

end.
