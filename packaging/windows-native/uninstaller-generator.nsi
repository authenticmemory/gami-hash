Unicode true
!include "MUI2.nsh"
!include "WinMessages.nsh"
!define PRODUCT_NAME "Authentic Memory Hashing Tool"
!define PRODUCT_EXE "GamiHash.exe"
!define WORKER_EXE "GamiHashEngine.exe"
!define CLI_EXE "gami-hash.exe"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\GAMIHash"
!define SETTINGS_KEY "Software\Authentic Memory\GAMI Hash\Installer"

Name "GAMI Hash Uninstaller Generator"
OutFile "uninstaller-generator.exe"
InstallDir "$LOCALAPPDATA\Programs\Authentic Memory\GAMI Hash"
RequestExecutionLevel user
SilentInstall silent
!define MUI_UNICON "..\..\windows\GamiHash.Windows\Assets\gami-logo.ico"
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section
  WriteUninstaller "$EXEDIR\Uninstall.exe"
SectionEnd

!include "uninstall-section.nsh"
