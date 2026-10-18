Unicode true
RequestExecutionLevel user
ManifestDPIAware true

!include "MUI2.nsh"
!include "LogicLib.nsh"

!ifndef PACKAGE_PATH
  !error "PACKAGE_PATH must point to the signed MSIX"
!endif
!ifndef OUTPUT_PATH
  !error "OUTPUT_PATH must name the bootstrapper EXE"
!endif
!ifndef PRODUCT_VERSION
  !error "PRODUCT_VERSION is required"
!endif

!define PRODUCT_NAME "GAMI Hash"
!define PACKAGE_FILE "gami-hash-windows-${PRODUCT_VERSION}-x64.msix"
!define APP_USER_MODEL_ID "AuthenticMemory.GAMIHash.Windows_gvy2j2522dmkc!GamiHash"

Name "${PRODUCT_NAME}"
OutFile "${OUTPUT_PATH}"
BrandingText "Authentic Memory"
ShowInstDetails show

VIProductVersion "${PRODUCT_VERSION}"
VIFileVersion "${PRODUCT_VERSION}"
VIAddVersionKey "CompanyName" "Authentic Memory"
VIAddVersionKey "FileDescription" "GAMI Hash Installer"
VIAddVersionKey "ProductName" "GAMI Hash"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "LegalCopyright" "Authentic Memory"

!define MUI_ICON "..\..\windows-appcontainer\assets\gami-logo.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Run GAMI Hash now"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchGamiHash

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

Section "Install GAMI Hash" SEC_INSTALL
  SetOutPath "$PLUGINSDIR"
  File "/oname=${PACKAGE_FILE}" "${PACKAGE_PATH}"

  DetailPrint "Installing the signed GAMI Hash application package..."
  nsExec::ExecToStack 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $"Add-AppxPackage -LiteralPath $\'$PLUGINSDIR\${PACKAGE_FILE}$\' -ForceApplicationShutdown -ErrorAction Stop$"'
  Pop $0
  Pop $1
  DetailPrint "$1"
  ${If} $0 != 0
    MessageBox MB_ICONSTOP|MB_OK "GAMI Hash could not be installed.$\r$\n$\r$\nWindows reported:$\r$\n$1"
    SetErrorLevel $0
    Abort
  ${EndIf}

  DetailPrint "GAMI Hash ${PRODUCT_VERSION} was installed successfully."
SectionEnd

Function LaunchGamiHash
  ExecShell "open" "explorer.exe" "shell:AppsFolder\${APP_USER_MODEL_ID}" SW_SHOWNORMAL
FunctionEnd
