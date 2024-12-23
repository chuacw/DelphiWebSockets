unit IdWebSocketServerSSL;

interface

uses
  IdWebSocketServer;

type
  TIdWebSocketServerSSL = class(TIdWebSocketServer)
  public
    procedure AfterConstruction; override;
  end;

implementation

uses
  IdServerIOHandlerWebsocket, IdServerIOHandlerWebSocketSSL;

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
