# Creating checksums for Authentic Memory

The Windows application is installed as **Authentic Memory Hashing Tool**. It reads your collection and creates a CSV checksum list. It does not upload your files or change them.

## Create a checksum list

1. Open **Authentic Memory Hashing Tool** from the Start menu.
2. Select **Choose folder** and pick the collection folder, drive, network share, or cloud-synced folder.
3. Choose where to save the result. Save it outside the collection being scanned.
4. Review both locations and select **Start**. If the app warns that a source or destination may use network or cloud storage, continue only when that storage access is expected.
5. Keep the source available while hashing. You may continue using the computer.
6. Select **Cancel** to stop safely. Open the application later and select **Continue** to resume.
7. On the Done screen, select **Open folder** and send the CSV to `tech@authenticmemory.org`.

## If files cannot be read

The run completes with a warning and creates an `_errors.log` next to the CSV. Send both files. Successfully read files remain in the manifest.

## What the application writes

It writes the selected CSV, an error log when needed, and temporary resume state for an unfinished run. It never intentionally writes into the selected source folder.

## CLI

The optional CLI component is intended for IT staff. Open a new PowerShell window after installation and run `gami-hash --help`.
