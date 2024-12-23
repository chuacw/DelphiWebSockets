unit IdServerIOHandlerWebSocket;
interface

uses
  System.Classes, IdServerIOHandlerStack, IdIOHandlerStack, IdGlobal,
  IdIOHandler, IdYarn, IdThread, IdSocketHandle, IdIOHandlerWebSocket,
  IdWebSocketTypes;

type
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
