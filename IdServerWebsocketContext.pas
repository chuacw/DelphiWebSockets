unit IdServerWebSocketContext;
interface
{$I wsdefines.pas}

uses
  System.Classes, System.StrUtils, IdContext, IdCustomTCPServer,
  IdCustomHTTPServer, IdIOHandlerWebSocket, IdServerBaseHandling,
  IdServerSocketIOHandling, IdWebSocketTypes, IdIIOHandlerWebSocket;

type
  TIdServerWSContext = class;

  TWebSocketUpgradeEvent = procedure(const AContext: TIdServerWSContext;
    const ARequestInfo: TIdHTTPRequestInfo; var Accept: Boolean) of object;

  TWebSocketChannelRequest = procedure(const AContext: TIdServerWSContext;
    var aType:TWSDataType; const strmRequest, strmResponse: TMemoryStream) of object;

  TWebSocketConnected    = procedure(const AContext: TIdServerWSContext) of object;
  TWebSocketDisconnected = procedure(const AContext: TIdServerWSContext) of object;

  TWebSocketConnectionEvents = record
    ConnectedEvent: TWebSocketConnected;
    DisconnectedEvent: TWebSocketDisconnected;
  end;

  TIdServerWSContext = class(TIdServerContext)
  private
    FWebSocketKey: string;
    FWebSocketVersion: Integer;
    FPath: string;
    FWebSocketProtocol: string;
    FResourceName: string;
    FOrigin: string;
    FQuery: string;
    FHost: string;
    FWebSocketExtensions: string;
    FCookie: string;
    FClientIP: string;
    // FSocketIOPingSend: Boolean;
    FOnWebSocketUpgrade: TWebSocketUpgradeEvent;
    FOnCustomChannelExecute: TWebSocketChannelRequest;
    FSocketIO: TIdServerSocketIOHandling;
    FOnDestroy: TIdContextEvent;
    function GetClientIP: string;
  public
    function IOHandler: IIOHandlerWebSocket;
  public
    function IsSocketIO: Boolean;
    property SocketIO: TIdServerSocketIOHandling read FSocketIO write FSocketIO;
    //property SocketIO: TIdServerBaseHandling read FSocketIO write FSocketIO;
    property OnDestroy: TIdContextEvent read FOnDestroy write FOnDestroy;
  public
    destructor Destroy; override;

    property ClientIP    : string read GetClientIP write FClientIP;
    property Path        : string read FPath write FPath;
    property Query       : string read FQuery write FQuery;
    property ResourceName: string read FResourceName write FResourceName;
    property Host        : string read FHost write FHost;
    property Origin      : string read FOrigin write FOrigin;
    property Cookie      : string read FCookie write FCookie;

    property WebSocketKey       : string  read FWebSocketKey write FWebSocketKey;
    property WebSocketProtocol  : string  read FWebSocketProtocol write FWebSocketProtocol;
    property WebSocketVersion   : Integer read FWebSocketVersion write FWebSocketVersion;
    property WebSocketExtensions: string  read FWebSocketExtensions write FWebSocketExtensions;
  public
    property OnWebSocketUpgrade: TWebSocketUpgradeEvent read FOnWebSocketUpgrade write FOnWebSocketUpgrade;
    property OnCustomChannelExecute: TWebSocketChannelRequest read FOnCustomChannelExecute write FOnCustomChannelExecute;
  end;

implementation

uses
  IdIOHandlerWebSocketSSL, IdIOHandlerStack;

{ TIdServerWSContext }

destructor TIdServerWSContext.Destroy;
begin
  if Assigned(OnDestroy) then
    OnDestroy(Self);
  inherited;
end;

function TIdServerWSContext.GetClientIP: string;
var
  LHandler: TIdIOHandlerStack;
begin
  if FClientIP = '' then
    begin
      LHandler := IOHandler as TIdIOHandlerStack;
      FClientIP := LHandler.Binding.IP;
    end;
  Result := FClientIP;
end;

function TIdServerWSContext.IOHandler: IIOHandlerWebSocket;
begin
  Result := Connection.IOHandler as IIOHandlerWebSocket;
end;

function TIdServerWSContext.IsSocketIO: Boolean;
begin
  //FDocument	= '/socket.io/1/websocket/13412152'
  Result := StartsText('/socket.io/1/websocket/', FPath);
end;

end.
