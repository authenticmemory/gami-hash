Unicode true
!include "MUI2.nsh"
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
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
Section "Application" SEC_APP
  SetOutPath "$INSTDIR"
  File "${PAYLOAD_DIR}\${PRODUCT_EXE}"
  File "${PAYLOAD_DIR}\${WORKER_EXE}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Authentic Memory"
  CreateShortcut "$SMPROGRAMS\Authentic Memory\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}"
  CreateShortcut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}"
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
Section "Uninstall"
  SetRegView 64
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\Authentic Memory\${PRODUCT_NAME}.lnk"
  RMDir "$SMPROGRAMS\Authentic Memory"
  Delete "$INSTDIR\${PRODUCT_EXE}"
  Delete "$INSTDIR\${WORKER_EXE}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  RMDir "$LOCALAPPDATA\Programs\Authentic Memory"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd
