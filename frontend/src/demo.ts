// Demo backend: lets the frontend run in a plain browser (npm run dev, or a
// static preview) when the Wails runtime is absent. Used for design review
// and frontend development only; inside the real application window.go
// exists and this file does nothing. It simulates a small archive so every
// screen (welcome, resume, progress, warnings, cancel, result) can be seen
// without hashing anything.

import type { EngineEvent, Progress, Result } from "./backend";

export function installDemoBackendIfNeeded(): void {
  if (window.go?.wailsadapter?.Backend) return;

  const listeners = new Map<string, ((event: EngineEvent) => void)[]>();
  const emit = (event: EngineEvent) =>
    (listeners.get("gami:engine") ?? []).forEach((cb) => cb(event));

  const demoRoot = "D:\\Archiv\\Akzessionslaufwerk\\Bestand_A";
  const totalFiles = 48_712;
  const totalBytes = 1_397_000_000_000; // 1.4 TB
  let recordedRows = 0; // survives "cancel" so resume can be demonstrated
  let cancel = false;
  let timer: ReturnType<typeof setInterval> | undefined;

  const finish = (canceled: boolean, done: number, bytes: number) => {
    clearInterval(timer);
    const result: Result = {
      FilesHashed: done - Math.min(recordedRows, done),
      FilesResumed: Math.min(recordedRows, done),
      FilesFailed: canceled ? 0 : 3,
      Skipped: canceled ? 0 : 2,
      Warnings: canceled ? 0 : 2,
      BytesHashed: bytes,
      FilesTotal: totalFiles,
      BytesTotal: totalBytes,
      Output: "C:\\Users\\archiv\\Desktop\\checksums_Bestand_A_2026-09-12.csv",
      ErrorLog: canceled ? "" : "C:\\Users\\archiv\\Desktop\\checksums_Bestand_A_2026-09-12_errors.log",
      Canceled: canceled,
      Elapsed: 0,
    };
    recordedRows = canceled ? done : 0;
    emit({ kind: "result", result });
  };

  window.go = {
    wailsadapter: {
      Backend: {
        SelectFolder: async () => demoRoot,
        SelectOutput: async (suggested: string) =>
          `C:\\Users\\archiv\\Desktop\\${suggested}`,
        InspectResume: async () => ({
          resumable: recordedRows > 0,
          root: demoRoot,
          rows: recordedRows,
        }),
        Preflight: async (request) => ({
          root: request.root,
          output: request.output,
          resume: { resumable: recordedRows > 0, root: demoRoot, rows: recordedRows },
          willResume: request.mode === "resume" && recordedRows > 0,
        }),
        Start: async () => {
          cancel = false;
          let done = Math.min(recordedRows, totalFiles);
          let bytes = Math.floor(totalBytes * (done / totalFiles));
          let scanTicks = 0;
          timer = setInterval(() => {
            if (cancel) return finish(true, done, bytes);
            let progress: Progress;
            if (scanTicks < 12) {
              scanTicks++;
              progress = {
                Phase: 0,
                FilesDone: 0,
                FilesTotal: Math.floor(totalFiles * (scanTicks / 12)),
                BytesDone: 0,
                BytesTotal: Math.floor(totalBytes * (scanTicks / 12)),
              };
            } else {
              done = Math.min(totalFiles, done + 390 + Math.floor(Math.random() * 90));
              bytes = Math.min(totalBytes, Math.floor(totalBytes * (done / totalFiles)));
              progress = {
                Phase: 1,
                FilesDone: done,
                FilesTotal: totalFiles,
                BytesDone: bytes,
                BytesTotal: totalBytes,
              };
            }
            emit({ kind: "progress", progress });
            if (done >= totalFiles) finish(false, done, bytes);
          }, 250);
        },
        Cancel: async () => {
          cancel = true;
        },
        OpenOutputFolder: async () => {
          /* nothing to open in a browser demo */
        },
      },
    },
  };
  window.runtime = {
    EventsOn: (name, callback) => {
      listeners.set(name, [...(listeners.get(name) ?? []), callback]);
      return () => listeners.delete(name);
    },
    EventsOff: (name) => void listeners.delete(name),
  };
  document.title = "Authentic Memory Hashing Tool (design preview, simulated data)";
}
