//! Rules that claim a file by what it is called, or by where it came from.
//!
//! A type rule asks what a file *is*, which settles a `.msi` and settles
//! nothing about an invoice: an invoice is a PDF like every other PDF. What
//! marks one out is its name, or the URL it arrived from — so a rule is a folder
//! and a list of tests, and the rule says whether one of them matching is
//! enough or all of them have to agree.
//!
//! Rules are consulted before the type rules and after everything that decides
//! whether a file moves at all. They answer *where*, never *when*.
//!
//! The contract is `docs/behaviour.md`; the cases are `fixtures/sweep-cases.json`.

use crate::organizer::Entry;
use crate::settings::is_valid_folder_name;
use crate::skip::glob_match_with;
use serde::{Deserialize, Serialize};

/// What a test looks at.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Field {
    /// The entry's own name, extension included.
    #[default]
    Name,
    /// Each URL the download was recorded as arriving from, in turn.
    WhereFrom,
}

impl Field {
    pub fn label(self) -> &'static str {
        match self {
            Field::Name => "Name",
            Field::WhereFrom => "Downloaded from",
        }
    }
}

/// One thing a rule asks about a file.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuleTest {
    #[serde(default)]
    pub field: Field,
    /// The skip list's grammar — `*`, `?`, `[a-z]`, `[!abc]` — so `*invoice*`
    /// means "contains" without needing a second operator.
    pub pattern: String,
    /// Off by default, unlike the skip list on macOS. A skip pattern names a
    /// file you can already see; a rule is a hunt for a word that could have
    /// been typed either way, and a rule that quietly stops matching is not
    /// something anyone notices.
    #[serde(rename = "matchCase", default)]
    pub match_case: bool,
}

impl RuleTest {
    pub fn new(field: Field, pattern: &str) -> Self {
        RuleTest {
            field,
            pattern: pattern.to_string(),
            match_case: false,
        }
    }

    /// Whether this test claims the entry.
    ///
    /// An empty pattern claims nothing. A half-written rule in the settings
    /// window would otherwise match everything the moment the field was
    /// cleared.
    pub fn matches(&self, entry: &Entry) -> bool {
        let pattern = self.pattern.trim();
        if pattern.is_empty() {
            return false;
        }

        match self.field {
            Field::Name => glob_match_with(pattern, &entry.name, self.match_case),
            // The interesting word is often escaped inside a query string, so
            // the URL is decoded before it is matched: someone who typed
            // `*/facturen/*` means to find `?path=%2Ffacturen%2F`.
            Field::WhereFrom => entry
                .where_from
                .iter()
                .any(|url| glob_match_with(pattern, &percent_decode(url), self.match_case)),
        }
    }
}

/// Whether a rule needs one of its tests or every one of them.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Match {
    /// Any one test is enough. What a rule has always meant, and the default a
    /// rule written before the setting existed falls back to.
    #[default]
    Any,
    /// Every test has to agree.
    All,
}

/// A folder in the root, and the tests that send files to it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Rule {
    /// Stable across renames, so a rule the user renamed is still the same rule
    /// next launch.
    pub id: String,
    /// The destination: a folder name in the root.
    pub name: String,
    /// What a list calls this rule, when that is not simply its folder. The
    /// engine never reads it; it is carried so writing the settings back does
    /// not throw away what the other platform's window put there.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(rename = "isEnabled")]
    pub is_enabled: bool,
    /// Whether one test is enough or all of them have to agree.
    #[serde(rename = "match", default)]
    pub match_mode: Match,
    #[serde(default)]
    pub tests: Vec<RuleTest>,
}

impl Rule {
    pub fn new(id: &str, name: &str, tests: Vec<RuleTest>) -> Self {
        Rule {
            id: id.to_string(),
            name: name.to_string(),
            title: None,
            is_enabled: false,
            match_mode: Match::Any,
            tests,
        }
    }

    /// Whether this rule claims the entry.
    ///
    /// A rule with no filled-in test claims nothing, which is what a rule
    /// someone has only just added looks like. An empty pattern is dropped
    /// before the question is asked rather than answered `false` inside it:
    /// under `all` a half-written test would otherwise stop the rule matching
    /// anything at all.
    pub fn matches(&self, entry: &Entry) -> bool {
        let mut live = self
            .tests
            .iter()
            .filter(|test| !test.pattern.trim().is_empty());
        match self.match_mode {
            Match::Any => live.any(|test| test.matches(entry)),
            Match::All => {
                let mut live = live.peekable();
                live.peek().is_some() && live.all(|test| test.matches(entry))
            }
        }
    }
}

/// Decides which rule, if any, claims a given file, and knows the names of the
/// folders those rules own so filing never files one of them away.
///
/// Built once per sweep from an immutable snapshot of the rules.
pub struct RuleRouter {
    /// Enabled rules whose folder name is usable, in the order they are tried.
    rules: Vec<Rule>,
    /// Lower-cased folder names, for the "is this a destination?" question.
    owned_names: Vec<String>,
}

