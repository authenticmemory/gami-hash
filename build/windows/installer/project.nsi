Unicode true

####
## Please note: Template replacements don't work in this file. They are provided with default defines like
## mentioned underneath.
## If the keyword is not defined, "wails_tools.nsh" will populate them with the values from ProjectInfo.
## If they are defined here, "wails_tools.nsh" will not touch them. This allows to use this project.nsi manually
## from outside of Wails for debugging and development of the installer.
##
## For development first make a wails nsis build to populate the "wails_tools.nsh":
## > wails build --target windows/amd64 --nsis
## Then you can call makensis on this file with specifying the path to your binary:
## For a AMD64 only installer:
## > makensis -DARG_WAILS_AMD64_BINARY=..\..\bin\app.exe
## For a ARM64 only installer:
## > makensis -DARG_WAILS_ARM64_BINARY=..\..\bin\app.exe
## For a installer with both architectures:
## > makensis -DARG_WAILS_AMD64_BINARY=..\..\bin\app-amd64.exe -DARG_WAILS_ARM64_BINARY=..\..\bin\app-arm64.exe
####
## The following information is taken from the ProjectInfo file, but they can be overwritten here.
####
## !define INFO_PROJECTNAME    "MyProject" # Default "{{.Name}}"
## !define INFO_COMPANYNAME    "MyCompany" # Default "{{.Info.CompanyName}}"
## !define INFO_PRODUCTNAME    "MyProduct" # Default "{{.Info.ProductName}}"
## !define INFO_PRODUCTVERSION "1.0.0"     # Default "{{.Info.ProductVersion}}"
## !define INFO_COPYRIGHT      "Copyright" # Default "{{.Info.Copyright}}"
###
## !define PRODUCT_EXECUTABLE  "Application.exe"      # Default "${INFO_PROJECTNAME}.exe"
## !define UNINST_KEY_NAME     "UninstKeyInRegistry"  # Default "${INFO_COMPANYNAME}${INFO_PRODUCTNAME}"
####
## !define REQUEST_EXECUTION_LEVEL "admin"            # Default "admin"  see also https://nsis.sourceforge.io/Docs/Chapter4.html
####
!define PRODUCT_EXECUTABLE "GAMI Hash.exe"
!define PRODUCT_CLI_EXECUTABLE "gami-hash.exe"
!define GAMI_PATH_SENTINEL ";$INSTDIR;"
## Include the wails tools
####
!include "wails_tools.nsh"

# The version information for this two must consist of 4 parts
VIProductVersion "${INFO_PRODUCTVERSION}.0"
VIFileVersion    "${INFO_PRODUCTVERSION}.0"

VIAddVersionKey "CompanyName"     "${INFO_COMPANYNAME}"
VIAddVersionKey "FileDescription" "${INFO_PRODUCTNAME} Installer"
VIAddVersionKey "ProductVersion"  "${INFO_PRODUCTVERSION}"
VIAddVersionKey "FileVersion"     "${INFO_PRODUCTVERSION}"
VIAddVersionKey "LegalCopyright"  "${INFO_COPYRIGHT}"
VIAddVersionKey "ProductName"     "${INFO_PRODUCTNAME}"

# Enable HiDPI support. https://nsis.sourceforge.io/Reference/ManifestDPIAware
ManifestDPIAware true

!include "MUI.nsh"

!define MUI_ICON "..\icon.ico"
!define MUI_UNICON "..\icon.ico"
# !define MUI_WELCOMEFINISHPAGE_BITMAP "resources\leftimage.bmp" #Include this to add a bitmap on the left side of the Welcome Page. Must be a size of 164x314
!define MUI_FINISHPAGE_NOAUTOCLOSE # Wait on the INSTFILES page so the user can take a look into the details of the installation steps
!define MUI_ABORTWARNING # This will warn the user if they exit from the installer.

!insertmacro MUI_PAGE_WELCOME # Welcome to the installer page.
# !insertmacro MUI_PAGE_LICENSE "resources\eula.txt" # Adds a EULA page to the installer
!insertmacro MUI_PAGE_DIRECTORY # In which folder install page.
!insertmacro MUI_PAGE_COMPONENTS # Optional shortcuts and command-line access.
!insertmacro MUI_PAGE_INSTFILES # Installing page.
!insertmacro MUI_PAGE_FINISH # Finished installation page.

!insertmacro MUI_UNPAGE_INSTFILES # Uinstalling page

!insertmacro MUI_LANGUAGE "English" # Set the Language of the installer

