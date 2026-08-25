//! Reading the folder, and carrying out what [`crate::organizer::plan`] decided.
//!
//! Everything that touches disk lives here. The rules do not.

use crate::organizer::{self, Entry, PlannedMove, SweepPlan};
use crate::settings::{DateBasis, RunConfiguration};
use chrono::{DateTime, Duration, Local};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::time::SystemTime;

/// What a history entry records.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RecordKind {
    Filed,
    Cleared,
    Removed,
    Renamed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MoveRecord {
    pub date: DateTime<Local>,
    pub name: String,
    pub folder: String,
    pub was_preview: bool,
    pub kind: RecordKind,
    /// Extra context a name and a folder cannot carry. Only ever a subtitle.
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RunResult {
    pub moves: Vec<MoveRecord>,
    /// Only filled on a preview, where it is the whole point: what would move.
    pub plan: Vec<PlannedMove>,
    pub inspected: usize,
    pub left_alone: usize,
    pub errors: Vec<String>,
    pub finished_at: Option<DateTime<Local>>,
}

#[derive(Debug)]
pub enum SweepError {
    FolderMissing(String),
    NotReadable(String),
}

impl std::fmt::Display for SweepError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SweepError::FolderMissing(path) => write!(f, "{path} does not exist."),
            SweepError::NotReadable(path) => write!(f, "{path} could not be read."),
        }
    }
}

impl std::error::Error for SweepError {}

/// Reads the root folder into the values the rules ask about.
///
/// The settle check is the only part that can block: a file written to in the
/// last ten minutes has its size read twice, 1.5 s apart.
pub fn scan(config: &RunConfiguration) -> Result<Vec<Entry>, SweepError> {
    let root = &config.root;
    if !root.is_dir() {
        return Err(SweepError::FolderMissing(root.display().to_string()));
    }

    let listing =
        fs::read_dir(root).map_err(|_| SweepError::NotReadable(root.display().to_string()))?;

    let mut entries = Vec::new();
    for item in listing.flatten() {
        let path = item.path();
        let name = item.file_name().to_string_lossy().to_string();

        // An entry that vanished between listing and stat is simply gone.
        let Ok(metadata) = item.metadata() else {
            continue;
        };
        let is_dir = metadata.is_dir();

        entries.push(Entry {
            stamp: stamp_of(&metadata, config.date_basis),
            settled: if is_dir {
                true
            } else {
                is_settled(&path, &metadata)
            },
            hidden: is_hidden(&name, &metadata),
            size: if is_dir { 0 } else { metadata.len() },
            is_dir,
            name,
        });
    }

    Ok(entries)
}

/// The date this entry is filed by, under the chosen basis.
///
/// Windows has no "date added" attribute, so `Added` and `Created` both read the
/// creation time — which for a download is the moment it arrived. Each basis
/// falls back when its attribute is missing, as filesystems vary in what they
/// keep.
fn stamp_of(metadata: &fs::Metadata, basis: DateBasis) -> Option<DateTime<Local>> {
    let created = metadata.created().ok().map(to_local);
    let modified = metadata.modified().ok().map(to_local);

    match basis {
        DateBasis::Added | DateBasis::Created => created.or(modified),
        DateBasis::Modified => modified.or(created),
    }
}

fn to_local(time: SystemTime) -> DateTime<Local> {
    DateTime::<Local>::from(time)
}

/// Nothing has written to it recently, and its size holds still.
fn is_settled(path: &Path, metadata: &fs::Metadata) -> bool {
    let Ok(modified) = metadata.modified() else {
        // No timestamp to judge by; assume it is done rather than never move it.
        return true;
    };

    let age = Local::now().signed_duration_since(to_local(modified));

    match organizer::settle_check(age.num_seconds()) {
        organizer::SettleCheck::InFlight => false,
        organizer::SettleCheck::Settled => true,
        organizer::SettleCheck::Recheck => {
            // A slow writer can leave an old timestamp between flushes, so the
            // size has to hold still as well.
            let first = metadata.len();
            std::thread::sleep(std::time::Duration::from_millis(1500));
            match fs::metadata(path) {
                Ok(second) => first == second.len(),
                Err(_) => false,
            }
        }
    }
}

#[cfg(windows)]
fn is_hidden(_name: &str, metadata: &fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;
    const FILE_ATTRIBUTE_HIDDEN: u32 = 0x2;
    const FILE_ATTRIBUTE_SYSTEM: u32 = 0x4;
    // Explorer hides both, and neither is ever something the user downloaded.
    metadata.file_attributes() & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM) != 0
}

#[cfg(not(windows))]
fn is_hidden(name: &str, _metadata: &fs::Metadata) -> bool {
    name.starts_with('.')
}

/// Plans a sweep against the folder as it is right now.
pub fn preview(config: &RunConfiguration) -> Result<SweepPlan, SweepError> {
    let entries = scan(config)?;
    Ok(organizer::plan(&entries, config, Local::now()))
}

