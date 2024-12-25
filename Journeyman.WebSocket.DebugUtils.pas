unit Journeyman.WebSocket.DebugUtils;

interface

{$IF DEFINED(DEBUG) OR DEFINED(DEBUG_WS) OR DEFINED(CHECKSPEED)}
uses
  {$IF DEFINED(MSWINDOWS)}
    Winapi.Windows,
  {$ENDIF}
  System.SysUtils;
{$ENDIF}

/// <summary>Helps in debugging. If WS_DEBUG is not defined, this is a NO-OP as
/// all the code are IF DEFINED out.</summary>
procedure OutputDebugString(const ARoleName, AMsg: string); overload; {$IF NOT DEFINED(WS_DEBUG)} inline; {$ENDIF}
procedure OutputDebugString(const ARoleName, AFormatMsg: string;
  const AArguments: array of const); overload;
/// <summary>Helps in debugging. If WS_DEBUG is not defined, this is a NO-OP as
/// all the code are IF DEFINED out.</summary>
procedure OutputDebugString(const AMsg: string); overload;
procedure OutputDebugString(const AFormatMsg: string; const AArguments: array of const); overload;
procedure OutputDebugString(Number: Integer; Elapsed: Int64); overload;

implementation

uses
  System.Classes,
{$IF DEFINED(ANDROID)}
  FMX.Platform, FMX.Platform.Logger.Android.Fix,
{$ENDIF}
  System.SyncObjs;

procedure OutputDebugString(const ARoleName, AMsg: string);
begin

{$IF DEFINED(DEBUG) OR DEFINED(DEBUG_WS) OR DEFINED(CHECKSPEED)}
var
  LMsg: string;
{$ENDIF}

{$IF DEFINED(DEBUG) OR DEFINED(DEBUG_WS) OR DEFINED(CHECKSPEED)}
  var LDateTime := FormatDateTime('hh:nn:ss', Now);
  {$IF DEFINED(MSWINDOWS)}
    LMsg := Format('%s - %s - %s', [LDateTime, ARoleName, AMsg]);
    Winapi.Windows.OutputDebugString(PChar(LMsg));
  {$ELSEIF DEFINED(ANDROID)}
    LMsg := Format('%s - %s', [ARoleName, AMsg]);
    var LLogService: IFMXLoggingService;
    if TPlatformServices.Current.SupportsPlatformService(IFMXLoggingService, LLogService) then
     begin
       var LTagService: IFMXTagPriority;
       if Supports(LLogService, IFMXTagPriority, LTagService) then
         LTagService.d(ARoleName, LMsg) else
         LLogService.Log('%s', [LMsg]);
     end;
  {$ENDIF}
{$ENDIF}
end;

procedure OutputDebugString(const ARoleName, AFormatMsg: string;
  const AArguments: array of const);
var
  LMsg: string;
begin
  LMsg := Format(AFormatMsg, AArguments);
  OutputDebugString(ARoleName, LMsg);
end;
procedure OutputDebugString(const AMsg: string);
{$IF DEFINED(DEBUG)}
var
  LDateTime, LMsg: string;
{$IF DEFINED(ANDROID)}
  LLogService: IFMXLoggingService;
{$ENDIF}
{$ENDIF}
begin
{$IF DEFINED(DEBUG) OR DEFINED(DEBUG_WS) OR DEFINED(CHECKSPEED)}
  LDateTime := FormatDateTime('hh:nn:ss', Now);
  LMsg := Format('%s - %s', [LDateTime, AMsg]);
  {$IF DECLARED(Winapi.Windows.OutputDebugString) AND DEFINED(DEBUG_WS)}
  Winapi.Windows.OutputDebugString(PChar(LMsg));
  {$ENDIF}
  {$IF DEFINED(ANDROID)}
   if TPlatformServices.Current.SupportsPlatformService(IFMXLoggingService, LLogService) then
     begin
       LLogService.Log('%s', [LMsg]);
     end;
  {$ENDIF}
{$ENDIF}
end;
procedure OutputDebugString(const AFormatMsg: string; const AArguments: array of const);
var
  LMsg: string;
begin
  LMsg := Format(AFormatMsg, AArguments);
  OutputDebugString(LMsg);
end;

procedure OutputDebugString(Number: Integer; Elapsed: Int64);
{$IF DEFINED(DEBUG) OR DEFINED(DEBUG_WS) OR DEFINED(CHECKSPEED)}
var
  LMsg: string;
{$IF DEFINED(ANDROID)}
  LLogService: IFMXLoggingService;
{$ENDIF}
{$ENDIF}
begin
  if Elapsed < 500 then
    Exit;
{$IF DEFINED(DEBUG) OR DEFINED(DEBUG_WS) OR DEFINED(CHECKSPEED)}
  LMsg := Format('%d: %d', [Number, Elapsed]);
  {$IF DECLARED(Winapi.Windows.OutputDebugString) AND DEFINED(DEBUG_WS)}
  Winapi.Windows.OutputDebugString(PChar(LMsg));
  {$ENDIF}
  {$IF DEFINED(ANDROID)}
   if TPlatformServices.Current.SupportsPlatformService(IFMXLoggingService, LLogService) then
     begin
       LLogService.Log('%s', [LMsg]);
     end;
  {$ENDIF}
{$ENDIF}
end;

end.
