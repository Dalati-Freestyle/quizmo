; Compiled by the release workflow; all paths are supplied by CI.
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef AppBuild
  #error AppBuild is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef RuntimeFile
  #error RuntimeFile is required
#endif

[Setup]
AppId={{BC60B295-9E89-48F2-935D-E04C84F4DE45}
AppName=Quizmo
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersion}.{#AppBuild}
AppPublisher=Quizmo
DefaultDirName={autopf}\Quizmo
DefaultGroupName=Quizmo
UninstallDisplayIcon={app}\quizmo.exe
OutputBaseFilename=quizmo-{#AppVersion}-windows-x64-setup
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
PrivilegesRequired=admin
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RuntimeFile}"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Quizmo"; Filename: "{app}\quizmo.exe"
Name: "{autodesktop}\Quizmo"; Filename: "{app}\quizmo.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\quizmo.exe"; Description: "Launch Quizmo"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  ExtractTemporaryFile('vc_redist.x64.exe');
  if not Exec(ExpandConstant('{tmp}\vc_redist.x64.exe'),
      '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Result := 'Could not start the Microsoft Visual C++ runtime installer.'
  else if ResultCode = 3010 then
    NeedsRestart := True
  else if (ResultCode <> 0) and (ResultCode <> 1638) then
    Result := Format('Microsoft Visual C++ runtime installation failed (exit %d).', [ResultCode]);
end;
