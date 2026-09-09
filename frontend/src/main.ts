import "./style.css";
import { api, type EngineEvent, type PreflightResult, type Result, type RunRequest } from "./backend";

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

function shell(content: string): void {
  const steps: Step[] = ["collection", "output", "review", "progress", "result"];
  const active = Math.max(0, steps.indexOf(step));
  app.innerHTML = `
    <div class="app-shell">
      <header class="brandbar">
        <div class="brand">
          <svg viewBox="17 33 52 53" class="logo" aria-hidden="true"><path fill="currentColor" d="m 30.959389,86.102479 c -2.703723,-0.452592 -5.237354,-2.571928 -5.960414,-4.985778 -0.237967,-0.794436 -0.251098,-0.80888 -0.984816,-1.083007 -3.23777,-1.209679 -5.388309,-5.019052 -4.545932,-8.052497 0.13729,-0.494383 0.124372,-0.525571 -0.502196,-1.212247 -2.664851,-2.920517 -2.41993,-7.347697 0.571984,-10.338719 l 1.093756,-1.093433 -.318011-.644921 c -1.372133,-2.782717 -.09261,-6.400474 2.807917,-7.939202 .577627-.306426 .616874-.36164 .616874-.867693 0,-3.465179 2.988798,-6.49038 7.079778,-7.165988 .851778-.140667 1.047703-.226114 1.376104-.600142 1.185007,-1.349654 3.954787,-2.19938 5.390196,-1.653639 .413874,.157355 .410424,.235024-.08594,1.9366-.311686,1.068487-.312114,1.080864-.356803,10.463527 l-.04474,9.393776 h-2.512745 c-4.061936,0-4.889604-.478751-5.432611-3.142403-.435229-2.135008-2.376217-4.23112-3.392364-3.66347-.676993,.378192-.560845,1.033635 .315886,1.782651 .872397,.745311 1.069353,1.083269 1.346271,2.310117 .803305,3.558854 2.208481,4.451306 7.009175,4.451635 l2.61286,.000136 v10.33499 c0,11.456953 .05163,10.78414-.8638,11.257524-.95779,.495292-3.708809,.765173-5.220425,.512137 z m8.220737-.767776-.336999-.337012 .04034-20.763134 c.04442-22.858867-.01667-21.17686 .84893-23.370661 3.840617-9.733753 18.699286-9.391963 22.780987,.524024 .821237,1.995095 .833407,2.092004 .903222,7.197535 .03684,2.693738 .115332,4.681433 .183206,4.639485 1.065768-.658682 3.815519,.954667 4.645793,2.725806 l.355748,.758876 .04018,6.886544 c.07746,13.26966-.581175,15.910165-4.819336,19.321276-3.195706,2.572074-3.669525,2.657825-14.978017,2.710679 l-9.327063,.04362 z m15.540196-8.719841 c.04635-.120724-.266929-1.906569-.696131-3.968538 l-.780372-3.749029 .324217-.203851 c4.665078-2.933248 .612236-10.168103-4.422833-7.895329-3.157297,1.42517-3.373535,6.365918-.349112,7.976865 .243035,.129452 .226508,.268531-.43515,3.662389-.681299,3.494653-.770157,4.135201-.597499,4.307855 .221722,.221717 6.869573,.09715 6.95688-.130362 z"/></svg>
          <div><strong>GAMI</strong><span>Hash</span></div>
        </div>
        ${step === "welcome" ? "" : `<ol class="stepper" aria-label="Progress through setup">${steps.map((item, index) => `<li class="${index <= active ? "active" : ""}" aria-current="${item === step ? "step" : "false"}"><span>${index + 1}</span><b>${["Collection", "Output", "Review", "Progress", "Results"][index]}</b></li>`).join("")}</ol>`}
      </header>
      <main>${content}</main>
      <footer><span>Runs entirely on this computer</span><span aria-hidden="true">•</span><span>No upload, accounts, or analytics</span></footer>
    </div>`;
}

function button(id: string, label: string, secondary = false, disabled = false): string {
  return `<button id="${id}" class="button ${secondary ? "secondary" : "primary"}" ${disabled ? "disabled" : ""}>${label}</button>`;
}

