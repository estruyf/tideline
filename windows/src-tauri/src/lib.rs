//! The Windows front end.
//!
//! The rules live in `tideline-core`; this wires them to a window, a tray icon
//! and a schedule. Everything here is about *when* a sweep happens and how it
//! is shown — never about which files move.

mod app_info;
mod settings_store;

use chrono::{DateTime, Datelike, Local, NaiveDate, TimeZone};
use serde::Serialize;
use settings_store::AppSettings;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager, State};
use tauri_plugin_autostart::ManagerExt;
use tideline_core::organizer::SweepPlan;
use tideline_core::sweep::{self, RunResult};

/// Everything the app knows that is not on disk.
pub struct Tideline {
    settings: Mutex<AppSettings>,
    settings_path: PathBuf,
    last_run: Mutex<Option<DateTime<Local>>>,
    last_result: Mutex<Option<RunResult>>,
}

impl Tideline {
    fn snapshot(&self) -> AppSettings {
        self.settings.lock().expect("settings lock").clone()
    }
}

/// What the Status tab shows.
#[derive(Serialize)]
pub struct Status {
    enabled: bool,
    dry_run: bool,
    downloads_path: String,
    folder_exists: bool,
    last_run: Option<DateTime<Local>>,
    next_run: Option<DateTime<Local>>,
    moved_last_run: usize,
    left_alone_last_run: usize,
    errors: Vec<String>,
}

#[tauri::command]
fn get_settings(state: State<Tideline>) -> AppSettings {
    state.snapshot()
}

#[tauri::command]
fn save_settings(settings: AppSettings, state: State<Tideline>) -> Result<(), String> {
    settings_store::save(&state.settings_path, &settings)?;
    *state.settings.lock().map_err(|e| e.to_string())? = settings;
    Ok(())
}

/// What a sweep would do, having touched nothing.
#[tauri::command]
fn preview_sweep(state: State<Tideline>) -> Result<SweepPlan, String> {
    let config = state.snapshot().run_configuration();
    sweep::preview(&config).map_err(|e| e.to_string())
}

/// One sweep, now. Honours preview mode: with it on, nothing moves.
#[tauri::command]
fn run_sweep(state: State<Tideline>) -> Result<RunResult, String> {
    let config = state.snapshot().run_configuration();
    let result = sweep::run(&config).map_err(|e| e.to_string())?;

    *state.last_run.lock().map_err(|e| e.to_string())? = result.finished_at;
    *state.last_result.lock().map_err(|e| e.to_string())? = Some(result.clone());

    Ok(result)
}

#[tauri::command]
fn status(state: State<Tideline>) -> Status {
    let settings = state.snapshot();
    let last_run = *state.last_run.lock().expect("last run lock");
    let last = state.last_result.lock().expect("last result lock");

    Status {
        folder_exists: PathBuf::from(&settings.downloads_path).is_dir(),
        next_run: next_daily_run(&settings, Local::now()),
        moved_last_run: last.as_ref().map(|r| r.moves.len()).unwrap_or(0),
        left_alone_last_run: last.as_ref().map(|r| r.left_alone).unwrap_or(0),
        errors: last.as_ref().map(|r| r.errors.clone()).unwrap_or_default(),
        enabled: settings.is_enabled,
        dry_run: settings.dry_run,
        downloads_path: settings.downloads_path,
        last_run,
    }
}

/// Whether Windows launches the app at sign-in.
///
/// Read from the OS rather than the settings file: the Startup tab in Task
/// Manager can switch it off behind the app's back, and the checkbox has to
/// show what is actually true.
#[tauri::command]
fn get_open_at_login(app: AppHandle) -> bool {
    app.autolaunch().is_enabled().unwrap_or(false)
}

