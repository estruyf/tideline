// The window. Everything it knows comes from the Rust side; nothing about which
// files move is decided here.

const { invoke } = window.__TAURI__.core;

let settings = null;
let saveTimer = null;

const $ = (id) => document.getElementById(id);

// -- Loading and saving -----------------------------------------------------

async function load() {
  settings = await invoke("get_settings");
  fillForm();
  await refreshStatus();
  await drawAbout();
}

/// Saving is debounced: typing a folder path should not write the file on every
/// keystroke, and a sweep must never read a half-typed one.
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {
    try {
      await invoke("save_settings", { settings });
      note("Saved");
    } catch (error) {
      note(`Could not save: ${error}`);
    }
  }, 400);
}

function note(text) {
  $("saved-note").textContent = text;
  setTimeout(() => ($("saved-note").textContent = ""), 2000);
}

// -- The form ---------------------------------------------------------------

function fillForm() {
  $("enabled").checked = settings.is_enabled;
  $("downloads-path").value = settings.downloads_path;
  $("keep-recent-days").value = String(settings.keep_recent_days);
  $("folder-format").value = settings.folder_format;
  $("date-basis").value = settings.date_basis;
  $("include-folders").checked = settings.include_folders;
  $("dry-run").checked = settings.dry_run;
  $("skip-names").value = settings.skip_names.join("\n");
  $("daily-run-enabled").checked = settings.daily_run_enabled;
  $("daily-run-time").value =
    `${String(settings.daily_run_hour).padStart(2, "0")}:` +
    `${String(settings.daily_run_minute).padStart(2, "0")}`;
  $("run-on-launch").checked = settings.run_on_launch;

  drawSketch();
  drawRules();
  drawBasisHint();
  drawLoginItem();
}

/// Read from Windows rather than the settings file — the Startup tab in Task
/// Manager can switch it off behind the app's back.
async function drawLoginItem() {
  try {
    $("open-at-login").checked = await invoke("get_open_at_login");
  } catch {
    // The registry can refuse; leaving the box as it is beats guessing.
  }
}

function bind(id, key, read) {
  $(id).addEventListener("input", () => {
    settings[key] = read($(id));
    save();
    drawSketch();
    drawBasisHint();
  });
}

bind("enabled", "is_enabled", (el) => el.checked);
bind("downloads-path", "downloads_path", (el) => el.value.trim());
bind("keep-recent-days", "keep_recent_days", (el) => Number(el.value));
bind("folder-format", "folder_format", (el) => el.value);
bind("date-basis", "date_basis", (el) => el.value);
bind("include-folders", "include_folders", (el) => el.checked);
bind("dry-run", "dry_run", (el) => el.checked);
bind("run-on-launch", "run_on_launch", (el) => el.checked);
bind("daily-run-enabled", "daily_run_enabled", (el) => el.checked);

// Blank lines are dropped rather than stored as a pattern that matches nothing.
$("skip-names").addEventListener("input", (event) => {
  settings.skip_names = event.target.value
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  save();
});

$("daily-run-time").addEventListener("input", (event) => {
  const [hour, minute] = event.target.value.split(":").map(Number);
  if (Number.isFinite(hour) && Number.isFinite(minute)) {
    settings.daily_run_hour = hour;
    settings.daily_run_minute = minute;
    save();
  }
});

// -- The sketch -------------------------------------------------------------

function drawSketch() {
  const monthly = settings.folder_format === "monthly";
  const older = monthly ? "2026-07" : "2026-08-18";
  const older2 = monthly ? "2026-08" : "2026-08-19";

  $("sketch").textContent = [
    "Downloads/",
    `├── ${older}/`,
    "│   └── invoice.pdf",
    `├── ${older2}/`,
    "│   ├── slides.pptx",
    "│   └── screenshot.png",
    "├── report.pdf          ← downloaded today, stays put",
    "└── archive.zip         ← downloaded today, stays put",
  ].join("\n");
}

function drawBasisHint() {
  // Windows has no per-folder "date added" attribute, so the first two options
  // read the same timestamp. Saying so beats letting someone switch between
  // them and wonder why nothing changed.
  const hints = {
    added:
      "The moment the file appeared in the folder. On Windows this is the creation time, which for a download is when it arrived.",
    created:
      "The date the file itself was created. On Windows this is the same timestamp as above.",
    modified:
      "The day the file was last written to. Editing an old file re-files it.",
  };
  $("basis-hint").textContent = hints[settings.date_basis] ?? "";
}

function drawRules() {
  const container = $("type-rules");
  container.textContent = "";

  settings.type_rules.forEach((rule, index) => {
    const row = document.createElement("label");
    row.className = "rule";

    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = rule.isEnabled;
    box.addEventListener("change", () => {
      settings.type_rules[index].isEnabled = box.checked;
      save();
    });

    const name = document.createElement("span");
    name.textContent = rule.name;

    const exts = document.createElement("span");
    exts.className = "exts";
    exts.textContent = rule.extensions.map((e) => `.${e}`).join(", ");

    row.append(box, name, exts);
    container.append(row);
  });
}

