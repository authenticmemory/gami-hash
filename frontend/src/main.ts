import "./style.css";
import { api, type EngineEvent, type PreflightResult, type Result, type RunRequest } from "./backend";
import logoUrl from "./assets/gami-logo-icon.svg";

type Step = "welcome" | "collection" | "output" | "review" | "progress" | "result";

const app = document.querySelector<HTMLDivElement>("#app")!;
let step: Step = "welcome";
let root = "";
let output = "";
let review: PreflightResult | null = null;
let resumeConflict: { root: string; rows: number } | null = null;
let finalResult: Result | null = null;
let fatalError = "";
let busy = false;
let cancelRequested = false;
let startedAt = 0;
let lastBytes = 0;
let lastProgressAt = 0;
let bytesPerSecond = 0;

const esc = (value: string) => value.replace(/[&<>'"]/g, (char) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;",
}[char]!));

const number = new Intl.NumberFormat();
const formatBytes = (bytes: number): string => {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB", "PB"];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / 1024 ** index).toFixed(index === 0 ? 0 : 1)} ${units[index]}`;
};
const formatETA = (seconds: number): string => {
  if (!Number.isFinite(seconds) || seconds < 0) return "Estimating…";
  if (seconds < 60) return `About ${Math.max(1, Math.round(seconds))} seconds remaining`;
  if (seconds < 3600) return `About ${Math.ceil(seconds / 60)} minutes remaining`;
  return `About ${Math.ceil(seconds / 3600)} hours remaining`;
};

// Window controls for the frameless window. In a plain-browser preview the
// Wails runtime is absent; the buttons are still drawn but do nothing.
// Icons follow the Windows caption-glyph vocabulary; straight lines sit on
// half-pixel positions so 1px strokes render crisp.
const winIcon = {
  min: '<svg viewBox="0 0 10 10" aria-hidden="true"><rect x="0" y="4.5" width="10" height="1" fill="currentColor"/></svg>',
  max: '<svg viewBox="0 0 10 10" aria-hidden="true"><rect x="0.5" y="0.5" width="9" height="9" fill="none" stroke="currentColor" stroke-width="1"/></svg>',
  restore:
    '<svg viewBox="0 0 10 10" aria-hidden="true"><rect x="0.5" y="2.5" width="7" height="7" fill="none" stroke="currentColor" stroke-width="1"/><path d="M2.5 2.5V0.5H9.5V7.5H7.5" fill="none" stroke="currentColor" stroke-width="1"/></svg>',
  close: '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M0 0l10 10M10 0L0 10" stroke="currentColor" stroke-width="1"/></svg>',
};

// The maximize button mirrors the real window state (maximize vs. restore),
// like every native Windows title bar.
async function updateMaxButton(): Promise<void> {
  const btn = document.querySelector<HTMLButtonElement>("#win-max");
  const isMax = await window.runtime?.WindowIsMaximised?.().catch(() => false);
  if (!btn) return;
  btn.innerHTML = isMax ? winIcon.restore : winIcon.max;
  btn.setAttribute("aria-label", isMax ? "Restore" : "Maximize");
}
window.addEventListener("resize", () => void updateMaxButton());

function shell(content: string): void {
  app.innerHTML = `
    <div class="app-shell">
      <header class="brandbar">
        <div class="brand">
          <img src="${logoUrl}" alt="" class="logo">
          <div><strong>Authentic Memory</strong><span class="sep" aria-hidden="true">·</span><span>Hashing Tool</span></div>
        </div>
        <div class="winctl">
          <button class="wbtn" id="win-min" aria-label="Minimize" tabindex="-1">${winIcon.min}</button>
          <button class="wbtn" id="win-max" aria-label="Maximize" tabindex="-1">${winIcon.max}</button>
          <button class="wbtn close" id="win-close" aria-label="Close" tabindex="-1">${winIcon.close}</button>
        </div>
      </header>
      <main>${content}</main>
    </div>`;
  const rt = window.runtime;
  const toggleMax = () => {
    rt?.WindowToggleMaximise?.();
    setTimeout(() => void updateMaxButton(), 50);
  };
  document.querySelector("#win-min")?.addEventListener("click", () => rt?.WindowMinimise?.());
  document.querySelector("#win-max")?.addEventListener("click", toggleMax);
  document.querySelector("#win-close")?.addEventListener("click", () => rt?.Quit?.());
  document.querySelector(".brandbar")?.addEventListener("dblclick", (event) => {
    if ((event.target as HTMLElement).closest(".winctl")) return;
    toggleMax();
  });
  void updateMaxButton();
  // Keyboard flow: Enter moves through the wizard. Never auto-focus during
  // a run, where the only button is Cancel.
  if (step !== "progress") {
    app.querySelector<HTMLButtonElement>(".button.primary")?.focus();
  }
}