#[tauri::command]
fn set_open_at_login(
    enabled: bool,
    app: AppHandle,
    state: State<Tideline>,
) -> Result<bool, String> {
    let manager = app.autolaunch();
    if enabled {
        manager.enable().map_err(|e| e.to_string())?;
    } else {
        manager.disable().map_err(|e| e.to_string())?;
    }

    // Store what the OS ended up with, not what was asked for.
    let actual = manager.is_enabled().unwrap_or(enabled);
    let mut settings = state.settings.lock().map_err(|e| e.to_string())?;
    settings.open_at_login = actual;
    settings_store::save(&state.settings_path, &settings)?;

    Ok(actual)
}

/// What the About tab shows.
#[derive(Serialize)]
pub struct About {
    name: String,
    version: String,
    /// WebView2 draws this window and updates itself on Microsoft's schedule
    /// rather than ours, so which one is installed belongs in a bug report
    /// beside the app's own version.
    webview_version: Option<String>,
    author: String,
    repository: String,
    settings_path: String,
}

#[tauri::command]
fn about(app: AppHandle, state: State<Tideline>) -> About {
    About {
        name: app_info::NAME.to_string(),
        version: app.package_info().version.to_string(),
        webview_version: tauri::webview_version().ok(),
        author: app_info::AUTHOR.to_string(),
        repository: app_info::REPOSITORY.to_string(),
        settings_path: state.settings_path.to_string_lossy().to_string(),
    }
}

/// Open one of the app's own links in the default browser.
#[tauri::command]
fn open_link(name: String) -> Result<(), String> {
    let url = app_info::link(&name).ok_or_else(|| format!("No such link: {name}"))?;
    tauri_plugin_opener::open_url(url, None::<&str>).map_err(|e| e.to_string())
}

/// Show the settings file in Explorer, selected, rather than opening it — the
/// answer to "where does this live" is usually the folder, not the JSON.
#[tauri::command]
fn reveal_settings_file(state: State<Tideline>) -> Result<(), String> {
    tauri_plugin_opener::reveal_item_in_dir(&state.settings_path).map_err(|e| e.to_string())
}

#[tauri::command]
fn default_downloads_path() -> String {
    settings_store::default_downloads_path()
        .to_string_lossy()
        .to_string()
}

/// The next moment the daily sweep is due, or `None` when it is switched off.
///
/// Kept pure and taking `now` so the rollover can be tested without waiting for
/// midnight.
fn next_daily_run(settings: &AppSettings, now: DateTime<Local>) -> Option<DateTime<Local>> {
    if !settings.daily_run_enabled || !settings.is_enabled {
        return None;
    }

    let at = |date: NaiveDate| -> Option<DateTime<Local>> {
        date.and_hms_opt(settings.daily_run_hour, settings.daily_run_minute, 0)
            .and_then(|naive| Local.from_local_datetime(&naive).earliest())
    };

    let today = NaiveDate::from_ymd_opt(now.year(), now.month(), now.day())?;

    match at(today) {
        // Already past today's slot, so the next one is tomorrow's.
        Some(slot) if slot > now => Some(slot),
        _ => at(today.succ_opt()?),
    }
}

/// Whether the daily sweep should fire now: its time has come round and it has
/// not already run since.
///
/// Comparing against the last run rather than counting down means a machine
/// asleep at the appointed minute still sweeps when it wakes, which is the
/// whole point of a scheduled tidy at five past midnight.
fn daily_run_is_due(
    settings: &AppSettings,
    last_run: Option<DateTime<Local>>,
    now: DateTime<Local>,
) -> bool {
    if !settings.is_enabled || !settings.daily_run_enabled {
        return false;
    }

    let Some(today) = NaiveDate::from_ymd_opt(now.year(), now.month(), now.day()) else {
        return false;
    };
    let Some(slot) = today
        .and_hms_opt(settings.daily_run_hour, settings.daily_run_minute, 0)
        .and_then(|naive| Local.from_local_datetime(&naive).earliest())
    else {
        return false;
    };

    if now < slot {
        return false;
    }

    match last_run {
        None => true,
        Some(last) => last < slot,
    }
}

