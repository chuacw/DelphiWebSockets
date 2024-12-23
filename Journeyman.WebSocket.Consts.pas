unit Journeyman.WebSocket.Consts;

interface

uses
{$IF DEFINED(MSWINDOWS)}
  IdWinSock2;
{$ELSEIF DEFINED(POSIX)}
  Posix.SysSocket;
{$ENDIF}

const
  SConnection: string          = 'Connection';
  SHTTPCookieHeader: string    = 'Cookie';
  SHTTPHostHeader: string      = 'Host';
  SHTTPOriginHeader: string    = 'Origin';
  SKeepAlive: string           = 'keep-alive';
  SNoCache: string             = 'no-cache';
  SServer: string              = 'Server';
  SSwitchingProtocols: string  = 'Switching Protocols';
  SUpgrade: string             = 'Upgrade';
  SWebSocket: string           = 'websocket';
  SWebSocketAccept: string     = 'Sec-WebSocket-Accept';
  SWebSocketExtensions: string = 'Sec-WebSocket-Extensions';
  SWebSocketGUID: string       = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
  SWebSocketKey: string        = 'Sec-WebSocket-Key';
  SWebSocketProtocol: string   = 'Sec-WebSocket-Protocol';
  SWebSocketVersion: string    = 'Sec-WebSocket-Version';

  CSwitchingProtocols: Int16   = 101;
  CNoContent: Int16            = 204;
  MSG_OOB                      = $01;                  // Process out-of-band data.

{$IF DEFINED(MSWINDOWS)}
  SIZE_INTEGER = IdWinSock2.SIZE_INTEGER;
{$ELSEIF DEFINED(ANDROID)}
  SIZE_INTEGER = SizeOf(Integer);
{$ENDIF}
  SO_ERROR            = $1007;      // get error status and clear
  SOCK_NONBLOCK       = $800;


// close frame codes
/// <summary> 1000 indicates a normal closure, meaning that the purpose for
/// which the connection was established has been fulfilled.</summary>
  C_FrameClose_Normal            = 1000;

/// <summary> 1001 indicates that an endpoint is "going away", such as a server
/// going down or a browser having navigated away from a page.</summary>
  C_FrameClose_GoingAway         = 1001;

/// <summary> 1002 indicates that an endpoint is terminating the connection due
/// to a protocol error.</summary>
  C_FrameClose_ProtocolError     = 1002;

/// <summary> 1003 indicates that an endpoint is terminating the connection
/// because it has received a type of data it cannot accept (e.g., an
/// endpoint that understands only text data MAY send this if it
/// receives a binary message).</summary>
  C_FrameClose_UnhandledDataType = 1003;

/// <summary> Reserved.  The specific meaning might be defined in the future.</summary>
  C_FrameClose_Reserved          = 1004;

/// <summary> 1005 is a reserved value and MUST NOT be set as a status code in a
/// Close control frame by an endpoint.  It is designated for use in
/// applications expecting a status code to indicate that no status
/// code was actually present.</summary>
  C_FrameClose_ReservedNoStatus  = 1005;

/// <summary> 1006 is a reserved value and MUST NOT be set as a status code in a
/// Close control frame by an endpoint.  It is designated for use in
/// applications expecting a status code to indicate that the
/// connection was closed abnormally, e.g., without sending or
/// receiving a Close control frame.</summary>
  C_FrameClose_ReservedAbnormal  = 1006;

/// <summary> 1007 indicates that an endpoint is terminating the connection
/// because it has received data within a message that was not
/// consistent with the type of the message (e.g., non-UTF-8 [RFC3629]
/// data within a text message).</summary>
  C_FrameClose_InconsistentData  = 1007;

/// <summary> 1008 indicates that an endpoint is terminating the connection
/// because it has received a message that violates its policy.  This
/// is a generic status code that can be returned when there is no
/// other more suitable status code (e.g., 1003 or 1009) or if there
/// is a need to hide specific details about the policy.</summary>
  C_FrameClose_PolicyError       = 1008;

/// <summary> 1009 indicates that an endpoint is terminating the connection
/// because it has received a message that is too big for it to process.</summary>
  C_FrameClose_ToBigMessage      = 1009;

/// <summary> 1010 indicates that an endpoint (client) is terminating the
/// connection because it has expected the server to negotiate one or
/// more extension, but the server didn't return them in the response
/// message of the WebSocket handshake.  The list of extensions that
/// are needed SHOULD appear in the /reason/ part of the Close frame.
/// Note that this status code is not used by the server, because it
/// can fail the WebSocket handshake instead.</summary>
  C_FrameClose_MissingExtenstion = 1010;

/// <summary> 1011 indicates that a server is terminating the connection because
/// it encountered an unexpected condition that prevented it from
/// fulfilling the request.</summary>
  C_FrameClose_UnExpectedError   = 1011;

/// <summary>1015 is a reserved value and MUST NOT be set as a status code in a
/// Close control frame by an endpoint.  It is designated for use in
/// applications expecting a status code to indicate that the
/// connection was closed due to a failure to perform a TLS handshake
/// (e.g., the server certificate can't be verified).</summary>
  C_FrameClose_ReservedTLSError  = 1015;

// frame codes
  C_FrameCode_Continuation = 0;
  C_FrameCode_Text         = 1;
  C_FrameCode_Binary       = 2;
  // 3-7 are reserved for further non-control frames
  C_FrameCode_Close        = 8;
  C_FrameCode_Ping         = 9;
  C_FrameCode_Pong         = 10 {A};
  // B-F are reserved for further control frames

implementation

end.