function button(id: string, label: string, secondary = false, disabled = false): string {
  return `<button id="${id}" class="button ${secondary ? "secondary" : "primary"}" ${disabled ? "disabled" : ""}>${label}</button>`;
}

// The one-click resume offer remembers the last run in localStorage. Storage
// can be unavailable or stale in a webview, so every access is defensive:
// losing this state only costs the convenience, never a run.
const lastRunStore = {
  key: "gami:last-run",
  read(): { root: string; output: string } | null {
    try {
      const raw = localStorage.getItem(this.key);
      if (!raw) return null;
      const run = JSON.parse(raw) as { root?: unknown; output?: unknown };
      if (typeof run.root === "string" && typeof run.output === "string") {
        return { root: run.root, output: run.output };
      }
    } catch { /* fall through */ }
    this.clear();
    return null;
  },
  write(rememberRoot: string, rememberOutput: string): void {
    try { localStorage.setItem(this.key, JSON.stringify({ root: rememberRoot, output: rememberOutput })); } catch { /* resume offer only */ }
  },
  clear(): void {
    try { localStorage.removeItem(this.key); } catch { /* nothing to clear */ }
  },
};

async function renderWelcome(): Promise<void> {
  step = "welcome";
  const run = lastRunStore.read();
  let resume = "";
  if (run) {
    try {
      const state = await api.inspectResume(run.output);
      if (state.resumable) {
        resume = `<section class="resume-card"><div><span class="eyebrow">Interrupted run</span><strong>${number.format(state.rows)} files recorded so far</strong><p>${esc(run.root)}</p></div>${button("resume", "Continue")}</section>`;
        root = run.root;
        output = run.output;
      } else lastRunStore.clear();
    } catch { lastRunStore.clear(); }
  }
  shell(`<section class="panel hero"><h1>Create a checksum list of your collection.</h1><p class="lede">The program reads every file in a folder you choose and writes one CSV file with a SHA-256 checksum per file, for handover to Authentic Memory. Your files are only read. Nothing is changed, moved or deleted.</p><p class="lede">You can stop at any time and continue later.</p>${resume}<div class="actions">${button("begin", "Choose folder", resume !== "")}</div></section>`);
  document.querySelector("#begin")?.addEventListener("click", () => chooseCollection());
  document.querySelector("#resume")?.addEventListener("click", () => resumeRun());
}

async function chooseCollection(): Promise<void> {
  try {
    const selected = await api.selectFolder();
    if (!selected) return;
    root = selected;
    step = "collection";
    shell(`<section class="panel"><span class="eyebrow">Step 1 of 3</span><h1>Folder selected</h1><p>All files in this folder and its subfolders will be recorded. Links and special files are skipped and noted in the report.</p><div class="path-card"><span>Folder</span><code>${esc(root)}</code></div><div class="actions">${button("back", "Back", true)}${button("next", "Choose where to save")}</div></section>`);
    document.querySelector("#back")?.addEventListener("click", () => renderWelcome());
    document.querySelector("#next")?.addEventListener("click", () => chooseOutput());
  } catch (error) { showInlineError(error); }
}

