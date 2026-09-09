export type RunMode = "resume" | "fresh" | "rehash-existing" | "resume-moved-root";

export interface RunRequest {
  root: string;
  output: string;
  workers: number;
  mode: RunMode;
}

export interface ResumeInspection {
  resumable: boolean;
  root?: string;
  rows: number;
}

export interface PreflightResult {
  root: string;
  output: string;
  resume: ResumeInspection;
  willResume: boolean;
}

export interface Progress {
  Phase: number;
  FilesDone: number;
  FilesTotal: number;
  BytesDone: number;
  BytesTotal: number;
}

export interface Result {
  FilesHashed: number;
  FilesResumed: number;
  FilesFailed: number;
  Skipped: number;
  Warnings: number;
  BytesHashed: number;
  FilesTotal: number;
  BytesTotal: number;
  Output: string;
  ErrorLog: string;
  Canceled: boolean;
  Elapsed: number;
}

export type EngineEvent =
  | { kind: "progress"; progress: Progress }
  | { kind: "result"; result: Result }
  | { kind: "fatal"; error: string };

interface BackendAPI {
  SelectFolder(): Promise<string>;
  SelectOutput(suggested: string): Promise<string>;
  InspectResume(output: string): Promise<ResumeInspection>;
  Preflight(request: RunRequest): Promise<PreflightResult>;
  Start(request: RunRequest): Promise<void>;
  Cancel(): Promise<void>;
  OpenOutputFolder(): Promise<void>;
}

declare global {
  interface Window {
    go?: { wailsadapter?: { Backend?: BackendAPI } };
    runtime?: {
      EventsOn(name: string, callback: (event: EngineEvent) => void): () => void;
      EventsOff(name: string): void;
    };
  }
}

function backend(): BackendAPI {
  const api = window.go?.wailsadapter?.Backend;
  if (!api) throw new Error("GAMI backend is not available");
  return api;
}

export const api = {
  selectFolder: () => backend().SelectFolder(),
  selectOutput: (suggested: string) => backend().SelectOutput(suggested),
  inspectResume: (output: string) => backend().InspectResume(output),
  preflight: (request: RunRequest) => backend().Preflight(request),
  start: (request: RunRequest) => backend().Start(request),
  cancel: () => backend().Cancel(),
  openOutputFolder: () => backend().OpenOutputFolder(),
  onEngineEvent(callback: (event: EngineEvent) => void): () => void {
    if (!window.runtime) throw new Error("GAMI event runtime is not available");
    return window.runtime.EventsOn("gami:engine", callback);
  },
};
