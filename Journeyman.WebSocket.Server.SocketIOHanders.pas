unit Journeyman.WebSocket.Server.SocketIOHanders;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.StrUtils,
  IdContext, IdCustomTCPServer, IdException,
  //
//  IdServerBaseHandling,
  Journeyman.WebSocket.Types;
//  IdSocketIOHandling

type
  TIdServerSocketIOHandling = class(TIdBaseSocketIOHandling)
  protected
    procedure ProcessHeatbeatRequest(const AContext: ISocketIOContext;
      const AText: string); override;
  public
    function  SendToAll(const AMessage: string;
      const ACallback: TSocketIOMsgJSON = nil;
      const AOnError: TSocketIOError = nil): Integer;
    procedure SendTo   (const aContext: TIdServerContext;
      const AMessage: string; const ACallback: TSocketIOMsgJSON = nil;
      const AOnError: TSocketIOError = nil);
    function  EmitEventToAll(const AEventName: string; const AData: string;
      const ACallback: TSocketIOMsgJSON = nil;
      const AOnError: TSocketIOError = nil): Integer; overload;
  end;

implementation

{ TIdServerSocketIOHandling }

procedure TIdServerSocketIOHandling.ProcessHeatbeatRequest(
  const AContext: ISocketIOContext; const AText: string);
begin
  inherited ProcessHeatbeatRequest(AContext, AText);
end;






function TIdServerSocketIOHandling.EmitEventToAll(const AEventName,
  AData: string; const ACallback: TSocketIOMsgJSON;
  const AOnError: TSocketIOError): Integer;
var
  LContext: ISocketIOContext;
  LJsonArray: string;
begin
  Result := 0;
  LJsonArray := '[' + AData + ']';

  Lock;
  try
    for LContext in FConnections.Values do
    begin
      if LContext.IsDisconnected then
        Continue;

      try
        if not Assigned(ACallback) then
          WriteSocketIOEvent(LContext, ''{no room}, AEventName, LJsonArray, nil, nil)
        else
          WriteSocketIOEventRef(LContext, ''{no room}, AEventName, LJsonArray,
            procedure(const AData: string)
            begin
              ACallback(LContext, SO(AData), nil);
            end, AOnError);
      except
        // try to send to others
      end;
      Inc(Result);
    end;
    for LContext in FConnectionsGUID.Values do
    begin
      if LContext.IsDisconnected then
        Continue;

      try
        if not Assigned(ACallback) then
          WriteSocketIOEvent(LContext, ''{no room}, AEventName, LJsonArray, nil, nil)
        else
          WriteSocketIOEventRef(LContext, ''{no room}, AEventName, LJsonArray,
            procedure(const AData: string)
            begin
              ACallback(LContext, SO(AData), nil);
            end, AOnError);
      except
        // try to send to others
      end;
      Inc(Result);
    end;
  finally
    Unlock;
  end;
end;

procedure TIdServerSocketIOHandling.SendTo(const aContext: TIdServerContext;
  const AMessage: string; const ACallback: TSocketIOMsgJSON;
  const AOnError: TSocketIOError);
var
  context: ISocketIOContext;
begin
  Lock;
  try
    context := FConnections.Items[aContext];
    if context.IsDisconnected then
      raise EIdSocketIoUnhandledMessage.Create('socket.io connection closed!');

    if not Assigned(ACallback) then
      WriteSocketIOMsg(context, ''{no room}, AMessage, nil)
    else
      WriteSocketIOMsg(context, ''{no room}, AMessage,
        procedure(const AData: string)
        begin
          ACallback(context, SO(AData), nil);
        end, AOnError);
  finally
    Unlock;
  end;
end;

function TIdServerSocketIOHandling.SendToAll(const AMessage: string;
  const ACallback: TSocketIOMsgJSON; const AOnError: TSocketIOError): Integer;
var
  context: ISocketIOContext;
begin
  Result := 0;
  Lock;
  try
    for context in FConnections.Values do
    begin
      if context.IsDisconnected then
        Continue;

      if not Assigned(ACallback) then
        WriteSocketIOMsg(context, ''{no room}, AMessage, nil)
      else
        WriteSocketIOMsg(context, ''{no room}, AMessage,
          procedure(const AData: string)
          begin
            ACallback(context, SO(AData), nil);
          end, AOnError);
      Inc(Result);
    end;
    for context in FConnectionsGUID.Values do
    begin
      if context.IsDisconnected then
        Continue;

      if not Assigned(ACallback) then
        WriteSocketIOMsg(context, ''{no room}, AMessage, nil)
      else
        WriteSocketIOMsg(context, ''{no room}, AMessage,
          procedure(const AData: string)
          begin
            ACallback(context, SO(AData), nil);
          end);
      Inc(Result);
    end;
  finally
    Unlock;
  end;
end;

end.