impl RuleRouter {
    /// Only enabled rules should be handed to this. They are tried in order and
    /// the first match wins, which is the order the settings window shows.
    pub fn new(rules: &[Rule]) -> Self {
        let mut kept: Vec<Rule> = Vec::new();
        let mut owned_names: Vec<String> = Vec::new();

        for rule in rules {
            let name = rule.name.trim();
            if !is_valid_folder_name(name) {
                continue;
            }
            let lowered = name.to_lowercase();
            if !owned_names.contains(&lowered) {
                owned_names.push(lowered);
            }
            kept.push(Rule {
                name: name.to_string(),
                ..rule.clone()
            });
        }

        RuleRouter {
            rules: kept,
            owned_names,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.rules.is_empty()
    }

    /// The folder this file belongs in, or `None` to let the type rules and
    /// then the date decide.
    pub fn folder_name(&self, entry: &Entry) -> Option<&str> {
        self.rules
            .iter()
            .find(|rule| rule.matches(entry))
            .map(|rule| rule.name.as_str())
    }

    /// A rule's folder is never itself filed into a dated one.
    pub fn owns(&self, name: &str) -> bool {
        self.owned_names.contains(&name.to_lowercase())
    }
}

/// `%2F` back to `/`, so a pattern can be written the way the path reads.
///
/// Anything that is not a valid escape is left exactly as it was: a lone `%` in
/// a filename-turned-URL is far more likely than a typo in an escape, and
/// mangling it would lose a character the pattern might be looking for.
pub fn percent_decode(text: &str) -> String {
    if !text.contains('%') {
        return text.to_string();
    }

    let bytes = text.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;

    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(high), Some(low)) = (hex(bytes[i + 1]), hex(bytes[i + 2])) {
                out.push(high * 16 + low);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }

    // A percent escape can name a byte that is not valid UTF-8 on its own. The
    // pattern could never have matched it anyway, so a replacement character is
    // a better answer than throwing the whole URL away.
    String::from_utf8_lossy(&out).into_owned()
}