async function chooseOutput(): Promise<void> {
  try {
    // Same naming convention as the CLI and the archivist guide:
    // checksums_<folder>_<date>.csv
    const now = new Date();
    const stamp = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
    const base = (root.split(/[\\/]/).filter(Boolean).pop() ?? "folder")
      .replace(/[/\\:*?"<>| ]/g, "_").slice(0, 60);
    const selected = await api.selectOutput(`checksums_${base}_${stamp}.csv`);
    if (!selected) return;
    output = selected.toLowerCase().endsWith(".csv") ? selected : `${selected}.csv`;
    const resume = await api.inspectResume(output);
    const normalized = (path: string) => path.replaceAll("/", "\\").replace(/[\\]+$/, "").toLocaleLowerCase();
    if (resume.resumable && resume.root && normalized(resume.root) !== normalized(root)) {
      resumeConflict = { root: resume.root, rows: resume.rows };
      renderResumeConflict();
      return;
    }
    resumeConflict = null;
    const mode = resume.resumable ? "resume" : "fresh";
    review = await api.preflight({ root, output, workers: 2, mode });
    renderReview();
  } catch (error) { showInlineError(error); }
}

function renderResumeConflict(): void {
  step = "review";
  shell(`<section class="panel"><span class="eyebrow">Interrupted run</span><h1>This file belongs to a different folder</h1><p>The chosen file already contains ${number.format(resumeConflict?.rows ?? 0)} recorded files from an earlier, interrupted run of the folder below. It will not be mixed with a different folder.</p><div class="path-card"><span>Recorded back then</span><code>${esc(resumeConflict?.root ?? "")}</code></div><div class="path-card"><span>Selected now</span><code>${esc(root)}</code></div><p>Continuing records the earlier folder. Starting over clears the file and records the newly selected folder instead.</p><div class="actions conflict-actions">${button("different", "Choose another file", true)}${button("restart", "Start over", true)}${button("resume-recorded", "Continue earlier run")}</div></section>`);
  document.querySelector("#different")?.addEventListener("click", () => chooseOutput());
  document.querySelector("#restart")?.addEventListener("click", async () => {
    try { resumeConflict = null; review = await api.preflight({ root, output, workers: 2, mode: "fresh" }); renderReview(); }
    catch (error) { showInlineError(error); }
  });
  document.querySelector("#resume-recorded")?.addEventListener("click", async () => {
    if (!resumeConflict) return;
    root = resumeConflict.root;
    resumeConflict = null;
    await resumeRun();
  });
}

function renderReview(): void {
  step = "review";
  const resumeText = review?.willResume
    ? `<div class="notice info"><b>Continuing an interrupted run</b><span>${number.format(review.resume.rows)} files are already recorded and will be kept.</span></div>`
    : "";
  shell(`<section class="panel"><span class="eyebrow">Step 3 of 3</span><h1>Ready to start</h1><p>Depending on the amount of data this can take several hours. You can keep using the computer, and you can stop and continue later at any time.</p><dl class="review-list"><div><dt>Folder</dt><dd>${esc(review?.root ?? root)}</dd></div><div><dt>Result file</dt><dd>${esc(review?.output ?? output)}</dd></div></dl>${resumeText}<div class="actions">${button("back", "Change", true)}${button("start", review?.willResume ? "Continue" : "Start")}</div></section>`);
  document.querySelector("#back")?.addEventListener("click", () => chooseOutput());
  document.querySelector("#start")?.addEventListener("click", () => startRun(review?.willResume ? "resume" : "fresh"));
}

async function resumeRun(): Promise<void> {
  try {
    review = await api.preflight({ root, output, workers: 2, mode: "resume" });
    renderReview();
  } catch (error) { lastRunStore.clear(); showInlineError(error); }
}

async function startRun(mode: RunRequest["mode"]): Promise<void> {
  busy = true;
  cancelRequested = false;
  startedAt = performance.now();
  lastProgressAt = startedAt;
  lastBytes = 0;
  bytesPerSecond = 0;
  step = "progress";
  renderProgress({ Phase: 0, FilesDone: 0, FilesTotal: 0, BytesDone: 0, BytesTotal: 0 });
  lastRunStore.write(root, output);
  try { await api.start({ root, output, workers: 2, mode }); }
  catch (error) { finishFatal(error); }
}

function renderProgress(progress: import("./backend").Progress): void {
  const scanning = progress.Phase === 0;
  const ratio = progress.BytesTotal > 0 ? progress.BytesDone / progress.BytesTotal : progress.FilesTotal > 0 ? progress.FilesDone / progress.FilesTotal : 0;
  const percent = Math.min(100, Math.max(0, ratio * 100));
  const now = performance.now();
  if (progress.BytesDone > lastBytes && now > lastProgressAt) {
    const instant = (progress.BytesDone - lastBytes) / ((now - lastProgressAt) / 1000);
    bytesPerSecond = bytesPerSecond ? bytesPerSecond * 0.75 + instant * 0.25 : instant;
    lastBytes = progress.BytesDone;
    lastProgressAt = now;
  }
  const eta = !scanning && bytesPerSecond > 0 ? formatETA((progress.BytesTotal - progress.BytesDone) / bytesPerSecond) : scanning ? "Counting files…" : "Estimating…";
  if (!document.querySelector(".progress-panel")) {
    shell(`<section class="panel progress-panel" aria-live="polite"><span id="progress-phase" class="eyebrow"></span><h1 id="progress-title"></h1><p id="progress-eta"></p><progress id="progress-bar" class="progress-track" aria-label="Hashing progress" max="100"></progress><div class="metrics"><article><span>Files</span><strong><b id="files-done">0</b> <small>of <b id="files-total">0</b></small></strong></article><article><span>Data read</span><strong><b id="bytes-done">0 B</b> <small>of <b id="bytes-total">0 B</b></small></strong></article><article><span>Elapsed</span><strong id="elapsed">0 sec</strong></article></div><div class="path-card compact"><span>Result file</span><code>${esc(output)}</code></div><div class="actions">${button("cancel", "Cancel", true)}</div></section>`);
    document.querySelector("#cancel")?.addEventListener("click", cancelRun);
  }
  const setText = (selector: string, value: string) => {
    const element = document.querySelector(selector);
    if (element) element.textContent = value;
  };
  setText("#progress-phase", cancelRequested ? "Stopping" : scanning ? "Preparing" : "Hashing");
  setText("#progress-title", cancelRequested ? "Stopping…" : scanning ? "Counting files" : `${percent.toFixed(1)}%`);
  setText("#progress-eta", cancelRequested ? "Finishing the current file. Progress is kept." : eta);
  setText("#files-done", number.format(progress.FilesDone));
  setText("#files-total", number.format(progress.FilesTotal));
  setText("#bytes-done", formatBytes(progress.BytesDone));
  setText("#bytes-total", formatBytes(progress.BytesTotal));
  setText("#elapsed", formatETAElapsed((performance.now() - startedAt) / 1000));
  const bar = document.querySelector<HTMLProgressElement>("#progress-bar");
  if (bar) {
    bar.classList.toggle("indeterminate", scanning);
    if (scanning) bar.removeAttribute("value");
    else bar.value = percent;
  }
}

const formatETAElapsed = (seconds: number) => seconds < 60 ? `${Math.floor(seconds)} sec` : seconds < 3600 ? `${Math.floor(seconds / 60)} min ${Math.floor(seconds % 60)} sec` : `${Math.floor(seconds / 3600)} hr ${Math.floor(seconds % 3600 / 60)} min`;

async function cancelRun(): Promise<void> {
  if (cancelRequested) return;
  cancelRequested = true;
  const button = document.querySelector<HTMLButtonElement>("#cancel");
  if (button) { button.disabled = true; button.textContent = "Stopping…"; }
  const heading = document.querySelector("#progress-title");
  const explanation = document.querySelector("#progress-eta");
  if (heading) heading.textContent = "Stopping…";
  if (explanation) explanation.textContent = "Finishing the current file. Progress is kept.";
  try { await api.cancel(); } catch (error) { showInlineError(error); }
}

function finishFatal(error: unknown): void {
  busy = false;
  fatalError = error instanceof Error ? error.message : String(error);
  finalResult = null;
  renderResult();
}

function renderResult(): void {
  step = "result";
  if (fatalError) {
    shell(`<section class="panel result"><div class="result-icon failure">!</div><h1>The run could not continue</h1><p class="error-copy">${esc(fatalError)}</p><p>Your files were not changed. You can simply try again.</p><div class="actions">${button("home", "Back to start", true)}</div></section>`);
  } else if (finalResult?.Canceled) {
    shell(`<section class="panel result"><div class="result-icon canceled">❚❚</div><h1>Stopped. Nothing is lost.</h1><p>Your progress is saved. Continue now, or close the program and continue another day: the next start will offer to pick up where you stopped.</p><div class="actions">${button("home", "Close", true)}${button("resume", "Continue now")}</div></section>`);
  } else {
    const issues = (finalResult?.FilesFailed ?? 0) + (finalResult?.Warnings ?? 0);
    const warning = issues > 0;
    const manifest = finalResult?.Output ?? output;
    const errorLog = finalResult?.ErrorLog ?? "";
    const files = number.format((finalResult?.FilesHashed ?? 0) + (finalResult?.FilesResumed ?? 0));
    const size = formatBytes(finalResult?.BytesTotal ?? 0);
    const warnBlock = warning
      ? `<div class="notice warning"><b>${number.format(issues)} file${issues === 1 ? "" : "s"} could not be read and are missing from the list.</b><span>Details are in the report next to the result file${errorLog ? `: <code>${esc(errorLog.split(/[\\/]/).pop() ?? "")}</code>` : "."} Please send it along.</span></div>`
      : "";
    shell(`<section class="panel result"><div class="result-icon ${warning ? "warning" : "success"}">${warning ? "!" : "✓"}</div><h1>Done</h1><p>${files} files (${size}) were recorded.</p>${warnBlock}<div class="path-card"><span>Result file</span><code>${esc(manifest)}</code></div><p>Please send the result file to Authentic Memory as agreed.</p><div class="actions">${button("home", "Close", true)}${button("open-manifest", "Open folder")}</div></section>`);
  }
  document.querySelector("#home")?.addEventListener("click", () => { fatalError = ""; finalResult = null; renderWelcome(); });
  document.querySelector("#resume")?.addEventListener("click", () => resumeRun());
  const openFolder = async () => { try { await api.openOutputFolder(); } catch (error) { showInlineError(error); } };
  document.querySelector("#open-manifest")?.addEventListener("click", openFolder);
  document.querySelector("#open-errors")?.addEventListener("click", openFolder);
}

function showInlineError(error: unknown): void {
  const message = error instanceof Error ? error.message : String(error);
  document.querySelector(".inline-error")?.remove();
  const alert = document.createElement("div");
  alert.className = "inline-error";
  alert.setAttribute("role", "alert");
  alert.textContent = message;
  document.querySelector("main")?.prepend(alert);
}

function onEvent(event: EngineEvent): void {
  if (event.kind === "progress" && step === "progress") renderProgress(event.progress);
  if (event.kind === "fatal") finishFatal(event.error);
  if (event.kind === "result") {
    busy = false;
    finalResult = event.result;
    fatalError = "";
    if (!event.result.Canceled) lastRunStore.clear();
    renderResult();
  }
}

window.addEventListener("keydown", (event) => {
  if (event.key === "Tab") document.documentElement.classList.add("kbd");
  if (event.key === "Escape" && busy && !cancelRequested) cancelRun();
});
window.addEventListener("pointerdown", () => document.documentElement.classList.remove("kbd"));

async function init(): Promise<void> {
  // Development only: without the Wails runtime (plain browser via
  // `npm run dev`), load a simulated backend so the flow can be reviewed
  // visually. The condition is compile-time false in production builds, so
  // the bundler drops demo.ts entirely; the shipped app never contains it.
  if (import.meta.env.DEV && !window.go?.wailsadapter?.Backend) {
    const demo = await import("./demo");
    demo.installDemoBackendIfNeeded();
  }
  api.onEngineEvent(onEvent);
  await renderWelcome();
}

void init();
