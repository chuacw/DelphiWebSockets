unit IdServerSocketIOHandling;
interface
{$I wsdefines.pas}

uses
  Classes, Generics.Collections, SysUtils, StrUtils
  , IdContext
  , IdCustomTCPServer
  , IdException
  //
  {$IFDEF SUPEROBJECT}
  , superobject
  {$ENDIF}
  , IdServerBaseHandling
  , IdSocketIOHandling
  ;

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
    {$IFDEF SUPEROBJECT}
    function  EmitEventToAll(const AEventName: string;
      const AData: ISuperObject; const ACallback: TSocketIOMsgJSON = nil;
      const AOnError: TSocketIOError = nil): Integer; overload;
    procedure EmitEventTo(const aContext: TIdServerContext;
      const AEventName: string; const AData: ISuperObject;
      const ACallback: TSocketIOMsgJSON = nil;
      const AOnError: TSocketIOError = nil); overload;
    procedure EmitEventTo(const aContext: ISocketIOContext;
      const AEventName: string; const AData: ISuperObject;
      const ACallback: TSocketIOMsgJSON = nil;
      const AOnError: TSocketIOError = nil);overload;
    {$ENDIF}
  end;

implementation

{ TIdServerSocketIOHandling }

procedure TIdServerSocketIOHandling.ProcessHeatbeatRequest(
  const AContext: ISocketIOContext; const AText: string);
begin
  inherited ProcessHeatbeatRequest(AContext, AText);
end;

{$IFDEF SUPEROBJECT}
procedure TIdServerSocketIOHandling.EmitEventTo(
  const aContext: ISocketIOContext; const AEventName: string;
  const AData: ISuperObject; const ACallback: TSocketIOMsgJSON;
  const AOnError: TSocketIOError);
var
  jsonarray: string;
begin
  if aContext.IsDisconnected then
    raise EIdSocketIoUnhandledMessage.Create('socket.io connection closed!');

  if AData.IsType(stArray) then
    jsonarray := AData.AsString
  else if AData.IsType(stString) then
    jsonarray := '["' + AData.AsString + '"]'
  else
    jsonarray := '[' + AData.AsString + ']';

  if not Assigned(ACallback) then
    WriteSocketIOEvent(aContext, ''{no room}, AEventName, jsonarray, nil, nil)
  else
    WriteSocketIOEventRef(aContext, ''{no room}, AEventName, jsonarray,
      procedure(const AData: string)
      begin
        ACallback(aContext, SO(AData), nil);
      end, AOnError);
end;

procedure TIdServerSocketIOHandling.EmitEventTo(
  const aContext: TIdServerContext; const AEventName: string;
  const AData: ISuperObject; const ACallback: TSocketIOMsgJSON;
  const AOnError: TSocketIOError);
var
  context: ISocketIOContext;
begin
  Lock;
  try
    context := FConnections.Items[aContext];
    EmitEventTo(context, AEventName, AData, ACallback, AOnError);
  finally
    Unlock;
  end;
end;

function TIdServerSocketIOHandling.EmitEventToAll(const AEventName: string;
  const AData: ISuperObject; const ACallback: TSocketIOMsgJSON;
  const AOnError: TSocketIOError): Integer;
begin
  if AData.IsType(stString) then
    Result := EmitEventToAll(AEventName, '"' + AData.AsString + '"', ACallback, AOnError)
  else
    Result := EmitEventToAll(AEventName, AData.AsString, ACallback, AOnError);
end;
{$ENDIF}

function TIdServerSocketIOHandling.EmitEventToAll(const AEventName,
  AData: string; const ACallback: TSocketIOMsgJSON;
  const AOnError: TSocketIOError): Integer;
var
  context: ISocketIOContext;
  jsonarray: string;
begin
  Result := 0;
  jsonarray := '[' + AData + ']';

  Lock;
  try
    for context in FConnections.Values do
    begin
      if context.IsDisconnected then
        Continue;

      try
        if not Assigned(ACallback) then
          WriteSocketIOEvent(context, ''{no room}, AEventName, jsonarray, nil, nil)
        else
          WriteSocketIOEventRef(context, ''{no room}, AEventName, jsonarray,
            procedure(const AData: string)
            begin
              ACallback(context, SO(AData), nil);
            end, AOnError);
      except
        //try to send to others
      end;
      Inc(Result);
    end;
    for context in FConnectionsGUID.Values do
    begin
      if context.IsDisconnected then
        Continue;

      try
        if not Assigned(ACallback) then
          WriteSocketIOEvent(context, ''{no room}, AEventName, jsonarray, nil, nil)
        else
          WriteSocketIOEventRef(context, ''{no room}, AEventName, jsonarray,
            procedure(const AData: string)
            begin
              ACallback(context, SO(AData), nil);
            end, AOnError);
      except
        //try to send to others
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
