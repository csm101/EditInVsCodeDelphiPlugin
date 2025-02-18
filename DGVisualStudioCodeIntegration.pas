unit DGVisualStudioCodeIntegration;

interface

procedure Register;

implementation
uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,                                                                 
  ToolsAPI,
  Vcl.Menus,
  OSCmdLineExecutor,
  Vcl.Dialogs,
  Vcl.ActnList,
  Vcl.Forms,
  Winapi.Windows,
  WinApi.ShellAPI;



// Returns true if the module was saved successfully (or it didn't need to be saved)
function SaveModule(Module: IOTAModule): boolean;
var 
  i: Integer;
  editor: IOTAEditor;
begin
  for i := 0 to Module.ModuleFileCount - 1 do begin
    editor := Module.ModuleFileEditors[i];
    if not Editor.Modified then
      continue;
    exit(Module.Save(False, True));
  end;
  exit(true);
end;

function SaveAllModules:boolean;
var
  Services: IOTAModuleServices;
  I: Integer;
  Module: IOTAModule;
begin
  result:=false;
  Services := BorlandIDEServices as IOTAModuleServices;
  for I := 0 to Services.ModuleCount - 1 do begin
    Module := Services.Modules[I];
    if not SaveModule(Module) then
      exit;
  end;
  result := true;
end;

function FindSourceEditor(Module: IOTAModule; const FileExtensions: array of string): IOTASourceEditor;
var 
  i: Integer;
  editor: IOTAEditor;
begin
  for i := 0 to Module.ModuleFileCount - 1 do
  begin
    editor := Module.ModuleFileEditors[i];
    if not Supports(editor, IOTASourceEditor, Result) then
      continue;
    var ext := ExtractFileExt(Result.FileName).toUpper;
    for var scan in FileExtensions do
      if scan = ext then
        exit;
  end;

  Result := nil;
end;

type TCurrentSourceFileInfos = record
  FileName: string;
  Line: Integer;
  Column: Integer;
end;

function GetCurrentSourceFileInfos: TCurrentSourceFileInfos;
var  EditView: IOTAEditView;
begin
  var Services := BorlandIDEServices as IOTAModuleServices;

  var Module := Services.CurrentModule;
  if Module = nil then
    raise Exception.Create('Current module not found');

  var editor := FindSourceEditor(Module, ['.PAS', '.DPR', '.INC', '.DPK','.DFM','.FMX']);

  if editor = nil then
    raise Exception.Create('Current module does not contain a source editor');
  if editor.EditViewCount = 0 then
     raise Exception.Create('Current module does not have visibile source code editors');

  Result.FileName := editor.FileName;
  result.Line := -1;
  result.Column := -1;

  EditView := editor.GetEditView(0); // Assume we always work with the first view
  if EditView <> nil then begin
    Result.Line := EditView.CursorPos.Line;
    Result.Column := EditView.CursorPos.Col;
  end
end;


procedure OpenCurrentFileInVisualStudioCode;
begin
  var Services := BorlandIDEServices as IOTAModuleServices;
  var sourceInfos: TCurrentSourceFileInfos;
  try
    sourceInfos := GetCurrentSourceFileInfos;
  except 
    on E: Exception do begin
      ShowMessage(E.Message);
      Exit;
    end;
  end;

  var FileName := sourceInfos.FileName;
  var project := (BorlandIDEServices as IOTAModuleServices).GetActiveProject;

  if project = nil then begin
       ShowMessage('No active project found');
       exit;
  end;

  var ProjectPath := ExtractFilePath(project.FileName);

  if not SaveAllModules then
    exit;

  var cmdline:string;
  if sourceInfos.Line < 0 then
    cmdline := Format('cmd /c "code --reuse-window %s"', [ProjectPath])
  else
    cmdline := Format('cmd /c "code --reuse-window %s -g %s:%d:%d"', [ProjectPath, FileName, sourceInfos.Line, sourceInfos.Column]);


  var executor := TOSCommandLineExecutor.Create(nil);
  try
     executor.WorkDir := ExtractFilePath(filename);
     executor.CmdLine := Cmdline;
     executor.Execute(
       procedure(Txt: string)
       begin
        ShowMessage(Format('Execution error: %s', [Txt]));
       end, nil);
  finally
     executor.Free;
  end;
end;


type
  TMenuHandler = class
  strict private
     Item:TMenuItem;
     Action: TProc;
     procedure OnExecute(Sender: TObject);
     Constructor Create(aCaption:String; aAction:TProc; aShortcut: String);
  class var
     MenuHandlers : TObjectList<TMenuHandler>;
     FActionList: TActionList;
  public
     destructor Destroy; override;
     class constructor create;
     class destructor Destroy;
     class procedure AddMenuItem(NTAServices: INTAServices; aCaption:String; aAction:TProc; aShortcut: String = '');
   end;

class constructor TMenuHandler.Create;
begin
   MenuHandlers := TObjectList<TMenuHandler>.Create;
   FActionList := TActionList.Create(nil);
end;

class destructor TMenuHandler.Destroy;
begin
   MenuHandlers.free;
   FActionList.Free;
end;

Constructor TMenuHandler.Create(aCaption:String; aAction:TProc;aShortcut: String);
var
  MyAction: TAction;
begin
  inherited Create;
  Action := aAction;
  MyAction := TAction.Create(FActionList);
  MyAction.Caption := aCaption;
  MyAction.OnExecute := OnExecute;

  if aShortcut <> '' then
    MyAction.ShortCut := TextToShortCut(aShortcut);

  Item := TMenuItem.Create(nil);
  Item.Action := MyAction;
end;

destructor TMenuHandler.Destroy;
begin
   FreeAndNil(Item);
   inherited;
end;

procedure TMenuHandler.OnExecute(Sender: TObject);
begin
   if assigned(action) then
     Action;
end;


class procedure TMenuHandler.AddMenuItem(NTAServices: INTAServices; aCaption:String; aAction:TProc; aShortcut: String = '');
begin
   var handler := TMenuHandler.Create(aCaption, aAction,aShortcut);
   MenuHandlers.Add(handler);
   // I am adding menu items to the top of the Tools menu because all 
   // the menu items under "Configure Tools..." get deleted whenever you
   // open its dialog.
   NTAServices.AddActionMenu( 'ToolsMenu', nil, handler.Item ,False, True);
end;

procedure Register;
var
  NTAServices: INTAServices;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTAServices) then
    exit;

  TThread.CreateAnonymousThread(
    procedure
    begin
      while not Application.Terminated do begin
        if  NTAServices.MainMenu.Items.Count = 0 then begin
          Sleep(1000);
          continue;
        end;
        TThread.Synchronize(nil,
          procedure
          begin
            TMenuHandler.AddMenuItem(NTAServices, '-', nil);
            TMenuHandler.AddMenuItem(NTAServices, 'Open in Visual Studio Code', OpenCurrentFileInVisualStudioCode, 'Ctrl+\');
          end);
        break;
      end;
    end).Start;
end;

end.