/// Wakes once a minute and sweeps when the daily slot has come round.
///
/// A minute of granularity is deliberate: a timer set to fire once, far in the
/// future, drifts across sleep and hibernation, and Windows is generous with
/// both. Polling a cheap comparison costs nothing and cannot drift.
fn start_scheduler(app: AppHandle) {
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_secs(60));

        let state = app.state::<Tideline>();
        let settings = state.snapshot();
        let last_run = *state.last_run.lock().expect("last run lock");

        if !daily_run_is_due(&settings, last_run, Local::now()) {
            continue;
        }

        let config = settings.run_configuration();
        if let Ok(result) = sweep::run(&config) {
            *state.last_run.lock().expect("last run lock") = result.finished_at;
            *state.last_result.lock().expect("last result lock") = Some(result);
        }
    });
}

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let file_now = MenuItem::with_id(app, "file-now", "File Downloads Now", true, None::<&str>)?;
    let open = MenuItem::with_id(app, "open", "Open Tideline", true, None::<&str>)?;
    let downloads = MenuItem::with_id(
        app,
        "downloads",
        "Open Downloads Folder",
        true,
        None::<&str>,
    )?;
    let starts = app.autolaunch().is_enabled().unwrap_or(false);
    let login = CheckMenuItem::with_id(
        app,
        "open-at-login",
        "Start When I Sign In",
        true,
        starts,
        None::<&str>,
    )?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;

    let menu = Menu::with_items(
        app,
        &[&open, &file_now, &downloads, &login, &separator, &quit],
    )?;

    let login_item = login.clone();

    TrayIconBuilder::with_id("main")
        .menu(&menu)
        .tooltip("Tideline")
        .on_menu_event(move |app, event| match event.id().as_ref() {
            "file-now" => {
                let state = app.state::<Tideline>();
                let config = state.snapshot().run_configuration();
                if let Ok(result) = sweep::run(&config) {
                    *state.last_run.lock().expect("last run lock") = result.finished_at;
                    *state.last_result.lock().expect("last result lock") = Some(result);
                }
            }
            "open" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            "downloads" => {
                let path = app.state::<Tideline>().snapshot().downloads_path;
                let _ = tauri_plugin_opener::open_path(path, None::<&str>);
            }
            "open-at-login" => {
                let manager = app.autolaunch();
                let starts = manager.is_enabled().unwrap_or(false);
                let _ = if starts {
                    manager.disable()
                } else {
                    manager.enable()
                };

                // The stored value follows what the OS reports, so a refusal
                // is recorded rather than the request that was refused.
                let now_starts = manager.is_enabled().unwrap_or(starts);
                let state = app.state::<Tideline>();
                let locked = state.settings.lock();
                if let Ok(mut settings) = locked {
                    settings.open_at_login = now_starts;
                    let _ = settings_store::save(&state.settings_path, &settings);
                }

                // Clicking flipped the tick already; put it back if Windows
                // refused, so the menu never claims something untrue.
                let _ = login_item.set_checked(now_starts);
            }
            // Closing the window leaves the app filing in the background, so
            // quitting has to be explicit — this is the only way out.
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_dialog::init())
        // `--minimized` tells the copy Windows starts at sign-in to come up
        // without a window, the way the macOS app starts with no window and no
        // Dock icon. MacosLauncher is ignored on Windows but the signature
        // wants it.
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--minimized"]),
        ))
        .setup(|app| {
            let settings_path = app
                .path()
                .app_config_dir()
                .unwrap_or_else(|_| PathBuf::from("."))
                .join("settings.json");

            let mut settings = settings_store::load(&settings_path);
            let run_on_launch = settings.run_on_launch && settings.is_enabled;
            let config = settings.run_configuration();

            // The Startup tab in Task Manager can switch the app off without
            // telling us, so the OS wins and the file is corrected to match.
            let actually_starts = app.autolaunch().is_enabled().unwrap_or(false);
            if settings.open_at_login != actually_starts {
                settings.open_at_login = actually_starts;
                let _ = settings_store::save(&settings_path, &settings);
            }

            app.manage(Tideline {
                settings: Mutex::new(settings),
                settings_path,
                last_run: Mutex::new(None),
                last_result: Mutex::new(None),
            });

            build_tray(app.handle())?;

            // Started by Windows at sign-in: come up in the tray with no
            // window, so signing in does not throw a window at you. Clicking
            // the app, or the tray's "Open Tideline", brings it back.
            let launched_at_login = std::env::args().any(|arg| arg == "--minimized");
            if let Some(window) = app.get_webview_window("main") {
                if launched_at_login {
                    let _ = window.hide();
                } else {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }

            // Covers a scheduled run missed because the machine was off.
            if run_on_launch {
                let handle = app.handle().clone();
                std::thread::spawn(move || {
                    if let Ok(result) = sweep::run(&config) {
                        let state = handle.state::<Tideline>();
                        *state.last_run.lock().expect("last run lock") = result.finished_at;
                        *state.last_result.lock().expect("last result lock") = Some(result);
                    }
                });
            }

            start_scheduler(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| {
            // Closing the window drops it out of sight; the app keeps filing
            // and the tray icon stays, exactly as the macOS one does.
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            preview_sweep,
            run_sweep,
            status,
            default_downloads_path,
            get_open_at_login,
            set_open_at_login,
            about,
            open_link,
            reveal_settings_file,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Tideline");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(text: &str) -> DateTime<Local> {
        let naive = chrono::NaiveDateTime::parse_from_str(text, "%Y-%m-%d %H:%M").unwrap();
        Local.from_local_datetime(&naive).earliest().unwrap()
    }

    fn settings() -> AppSettings {
        AppSettings {
            daily_run_hour: 0,
            daily_run_minute: 5,
            ..Default::default()
        }
    }

    #[test]
    fn the_next_run_is_today_when_the_slot_is_still_ahead() {
        let next = next_daily_run(&settings(), at("2026-08-19 00:01")).unwrap();
        assert_eq!(next, at("2026-08-19 00:05"));
    }

    #[test]
    fn the_next_run_rolls_over_once_the_slot_has_passed() {
        let next = next_daily_run(&settings(), at("2026-08-19 09:00")).unwrap();
        assert_eq!(next, at("2026-08-20 00:05"));
    }

    #[test]
    fn the_next_run_rolls_over_a_month_end() {
        let next = next_daily_run(&settings(), at("2026-08-31 09:00")).unwrap();
        assert_eq!(next, at("2026-09-01 00:05"));
    }

    #[test]
    fn there_is_no_next_run_when_it_is_switched_off() {
        let mut s = settings();
        s.daily_run_enabled = false;
        assert!(next_daily_run(&s, at("2026-08-19 09:00")).is_none());

        let mut s = settings();
        s.is_enabled = false;
        assert!(next_daily_run(&s, at("2026-08-19 09:00")).is_none());
    }

    #[test]
    fn a_run_is_due_once_the_slot_has_passed_and_not_before() {
        let s = settings();
        assert!(!daily_run_is_due(&s, None, at("2026-08-19 00:01")));
        assert!(daily_run_is_due(&s, None, at("2026-08-19 00:06")));
    }

    #[test]
    fn a_run_is_not_repeated_once_it_has_happened() {
        let s = settings();
        let ran = at("2026-08-19 00:06");
        assert!(!daily_run_is_due(&s, Some(ran), at("2026-08-19 09:00")));
        // ...but tomorrow's slot is a fresh one.
        assert!(daily_run_is_due(&s, Some(ran), at("2026-08-20 00:06")));
    }

    #[test]
    fn a_slot_missed_while_the_machine_slept_fires_on_waking() {
        // Last swept two days ago; the machine wakes at lunchtime.
        let s = settings();
        let ran = at("2026-08-17 00:06");
        assert!(daily_run_is_due(&s, Some(ran), at("2026-08-19 12:00")));
    }

    #[test]
    fn nothing_is_due_while_filing_is_paused() {
        let mut s = settings();
        s.is_enabled = false;
        assert!(!daily_run_is_due(&s, None, at("2026-08-19 09:00")));
    }
}
