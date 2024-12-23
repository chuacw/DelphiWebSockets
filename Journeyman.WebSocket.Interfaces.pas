unit Journeyman.WebSocket.Interfaces;

interface

uses
  System.Classes, IdGlobal, IdSocketHandle, IdBuffer, Journeyman.WebSocket.Types,
  System.SysUtils;

type
  {$IF CompilerVersion >= 26}   // XE5
  TIdTextEncoding = IIdTextEncoding;
  {$ENDIF}
  ISetWebSocketClosing = interface
    ['{7EB09E63-DF10-472E-8B1C-DAB7EAE2164E}']
    procedure SetWebSocketClosing(const AValue: TOnWebSocketClosing);
  end;

  IIOHandlerWebSocket = interface
    ['{6F5E19B2-7D2D-436D-B5A7-063C2B4E59B8}']
    function  CheckForDataOnSource(ATimeout: Integer = 0): Boolean;
    procedure CheckForDisconnect(ARaiseExceptionIfDisconnected: Boolean;
      AIgnoreBuffer: Boolean);
    procedure Clear;
    procedure Close;
    procedure CloseWithReason(const AReason: string);
    function  GetBinding: TIdSocketHandle;
    function  GetBusyUpgrading: Boolean;
    function  GetClosedGracefully: Boolean;
    function  GetCloseReason: string;
    function  GetConnected: Boolean;
    function  GetInputBuffer: TIdBuffer;
    function  GetIsWebSocket: Boolean;
    function  GetLastPingTime: TDateTime;
    function  GetLastActivityTime: TDateTime;
    function  GetOnNotifyClosed: TProc;
    function  GetOnNotifyClosing: TProc;
    function  HasData: Boolean;
    procedure Lock;
    function  ReadLongWord(AConvert: Boolean = True): UInt32;
    procedure ReadStream(AStream: TStream; AByteCount: TIdStreamSize = -1;
      AReadUntilDisconnect: Boolean = False);
    function  Readable(AMSec: Integer = IdTimeoutDefault): Boolean;
    function  ReadUInt32(AConvert: Boolean = True): UInt32;
    procedure SetBusyUpgrading(const Value: Boolean);
    procedure SetClosedGracefully(const Value: Boolean);
    procedure SetCloseReason(const AReason: string);
    procedure SetIsWebSocket(const Value: Boolean);
    procedure SetLastActivityTime(const Value: TDateTime);
    procedure SetLastPingTime(const Value: TDateTime);
    procedure SetOnNotifyClosed(const Value: TProc);
    procedure SetOnNotifyClosing(const Value: TProc);
    procedure SetUseNagle(const Value: Boolean);
    function  TryLock: Boolean;
    procedure Unlock;
    procedure Write(const ABuffer: TIdBytes; const ALength: Integer = -1;
      const AOffset: Integer = 0); overload;
    procedure Write(const AOut: string; AEncoding: TIdTextEncoding = nil); overload;
    procedure Write(AStream: TStream; AType: TWSDataType); overload;
    procedure WriteBin(const ABytes: TArray<Byte>);
    function  WriteData(const AData: TIdBytes; AType: TWSDataCode;
      aFIN: boolean = true; aRSV1: boolean = false; aRSV2: boolean = false;
      aRSV3: boolean = false): integer;
    procedure WriteLn(AEncoding: IIdTextEncoding = nil); overload;
    procedure WriteLn(const AOut: string; AByteEncoding: IIdTextEncoding = nil); overload;

    property  Binding: TIdSocketHandle read GetBinding;
    property  BusyUpgrading: Boolean read GetBusyUpgrading write SetBusyUpgrading;
    property  ClosedGracefully: Boolean read GetClosedGracefully write SetClosedGracefully;
    property  CloseReason: string read GetCloseReason write SetCloseReason;
    property  Connected: Boolean read GetConnected;
    property  InputBuffer: TIdBuffer read GetInputBuffer;
    property  IsWebSocket: Boolean read GetIsWebSocket write SetIsWebSocket;
    property  LastActivityTime: TDateTime read GetLastActivityTime write SetLastActivityTime;
    property  LastPingTime: TDateTime read GetLastPingTime write SetLastPingTime;
    property  OnNotifyClosed: TProc read GetOnNotifyClosed write SetOnNotifyClosed;
    property  OnNotifyClosing: TProc read GetOnNotifyClosing write SetOnNotifyClosing;
    property  UseNagle: Boolean write SetUseNagle;
  end;

implementation

end.
