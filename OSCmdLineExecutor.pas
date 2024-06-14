unit OSCmdLineExecutor;
interface
uses windows,classes;

type
  TOSCommandLineExecutor = class;
  TOSCmdLineOutputProc = procedure(sender:TOSCommandLineExecutor; const txt:string) of object;

  
  /// <summary>
  /// Runs a command line command and captures its stdout/stderr 
  /// </summary>
  TOSCommandLineExecutor = class(TComponent)
  public
    type TLogProc = reference to procedure(txt:string); 
  private
    type
       TPipeHandles = record
          hRead, hWrite: THandle;
       end;
    var FCmdLine: string;
        FWorkDir: string;
        PipeStdOut,PipeStdErr,pipeStdIn: TPipeHandles;
        StartupInfo: TStartupInfo;
        FOnStdOut: TOSCmdLineOutputProc;
        FOnStdErr: TOSCmdLineOutputProc;
        FOnIdle : TNotifyEvent;
        FAnonProcStdOut,FAnonProcStdErr:TLogProc;
    procedure ClearPipe(var pipe:TPipeHandles);
    procedure InitPipe(var Pipe:TPipeHandles;SecAttr : TSecurityAttributes);
    procedure ClosePipe(var Pipe: TPipeHandles);
    function ReadPipe(var Pipe: TPipeHandles):AnsiString;
    procedure InitStartupInfo;
    procedure LogOutput(var msg:AnsiString;IsError:boolean);
  public
    function Execute: DWORD; overload;                  
    function Execute(StdErrProc,StdOutProc:TLogProc):DWORD; overload; 
    function Execute(OutProc:TLogProc):DWORD; overload;               
  published
    property OnStdOut : TOSCmdLineOutputProc read FOnStdOut write FOnStdOut;
    property OnStdErr : TOSCmdLineOutputProc read FOnStdErr write FOnStdErr;
    property OnIdle : TNotifyEvent read FOnIdle write FOnIdle; 
    property WorkDir:string read FWorkDir write FWorkDir; 
    property CmdLine:string read FCmdLine write FCmdLine;    
  end;


procedure Register;

implementation
uses sysutils;

const BufSize = $4000;

procedure TOSCommandLineExecutor.ClearPipe(var pipe:TPipeHandles);
begin
  pipe.hRead := 0;
  pipe.hWrite := 0;
end;

procedure TOSCommandLineExecutor.InitPipe(var Pipe:TPipeHandles;SecAttr : TSecurityAttributes);
begin
  if not CreatePipe (pipe.hRead, pipe.hWrite, @SecAttr, BufSize) then
     Raise Exception.Create('Can''t Create pipe!');
end;

procedure TOSCommandLineExecutor.ClosePipe(var Pipe: TPipeHandles);
begin
  if Pipe.hRead  <> 0 then CloseHandle (Pipe.hRead);
  if Pipe.hWrite <> 0 then CloseHandle (Pipe.hWrite);
  ClearPipe(Pipe);
end;

function TOSCommandLineExecutor.ReadPipe(var Pipe: TPipeHandles):AnsiString;
var ReadBuf: array[0..BufSize] of AnsiChar;
    BytesRead: Dword;
begin
   result := '';
   if not PeekNamedPipe(Pipe.hRead, nil, 0, nil, @BytesRead, nil) or (BytesRead <= 0) then exit;

   ReadFile( Pipe.hRead, ReadBuf, BufSize, BytesRead, nil);
   if BytesRead <= 0 then exit;

   ReadBuf[BytesRead] := #0;
   result := pAnsichar(@readbuf[0]);
end;



procedure TOSCommandLineExecutor.InitStartupInfo;
begin
   FillChar(StartupInfo,SizeOf(TStartupInfo), 0);
   StartupInfo.cb          := SizeOf(TStartupInfo);
   StartupInfo.dwFlags     := STARTF_USESTDHANDLES;
   StartupInfo.hStdOutput  := PipeStdOut.hWrite;
   StartupInfo.hStdError   := PipeStdErr.hWrite;
   StartupInfo.hStdInput   := PipeStdIn.hRead;
   StartupInfo.wShowWindow := SW_HIDE;
end;