async function renderWelcome(): Promise<void> {
  step = "welcome";
  const saved = localStorage.getItem("gami:last-run");
  let resume = "";
  if (saved) {
    try {
      const run = JSON.parse(saved) as { root: string; output: string };
      const state = await api.inspectResume(run.output);
      if (state.resumable) {
        resume = `<section class="resume-card"><div><span class="eyebrow">Interrupted run found</span><strong>${number.format(state.rows)} files are safely recorded</strong><p>${esc(run.root)}</p></div>${button("resume", "Resume run")}</section>`;
        root = run.root;
        output = run.output;
      } else localStorage.removeItem("gami:last-run");
    } catch { localStorage.removeItem("gami:last-run"); }
  }
  shell(`<section class="hero"><span class="eyebrow">Preservation checksum tool</span><h1>Create a trustworthy record of your collection.</h1><p class="lede">GAMI Hash reads every file and records its SHA-256 fingerprint in a CSV manifest. Your originals are never edited, moved, or uploaded.</p><div class="trust-grid"><article><b>Read-only source</b><span>Your collection is opened only for reading.</span></article><article><b>Works offline</b><span>No accounts, cloud services, or tracking.</span></article><article><b>Safe to resume</b><span>Interrupted work continues from a verified checkpoint.</span></article></div>${resume}<div class="actions">${button("begin", "Choose a collection")}</div></section>`);
  document.querySelector("#begin")?.addEventListener("click", () => chooseCollection());
  document.querySelector("#resume")?.addEventListener("click", () => resumeRun());
}

async function chooseCollection(): Promise<void> {
  try {
    const selected = await api.selectFolder();
    if (!selected) return;
    root = selected;
    step = "collection";
    shell(`<section class="panel"><span class="eyebrow">Step 1</span><h1>Collection selected</h1><p>GAMI will include regular files in this folder and its subfolders. Links and special files are reported but never followed.</p><div class="path-card"><span>Collection folder</span><code>${esc(root)}</code></div><div class="actions">${button("back", "Back", true)}${button("next", "Choose output")}</div></section>`);
    document.querySelector("#back")?.addEventListener("click", () => renderWelcome());
    document.querySelector("#next")?.addEventListener("click", () => chooseOutput());
  } catch (error) { showInlineError(error); }
}

async function chooseOutput(): Promise<void> {
  try {
    const now = new Date();
    const stamp = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}_${String(now.getHours()).padStart(2, "0")}-${String(now.getMinutes()).padStart(2, "0")}-${String(now.getSeconds()).padStart(2, "0")}`;
    const selected = await api.selectOutput(`gami-hash-${stamp}.csv`);
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
  shell(`<section class="panel"><span class="eyebrow">Existing checkpoint</span><h1>This output belongs to another collection.</h1><p>The selected manifest contains ${number.format(resumeConflict?.rows ?? 0)} verified rows for the collection below. GAMI will not combine it with a different source.</p><div class="path-card"><span>Checkpoint collection</span><code>${esc(resumeConflict?.root ?? "")}</code></div><div class="path-card"><span>Currently selected collection</span><code>${esc(root)}</code></div><div class="notice warning"><b>Starting over replaces the partial manifest</b><span>Your source files are never changed, but the saved hashing progress for this output will be discarded.</span></div><div class="actions conflict-actions">${button("different", "Choose another output", true)}${button("restart", "Start over", true)}${button("resume-recorded", "Resume recorded collection")}</div></section>`);
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
    ? `<div class="notice info"><b>Verified checkpoint found</b><span>${number.format(review.resume.rows)} existing rows will be validated and reused.</span></div>`
    : `<div class="notice"><b>New manifest</b><span>The selected output will be safely created when you start.</span></div>`;
  shell(`<section class="panel"><span class="eyebrow">Step 3</span><h1>Review before starting</h1><p>Confirm these locations. The output is outside the collection and has passed the engine's safety checks.</p><dl class="review-list"><div><dt>Read from</dt><dd>${esc(review?.root ?? root)}</dd></div><div><dt>Write manifest to</dt><dd>${esc(review?.output ?? output)}</dd></div></dl>${resumeText}<div class="actions">${button("back", "Change output", true)}${button("start", review?.willResume ? "Resume hashing" : "Start hashing")}</div></section>`);
  document.querySelector("#back")?.addEventListener("click", () => chooseOutput());
  document.querySelector("#start")?.addEventListener("click", () => startRun(review?.willResume ? "resume" : "fresh"));
}

