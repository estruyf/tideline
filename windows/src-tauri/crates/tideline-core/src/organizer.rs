//! The filing rules: today's downloads stay loose, older ones move into a
//! folder named for the day they arrived.
//!
//! [`plan`] is pure — it takes the entries and answers what would move. [`scan`]
//! reads those entries off disk and [`run`] carries the moves out. Keeping the
//! three apart is what lets the rules be tested against fixtures, and is why a
//! preview and a real sweep cannot drift: both call the same [`plan`].

use crate::rule::RuleRouter;
use crate::settings::RunConfiguration;
use crate::skip::matches_skip_list;
use crate::typefolder::TypeRouter;
use chrono::{DateTime, Datelike, Duration, Local, NaiveDate, TimeZone};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Extensions that mean "still downloading".
pub const INCOMPLETE_EXTENSIONS: [&str; 8] = [
    "crdownload",
    "download",
    "part",
    "partial",
    "opdownload",
    "tmp",
    "temp",
    "aria2",
];

/// A file whose contents changed this recently is assumed to be still in flight.
pub const SETTLE_SECONDS: i64 = 30;

/// Past this, a stale timestamp is taken at face value rather than re-measured.
pub const RECHECK_WINDOW_SECONDS: i64 = 600;

/// One entry in the root folder, reduced to what the rules actually ask about.
///
/// Built by [`scan`] from disk, or by a fixture in a test. Nothing here is a
/// handle to anything — a plan can be made without the folder being present.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub name: String,
    #[serde(default)]
    pub is_dir: bool,
    /// The date this is filed by, already resolved under the chosen basis.
    /// `None` when the platform could give no date at all, which means no move.
    pub stamp: Option<DateTime<Local>>,
    #[serde(default)]
    pub size: u64,
    /// False when something was still writing to it. Folders are never checked.
    #[serde(default = "default_true")]
    pub settled: bool,
    #[serde(default)]
    pub hidden: bool,
    /// Every URL the download was recorded as arriving from — the source and
    /// the referrer, where the platform kept them. Empty is normal: a file
    /// saved out of a mail client or fetched with `curl` carries none.
    #[serde(default)]
    pub where_from: Vec<String>,
}

fn default_true() -> bool {
    true
}

impl Entry {
    /// The part after the last dot, lower-cased. `archive.tar.gz` is `gz`, which
    /// is what both the type rules and the partial-download list expect.
    pub fn extension(&self) -> String {
        Path::new(&self.name)
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase()
    }
}

/// One item a sweep would move, and where to.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlannedMove {
    pub name: String,
    /// Where it would land — a dated folder, or a type folder.
    pub target_folder: String,
    pub stamp: DateTime<Local>,
    pub size: u64,
    pub is_folder: bool,
    /// True when a routing rule claimed it. Exclusive with `is_by_type`.
    #[serde(default)]
    pub is_by_rule: bool,
    /// True when a type rule claimed it rather than the date.
    pub is_by_type: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SweepPlan {
    pub moves: Vec<PlannedMove>,
    pub inspected: usize,
    pub left_alone: usize,
}

/// Why an entry was passed over. Only used to explain a preview; the rules do
/// not branch on it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Skipped {
    ManagedFolder,
    RuleFolder,
    TypeFolder,
    OnSkipList,
    StillDownloading,
    Hidden,
    FoldersExcluded,
    NoDate,
    WithinGraceWindow,
    StillBeingWritten,
}

/// Folder names this app creates itself, in either format, are never re-filed.
///
/// `2026-08-19` or `2026-08`, and nothing else — a folder the user happened to
/// name `2026-08-19-holiday` is theirs, not ours.
pub fn is_managed_folder_name(name: &str) -> bool {
    let bytes = name.as_bytes();
    let digits = |range: std::ops::Range<usize>| bytes[range].iter().all(|b| b.is_ascii_digit());

    match bytes.len() {
        7 => digits(0..4) && bytes[4] == b'-' && digits(5..7),
        10 => digits(0..4) && bytes[4] == b'-' && digits(5..7) && bytes[7] == b'-' && digits(8..10),
        _ => false,
    }
}

/// Works out what a sweep would do, and touches nothing.
///
/// `now` is passed in rather than read, so a fixture can pin the day and the
/// grace window means the same thing in a test as it does at midnight.
pub fn plan(entries: &[Entry], config: &RunConfiguration, now: DateTime<Local>) -> SweepPlan {
    let rules = RuleRouter::new(&config.rules);
    let router = TypeRouter::new(&config.type_rules);
    let cutoff = start_of_day(now) - Duration::days(config.keep_recent_days.max(0));

    let mut sorted: Vec<&Entry> = entries.iter().collect();
    sorted.sort_by(|a, b| a.name.cmp(&b.name));

    let mut plan = SweepPlan::default();

    for entry in sorted {
        plan.inspected += 1;
        match decide(entry, config, &rules, &router, cutoff) {
            Ok(planned) => plan.moves.push(planned),
            Err(_) => plan.left_alone += 1,
        }
    }

    plan
}

