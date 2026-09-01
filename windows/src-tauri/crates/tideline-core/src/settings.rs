//! Every preference a sweep reads, and the shapes they are stored in.
//!
//! The field names match the macOS app's `UserDefaults` keys so a settings file
//! written by one is readable by the other.

use serde::{Deserialize, Serialize};

/// One folder per day, or one per month.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum FolderFormat {
    #[default]
    Daily,
    Monthly,
}

impl FolderFormat {
    /// The `chrono` format string the folder is named with.
    pub fn date_format(self) -> &'static str {
        match self {
            FolderFormat::Daily => "%Y-%m-%d",
            FolderFormat::Monthly => "%Y-%m",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            FolderFormat::Daily => "One folder per day",
            FolderFormat::Monthly => "One folder per month",
        }
    }
}

/// Which of a file's dates decides the folder it lands in.
///
/// On Windows `Added` and `Created` both resolve to the NTFS creation time:
/// there is no per-folder "date added" attribute to read. See
/// `docs/behaviour.md` for what that does and does not change.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum DateBasis {
    #[default]
    Added,
    Created,
    Modified,
}

impl DateBasis {
    pub fn label(self) -> &'static str {
        match self {
            // Worded for Windows, where this is the creation time rather than
            // a separate attribute — promising "date added" would be a lie.
            DateBasis::Added => "Date the file arrived",
            DateBasis::Created => "Date the file was created",
            DateBasis::Modified => "Date last modified",
        }
    }
}

/// A folder at the root that claims files by extension: with `Installers` on, a
/// `.msi` lands in `Installers/` rather than in the folder named for the day it
/// arrived.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TypeRule {
    /// Stable across renames, so a shipped rule the user renamed is still
    /// recognised as that rule next launch.
    pub id: String,
    pub name: String,
    pub extensions: Vec<String>,
    #[serde(rename = "isEnabled")]
    pub is_enabled: bool,
    #[serde(rename = "isBuiltIn")]
    pub is_built_in: bool,
}

impl TypeRule {
    pub fn new(id: &str, name: &str, extensions: &[&str], built_in: bool) -> Self {
        TypeRule {
            id: id.to_string(),
            name: name.to_string(),
            extensions: normalize(extensions.iter().map(|s| s.to_string())),
            is_enabled: false,
            is_built_in: built_in,
        }
    }

    /// The rules the app ships with, all switched off. Nothing is filed by type
    /// until the user says so.
    ///
    /// The macOS list, with the Windows equivalents added where the Mac one is
    /// Apple-only: `.exe`/`.msi` alongside `.dmg`/`.pkg`, `.lnk` is left out
    /// entirely (a shortcut is not a download).
    pub fn built_ins() -> Vec<TypeRule> {
        vec![
            TypeRule::new(
                "installers",
                "Installers",
                &["exe", "msi", "msix", "appx", "iso", "dmg", "pkg", "mpkg"],
                true,
            ),
            TypeRule::new(
                "archives",
                "Archives",
                &["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"],
                true,
            ),
            TypeRule::new(
                "images",
                "Images",
                &[
                    "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp",
                    "svg",
                ],
                true,
            ),
            TypeRule::new(
                "documents",
                "Documents",
                &[
                    "pdf", "doc", "docx", "pages", "rtf", "txt", "md", "odt", "epub",
                ],
                true,
            ),
            TypeRule::new(
                "spreadsheets",
                "Spreadsheets",
                &["xls", "xlsx", "numbers", "csv", "tsv", "ods"],
                true,
            ),
            TypeRule::new(
                "presentations",
                "Presentations",
                &["ppt", "pptx", "key", "odp"],
                true,
            ),
            TypeRule::new(
                "audio",
                "Audio",
                &["mp3", "m4a", "wav", "aac", "flac", "aiff", "aif", "ogg"],
                true,
            ),
            TypeRule::new(
                "video",
                "Video",
                &["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv"],
                true,
            ),
            TypeRule::new(
                "fonts",
                "Fonts",
                &["ttf", "otf", "ttc", "woff", "woff2"],
                true,
            ),
        ]
    }

    /// Stored rules, with any shipped rule the stored list has never seen
    /// appended — so a version that adds a preset shows it, switched off,
    /// without disturbing what the user has already set up.
    pub fn merged(stored: Vec<TypeRule>) -> Vec<TypeRule> {
        let known: Vec<String> = stored.iter().map(|r| r.id.clone()).collect();
        let mut result = stored;
        for rule in TypeRule::built_ins() {
            if !known.contains(&rule.id) {
                result.push(rule);
            }
        }
        result
    }