// This one is applied straight away instead of being debounced with the rest:
// Windows owns it, so the checkbox shows what the OS reports back, not what was
// asked for.
$("open-at-login").addEventListener("change", async (event) => {
  const wanted = event.target.checked;
  try {
    event.target.checked = await invoke("set_open_at_login", { enabled: wanted });
    note(wanted ? "Tideline will start when you sign in" : "Startup entry removed");
  } catch (error) {
    event.target.checked = !wanted;
    note(`Could not change it: ${error}`);
  }
});

// -- Status -----------------------------------------------------------------

function when(iso) {
  if (!iso) return null;
  return new Date(iso).toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

async function refreshStatus() {
  const status = await invoke("status");

  const banner = $("banner");
  if (!status.folder_exists) {
    banner.textContent = `${status.downloads_path} does not exist. Pick another folder under Filing.`;
    banner.hidden = false;
  } else {
    banner.hidden = true;
  }

  const last = when(status.last_run);
  if (!last) {
    $("summary").textContent = status.enabled
      ? "Not run yet."
      : "Filing is paused.";
  } else {
    const moved = status.moved_last_run;
    const verb = status.dry_run ? "would have filed" : "filed";
    $("summary").textContent =
      moved === 0
        ? `Last run ${last} — nothing to file.`
        : `Last run ${last} — ${verb} ${moved} item${moved === 1 ? "" : "s"}.`;
  }

  const next = when(status.next_run);
  $("next").textContent = next ? `Next sweep ${next}.` : "No sweep scheduled.";

  $("run").textContent = status.dry_run ? "Preview a Sweep…" : "File Now";
  $("preview").hidden = status.dry_run;
}

function showActivity(result) {
  const list = $("activity");
  list.textContent = "";

  const moves = result.moves ?? result.plan ?? [];
  if (moves.length === 0) {
    const empty = document.createElement("li");
    empty.className = "empty";
    empty.textContent = "Nothing to file.";
    list.append(empty);
    return;
  }

  for (const move of moves.slice(0, 12)) {
    const row = document.createElement("li");
    const name = document.createElement("span");
    name.textContent = move.name;
    const folder = document.createElement("span");
    folder.className = "folder";
    folder.textContent = move.folder ?? move.target_folder;
    row.append(name, folder);
    list.append(row);
  }
}

$("run").addEventListener("click", async () => {
  $("run").disabled = true;
  try {
    showActivity(await invoke("run_sweep"));
    await refreshStatus();
  } catch (error) {
    note(String(error));
  } finally {
    $("run").disabled = false;
  }
});

$("preview").addEventListener("click", async () => {
  try {
    showActivity(await invoke("preview_sweep"));
  } catch (error) {
    note(String(error));
  }
});

// -- About ------------------------------------------------------------------

/// Filled once on load. Everything here is fixed for the life of the process,
/// so there is nothing to refresh.
async function drawAbout() {
  const about = await invoke("about");

  $("about-name").textContent = about.name;
  $("about-version").textContent = about.webview_version
    ? `Version ${about.version} · WebView2 ${about.webview_version}`
    : `Version ${about.version}`;

  // The URL is the label: a link is more use when you can read where it goes.
  $("about-repository").textContent = about.repository.replace("https://", "");
  $("about-author").textContent = about.author;
  // Into the <bdi>, not the button: the button reads right-to-left so the
  // ellipsis lands at the front and the file name survives, and the isolate is
  // what stops that flipping the path's own leading slash to the far end.
  $("about-settings").firstElementChild.textContent = about.settings_path;
}

// The window asks for a link by name and the Rust side decides what that means,
// so nothing here can send the browser somewhere of its own choosing.
for (const button of document.querySelectorAll("[data-link]")) {
  button.addEventListener("click", async () => {
    try {
      await invoke("open_link", { name: button.dataset.link });
    } catch (error) {
      note(String(error));
    }
  });
}

$("about-settings").addEventListener("click", async () => {
  try {
    await invoke("reveal_settings_file");
  } catch (error) {
    note(`Could not show it: ${error}`);
  }
});

// -- Tabs -------------------------------------------------------------------

const tabs = [...document.querySelectorAll(".tabs button")];

function selectTab(tab, focus = false) {
  for (const other of tabs) {
    const chosen = other === tab;
    other.classList.toggle("active", chosen);
    other.setAttribute("aria-selected", String(chosen));
    // Only the selected tab is a tab stop, so Tab moves past the strip into the
    // panel rather than through all three headings first.
    other.tabIndex = chosen ? 0 : -1;
  }
  for (const panel of document.querySelectorAll(".tab")) {
    panel.hidden = panel.dataset.panel !== tab.dataset.tab;
  }
  if (focus) tab.focus();
}

for (const tab of tabs) {
  tab.addEventListener("click", () => selectTab(tab));
}

// A tablist is expected to move under the arrow keys and wrap at either end.
document.querySelector(".tabs").addEventListener("keydown", (event) => {
  const step = { ArrowLeft: -1, ArrowRight: 1 }[event.key];
  if (!step) return;
  event.preventDefault();
  const at = tabs.findIndex((tab) => tab.classList.contains("active"));
  selectTab(tabs[(at + step + tabs.length) % tabs.length], true);
});

selectTab(tabs[0]);

load();
