unit Journeyman.WebSocket.CompressUtils;

interface

uses
  System.SysUtils;

function CompressMessage(const Input: TBytes; maxWindowBits: Integer): TBytes;
function DecompressMessage(const Input: TBytes; maxWindowBits: Integer): TBytes;

implementation

uses
  System.ZLib, System.Classes;

function CompressMessage(const Input: TBytes; maxWindowBits: Integer): TBytes;
var
  Compressor: TZCompressionStream;
  InputStream, OutputStream: TStream;
begin
  OutputStream := TMemoryStream.Create;
  try
    InputStream := TMemoryStream.Create;
    try
      InputStream.Write(Input, Length(Input));
      Compressor := TZCompressionStream.Create(OutputStream, zcDefault, maxWindowBits);
      try
        InputStream.Position := 0;
        Compressor.CopyFrom(InputStream, InputStream.Size);
      finally
        Compressor.Free;
      end;
      SetLength(Result, OutputStream.Size);
      OutputStream.Position := 0;
      OutputStream.ReadBuffer(Result[0], OutputStream.Size);
    finally
      InputStream.Free;
    end;
  finally
    OutputStream.Free;
  end;
end;

function DecompressMessage(const Input: TBytes; maxWindowBits: Integer): TBytes;
var
  Decompressor: TZDecompressionStream;
  InputStream, OutputStream: TMemoryStream;
begin
  InputStream := TMemoryStream.Create;
  try
    InputStream.WriteBuffer(Input[0], Length(Input));
    InputStream.Position := 0;
    OutputStream := TMemoryStream.Create;
    try
      Decompressor := TZDecompressionStream.Create(InputStream, maxWindowBits);
      try
        OutputStream.CopyFrom(Decompressor, 0);
      finally
        Decompressor.Free;
      end;
      SetLength(Result, OutputStream.Size);
      OutputStream.Position := 0;
      OutputStream.ReadBuffer(Result[0], OutputStream.Size);
    finally
      OutputStream.Free;
    end;
  finally
    InputStream.Free;
  end;
end;

end.
