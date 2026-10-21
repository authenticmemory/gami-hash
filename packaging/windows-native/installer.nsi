Unicode true
!include "MUI2.nsh"
!include "WinMessages.nsh"
!include "Sections.nsh"
!ifndef PRODUCT_VERSION
  !define PRODUCT_VERSION "0.1.0.0"
!endif
!ifndef PAYLOAD_DIR
  !error "PAYLOAD_DIR is required"
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required"
!endif
!ifndef INSTALL_DATE
  !define INSTALL_DATE ""
!endif
!ifndef INSTALLED_SIZE_KB
  !define INSTALLED_SIZE_KB 0
!endif
!ifndef VERSION_MAJOR
  !define VERSION_MAJOR 0
!endif
!ifndef VERSION_MINOR
  !define VERSION_MINOR 1
!endif
!define PRODUCT_NAME "Authentic Memory Hashing Tool"
!define PRODUCT_PUBLISHER "Authentic Memory"
!define PRODUCT_EXE "GamiHash.exe"
!define WORKER_EXE "GamiHashEngine.exe"
!define CLI_EXE "gami-hash.exe"
!define PATH_SENTINEL ";$INSTDIR;"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\GAMIHash"
!define SETTINGS_KEY "Software\Authentic Memory\GAMI Hash\Installer"
!define OLD_INSTALL_DIR "$LOCALAPPDATA\Programs\Authentic Memory Hashing Tool"
Name "${PRODUCT_NAME}"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\Authentic Memory\GAMI Hash"
RequestExecutionLevel user
ManifestDPIAware true
VIProductVersion "${PRODUCT_VERSION}"
VIAddVersionKey "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "FileDescription" "${PRODUCT_NAME} Installer"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright (c) 2026 Authentic Memory"
!define MUI_ICON "..\..\windows\GamiHash.Windows\Assets\gami-logo.ico"
!define MUI_UNICON "..\..\windows\GamiHash.Windows\Assets\gami-logo.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Run Authentic Memory Hashing Tool now"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "English"
!macro AddToPath
  ReadRegStr $0 HKCU "Environment" "Path"
  StrCmp $0 "" 0 +3
    WriteRegExpandStr HKCU "Environment" "Path" "$INSTDIR"
    Goto done
  Push ";$0;"
  Push "${PATH_SENTINEL}"
  Call StrStr
  Pop $1
  StrCmp $1 "" 0 done
  WriteRegExpandStr HKCU "Environment" "Path" "$0;$INSTDIR"
done:
  SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000
!macroend

Function StrStr
  Exch $R1
  Exch
  Exch $R2
  Push $R3
  Push $R4
  Push $R5
  StrLen $R3 $R1
  StrCpy $R4 0
loop:
  StrCpy $R5 $R2 $R3 $R4
  StrCmp $R5 $R1 found
  StrCmp $R5 "" notfound
  IntOp $R4 $R4 + 1
  Goto loop
found:
  StrCpy $R1 $R2 "" $R4
  Goto done
notfound:
  StrCpy $R1 ""
done:
  Pop $R5
  Pop $R4
  Pop $R3
  Pop $R2
  Exch $R1
FunctionEnd

Function RemovePathEntry
  Exch $R1
  Exch
  Exch $R2
  Push $R3
  Push $R4
  Push $R5
  StrCpy $R0 ""
  StrCpy $R3 ""
  StrCpy $R4 "$R2;"
loop:
  StrCpy $R5 $R4 1
  StrCmp $R5 "" done
  StrCmp $R5 ";" segment
  StrCpy $R3 "$R3$R5"
  StrCpy $R4 $R4 "" 1
  Goto loop
segment:
  StrCmp $R3 $R1 skip add
add:
  StrCpy $R0 "$R0$R3;"
skip:
  StrCpy $R3 ""
  StrCpy $R4 $R4 "" 1
  Goto loop
done:
  StrCpy $R0 $R0 -1
  Pop $R5
  Pop $R4
  Pop $R3
  Pop $R2
  Pop $R1
  Push $R0
FunctionEnd

# Upgrades cannot replace the WPF executable while it is open. CloseMainWindow
# uses the application's normal shutdown path, which cancels an active hash and
# waits for its checkpoint before the process exits.
Function CloseRunningApplication
  DetailPrint "Closing the running GAMI Hash application..."
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "Get-Process -Name $\'GamiHash$\' -ErrorAction SilentlyContinue | ForEach-Object { [void]$$_.CloseMainWindow(); if (-not $$_.WaitForExit(15000)) { exit 25 } }"'
  Pop $0
  Pop $1
  StrCmp $0 25 timeout
  # Allow the child hashing engine to release its image.
  Sleep 500
  Return
timeout:
  MessageBox MB_OK|MB_ICONSTOP "GAMI Hash is still running. Close it, then run this installer again. Your interrupted progress will be preserved."
  Abort
FunctionEnd

Function CheckWorkerNotRunning
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "Wait-Process -Name $\'GamiHashEngine$\',$\'gami-hash$\' -Timeout 10 -ErrorAction SilentlyContinue; if (Get-Process -Name $\'GamiHashEngine$\',$\'gami-hash$\' -ErrorAction SilentlyContinue) { exit 24 }"'
  Pop $0
  Pop $1
  StrCmp $0 24 0 done
  MessageBox MB_OK|MB_ICONSTOP "A GAMI Hash command-line or hashing process is still running. Let it finish or stop it, close Authentic Memory Hashing Tool, then run this installer again. Interrupted progress will be preserved."
  Abort
done:
FunctionEnd