/// The whole rule set for one entry, in the order `docs/behaviour.md` lists it.
fn decide(
    entry: &Entry,
    config: &RunConfiguration,
    rules: &RuleRouter,
    router: &TypeRouter,
    cutoff: DateTime<Local>,
) -> Result<PlannedMove, Skipped> {
    if entry.hidden {
        return Err(Skipped::Hidden);
    }
    if is_managed_folder_name(&entry.name) {
        return Err(Skipped::ManagedFolder);
    }
    // A folder a rule owns is a destination, not something to file. This holds
    // even while the rule has no tests yet, so a folder does not get filed away
    // in the middle of writing the rule that fills it.
    if rules.owns(&entry.name) {
        return Err(Skipped::RuleFolder);
    }
    if router.owns(&entry.name) {
        return Err(Skipped::TypeFolder);
    }
    if matches_skip_list(&entry.name, &config.skip_names) {
        return Err(Skipped::OnSkipList);
    }

    let ext = entry.extension();
    if INCOMPLETE_EXTENSIONS.contains(&ext.as_str()) {
        return Err(Skipped::StillDownloading);
    }

    if entry.is_dir {
        // Safari keeps in-progress downloads in a .download bundle. Windows has
        // no equivalent, but a folder shared from a Mac still arrives as one.
        if ext == "download" {
            return Err(Skipped::StillDownloading);
        }
        if !config.include_folders {
            return Err(Skipped::FoldersExcluded);
        }
    }

    let stamp = entry.stamp.ok_or(Skipped::NoDate)?;

    // Anything from today — or inside the grace window — stays loose.
    if start_of_day(stamp) >= cutoff {
        return Err(Skipped::WithinGraceWindow);
    }

    // Folders are never settle-checked: a folder's own timestamp says nothing
    // about what is being written inside it.
    if !entry.is_dir && !entry.settled {
        return Err(Skipped::StillBeingWritten);
    }

    // A rule decides where it goes; the window above already decided that it
    // goes at all. Routing rules are asked first, or `Documents` would swallow
    // an invoice before `Invoices` ever saw it.
    let by_rule = rules.folder_name(entry);
    let by_type = if by_rule.is_none() {
        router.folder_name(&ext)
    } else {
        None
    };

    let target_folder = match by_rule.or(by_type) {
        Some(folder) => folder.to_string(),
        None => stamp.format(config.folder_format.date_format()).to_string(),
    };

    Ok(PlannedMove {
        name: entry.name.clone(),
        target_folder,
        stamp,
        size: entry.size,
        is_folder: entry.is_dir,
        is_by_rule: by_rule.is_some(),
        is_by_type: by_type.is_some(),
    })
}

/// Midnight at the start of the day the given moment falls in.
///
/// Falls back to the moment itself across a DST gap, where midnight does not
/// exist in local time — filing a file an hour early beats not filing it.
pub fn start_of_day(moment: DateTime<Local>) -> DateTime<Local> {
    NaiveDate::from_ymd_opt(moment.year(), moment.month(), moment.day())
        .and_then(|d| d.and_hms_opt(0, 0, 0))
        .and_then(|naive| Local.from_local_datetime(&naive).earliest())
        .unwrap_or(moment)
}

/// What the settle check should do with a file, given how long ago it changed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SettleCheck {
    /// Written to just now — leave it for the next sweep.
    InFlight,
    /// Recently written; read the size twice and move it only if they agree.
    Recheck,
    /// Old enough to take at face value.
    Settled,
}

pub fn settle_check(age_seconds: i64) -> SettleCheck {
    if age_seconds < SETTLE_SECONDS {
        SettleCheck::InFlight
    } else if age_seconds < RECHECK_WINDOW_SECONDS {
        SettleCheck::Recheck
    } else {
        SettleCheck::Settled
    }
}

/// `report.pdf` → `report-1.pdf` when the name is taken. Nothing is overwritten.
///
/// `is_taken` is a predicate rather than a folder so the counting can be tested
/// without a filesystem, and so the caller decides what "taken" means.
pub fn free_name<F: Fn(&str) -> bool>(name: &str, is_taken: F) -> String {
    if !is_taken(name) {
        return name.to_string();
    }

    let path = Path::new(name);
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or(name);
    let ext = path.extension().and_then(|e| e.to_str());

    let mut index = 1u32;
    loop {
        let attempt = match ext {
            Some(ext) => format!("{stem}-{index}.{ext}"),
            None => format!("{stem}-{index}"),
        };
        if !is_taken(&attempt) {
            return attempt;
        }
        index += 1;
    }
}

