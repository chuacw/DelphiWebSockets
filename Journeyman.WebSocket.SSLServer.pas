unit Journeyman.WebSocket.SSLServer;

interface

uses
  Journeyman.WebSocket.Server;

type
  TIdWebSocketServerSSL = class(TIdWebSocketServer)
  public
    procedure AfterConstruction; override;
  end;

implementation

uses
  Journeyman.WebSocket.Server.IOHandlers,
  Journeyman.WebSocket.Server.SSLIOHandlers;

{ TIdWebSocketServerSSL }

procedure TIdWebSocketServerSSL.AfterConstruction;
begin
  inherited;
  if IOHandler is TIdServerIOHandlerWebSocket then
    begin
      IOHandler.Free;
      IOHandler := TIdServerIOHandlerWebSocketSSL.Create(Self);
    end;
end;

end.
