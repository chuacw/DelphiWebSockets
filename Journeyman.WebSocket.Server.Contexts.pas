unit Journeyman.WebSocket.Server.Contexts;
interface

uses
  System.Classes, System.StrUtils, IdContext, IdCustomTCPServer,
  IdTCPConnection, // TIdTCPConnection
  IdCustomHTTPServer,
  Journeyman.WebSocket.IOHandlers,
  Journeyman.WebSocket.Types,
  Journeyman.WebSocket.Interfaces;

type
  TIdServerWSContext = class;

  TWebSocketUpgradeEvent = procedure(const AContext: TIdServerWSContext;
    const ARequestInfo: TIdHTTPRequestInfo; var Accept: Boolean) of object;

  TWebSocketChannelRequest = procedure(const AContext: TIdServerWSContext;
    var aType:TWSDataType; const strmRequest, strmResponse: TMemoryStream) of object;

  TWebSocketConnected    = procedure(const AContext: TIdServerWSContext) of object;
  TWebSocketDisconnected = procedure(const AContext: TIdServerWSContext) of object;

  TOnBeforeSendHeaders = procedure(const AContext: TIdServerWSContext;
    const AResponseInfo: TIdHTTPResponseInfo) of object;
  TWebSocketConnectionEvents = record
    ConnectedEvent: TWebSocketConnected;
    DisconnectedEvent: TWebSocketDisconnected;
    OnBeforeSendHeaders: TOnBeforeSendHeaders;
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
    FEncoding: string;
    FServerSoftware: string;
    // FSocketIOPingSend: Boolean;
    FOnWebSocketUpgrade: TWebSocketUpgradeEvent;
    FOnCustomChannelExecute: TWebSocketChannelRequest;
//    FSocketIO: TIdServerSocketIOHandling;
    FOnDestroy: TIdContextEvent;
    FSupportsPerMessageDeflate: Boolean;
    FClientMaxWindowBits: Integer;
    FServerMaxWindowBits: Integer;
    function GetClientIP: string;
  public
    function IOHandler: IIOHandlerWebSocket;
  public
    function IsSocketIO: Boolean;
//    property SocketIO: TIdServerSocketIOHandling read FSocketIO write FSocketIO;
    property OnDestroy: TIdContextEvent read FOnDestroy write FOnDestroy;
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;

    property Cookie      : string read FCookie write FCookie;
    property ClientIP    : string read GetClientIP write FClientIP;
    property Host        : string read FHost write FHost;
    property Origin      : string read FOrigin write FOrigin;
    property Path        : string read FPath write FPath;
    property Query       : string read FQuery write FQuery;
    property ResourceName: string read FResourceName write FResourceName;
    property Encoding    : string read FEncoding write FEncoding;
    property ServerSoftware: string read FServerSoftware write FServerSoftware;

    property ClientMaxWindowBits: Integer read FClientMaxWindowBits write FClientMaxWindowBits;
    property ServerMaxWindowBits: Integer read FServerMaxWindowBits write FServerMaxWindowBits;
    property SupportsPerMessageDeflate: Boolean read FSupportsPerMessageDeflate write FSupportsPerMessageDeflate;
    property WebSocketKey       : string  read FWebSocketKey write FWebSocketKey;
    property WebSocketProtocol  : string  read FWebSocketProtocol write FWebSocketProtocol;
    property WebSocketVersion   : Integer read FWebSocketVersion write FWebSocketVersion;
    property WebSocketExtensions: string  read FWebSocketExtensions write FWebSocketExtensions;
    property OnWebSocketUpgrade: TWebSocketUpgradeEvent read FOnWebSocketUpgrade write FOnWebSocketUpgrade;
    property OnCustomChannelExecute: TWebSocketChannelRequest read FOnCustomChannelExecute write FOnCustomChannelExecute;
  end;

implementation

uses
  Journeyman.WebSocket.SSLIOHandlers,
  IdIOHandlerStack, Journeyman.WebSocket.Consts;

{ TIdServerWSContext }
procedure TIdServerWSContext.AfterConstruction;
begin
  FClientMaxWindowBits := TClientMaxWindowBits.Disabled;
  FServerMaxWindowBits := TServerMaxWindowBits.Disabled;
  FSupportsPerMessageDeflate := False;
end;

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
  if Connection = nil then
    Exit(nil);
  Result := Connection.IOHandler as IIOHandlerWebSocket;
end;

function TIdServerWSContext.IsSocketIO: Boolean;
begin
  // FDocument	= '/socket.io/1/websocket/13412152'
  Result := StartsText('/socket.io/1/websocket/', FPath);
end;

end.