## The following two statements can be used to sign the installer and the uninstaller. The path to the binaries are provided in %1
#!uninstfinalize 'signtool --file "%1"'
#!finalize 'signtool --file "%1"'

Name "${INFO_PRODUCTNAME}"
OutFile "..\..\bin\${INFO_PROJECTNAME}-${ARCH}-installer.exe" # Name of the installer's file.
!ifdef WAILS_INSTALL_SCOPE
  !if "${WAILS_INSTALL_SCOPE}" == "user"
    InstallDir "$LOCALAPPDATA\Programs\${INFO_PRODUCTNAME}"
  !else
    InstallDir "$PROGRAMFILES64\${INFO_COMPANYNAME}\${INFO_PRODUCTNAME}"
  !endif
!else
  InstallDir "$PROGRAMFILES64\${INFO_COMPANYNAME}\${INFO_PRODUCTNAME}"
!endif # Default installing folder ($PROGRAMFILES is Program Files folder).
ShowInstDetails show # This will always show the installation details.

!macro AddToPath REGROOT REGPATH
    ReadRegStr $0 ${REGROOT} "${REGPATH}" "Path"
    StrCmp $0 "" 0 +3
        WriteRegExpandStr ${REGROOT} "${REGPATH}" "Path" "$INSTDIR"
        Goto done
    Push ";$0;"
    Push "${GAMI_PATH_SENTINEL}"
    Call StrStr
    Pop $1
    StrCmp $1 "" 0 done
    WriteRegExpandStr ${REGROOT} "${REGPATH}" "Path" "$0;$INSTDIR"
done:
    SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000
!macroend

!macro RemoveFromPath REGROOT REGPATH
    ReadRegStr $0 ${REGROOT} "${REGPATH}" "Path"
    StrCmp $0 "" done
    Push "$0"
    Push "$INSTDIR"
    Call un.RemovePathEntry
    Pop $1
    StrCmp $0 $1 done
    WriteRegExpandStr ${REGROOT} "${REGPATH}" "Path" "$1"
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
    StrCmp $R5 "" +2
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

Section "GAMI Hash application" SEC_APP
    SectionIn RO
    !insertmacro wails.setShellContext

    !insertmacro wails.webview2runtime

    SetOutPath $INSTDIR

    !insertmacro wails.files
    File "/oname=${PRODUCT_CLI_EXECUTABLE}" "gami-hash-cli.exe"

    CreateShortcut "$SMPROGRAMS\${INFO_PRODUCTNAME}.lnk" "$INSTDIR\${PRODUCT_EXECUTABLE}"

    !insertmacro wails.associateFiles
    !insertmacro wails.associateCustomProtocols

    !insertmacro wails.writeUninstaller
SectionEnd

Section "Create desktop shortcut" SEC_DESKTOP
    !insertmacro wails.setShellContext
    CreateShortCut "$DESKTOP\${INFO_PRODUCTNAME}.lnk" "$INSTDIR\${PRODUCT_EXECUTABLE}"
SectionEnd

Section "Add GAMI Hash to PATH for command-line use" SEC_PATH
    !ifdef WAILS_INSTALL_SCOPE
      !if "${WAILS_INSTALL_SCOPE}" == "user"
        !insertmacro AddToPath HKCU "Environment"
      !else
        !insertmacro AddToPath HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
      !endif
    !else
      !insertmacro AddToPath HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    !endif
SectionEnd

Function .onInit
   !insertmacro wails.checkArchitecture
   SectionGetFlags ${SEC_PATH} $0
   IntOp $0 $0 & 0xFFFFFFFE
   SectionSetFlags ${SEC_PATH} $0
FunctionEnd

Section "uninstall"
    !insertmacro wails.setShellContext

    RMDir /r "$AppData\${PRODUCT_EXECUTABLE}" # Remove the WebView2 DataPath

    RMDir /r $INSTDIR

    Delete "$SMPROGRAMS\${INFO_PRODUCTNAME}.lnk"
    Delete "$DESKTOP\${INFO_PRODUCTNAME}.lnk"

    !ifdef WAILS_INSTALL_SCOPE
      !if "${WAILS_INSTALL_SCOPE}" == "user"
        !insertmacro RemoveFromPath HKCU "Environment"
      !else
        !insertmacro RemoveFromPath HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
      !endif
    !else
      !insertmacro RemoveFromPath HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    !endif

    !insertmacro wails.unassociateFiles
    !insertmacro wails.unassociateCustomProtocols

    !insertmacro wails.deleteUninstaller
SectionEnd