Function CheckConflictingMsix
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "if ((@(Get-AppxPackage -Name $\'AuthenticMemory.GAMIHash.Windows$\') + @(Get-AppxPackage -Name $\'AuthenticMemory.GAMIHash.Phase2Product$\')).Count -gt 0) { exit 23 }"'
  Pop $0
  Pop $1
  StrCmp $0 23 0 done
  MessageBox MB_OK|MB_ICONSTOP "A packaged GAMI Hash release is installed for this Windows account. Uninstall GAMI Hash from Windows Settings > Apps > Installed apps, then run this installer again. Your manifests outside the application remain untouched."
  Abort
done:
FunctionEnd

Function RemoveLegacyExeInstall
  IfFileExists "${OLD_INSTALL_DIR}\uninstall.exe" 0 cleanup
  DetailPrint "Removing the previous Authentic Memory Hashing Tool application files..."
  ExecWait '"${OLD_INSTALL_DIR}\uninstall.exe" /S' $0
  StrCmp $0 0 cleanup
  MessageBox MB_OK|MB_ICONSTOP "The previous Authentic Memory Hashing Tool installation could not be removed. Uninstall it from Windows Settings, then run this installer again."
  Abort
cleanup:
  Delete "$DESKTOP\GAMI Hash.lnk"
  Delete "$SMPROGRAMS\GAMI Hash.lnk"
  Delete "$SMPROGRAMS\Authentic Memory\GAMI Hash.lnk"
FunctionEnd

Section "GAMI Hash application" SEC_APP
  SectionIn RO
  Call CheckConflictingMsix
  Call CloseRunningApplication
  Call CheckWorkerNotRunning
  Call RemoveLegacyExeInstall
  SetOutPath "$INSTDIR"
  File "${PAYLOAD_DIR}\${PRODUCT_EXE}"
  File "${PAYLOAD_DIR}\${WORKER_EXE}"
  File "/oname=Uninstall.exe" "${PAYLOAD_DIR}\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Authentic Memory"
  CreateShortcut "$SMPROGRAMS\Authentic Memory\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}"
  SetRegView 64
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT_EXE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallDate" "${INSTALL_DATE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://authenticmemory.org/tools/"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "HelpLink" "mailto:tech@authenticmemory.org"
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" ${INSTALLED_SIZE_KB}
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "VersionMajor" ${VERSION_MAJOR}
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "VersionMinor" ${VERSION_MINOR}
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1

SectionEnd

Section "Create desktop shortcut" SEC_DESKTOP
  CreateShortcut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}"
  WriteRegDWORD HKCU "${SETTINGS_KEY}" "DesktopShortcut" 1
SectionEnd

Section /o "Install command-line tool and add to PATH" SEC_CLI
  SetOutPath "$INSTDIR"
  File "/oname=${CLI_EXE}" "${PAYLOAD_DIR}\${WORKER_EXE}"
  !insertmacro AddToPath
  WriteRegDWORD HKCU "${SETTINGS_KEY}" "CLI" 1
SectionEnd

Section "-Finalize component choices"
  SectionGetFlags ${SEC_DESKTOP} $0
  IntOp $0 $0 & ${SF_SELECTED}
  StrCmp $0 ${SF_SELECTED} desktopSelected
    Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
    WriteRegDWORD HKCU "${SETTINGS_KEY}" "DesktopShortcut" 0
desktopSelected:
  SectionGetFlags ${SEC_CLI} $0
  IntOp $0 $0 & ${SF_SELECTED}
  StrCmp $0 ${SF_SELECTED} cliSelected
    Delete "$INSTDIR\${CLI_EXE}"
    ReadRegStr $0 HKCU "Environment" "Path"
    Push "$0"
    Push "$INSTDIR"
    Call RemovePathEntry
    Pop $1
    StrCmp $0 $1 +2
      WriteRegExpandStr HKCU "Environment" "Path" "$1"
    WriteRegDWORD HKCU "${SETTINGS_KEY}" "CLI" 0
cliSelected:
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_APP} "Install the GAMI Hash desktop application and hashing engine."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_DESKTOP} "Create a GAMI Hash shortcut on the desktop."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_CLI} "Install gami-hash.exe and add its folder to your user PATH."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
  SetRegView 64

  ReadRegDWORD $0 HKCU "${SETTINGS_KEY}" "DesktopShortcut"
  IfErrors desktopLegacy
  StrCmp $0 0 desktopOff desktopOn
desktopLegacy:
  IfFileExists "$DESKTOP\GAMI Hash.lnk" desktopOn
  IfFileExists "$DESKTOP\${PRODUCT_NAME}.lnk" desktopOn desktopDone
desktopOn:
  SectionGetFlags ${SEC_DESKTOP} $1
  IntOp $1 $1 | ${SF_SELECTED}
  SectionSetFlags ${SEC_DESKTOP} $1
  Goto desktopDone
desktopOff:
  SectionGetFlags ${SEC_DESKTOP} $1
  IntOp $1 $1 & 0xFFFFFFFE
  SectionSetFlags ${SEC_DESKTOP} $1
desktopDone:

  ReadRegDWORD $0 HKCU "${SETTINGS_KEY}" "CLI"
  IfErrors cliLegacy
  StrCmp $0 0 cliOff cliOn
cliLegacy:
  IfFileExists "$INSTDIR\${CLI_EXE}" cliOn cliDone
cliOn:
  SectionGetFlags ${SEC_CLI} $1
  IntOp $1 $1 | ${SF_SELECTED}
  SectionSetFlags ${SEC_CLI} $1
  Goto cliDone
cliOff:
  SectionGetFlags ${SEC_CLI} $1
  IntOp $1 $1 & 0xFFFFFFFE
  SectionSetFlags ${SEC_CLI} $1
cliDone:
FunctionEnd
