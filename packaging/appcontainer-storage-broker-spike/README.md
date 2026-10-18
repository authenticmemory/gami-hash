# AppContainer storage broker feasibility spike

This is a disposable local-first spike. It proves only that a foreground
`windowsApp` component can show `FolderPicker` from the same networkless MSIX
as the contained desktop frontend and publish bounded metadata through the
package application-data store.

Pass only when the local Windows 11 23H2 machine shows the picker, enumerates
one selected file, and both processes have AppContainer tokens. Stop if the
package needs `runFullTrust`, filesystem-library capabilities, or any network
capability.
