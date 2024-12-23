unit Journeyman.WebSocket.Server.SSLIOHandlers;
// unit IdServerIOHandlerWebSocketSSL;

interface

uses
  IdServerIOHandlerStack,
  Journeyman.WebSocket.SSLIOHandlers,
  IdSocketHandle, IdThread,
  IdYarn, IdIOHandler, Journeyman.WebSocket.Types,
  Journeyman.WebSocket.Interfaces,
  Journeyman.WebSocket.IOHandlers,
  IdSSLOpenSSL,
  IdSSL;

type
  TIdServerIOHandlerWebSocketSSL = class(TIdServerIOHandlerSSLOpenSSL,
    ISetWebSocketClosing)
  protected
    FOnWebSocketClosing: TOnWebSocketClosing;
    procedure SetWebSocketClosing(const AValue: TOnWebSocketClosing);
  public
    procedure InitServerSettings(AIOHandler: TIdIOHandlerWebSocketSSL); overload;
  public
    function Accept(ASocket: TIdSocketHandle; AListenerThread: TIdThread;
      AYarn: TIdYarn): TIdIOHandler; override;
    function MakeClientIOHandler(ATheThread: TIdYarn): TIdIOHandler; override;
    function MakeClientIOHandler: TIdSSLIOHandlerSocketBase; override;
  end;

implementation

uses
  System.SysUtils;

function TIdServerIOHandlerWebSocketSSL.Accept(ASocket: TIdSocketHandle;
  AListenerThread: TIdThread; AYarn: TIdYarn): TIdIOHandler;
var
  LIO: TIdIOHandlerWebSocketSSL;
begin
  Assert(ASocket<>nil);
  Assert(fSSLContext<>nil);
  LIO := TIdIOHandlerWebSocketSSL.Create(Self);
  InitServerSettings(LIO);

  try
//    LIO.PassThrough := True; // passthrough set in InitServerSettings
    LIO.Open;
    if LIO.Binding.Accept(ASocket.Handle) then begin
      // we need to pass the SSLOptions for the socket from the server
      LIO.SSLOptions.Free;
      LIO.IsPeer := True;
      LIO.SSLOptions := fxSSLOptions;
//      LIO.SSLSocket.Free;
//      LIO.SSLSocket := TIdSSLSocket.Create(Self);
      LIO.SSLContext := fSSLContext;

      // - Set up an additional SSL_CTX for each different certificate;
      // - Add a servername callback to each SSL_CTX using SSL_CTX_set_tlsext_servername_callback();
      // - In the callback, retrieve the client-supplied servername with
      //   SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name). Figure out the right
      //   SSL_CTX to go with that host name, then switch the SSL object to that
      //   SSL_CTX with SSL_set_SSL_CTX().
    end else begin
      FreeAndNil(LIO);
    end;
  except
    LIO.Free;
    raise;
  end;
  Result := LIO;
end;

procedure TIdServerIOHandlerWebSocketSSL.InitServerSettings(AIOHandler: TIdIOHandlerWebSocketSSL);
var
  LSetWebSocketClosing: ISetWebSocketClosing;
begin
  if AIOHandler <> nil then
    begin
      AIOHandler.RoleName := 'Server';
      AIOHandler.IsServerSide := True;  // server must not mask, only client
      AIOHandler.UseNagle := False;
      AIOHandler.PassThrough := True;   // Don't use SSL for now...
//      AIOHandler.SSLOptions.SSLVersions := [sslvTLSv1, sslvTLSv1_1, sslvTLSv1_2]; // working
      AIOHandler.SSLOptions.Method := sslvSSLv23;
      AIOHandler.SSLOptions.Mode := sslmUnassigned;
// Do not set the VerifyMode!!!
      if Supports(AIOHandler, ISetWebSocketClosing, LSetWebSocketClosing) then
        LSetWebSocketClosing.SetWebSocketClosing(FOnWebSocketClosing);
    end;
end;

function TIdServerIOHandlerWebSocketSSL.MakeClientIOHandler: TIdSSLIOHandlerSocketBase;
begin
  Result := inherited;
end;

function TIdServerIOHandlerWebSocketSSL.MakeClientIOHandler(
  ATheThread: TIdYarn): TIdIOHandler;
begin
  Result := inherited MakeClientIOHandler(ATheThread);
  InitServerSettings(Result as TIdIOHandlerWebSocketSSL);
end;

procedure TIdServerIOHandlerWebSocketSSL.SetWebSocketClosing(
  const AValue: TOnWebSocketClosing);
begin
  FOnWebSocketClosing := AValue;
end;

end.

