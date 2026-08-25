//! Decides which type folder, if any, claims a given file, and knows the names
//! of the folders those rules own so filing never files one of them away.
//!
//! Built once per sweep from an immutable snapshot of the rules.

use crate::settings::TypeRule;

pub struct TypeRouter {
    /// extension -> folder name.
    folder_for_extension: Vec<(String, String)>,
    /// Lower-cased folder names, for the "is this a destination?" question.
    owned_names: Vec<String>,
}

impl TypeRouter {
    /// Only enabled rules should be handed to this. Where two of them claim the
    /// same extension the one higher up the list wins, which is the order the
    /// settings window shows.
    pub fn new(rules: &[TypeRule]) -> Self {
        let mut folder_for_extension: Vec<(String, String)> = Vec::new();
        let mut owned_names: Vec<String> = Vec::new();

        for rule in rules {
            let name = rule.name.trim();
            if !TypeRule::is_valid_folder_name(name) {
                continue;
            }
            let lowered = name.to_lowercase();
            if !owned_names.contains(&lowered) {
                owned_names.push(lowered);
            }
            for ext in &rule.extensions {
                if !folder_for_extension.iter().any(|(e, _)| e == ext) {
                    folder_for_extension.push((ext.clone(), name.to_string()));
                }
            }
        }

        TypeRouter {
            folder_for_extension,
            owned_names,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.folder_for_extension.is_empty()
    }

    /// The folder this file belongs in, or `None` to let the date decide.
    pub fn folder_name(&self, extension: &str) -> Option<&str> {
        if extension.is_empty() {
            return None;
        }
        let lowered = extension.to_lowercase();
        self.folder_for_extension
            .iter()
            .find(|(e, _)| *e == lowered)
            .map(|(_, folder)| folder.as_str())
    }

    /// A type folder is never itself filed into a dated one.
    pub fn owns(&self, name: &str) -> bool {
        self.owned_names.contains(&name.to_lowercase())
    }

    /// Extensions more than one enabled rule asks for. The second rule never
    /// sees them, so the settings window says so rather than letting it puzzle.
    pub fn conflicts(rules: &[TypeRule]) -> Vec<String> {
        let mut seen: Vec<String> = Vec::new();
        let mut clashing: Vec<String> = Vec::new();
        for rule in rules.iter().filter(|r| r.is_enabled) {
            for ext in &rule.extensions {
                if seen.contains(ext) {
                    if !clashing.contains(ext) {
                        clashing.push(ext.clone());
                    }
                } else {
                    seen.push(ext.clone());
                }
            }
        }
        clashing
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule(id: &str, name: &str, exts: &[&str]) -> TypeRule {
        let mut r = TypeRule::new(id, name, exts, false);
        r.is_enabled = true;
        r
    }

    #[test]
    fn claims_by_extension_ignoring_case() {
        let router = TypeRouter::new(&[rule("i", "Installers", &["msi", "exe"])]);
        assert_eq!(router.folder_name("msi"), Some("Installers"));
        assert_eq!(router.folder_name("MSI"), Some("Installers"));
        assert_eq!(router.folder_name("zip"), None);
        assert_eq!(router.folder_name(""), None);
    }

    #[test]
    fn the_first_rule_wins_a_shared_extension() {
        let router = TypeRouter::new(&[
            rule("i", "Installers", &["iso"]),
            rule("a", "Archives", &["iso", "zip"]),
        ]);
        assert_eq!(router.folder_name("iso"), Some("Installers"));
        assert_eq!(router.folder_name("zip"), Some("Archives"));
    }

    #[test]
    fn conflicts_are_reported_once() {
        let rules = vec![
            rule("i", "Installers", &["iso", "msi"]),
            rule("a", "Archives", &["iso", "zip"]),
            rule("b", "Backups", &["iso"]),
        ];
        assert_eq!(TypeRouter::conflicts(&rules), vec!["iso".to_string()]);
    }

    #[test]
    fn a_rule_owns_its_folder_name() {
        let router = TypeRouter::new(&[rule("i", "Installers", &["msi"])]);
        assert!(router.owns("Installers"));
        assert!(router.owns("installers"));
        assert!(!router.owns("Invoices"));
    }

    #[test]
    fn a_rule_named_like_a_dated_folder_is_refused() {
        let router = TypeRouter::new(&[rule("bad", "2026-08", &["msi"])]);
        assert!(router.is_empty());
        assert!(!router.owns("2026-08"));
    }

    #[test]
    fn reserved_windows_names_are_refused() {
        for name in ["CON", "nul", "COM1", "LPT9.txt"] {
            assert!(
                !TypeRule::is_valid_folder_name(name),
                "{name} should be refused"
            );
        }
        assert!(TypeRule::is_valid_folder_name("Installers"));
        // A trailing space is trimmed away rather than refused — the router
        // uses the trimmed name, so the folder it makes is never the bad one.
        assert!(TypeRule::is_valid_folder_name("Trailing "));
        // A trailing dot survives the trim, and Explorer would strip it later.
        assert!(!TypeRule::is_valid_folder_name("Trailing."));
        assert!(!TypeRule::is_valid_folder_name("with:colon"));
        assert!(!TypeRule::is_valid_folder_name("with\\slash"));
    }
}
