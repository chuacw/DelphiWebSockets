unit Journeyman.WebSocket.Exceptions;

interface

uses
  IdStack, IdException, IdHTTP;

type

  EIdSocketError = IdStack.EIdSocketError;
  EIdHTTPProtocolException = IdHTTP.EIdHTTPProtocolException;

  EIdWebSocketException = class(EIdException);
  EIdWebSocketHandleError = class(EIdSocketHandleError);

implementation

end.
