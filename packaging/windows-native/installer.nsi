Unicode true
!include "MUI2.nsh"
!include "WinMessages.nsh"
!ifndef PRODUCT_VERSION
  !define PRODUCT_VERSION "0.1.0.0"
!endif
!ifndef PAYLOAD_DIR
  !error "PAYLOAD_DIR is required"
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required"
!endif
!define PRODUCT_NAME "GAMI Hash"
!define PRODUCT_PUBLISHER "Authentic Memory"
!define PRODUCT_EXE "GamiHash.exe"
!define WORKER_EXE "GamiHashEngine.exe"
!define CLI_EXE "gami-hash.exe"
!define PATH_SENTINEL ";$INSTDIR;"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\GAMIHash"
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
!define MUI_FINISHPAGE_RUN_TEXT "Run GAMI Hash now"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
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

Function un.RemovePathEntry
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

# Upgrades cannot replace the WPF executable while it is open. WM_CLOSE uses
# the application's normal shutdown path, which cancels an active hash and
# waits for its checkpoint before the window closes.
Function CloseRunningApplication
  FindWindow $0 "" "Authentic Memory · Hashing Tool"
  StrCmp $0 0 done
  DetailPrint "Closing the running GAMI Hash application..."
  SendMessage $0 ${WM_CLOSE} 0 0
  StrCpy $1 0
wait:
  Sleep 500
  FindWindow $0 "" "Authentic Memory · Hashing Tool"
  StrCmp $0 0 closed
  IntOp $1 $1 + 1
  IntCmp $1 240 wait wait timeout
closed:
  # Allow the child hashing engine to finish exiting and release its image.
  Sleep 500
  Goto done
timeout:
  MessageBox MB_OK|MB_ICONSTOP "GAMI Hash is still running. Close it, then run this installer again. Your interrupted progress will be preserved."
  Abort
done:
FunctionEnd

Section "GAMI Hash application" SEC_APP
  SectionIn RO
  Call CloseRunningApplication
  SetOutPath "$INSTDIR"
  File "${PAYLOAD_DIR}\${PRODUCT_EXE}"
  File "${PAYLOAD_DIR}\${WORKER_EXE}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Authentic Memory"
  CreateShortcut "$SMPROGRAMS\Authentic Memory\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}"
  SetRegView 64
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT_EXE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$INSTDIR\Uninstall.exe'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Create desktop shortcut" SEC_DESKTOP
  CreateShortcut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}"
SectionEnd

Section /o "Install command-line tool and add to PATH" SEC_CLI
  SetOutPath "$INSTDIR"
  File "/oname=${CLI_EXE}" "${PAYLOAD_DIR}\${WORKER_EXE}"
  !insertmacro AddToPath
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_APP} "Install the GAMI Hash desktop application and hashing engine."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_DESKTOP} "Create a GAMI Hash shortcut on the desktop."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_CLI} "Install gami-hash.exe and add its folder to your user PATH."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  SetRegView 64
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\Authentic Memory\${PRODUCT_NAME}.lnk"
  RMDir "$SMPROGRAMS\Authentic Memory"
  Delete "$INSTDIR\${PRODUCT_EXE}"
  Delete "$INSTDIR\${WORKER_EXE}"
  Delete "$INSTDIR\${CLI_EXE}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  RMDir "$LOCALAPPDATA\Programs\Authentic Memory"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  ReadRegStr $0 HKCU "Environment" "Path"
  Push "$0"
  Push "$INSTDIR"
  Call un.RemovePathEntry
  Pop $1
  StrCmp $0 $1 +2
    WriteRegExpandStr HKCU "Environment" "Path" "$1"
  SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000
SectionEnd
