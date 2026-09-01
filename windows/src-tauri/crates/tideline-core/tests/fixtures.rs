//! Runs the shared cases in `fixtures/sweep-cases.json`.
//!
//! These are the cases both apps are expected to agree on. Adding one here and
//! nowhere else is the point: the file is the contract, and each implementation
//! brings its own runner to it.

use chrono::{DateTime, Local, NaiveDateTime, TimeZone};
use serde::Deserialize;
use std::path::PathBuf;
use tideline_core::organizer::{plan, Entry};
use tideline_core::rule::Rule;
use tideline_core::settings::{DateBasis, FolderFormat, RunConfiguration, TypeRule};

#[derive(Debug, Deserialize)]
struct Case {
    name: String,
    now: String,
    /// A case describing behaviour this engine has not implemented yet. The
    /// contract is written down first, so the fixture is allowed to be ahead of
    /// the code; dropping the flag is what turns it into a failing test.
    #[serde(default)]
    pending: bool,
    #[serde(default)]
    config: CaseConfig,
    entries: Vec<CaseEntry>,
    expected: Vec<Expected>,
}

#[derive(Debug, Default, Deserialize)]
struct CaseConfig {
    #[serde(default)]
    keep_recent_days: i64,
    #[serde(default)]
    folder_format: FolderFormat,
    #[serde(default)]
    date_basis: DateBasis,
    #[serde(default = "yes")]
    include_folders: bool,
    #[serde(default)]
    skip_names: Vec<String>,
    #[serde(default)]
    rules: Vec<Rule>,
    #[serde(default)]
    type_rules: Vec<TypeRule>,
}

fn yes() -> bool {
    true
}

#[derive(Debug, Deserialize)]
struct CaseEntry {
    name: String,
    #[serde(default)]
    is_dir: bool,
    /// A naive local time, or null for "no date could be read".
    stamp: Option<String>,
    #[serde(default)]
    size: u64,
    #[serde(default = "yes")]
    settled: bool,
    #[serde(default)]
    hidden: bool,
    #[serde(default)]
    where_from: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct Expected {
    name: String,
    target_folder: String,
    #[serde(default)]
    is_by_rule: bool,
    #[serde(default)]
    is_by_type: bool,
}

/// Naive local time — see `fixtures/README.md` for why these are not absolute.
fn local(text: &str) -> DateTime<Local> {
    let naive = NaiveDateTime::parse_from_str(text, "%Y-%m-%dT%H:%M:%S")
        .unwrap_or_else(|e| panic!("bad timestamp {text:?}: {e}"));
    Local
        .from_local_datetime(&naive)
        .earliest()
        .unwrap_or_else(|| panic!("{text:?} does not exist in the local zone"))
}

fn fixtures_path() -> PathBuf {
    // crates/tideline-core -> src-tauri -> windows -> repo root
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../../fixtures/sweep-cases.json")
}

#[test]
fn shared_cases_agree() {
    let path = fixtures_path();
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("could not read {}: {e}", path.display()));
    let cases: Vec<Case> = serde_json::from_str(&raw).expect("fixtures are not valid JSON");

    assert!(!cases.is_empty(), "no cases found in {}", path.display());

    let mut failures = Vec::new();
    let mut pending = 0;

    for case in &cases {
        if case.pending {
            pending += 1;
            continue;
        }

        let config = RunConfiguration {
            root: PathBuf::from("/downloads"),
            keep_recent_days: case.config.keep_recent_days,
            folder_format: case.config.folder_format,
            date_basis: case.config.date_basis,
            include_folders: case.config.include_folders,
            dry_run: false,
            skip_names: case.config.skip_names.clone(),
            rules: case
                .config
                .rules
                .iter()
                .filter(|r| r.is_enabled)
                .cloned()
                .collect(),
            type_rules: case
                .config
                .type_rules
                .iter()
                .filter(|r| r.is_enabled)
                .cloned()
                .collect(),
        };

        let entries: Vec<Entry> = case
            .entries
            .iter()
            .map(|e| Entry {
                name: e.name.clone(),
                is_dir: e.is_dir,
                stamp: e.stamp.as_deref().map(local),
                size: e.size,
                settled: e.settled,
                hidden: e.hidden,
                where_from: e.where_from.clone(),
            })
            .collect();

        let result = plan(&entries, &config, local(&case.now));

        let got: Vec<(String, String, bool, bool)> = result
            .moves
            .iter()
            .map(|m| {
                (
                    m.name.clone(),
                    m.target_folder.clone(),
                    m.is_by_rule,
                    m.is_by_type,
                )
            })
            .collect();
        let want: Vec<(String, String, bool, bool)> = case
            .expected
            .iter()
            .map(|e| {
                (
                    e.name.clone(),
                    e.target_folder.clone(),
                    e.is_by_rule,
                    e.is_by_type,
                )
            })
            .collect();

        if got != want {
            failures.push(format!(
                "\n  {}\n    expected {want:#?}\n    got      {got:#?}",
                case.name
            ));
        }

        // Every entry is either moved or left alone; nothing may fall through.
        if result.inspected != case.entries.len() {
            failures.push(format!(
                "\n  {}\n    inspected {} of {} entries",
                case.name,
                result.inspected,
                case.entries.len()
            ));
        }
        if result.moves.len() + result.left_alone != result.inspected {
            failures.push(format!(
                "\n  {}\n    {} moved + {} left alone != {} inspected",
                case.name,
                result.moves.len(),
                result.left_alone,
                result.inspected
            ));
        }
    }

    assert!(
        failures.is_empty(),
        "{} case(s) disagree:{}",
        failures.len(),
        failures.join("")
    );

    if pending > 0 {
        println!(
            "{} shared cases agree, {pending} pending",
            cases.len() - pending
        );
    } else {
        println!("{} shared cases agree", cases.len());
    }
}
