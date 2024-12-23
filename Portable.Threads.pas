unit Portable.Threads;

interface

uses
{$IF DEFINED(ANDROID)}
  FMX.Helpers.Android;
{$ELSE}
  System.Classes;
{$ENDIF}

type
{$IF DECLARED(FMX.Helpers.Android.TMethodCallback)}
  TMethodCallback = FMX.Helpers.Android.TMethodCallback;
  TCallBack = FMX.Helpers.Android.TCallBack;
{$ELSEIF DECLARED(System.Classes.TThreadMethod)}
  TMethodCallback = System.Classes.TThreadMethod;
  TCallBack = System.Classes.TThreadProcedure;
{$ENDIF} // System.Threading

procedure CallInUIThread(const AMethod: TMethodCallback); overload;
procedure CallInUIThread(const AMethod: TCallBack); overload;

implementation

procedure CallInUIThread(const AMethod: TMethodCallback);
begin
{$IF DECLARED(FMX.Helpers.Android.CallInUIThread)}
  FMX.Helpers.Android.CallInUIThread(AMethod);
{$ELSE}
  TThread.ForceQueue(nil, AMethod);
{$ENDIF}
end;

procedure CallInUIThread(const AMethod: TCallBack);
begin
{$IF DECLARED(FMX.Helpers.Android.CallInUIThread)}
  FMX.Helpers.Android.CallInUIThread(AMethod);
{$ELSE}
  TThread.ForceQueue(nil, AMethod);
{$ENDIF}
end;

end.