procedure TOSCommandLineExecutor.LogOutput(var msg:AnsiString;IsError:boolean);
var newLinePosition:integer;
    newLineSeparatorLength:integer;

    procedure LocateNewLineSeparator;
    var p0,p1,p2:integer;
    begin
       p0 := pos(AnsiString(#13#10),msg);
       p1 := pos(AnsiChar(#13),msg);
       p2 := pos(AnsiChar(#10),msg);

       if (p1 >= p0) and (p2 >= p0) then begin
          newLineSeparatorLength := 2;
          newLinePosition := p0;
       end else begin
          newLineSeparatorLength := 1;
          if      p1 <=0  then newLinePosition := p2
          else if p2 <=0  then newLinePosition := p1
          else if p1 < p2 then newLinePosition := p1
          else newLinePosition := p2;
       end;
    end;

var s:String;
begin
    LocateNewLineSeparator;
    while newLinePosition>=1 do begin
       s := String(copy( msg,1,newLinePosition-1));

       if IsError then begin
          if Assigned(FOnStdErr) then
             FOnStdErr(self,s);
          if Assigned(FAnonProcStdErr) then
             FAnonProcStdErr(s);
       end;

       if not IsError then begin
          if Assigned(FOnStdOut) then
             FOnStdOut(self,s);
          if Assigned(FAnonProcStdOut) then
             FAnonProcStdOut(s);
       end;

       msg := copy(msg,newLinePosition+newLineSeparatorLength,length(msg));
       LocateNewLineSeparator;
    end;
end;



function  TOSCommandLineExecutor.Execute(StdErrProc,StdOutProc:TLogProc):DWORD; // returns the exit code of the process
var SecAttr : TSecurityAttributes;

    function DoExecuteProcess:DWORD;
    var  strError,strOut:AnsiString;
         ProcessInformation:TProcessInformation;
    begin
       if not CreateProcess(
                 nil, PChar(FCmdLine), nil, nil, True,
                 NORMAL_PRIORITY_CLASS or CREATE_NO_WINDOW,
                 nil, PChar(FWorkDir),
                 StartupInfo,
                 ProcessInformation ) 
          then  Raise Exception.create('Cannot create process for '+FCmdLine+ #13#10+SysErrorMessage(GetLastError));
      result := STILL_ACTIVE;

      strError := '';
      strOut    := '';
      try
         repeat
             WaitForSingleObject(ProcessInformation.hProcess, 100);
             GetExitCodeProcess(ProcessInformation.hProcess,result);
             if assigned(FOnIdle) then
               FOnIdle(self);
             strError := strError + ReadPipe(PipeStdErr);
             StrOut    := StrOut    + ReadPipe(PipeStdOut);
             LogOutput(strError,true);
             LogOutput(strOut,False);
         until result <> STILL_ACTIVE;

         if not GetExitCodeProcess(ProcessInformation.hProcess,result) then
              Raise Exception.Create('Cannot get exit code!');

         result := result;
      finally
         if result = STILL_ACTIVE then TerminateProcess(ProcessInformation.hProcess, 1);
         CloseHandle(ProcessInformation.hProcess);
         CloseHandle(ProcessInformation.hThread);
         ProcessInformation.hProcess := 0;
      end;
    end;

begin
  FAnonProcStdOut :=  StdOutProc;
  FAnonProcStdErr :=  StdErrProc;
  try
     SecAttr.nLength              := SizeOf(SecAttr);
     SecAttr.lpSecurityDescriptor := nil;
     SecAttr.bInheritHandle       := TRUE;

     ClearPipe(pipeStdIn);
     ClearPipe(PipeStdErr);
     ClearPipe(PipeStdOut);
     try
       InitPipe(PipeStdIn,SecAttr);
       InitPipe(PipeStdErr,SecAttr);
       InitPipe(PipeStdOut,SecAttr);
       // child process must not inherit stdin/stdout/stderr stream handles from the current process
       if not SetHandleInformation(pipeStdIn.hWrite, HANDLE_FLAG_INHERIT, 0)  then
            Raise Exception.Create('error calling SetHandleInformation for pipeStdIn.hWrite');
       if not SetHandleInformation(pipeStdOut.hRead, HANDLE_FLAG_INHERIT, 0)  then
            Raise Exception.Create('error calling SetHandleInformation for pipeStdOut.hRead');
       if not SetHandleInformation(PipeStdErr.hRead, HANDLE_FLAG_INHERIT, 0) then
            Raise Exception.Create('error calling SetHandleInformation for PipeStdErr.hRead');
       InitStartupInfo;
       result := DoExecuteProcess;
     finally
       ClosePipe(PipeStdOut);
       ClosePipe(PipeStdErr);
       ClosePipe(PipeStdIn);
     end;
  finally
     FAnonProcStdOut := nil;
     FAnonProcStdErr := nil;
  end;
end;

function TOSCommandLineExecutor.Execute: DWORD;
begin
   result := Execute(nil,nil);
end;

function TOSCommandLineExecutor.Execute(OutProc:TLogProc):DWORD;
begin
   result := Execute(OutProc,OutProc);
end;

procedure Register;
begin
//  RegisterComponents('CSTools',[TOSCommandLineExecutor]);
end;

end.

