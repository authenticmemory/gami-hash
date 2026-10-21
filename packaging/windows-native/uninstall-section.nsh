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

Section "Uninstall"
  SetRegView 64
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  Delete "$DESKTOP\GAMI Hash.lnk"
  Delete "$SMPROGRAMS\GAMI Hash.lnk"
  Delete "$SMPROGRAMS\Authentic Memory\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\Authentic Memory\GAMI Hash.lnk"
  RMDir "$SMPROGRAMS\Authentic Memory"
  Delete "$INSTDIR\${PRODUCT_EXE}"
  Delete "$INSTDIR\${WORKER_EXE}"
  Delete "$INSTDIR\${CLI_EXE}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  RMDir "$LOCALAPPDATA\Programs\Authentic Memory"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "${SETTINGS_KEY}"
  ReadRegStr $0 HKCU "Environment" "Path"
  Push "$0"
  Push "$INSTDIR"
  Call un.RemovePathEntry
  Pop $1
  StrCmp $0 $1 +2
    WriteRegExpandStr HKCU "Environment" "Path" "$1"
  SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000
SectionEnd