/// Runs one sweep. Blocking — call it off the UI thread.
pub fn run(config: &RunConfiguration) -> Result<RunResult, SweepError> {
    let now = Local::now();
    let plan = preview(config)?;

    let mut result = RunResult {
        inspected: plan.inspected,
        left_alone: plan.left_alone,
        ..Default::default()
    };

    // Preview mode stops here: the plan is the answer, and nothing on disk has
    // been opened for writing to produce it.
    if config.dry_run {
        result.moves = plan
            .moves
            .iter()
            .map(|m| MoveRecord {
                date: now,
                name: m.name.clone(),
                folder: m.target_folder.clone(),
                was_preview: true,
                kind: RecordKind::Filed,
                detail: None,
            })
            .collect();
        result.plan = plan.moves;
        result.finished_at = Some(Local::now());
        return Ok(result);
    }

    for move_ in &plan.moves {
        let destination = config.root.join(&move_.target_folder);
        let source = config.root.join(&move_.name);

        if let Err(error) = fs::create_dir_all(&destination) {
            result.errors.push(format!("{}: {error}", move_.name));
            continue;
        }

        let target = organizer::free_target(&destination, &move_.name);
        match fs::rename(&source, &target) {
            Ok(()) => result.moves.push(MoveRecord {
                date: Local::now(),
                name: move_.name.clone(),
                folder: move_.target_folder.clone(),
                was_preview: false,
                kind: RecordKind::Filed,
                detail: None,
            }),
            Err(error) => result.errors.push(format!("{}: {error}", move_.name)),
        }
    }

    result.finished_at = Some(Local::now());
    Ok(result)
}

/// Sends a path to the Recycle Bin. Never unlinks — a setting the user regrets
/// has to be a drag back out, not a restore from backup.
#[cfg(windows)]
pub fn recycle(path: &Path) -> Result<(), String> {
    trash::delete(path).map_err(|e| e.to_string())
}

#[cfg(not(windows))]
pub fn recycle(_path: &Path) -> Result<(), String> {
    Err("The recycle bin is only wired up on Windows.".into())
}

/// How long ago, for the settle check. Exposed so the scanner and the tests
/// agree on the arithmetic.
pub fn age_seconds(modified: DateTime<Local>, now: DateTime<Local>) -> i64 {
    now.signed_duration_since(modified).num_seconds()
}

/// Whether a run is due, given when the last one finished.
pub fn is_due(last_run: Option<DateTime<Local>>, now: DateTime<Local>, every: Duration) -> bool {
    match last_run {
        None => true,
        Some(last) => now.signed_duration_since(last) >= every,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;

    /// A sweep against a real folder, with the timestamps forced far enough
    /// into the past that the grace window and the settle check both clear.
    fn folder_with(names: &[&str]) -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        for name in names {
            let mut f = File::create(dir.path().join(name)).unwrap();
            writeln!(f, "contents of {name}").unwrap();
        }
        dir
    }

    /// Backdates every file so it is neither in the grace window nor unsettled.
    fn backdate(dir: &Path, days: u64) {
        let when = SystemTime::now() - std::time::Duration::from_secs(days * 86_400);
        for entry in fs::read_dir(dir).unwrap().flatten() {
            let file = File::options().write(true).open(entry.path()).unwrap();
            file.set_modified(when).unwrap();
        }
    }

    #[test]
    fn a_sweep_moves_old_files_and_leaves_todays() {
        let dir = folder_with(&["old.pdf"]);
        backdate(dir.path(), 3);

        let mut fresh = File::create(dir.path().join("today.pdf")).unwrap();
        writeln!(fresh, "fresh").unwrap();

        let mut config = RunConfiguration::new(dir.path());
        config.skip_names = Vec::new();
        config.date_basis = DateBasis::Modified;

        let result = run(&config).unwrap();

        assert_eq!(result.moves.len(), 1, "errors: {:?}", result.errors);
        assert_eq!(result.moves[0].name, "old.pdf");
        assert!(dir.path().join("today.pdf").exists());
        assert!(!dir.path().join("old.pdf").exists());

        let filed = dir.path().join(&result.moves[0].folder).join("old.pdf");
        assert!(filed.exists(), "expected {filed:?} to exist");
    }

    #[test]
    fn a_preview_moves_nothing() {
        let dir = folder_with(&["old.pdf"]);
        backdate(dir.path(), 3);

        let mut config = RunConfiguration::new(dir.path());
        config.skip_names = Vec::new();
        config.date_basis = DateBasis::Modified;
        config.dry_run = true;

        let result = run(&config).unwrap();

        assert_eq!(result.plan.len(), 1);
        assert!(result.moves.iter().all(|m| m.was_preview));
        assert!(dir.path().join("old.pdf").exists(), "preview moved a file");
    }

    #[test]
    fn a_name_already_taken_is_never_overwritten() {
        let dir = folder_with(&["report.pdf"]);
        backdate(dir.path(), 3);

        let mut config = RunConfiguration::new(dir.path());
        config.skip_names = Vec::new();
        config.date_basis = DateBasis::Modified;

        // Put a file of the same name in the folder the sweep is about to use.
        let plan = preview(&config).unwrap();
        let target_folder = dir.path().join(&plan.moves[0].target_folder);
        fs::create_dir_all(&target_folder).unwrap();
        let mut existing = File::create(target_folder.join("report.pdf")).unwrap();
        writeln!(existing, "the one that was already there").unwrap();

        run(&config).unwrap();

        assert!(target_folder.join("report-1.pdf").exists());
        let kept = fs::read_to_string(target_folder.join("report.pdf")).unwrap();
        assert!(
            kept.contains("already there"),
            "the existing file was overwritten"
        );
    }

    #[test]
    fn a_missing_folder_is_reported_rather_than_created() {
        let config = RunConfiguration::new("/nowhere/at/all/we/hope");
        assert!(matches!(run(&config), Err(SweepError::FolderMissing(_))));
    }

    #[test]
    fn due_dates() {
        let now = Local::now();
        assert!(is_due(None, now, Duration::hours(24)));
        assert!(is_due(
            Some(now - Duration::hours(25)),
            now,
            Duration::hours(24)
        ));
        assert!(!is_due(
            Some(now - Duration::hours(1)),
            now,
            Duration::hours(24)
        ));
    }
}