/// The same thing against a real folder.
pub fn free_target(folder: &Path, name: &str) -> PathBuf {
    folder.join(free_name(name, |candidate| folder.join(candidate).exists()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::{FolderFormat, TypeRule};

    fn at(text: &str) -> DateTime<Local> {
        // `2026-08-19 14:30` in whatever zone the test machine keeps, which is
        // the zone the app files in.
        let naive = chrono::NaiveDateTime::parse_from_str(text, "%Y-%m-%d %H:%M").unwrap();
        Local.from_local_datetime(&naive).unwrap()
    }

    fn file(name: &str, stamp: &str) -> Entry {
        Entry {
            name: name.into(),
            is_dir: false,
            stamp: Some(at(stamp)),
            size: 1024,
            settled: true,
            hidden: false,
            where_from: Vec::new(),
        }
    }

    fn config() -> RunConfiguration {
        let mut c = RunConfiguration::new("/downloads");
        c.skip_names = Vec::new();
        c
    }

    const NOW: &str = "2026-08-19 09:00";

    #[test]
    fn managed_folder_names() {
        assert!(is_managed_folder_name("2026-08-19"));
        assert!(is_managed_folder_name("2026-08"));
        assert!(!is_managed_folder_name("2026-08-19-holiday"));
        assert!(!is_managed_folder_name("2026-8-19"));
        assert!(!is_managed_folder_name("Installers"));
        assert!(!is_managed_folder_name(""));
        assert!(!is_managed_folder_name("20xx-08-19"));
    }

    #[test]
    fn managed_folder_names_do_not_panic_on_multibyte() {
        // Ten bytes, four characters — the byte-indexed check must not slice
        // through a character boundary.
        assert!(!is_managed_folder_name("日本語です"));
        assert!(!is_managed_folder_name("café-au"));
    }

    #[test]
    fn yesterdays_file_is_filed_todays_is_not() {
        let entries = vec![
            file("old.pdf", "2026-08-18 10:00"),
            file("new.pdf", "2026-08-19 08:00"),
        ];
        let plan = plan(&entries, &config(), at(NOW));

        assert_eq!(plan.moves.len(), 1);
        assert_eq!(plan.moves[0].name, "old.pdf");
        assert_eq!(plan.moves[0].target_folder, "2026-08-18");
        assert_eq!(plan.left_alone, 1);
        assert_eq!(plan.inspected, 2);
    }

    #[test]
    fn the_grace_window_holds_files_back() {
        let entries = vec![
            file("two-days.pdf", "2026-08-17 10:00"),
            file("yesterday.pdf", "2026-08-18 10:00"),
        ];

        let mut c = config();
        c.keep_recent_days = 1;
        let plan = plan(&entries, &c, at(NOW));

        assert_eq!(plan.moves.len(), 1);
        assert_eq!(plan.moves[0].name, "two-days.pdf");
    }

    #[test]
    fn monthly_folders() {
        let mut c = config();
        c.folder_format = FolderFormat::Monthly;
        let plan = plan(&[file("old.pdf", "2026-07-18 10:00")], &c, at(NOW));
        assert_eq!(plan.moves[0].target_folder, "2026-07");
    }

    #[test]
    fn a_type_rule_claims_the_file_but_not_the_timing() {
        let mut rule = TypeRule::new("i", "Installers", &["msi"], false);
        rule.is_enabled = true;
        let mut c = config();
        c.type_rules = vec![rule];

        let entries = vec![
            file("setup.msi", "2026-08-18 10:00"),
            file("today.msi", "2026-08-19 08:00"),
        ];
        let plan = plan(&entries, &c, at(NOW));

        // Only the older one moves, and it goes by type rather than by date.
        assert_eq!(plan.moves.len(), 1);
        assert_eq!(plan.moves[0].name, "setup.msi");
        assert_eq!(plan.moves[0].target_folder, "Installers");
        assert!(plan.moves[0].is_by_type);
    }

    #[test]
    fn our_own_folders_are_never_refiled() {
        let mut rule = TypeRule::new("i", "Installers", &["msi"], false);
        rule.is_enabled = true;
        let mut c = config();
        c.type_rules = vec![rule];

        let entries = vec![
            Entry {
                is_dir: true,
                ..file("2026-08-18", "2026-08-18 10:00")
            },
            Entry {
                is_dir: true,
                ..file("2026-08", "2026-08-18 10:00")
            },
            Entry {
                is_dir: true,
                ..file("Installers", "2026-08-18 10:00")
            },
        ];
        let plan = plan(&entries, &c, at(NOW));

        assert!(plan.moves.is_empty());
        assert_eq!(plan.left_alone, 3);
    }

    #[test]
    fn partial_downloads_and_hidden_files_stay() {
        let entries = vec![
            file("big.zip.crdownload", "2026-08-18 10:00"),
            file("half.part", "2026-08-18 10:00"),
            Entry {
                hidden: true,
                ..file(".DS_Store", "2026-08-18 10:00")
            },
            Entry {
                settled: false,
                ..file("writing.iso", "2026-08-18 10:00")
            },
        ];
        let plan = plan(&entries, &config(), at(NOW));
        assert!(plan.moves.is_empty(), "{:?}", plan.moves);
    }

    #[test]
    fn folders_are_never_settle_checked() {
        // A folder carrying settled=false still moves: the flag is meaningless
        // for a directory, and the scanner never sets it.
        let entry = Entry {
            is_dir: true,
            settled: false,
            ..file("holiday-pics", "2026-08-18 10:00")
        };
        let plan = plan(&[entry], &config(), at(NOW));
        assert_eq!(plan.moves.len(), 1);
    }

    #[test]
    fn folders_can_be_excluded_altogether() {
        let mut c = config();
        c.include_folders = false;
        let entry = Entry {
            is_dir: true,
            ..file("holiday-pics", "2026-08-18 10:00")
        };
        assert!(plan(&[entry], &c, at(NOW)).moves.is_empty());
    }

    #[test]
    fn the_skip_list_is_honoured() {
        let mut c = config();
        c.skip_names = vec!["Inbox".into(), "*.iso".into()];
        let entries = vec![
            Entry {
                is_dir: true,
                ..file("Inbox", "2026-08-18 10:00")
            },
            file("ubuntu.iso", "2026-08-18 10:00"),
            file("keep.pdf", "2026-08-18 10:00"),
        ];
        let plan = plan(&entries, &c, at(NOW));
        assert_eq!(plan.moves.len(), 1);
        assert_eq!(plan.moves[0].name, "keep.pdf");
    }

    #[test]
    fn an_entry_with_no_date_is_left_alone() {
        let entry = Entry {
            stamp: None,
            ..file("mystery.pdf", "2026-08-18 10:00")
        };
        assert!(plan(&[entry], &config(), at(NOW)).moves.is_empty());
    }

    #[test]
    fn the_plan_is_ordered_by_name() {
        let entries = vec![
            file("zebra.pdf", "2026-08-18 10:00"),
            file("apple.pdf", "2026-08-18 10:00"),
            file("mango.pdf", "2026-08-18 10:00"),
        ];
        let names: Vec<_> = plan(&entries, &config(), at(NOW))
            .moves
            .iter()
            .map(|m| m.name.as_str().to_string())
            .collect();
        assert_eq!(names, vec!["apple.pdf", "mango.pdf", "zebra.pdf"]);
    }

    #[test]
    fn settle_policy() {
        assert_eq!(settle_check(0), SettleCheck::InFlight);
        assert_eq!(settle_check(29), SettleCheck::InFlight);
        assert_eq!(settle_check(30), SettleCheck::Recheck);
        assert_eq!(settle_check(599), SettleCheck::Recheck);
        assert_eq!(settle_check(600), SettleCheck::Settled);
        // A clock skew that puts the file in the future must not read as in-flight.
        assert_eq!(settle_check(-5), SettleCheck::InFlight);
    }

    #[test]
    fn free_names_count_up() {
        let taken = ["report.pdf", "report-1.pdf"];
        let is_taken = |c: &str| taken.contains(&c);

        assert_eq!(free_name("report.pdf", is_taken), "report-2.pdf");
        assert_eq!(free_name("fresh.pdf", is_taken), "fresh.pdf");
    }

    #[test]
    fn free_names_handle_odd_shapes() {
        let is_taken = |c: &str| ["README", "archive.tar.gz", ".env"].contains(&c);

        assert_eq!(free_name("README", is_taken), "README-1");
        // Only the last extension is kept, which is what the macOS app does too.
        assert_eq!(free_name("archive.tar.gz", is_taken), "archive.tar-1.gz");
        assert_eq!(free_name(".env", is_taken), ".env-1");
    }

    #[test]
    fn extensions_come_from_the_last_dot() {
        assert_eq!(file("archive.tar.gz", NOW).extension(), "gz");
        assert_eq!(file("Setup.EXE", NOW).extension(), "exe");
        assert_eq!(file("README", NOW).extension(), "");
    }
}