fn hex(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Local;

    fn entry(name: &str, where_from: &[&str]) -> Entry {
        Entry {
            name: name.into(),
            is_dir: false,
            stamp: Some(Local::now()),
            size: 1024,
            settled: true,
            hidden: false,
            where_from: where_from.iter().map(|s| s.to_string()).collect(),
        }
    }

    fn enabled(id: &str, name: &str, tests: Vec<RuleTest>) -> Rule {
        let mut rule = Rule::new(id, name, tests);
        rule.is_enabled = true;
        rule
    }

    #[test]
    fn a_name_test_ignores_case_by_default() {
        let test = RuleTest::new(Field::Name, "invoice-*");
        assert!(test.matches(&entry("Invoice-0005.pdf", &[])));
        assert!(test.matches(&entry("INVOICE-0005.PDF", &[])));
        assert!(!test.matches(&entry("statement-0005.pdf", &[])));
    }

    #[test]
    fn match_case_compares_exactly() {
        let mut test = RuleTest::new(Field::Name, "Invoice-*");
        test.match_case = true;
        assert!(test.matches(&entry("Invoice-0005.pdf", &[])));
        assert!(!test.matches(&entry("INVOICE-0005.pdf", &[])));
    }

    #[test]
    fn folding_is_ascii_only() {
        // Ä and ä stay different words. Full Unicode folding is
        // locale-dependent, and the two engines have to agree.
        let test = RuleTest::new(Field::Name, "factuur-ä*");
        assert!(test.matches(&entry("Factuur-ä-0042.pdf", &[])));
        assert!(!test.matches(&entry("Factuur-Ä-0042.pdf", &[])));
    }

    #[test]
    fn a_where_from_test_reads_every_recorded_url() {
        let test = RuleTest::new(Field::WhereFrom, "*invoice*");
        // The identifying word is in the path, not the host — matching only the
        // hostname would miss this entirely.
        assert!(test.matches(&entry(
            "logitech-palm-rest.pdf",
            &[
                "https://api.global-e.com/Document/CustomerReceiptInvoice?documentParam=KqND",
                "https://www.logitech.com/",
            ],
        )));
        assert!(!test.matches(&entry("manual.pdf", &["https://www.logitech.com/"])));
    }

    #[test]
    fn a_url_is_decoded_before_it_is_matched() {
        let test = RuleTest::new(Field::WhereFrom, "*/facturen/*");
        assert!(test.matches(&entry(
            "20260702.pdf",
            &["https://portal.example.com/download?path=%2Ffacturen%2Ffactuur-42.pdf"],
        )));
        assert!(!test.matches(&entry(
            "bon.pdf",
            &["https://portal.example.com/download?path=%2Fbonnen%2Fbon-7.pdf"],
        )));
    }

    #[test]
    fn a_file_with_no_recorded_source_matches_nothing_on_that_field() {
        let test = RuleTest::new(Field::WhereFrom, "*invoice*");
        // Not an error, and not a match: the rule falls through to its next
        // test, and the file to the next rule.
        assert!(!test.matches(&entry("Invoice-0005.pdf", &[])));
    }

    #[test]
    fn tests_are_ord() {
        let rule = enabled(
            "invoices",
            "Invoices",
            vec![
                RuleTest::new(Field::Name, "*invoice*"),
                RuleTest::new(Field::WhereFrom, "*stripe*"),
            ],
        );
        assert!(rule.matches(&entry("Invoice-0005.pdf", &[])));
        assert!(rule.matches(&entry(
            "2026-07.pdf",
            &["https://stripe-upload-api.s3.aws/x"]
        )));
        assert!(!rule.matches(&entry("holiday.jpg", &["https://example.com/"])));
    }

    #[test]
    fn a_rule_set_to_all_needs_every_test() {
        let mut rule = enabled(
            "stripe-invoices",
            "Stripe invoices",
            vec![
                RuleTest::new(Field::Name, "*invoice*"),
                RuleTest::new(Field::WhereFrom, "*stripe.com*"),
            ],
        );
        rule.match_mode = Match::All;

        assert!(rule.matches(&entry(
            "invoice-0042.pdf",
            &["https://files.stripe.com/invoices/acct_1/0042"]
        )));
        // Each of these satisfies one test and not the other, which under `any`
        // would have been enough for both of them.
        assert!(!rule.matches(&entry(
            "invoice-from-the-bank.pdf",
            &["https://bank.example.com/"]
        )));
        assert!(!rule.matches(&entry(
            "products.csv",
            &["https://files.stripe.com/exports/products"]
        )));
    }

    #[test]
    fn a_half_written_test_does_not_stop_a_rule_set_to_all() {
        let mut rule = enabled(
            "invoices",
            "Invoices",
            vec![
                RuleTest::new(Field::Name, "*invoice*"),
                RuleTest::new(Field::WhereFrom, "   "),
            ],
        );
        rule.match_mode = Match::All;
        assert!(rule.matches(&entry("invoice-0042.pdf", &[])));
    }

    #[test]
    fn a_rule_set_to_all_with_nothing_written_down_claims_nothing() {
        let mut rule = enabled("new", "Invoices", vec![RuleTest::new(Field::Name, "")]);
        rule.match_mode = Match::All;
        assert!(!rule.matches(&entry("anything.pdf", &[])));
    }

    #[test]
    fn a_rule_stored_without_a_match_means_any() {
        // Every rule written before the setting existed, and every rule the
        // Windows window has ever saved.
        let rule: Rule = serde_json::from_str(
            r#"{"id":"invoices","name":"Invoices","isEnabled":true,
                "tests":[{"field":"name","pattern":"*invoice*"},
                         {"field":"where_from","pattern":"*stripe.com*"}]}"#,
        )
        .expect("a rule with no match still reads");
        assert_eq!(rule.match_mode, Match::Any);
        assert!(rule.matches(&entry("invoice-0042.pdf", &[])));
    }

    #[test]
    fn an_empty_pattern_claims_nothing() {
        let test = RuleTest::new(Field::Name, "   ");
        assert!(!test.matches(&entry("anything.pdf", &[])));
    }

    #[test]
    fn a_rule_with_no_tests_claims_nothing() {
        let rule = enabled("new", "Invoices", vec![]);
        let router = RuleRouter::new(&[rule]);
        assert_eq!(router.folder_name(&entry("Invoice-0005.pdf", &[])), None);
        // It still owns its folder, so the folder is not filed away while the
        // rule is being written.
        assert!(router.owns("Invoices"));
    }

    #[test]
    fn the_first_rule_that_matches_wins() {
        let router = RuleRouter::new(&[
            enabled(
                "receipts",
                "Receipts",
                vec![RuleTest::new(Field::Name, "*receipt*")],
            ),
            enabled(
                "invoices",
                "Invoices",
                vec![RuleTest::new(Field::Name, "*invoice*")],
            ),
        ]);
        assert_eq!(
            router.folder_name(&entry("invoice-receipt.pdf", &[])),
            Some("Receipts")
        );
    }

    #[test]
    fn a_rule_named_like_a_dated_folder_is_refused() {
        let router = RuleRouter::new(&[enabled(
            "bad",
            "2026-08",
            vec![RuleTest::new(Field::Name, "*invoice*")],
        )]);
        assert!(router.is_empty());
        assert!(!router.owns("2026-08"));
    }

    #[test]
    fn decoding_leaves_a_stray_percent_alone() {
        assert_eq!(percent_decode("100%"), "100%");
        assert_eq!(percent_decode("a%zzb"), "a%zzb");
        assert_eq!(percent_decode("a%2"), "a%2");
        assert_eq!(percent_decode("%2Ffacturen%2F"), "/facturen/");
        assert_eq!(percent_decode("no escapes here"), "no escapes here");
        assert_eq!(percent_decode("%C3%A4"), "ä");
    }
}