    /// `.msi, .exe` — how the list reads back in the settings window.
    pub fn display_extensions(&self) -> String {
        self.extensions
            .iter()
            .map(|e| format!(".{e}"))
            .collect::<Vec<_>>()
            .join(", ")
    }

    /// A folder name has to be usable as one, and must not look like something
    /// the app files by date — a rule called `2026-08` would collide with the
    /// dated folders and clearing would take it away.
    ///
    /// The reserved DOS device names are Windows' own trap: a folder called
    /// `CON` or `NUL` cannot be created at all.
    pub fn is_valid_folder_name(name: &str) -> bool {
        is_valid_folder_name(name)
    }
}

/// A destination folder name has to be usable as one, and must not look like
/// something the app files by date — a rule called `2026-08` would collide with
/// the dated folders and clearing would take it away.
///
/// The reserved DOS device names are Windows' own trap: a folder called `CON`
/// or `NUL` cannot be created at all.
///
/// Type rules and routing rules are held to the same standard, since both end
/// up as a folder in the root.
pub fn is_valid_folder_name(name: &str) -> bool {
    const RESERVED: [&str; 22] = [
        "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8",
        "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    ];

    let trimmed = name.trim();
    if trimmed.is_empty() || trimmed.chars().count() > 60 {
        return false;
    }
    if trimmed.starts_with('.') {
        return false;
    }
    // Windows forbids rather more than macOS does, and a trailing dot or
    // space is silently stripped by the shell — which would rename the
    // folder out from under the rule.
    if trimmed.contains(['/', '\\', ':', '*', '?', '"', '<', '>', '|']) {
        return false;
    }
    if trimmed.ends_with('.') || trimmed.ends_with(' ') {
        return false;
    }
    let stem = trimmed
        .split('.')
        .next()
        .unwrap_or(trimmed)
        .to_ascii_uppercase();
    if RESERVED.contains(&stem.as_str()) {
        return false;
    }
    !crate::organizer::is_managed_folder_name(trimmed)
}

/// Lower-cased, leading dots dropped, duplicates removed, order kept.
pub fn normalize<I: IntoIterator<Item = String>>(values: I) -> Vec<String> {
    let mut seen: Vec<String> = Vec::new();
    for value in values {
        let cleaned = value.trim().to_lowercase();
        let cleaned = cleaned.trim_start_matches('.').to_string();
        if cleaned.is_empty() || seen.contains(&cleaned) {
            continue;
        }
        seen.push(cleaned);
    }
    seen
}

/// Accepts whatever separator comes to hand — `msi, exe`, `msi exe`, `.msi;.exe`.
pub fn parse_extensions(text: &str) -> Vec<String> {
    normalize(
        text.split([',', ' ', ';', '\n', '\t'])
            .map(|s| s.to_string()),
    )
}

/// An immutable copy of the settings, so a sweep on a background thread never
/// reads a value the UI is busy changing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunConfiguration {
    pub root: std::path::PathBuf,
    #[serde(default)]
    pub keep_recent_days: i64,
    #[serde(default)]
    pub folder_format: FolderFormat,
    #[serde(default)]
    pub date_basis: DateBasis,
    #[serde(default = "default_true")]
    pub include_folders: bool,
    #[serde(default)]
    pub dry_run: bool,
    #[serde(default)]
    pub skip_names: Vec<String>,
    /// Tried before the type rules, and in this order. Only the rules that are
    /// switched on ever reach a sweep.
    #[serde(default)]
    pub rules: Vec<crate::rule::Rule>,
    /// Only the rules that are switched on ever reach a sweep.
    #[serde(default)]
    pub type_rules: Vec<TypeRule>,
}

fn default_true() -> bool {
    true
}

impl RunConfiguration {
    pub fn new(root: impl Into<std::path::PathBuf>) -> Self {
        RunConfiguration {
            root: root.into(),
            keep_recent_days: 0,
            folder_format: FolderFormat::Daily,
            date_basis: DateBasis::Added,
            include_folders: true,
            dry_run: false,
            skip_names: vec!["Inbox".into(), "Screenshots".into()],
            rules: Vec::new(),
            type_rules: Vec::new(),
        }
    }
}
