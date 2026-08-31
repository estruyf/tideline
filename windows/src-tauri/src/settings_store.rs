//! Where the preferences live between launches.
//!
//! macOS keeps these in `UserDefaults`; Windows gets a JSON file under
//! `%APPDATA%\Tideline\`. The field names match the macOS keys so the two files
//! describe the same thing, and a missing field falls back to its default
//! rather than failing the load — an upgrade that adds a setting must never
//! blank the ones already there.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tideline_core::rule::Rule;
use tideline_core::settings::{DateBasis, FolderFormat, RunConfiguration, TypeRule};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AppSettings {
    pub is_enabled: bool,
    pub downloads_path: String,
    pub keep_recent_days: i64,
    pub folder_format: FolderFormat,
    pub date_basis: DateBasis,
    pub watch_folder: bool,
    pub daily_run_enabled: bool,
    pub daily_run_hour: u32,
    pub daily_run_minute: u32,
    pub run_on_launch: bool,
    pub dry_run: bool,
    pub include_folders: bool,
    pub notify_on_move: bool,
    pub skip_names: Vec<String>,
    /// Tried before the type rules, and in this order.
    pub rules: Vec<Rule>,
    pub type_rules: Vec<TypeRule>,
    pub cleanup_after_days: i64,
    pub cleanup_on_schedule: bool,
    pub cleanup_keep_newest: usize,
    pub duplicate_restore_names: bool,
    pub large_file_threshold_mb: u64,
    pub open_at_login: bool,
    pub has_answered_login_suggestion: bool,
}

impl Default for AppSettings {
    fn default() -> Self {
        AppSettings {
            is_enabled: true,
            downloads_path: default_downloads_path().to_string_lossy().to_string(),
            keep_recent_days: 0,
            folder_format: FolderFormat::Daily,
            date_basis: DateBasis::Added,
            watch_folder: true,
            daily_run_enabled: true,
            daily_run_hour: 0,
            daily_run_minute: 5,
            run_on_launch: true,
            dry_run: false,
            include_folders: true,
            notify_on_move: false,
            skip_names: vec!["Inbox".into(), "Screenshots".into()],
            // Nothing is shipped: a rule only exists because someone wrote it.
            rules: Vec::new(),
            type_rules: TypeRule::built_ins(),
            cleanup_after_days: 90,
            cleanup_on_schedule: false,
            cleanup_keep_newest: 3,
            duplicate_restore_names: true,
            large_file_threshold_mb: 100,
            open_at_login: false,
            has_answered_login_suggestion: false,
        }
    }
}

impl AppSettings {
    /// The immutable snapshot a sweep runs against.
    pub fn run_configuration(&self) -> RunConfiguration {
        RunConfiguration {
            root: PathBuf::from(&self.downloads_path),
            keep_recent_days: self.keep_recent_days,
            folder_format: self.folder_format,
            date_basis: self.date_basis,
            include_folders: self.include_folders,
            dry_run: self.dry_run,
            skip_names: self.skip_names.clone(),
            // Only the rules that are switched on ever reach a sweep.
            rules: self
                .rules
                .iter()
                .filter(|r| r.is_enabled)
                .cloned()
                .collect(),
            type_rules: self
                .type_rules
                .iter()
                .filter(|r| r.is_enabled)
                .cloned()
                .collect(),
        }
    }
}

/// `%USERPROFILE%\Downloads`, or the platform equivalent.
pub fn default_downloads_path() -> PathBuf {
    if let Some(dir) = dirs_downloads() {
        return dir;
    }
    PathBuf::from(
        std::env::var("USERPROFILE")
            .unwrap_or_else(|_| std::env::var("HOME").unwrap_or_else(|_| ".".into())),
    )
    .join("Downloads")
}

#[cfg(windows)]
fn dirs_downloads() -> Option<PathBuf> {
    // The user can move Downloads anywhere; the registry is the only place that
    // knows where it actually is. Falling back to the profile is fine when it
    // has not been moved, which is the usual case.
    std::env::var("USERPROFILE")
        .ok()
        .map(|p| PathBuf::from(p).join("Downloads"))
}

#[cfg(not(windows))]
fn dirs_downloads() -> Option<PathBuf> {
    std::env::var("HOME")
        .ok()
        .map(|p| PathBuf::from(p).join("Downloads"))
}

/// Reads the settings file, falling back to defaults for anything it cannot
/// make sense of. A corrupt file is never a reason to refuse to start.
pub fn load(path: &PathBuf) -> AppSettings {
    let Ok(raw) = std::fs::read_to_string(path) else {
        return AppSettings::default();
    };
    let mut settings: AppSettings = serde_json::from_str(&raw).unwrap_or_default();
    // A version that adds a preset shows it, switched off, without disturbing
    // what the user has already set up.
    settings.type_rules = TypeRule::merged(settings.type_rules);
    settings
}

pub fn save(path: &PathBuf, settings: &AppSettings) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    // Written to one side and renamed, so a crash mid-write cannot leave a
    // half-file where the settings used to be.
    let temporary = path.with_extension("json.tmp");
    std::fs::write(&temporary, json).map_err(|e| e.to_string())?;
    std::fs::rename(&temporary, path).map_err(|e| e.to_string())
}
