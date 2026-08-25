//! The "never touch these" list: exact names, or shell-style globs.
//!
//! The macOS app hands the pattern to `fnmatch(3)`. There is no `fnmatch` on
//! Windows, so the same grammar is implemented here: `*` for any run of
//! characters, `?` for exactly one, `[abc]` / `[a-z]` / `[!abc]` for a set.
//!
//! Matching is case-insensitive on Windows and case-sensitive elsewhere, which
//! follows the filesystem underneath in each case: a user who writes `*.EXE`
//! on Windows means the file that Explorer shows as `.exe`.

/// Whether any pattern in the list claims this name.
pub fn matches_skip_list(name: &str, patterns: &[String]) -> bool {
    patterns.iter().any(|pattern| {
        let trimmed = pattern.trim();
        if trimmed.is_empty() {
            return false;
        }
        if eq(trimmed, name) {
            return true;
        }
        if trimmed.contains(['*', '?', '[']) {
            return glob_match(trimmed, name);
        }
        false
    })
}

fn case_insensitive() -> bool {
    cfg!(windows)
}

fn eq(a: &str, b: &str) -> bool {
    if case_insensitive() {
        a.eq_ignore_ascii_case(b)
    } else {
        a == b
    }
}

fn fold(c: char) -> char {
    if case_insensitive() {
        c.to_ascii_lowercase()
    } else {
        c
    }
}

/// `fnmatch`-style matching, without `FNM_PATHNAME` — these are single path
/// components, so there is no separator to be careful about.
pub fn glob_match(pattern: &str, name: &str) -> bool {
    let pattern: Vec<char> = pattern.chars().collect();
    let name: Vec<char> = name.chars().collect();
    matches_from(&pattern, 0, &name, 0)
}

fn matches_from(pattern: &[char], mut p: usize, name: &[char], mut n: usize) -> bool {
    // Where to resume if a `*` turns out to have swallowed too little. Tracking
    // one backtrack point keeps this linear on the patterns people actually
    // write, rather than exponential on `*a*a*a*`.
    let mut star: Option<(usize, usize)> = None;

    loop {
        if p < pattern.len() {
            match pattern[p] {
                '*' => {
                    // Collapse a run of stars; they mean no more than one does.
                    while p < pattern.len() && pattern[p] == '*' {
                        p += 1;
                    }
                    if p == pattern.len() {
                        return true;
                    }
                    star = Some((p, n));
                    continue;
                }
                '?' if n < name.len() => {
                    p += 1;
                    n += 1;
                    continue;
                }
                '[' if n < name.len() => {
                    if let Some((next, matched)) = match_class(pattern, p, name[n]) {
                        if matched {
                            p = next;
                            n += 1;
                            continue;
                        }
                    } else if fold(pattern[p]) == fold(name[n]) {
                        // An unterminated `[` is a literal bracket, as fnmatch has it.
                        p += 1;
                        n += 1;
                        continue;
                    }
                }
                c if n < name.len() && fold(c) == fold(name[n]) => {
                    p += 1;
                    n += 1;
                    continue;
                }
                _ => {}
            }
        } else if n == name.len() {
            return true;
        }

        // No match here: let the last `*` take one more character, if there was one.
        match star {
            Some((sp, sn)) if sn < name.len() => {
                p = sp;
                n = sn + 1;
                star = Some((sp, n));
            }
            _ => return false,
        }
    }
}

/// Reads a `[...]` class starting at `open`. Returns where the class ends and
/// whether `candidate` is in it, or `None` if the bracket is never closed.
fn match_class(pattern: &[char], open: usize, candidate: char) -> Option<(usize, bool)> {
    let mut i = open + 1;
    let mut negated = false;
    if i < pattern.len() && (pattern[i] == '!' || pattern[i] == '^') {
        negated = true;
        i += 1;
    }

    let mut found = false;
    let mut first = true;
    while i < pattern.len() {
        // A `]` in the first position is a literal, not the end of the class.
        if pattern[i] == ']' && !first {
            return Some((i + 1, found != negated));
        }
        first = false;

        // `a-z`, but only when the `-` is not the last character before `]`.
        if i + 2 < pattern.len() && pattern[i + 1] == '-' && pattern[i + 2] != ']' {
            let (lo, hi) = (fold(pattern[i]), fold(pattern[i + 2]));
            let c = fold(candidate);
            if lo <= c && c <= hi {
                found = true;
            }
            i += 3;
            continue;
        }

        if fold(pattern[i]) == fold(candidate) {
            found = true;
        }
        i += 1;
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn list(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn exact_names_match() {
        assert!(matches_skip_list("Inbox", &list(&["Inbox"])));
        assert!(!matches_skip_list("Inbox2", &list(&["Inbox"])));
    }

    #[test]
    fn star_matches_extensions() {
        assert!(matches_skip_list("Figma.dmg", &list(&["*.dmg"])));
        assert!(!matches_skip_list("Figma.zip", &list(&["*.dmg"])));
        assert!(glob_match("*", "anything"));
        assert!(glob_match("a*b*c", "azzzbzzzc"));
        assert!(!glob_match("a*b*c", "azzzbzzz"));
    }

    #[test]
    fn question_mark_matches_exactly_one() {
        assert!(glob_match("file?.txt", "file1.txt"));
        assert!(!glob_match("file?.txt", "file.txt"));
        assert!(!glob_match("file?.txt", "file12.txt"));
    }

    #[test]
    fn character_classes() {
        assert!(glob_match("file[0-9].txt", "file7.txt"));
        assert!(!glob_match("file[0-9].txt", "filex.txt"));
        assert!(glob_match("file[!0-9].txt", "filex.txt"));
        assert!(!glob_match("file[!0-9].txt", "file7.txt"));
        assert!(glob_match("[abc]nd", "and"));
    }

    #[test]
    fn unterminated_bracket_is_a_literal() {
        assert!(glob_match("a[b", "a[b"));
    }

    #[test]
    fn trailing_star_after_a_literal_run() {
        // The backtracking path: the first `*` has to give a character back.
        assert!(glob_match("*report*", "my-report-final"));
        assert!(glob_match("*.tar.gz", "archive.tar.gz"));
        assert!(!glob_match("*.tar.gz", "archive.tar.bz2"));
    }

    #[test]
    fn blank_patterns_are_ignored() {
        assert!(!matches_skip_list("anything", &list(&["", "   "])));
    }

    #[test]
    #[cfg(windows)]
    fn windows_matching_ignores_case() {
        assert!(matches_skip_list("SETUP.EXE", &list(&["*.exe"])));
        assert!(matches_skip_list("inbox", &list(&["Inbox"])));
    }

    #[test]
    #[cfg(not(windows))]
    fn elsewhere_matching_respects_case() {
        assert!(!matches_skip_list("SETUP.EXE", &list(&["*.exe"])));
        assert!(!matches_skip_list("inbox", &list(&["Inbox"])));
    }
}
