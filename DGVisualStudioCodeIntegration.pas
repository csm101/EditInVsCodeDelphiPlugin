unit DGVisualStudioCodeIntegration;

interface
procedure OpenCurrentFileInVisualStudioCode;

procedure Register;


implementation
uses
  System.Classes,
  System.SysUtils,
  ToolsApi,
  Menus,
  OSCommandLineExecutor,
  Dialogs,
  ActnList,
  Forms,
  ShellAPI,
  Windows;

procedure SaveAllModules;
var
  Services: IOTAModuleServices;
  I: Integer;
  Module: IOTAModule;

begin
  Services := BorlandIDEServices as IOTAModuleServices;
  for I := 0 to Services.ModuleCount - 1 do
  begin
    Module := Services.Modules[I];
    var editor := Module.CurrentEditor;
    if editor = nil then
      continue;

    if editor.Modified then
      Module.Save(False, True);
  end;
end;

procedure OpenCurrentFileInVisualStudioCode;
var
  SourceEditor: IOTASourceEditor;
begin
  var Services := BorlandIDEServices as IOTAModuleServices;

  var Module := Services.CurrentModule;
  if Module = nil then begin
     ShowMessage('No current module');
     Exit;
  end;

  if not Supports(Module.CurrentEditor, IOTASourceEditor, SourceEditor) then begin
     ShowMessage('Current module does not support IOTASourceEditor interface');
     exit;
  end;

  var EditView:IOTAEditView := SourceEditor.GetEditView(0); // I assume we are working only in the first view
  if EditView = nil then begin
     ShowMessage('Can''t locate editor view');
     exit;
  end;

  var FileName := Module.FileName;

  var project := (BorlandIDEServices as IOTAModuleServices).GetActiveProject;

  if project = nil then begin
       ShowMessage('Currently these isn''t any active project');
       exit;
  end;

  var ProjectPath := ExtractFilePath(project.FileName);

  SaveAllModules;

  var CursorPos := EditView.CursorPos;

  var cmdline := Format('cmd /c "code --reuse-window %s -g %s:%d"', [ProjectPath, FileName, CursorPos.Line]);

  var executor := TOSCommandLineExecutor.Create(nil);
  try
     executor.WorkDir := ExtractFilePath(filename);
     executor.CmdLine := Cmdline;
     executor.Execute;
  finally
     executor.Free;
  end;
end;



Type
   TVSCMenuHandler=class
   public
     Item:TMenuItem;
     procedure OnExecute(Sender: TObject);
     Constructor Create;
     destructor Destroy; override;
   end;

var MenuHandler :TVSCMenuHandler = nil;

Constructor TVSCMenuHandler.Create;
begin
   inherited;
   Item := TMenuItem.Create(nil);
   item.Caption := 'Open in Visual Studio Code';
   Item.OnClick := OnExecute;
end;

destructor TVSCMenuHandler.Destroy;
begin
   FreeAndNil(Item);
   inherited;
end;

procedure TVSCMenuHandler.OnExecute(Sender: TObject);
begin
   OpenCurrentFileInVisualStudioCode;
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
            MenuHandler := TVSCMenuHandler.Create;
            NTAServices.AddActionMenu( 'ToolsMenu', nil, MenuHandler.Item ,True, True);
          end);
        break;
      end;
    end).Start;
end;

initialization

finalization
   FreeAndNil(MenuHandler);
end.