async function resumeRun(): Promise<void> {
  try {
    review = await api.preflight({ root, output, workers: 2, mode: "resume" });
    renderReview();
  } catch (error) { localStorage.removeItem("gami:last-run"); showInlineError(error); }
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
  localStorage.setItem("gami:last-run", JSON.stringify({ root, output }));
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
  const eta = !scanning && bytesPerSecond > 0 ? formatETA((progress.BytesTotal - progress.BytesDone) / bytesPerSecond) : scanning ? "Counting files safely…" : "Estimating…";
  if (!document.querySelector(".progress-panel")) {
    shell(`<section class="panel progress-panel" aria-live="polite"><span id="progress-phase" class="eyebrow"></span><h1 id="progress-title"></h1><p id="progress-eta"></p><progress id="progress-bar" class="progress-track" aria-label="Hashing progress" max="100"></progress><div class="metrics"><article><span>Files</span><strong><b id="files-done">0</b> <small>of <b id="files-total">0</b></small></strong></article><article><span>Data read</span><strong><b id="bytes-done">0 B</b> <small>of <b id="bytes-total">0 B</b></small></strong></article><article><span>Elapsed</span><strong id="elapsed">0 sec</strong></article></div><div class="path-card compact"><span>Writing manifest to</span><code>${esc(output)}</code></div><div class="actions">${button("cancel", "Cancel", true)}</div></section>`);
    document.querySelector("#cancel")?.addEventListener("click", cancelRun);
  }
  const setText = (selector: string, value: string) => {
    const element = document.querySelector(selector);
    if (element) element.textContent = value;
  };
  setText("#progress-phase", cancelRequested ? "Saving checkpoint" : scanning ? "Preparing" : "Hashing collection");
  setText("#progress-title", cancelRequested ? "Canceling safely…" : scanning ? "Counting files and bytes" : `${percent.toFixed(1)}% complete`);
  setText("#progress-eta", cancelRequested ? "Finishing current reads and making the partial manifest safe to resume." : eta);
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
  if (button) { button.disabled = true; button.textContent = "Canceling safely…"; }
  const heading = document.querySelector("#progress-title");
  const explanation = document.querySelector("#progress-eta");
  if (heading) heading.textContent = "Canceling safely…";
  if (explanation) explanation.textContent = "Finishing current reads and making the partial manifest safe to resume.";
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
    shell(`<section class="panel result"><div class="result-icon failure">!</div><span class="eyebrow">Run stopped</span><h1>GAMI could not create the manifest.</h1><p class="error-copy">${esc(fatalError)}</p><p>Your collection was not modified. Resolve the problem and try again.</p><div class="actions">${button("home", "Return to start", true)}</div></section>`);
  } else if (finalResult?.Canceled) {
    shell(`<section class="panel result"><div class="result-icon canceled">Ⅱ</div><span class="eyebrow">Canceled safely</span><h1>Your progress has been saved.</h1><p>GAMI saved a partial manifest and a small <code>.part.json</code> checkpoint beside it. Resume validates every saved row before continuing.</p><div class="path-card"><span>Partial manifest</span><code>${esc(finalResult.Output)}</code></div><div class="path-card compact"><span>Resume checkpoint</span><code>${esc(`${finalResult.Output}.part.json`)}</code></div><div class="actions">${button("home", "Close", true)}${button("resume", "Resume now")}</div></section>`);
  } else {
    const issues = (finalResult?.FilesFailed ?? 0) + (finalResult?.Warnings ?? 0);
    const warning = issues > 0;
    const manifest = finalResult?.Output ?? output;
    const errorLog = finalResult?.ErrorLog ?? "";
    const hasErrorLog = errorLog.length > 0;
    const openButtons = hasErrorLog
      ? `${button("open-manifest", "Open manifest folder", true)}${button("open-errors", "Open error log folder")}`
      : button("open-manifest", "Open manifest folder");
    const issueGuidance = hasErrorLog ? "Review the error log before treating the manifest as complete." : "Review the reported omissions before treating the manifest as complete.";
    const errorLogCard = hasErrorLog ? `<div class="path-card"><span>Error log</span><code>${esc(errorLog)}</code></div>` : "";
    shell(`<section class="panel result"><div class="result-icon ${warning ? "warning" : "success"}">${warning ? "!" : "✓"}</div><span class="eyebrow">${warning ? "Completed with warnings" : "Complete"}</span><h1>${warning ? "Your manifest is ready—review the omissions." : "Your manifest is ready."}</h1><div class="summary"><strong>${number.format((finalResult?.FilesHashed ?? 0) + (finalResult?.FilesResumed ?? 0))}</strong><span>files recorded</span></div>${warning ? `<div class="notice warning"><b>${number.format(issues)} item${issues === 1 ? "" : "s"} need attention</b><span>${issueGuidance}</span></div>${errorLogCard}` : ""}<div class="path-card"><span>Manifest saved to</span><code>${esc(manifest)}</code></div><div class="actions">${button("home", "Start another", true)}${openButtons}</div></section>`);
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
    if (!event.result.Canceled) localStorage.removeItem("gami:last-run");
    renderResult();
  }
}

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && busy && !cancelRequested) cancelRun();
});

api.onEngineEvent(onEvent);
renderWelcome();
