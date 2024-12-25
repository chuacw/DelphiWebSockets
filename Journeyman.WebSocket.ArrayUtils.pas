unit Journeyman.WebSocket.ArrayUtils;

interface

procedure RemoveEmptyElements(var VArray: TArray<string>);

implementation

procedure RemoveEmptyElements(var VArray: TArray<string>);
begin
  for var I := High(VArray) downto Low(VArray) do
    if VArray[I] = '' then
      Delete(VArray, I, 1);
end;

end.
