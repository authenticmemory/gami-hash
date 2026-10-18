Unicode true

!include "MUI2.nsh"

!define PRODUCT_NAME "GAMI Hash Native Test"
!define PRODUCT_VERSION "0.2.0.0"
!define PRODUCT_PUBLISHER "Authentic Memory"
!define PRODUCT_EXE "GamiHash.WpfSpike.exe"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\GAMIHashNativeTest"

Name "${PRODUCT_NAME}"
OutFile "..\..\build\bin\gami-hash-native-test-0.2.0-x64-installer.exe"
InstallDir "$LOCALAPPDATA\Programs\Authentic Memory\GAMI Hash Native Test"
RequestExecutionLevel user
ManifestDPIAware true
VIProductVersion "${PRODUCT_VERSION}"
VIAddVersionKey "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "FileDescription" "${PRODUCT_NAME} Installer"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"

!define MUI_ICON "GamiHash.WpfSpike\Assets\gami-logo.ico"
!define MUI_UNICON "GamiHash.WpfSpike\Assets\gami-logo.ico"
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
  File "..\..\build\native-installer-payload\GamiHash.WpfSpike.exe"
  File "..\..\build\native-installer-payload\GamiHashEngine.exe"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\Authentic Memory"
  CreateShortcut "$SMPROGRAMS\Authentic Memory\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}"
  CreateShortcut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}"

  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "0.2.0"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT_EXE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\Authentic Memory\${PRODUCT_NAME}.lnk"
  RMDir "$SMPROGRAMS\Authentic Memory"
  Delete "$INSTDIR\GamiHash.WpfSpike.exe"
  Delete "$INSTDIR\GamiHashEngine.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  RMDir "$LOCALAPPDATA\Programs\Authentic Memory"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd
