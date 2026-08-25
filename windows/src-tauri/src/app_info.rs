//! The fixed facts about the app: what it is called, who made it, and where to
//! reach them. The Windows half of `AppInfo.swift`.
//!
//! The links live here rather than in the window so the front end never hands
//! the OS a URL of its own. It asks for one of these by name, and a name that
//! is not on the list opens nothing — the About tab is a row of buttons, not a
//! way to launch a browser at anything the page fancies.

pub const NAME: &str = "Tideline";
pub const AUTHOR: &str = "Elio Struyf";

pub const REPOSITORY: &str = "https://github.com/estruyf/tideline";
pub const ISSUES: &str = "https://github.com/estruyf/tideline/issues";
pub const NEW_ISSUE: &str = "https://github.com/estruyf/tideline/issues/new";
pub const AUTHOR_PROFILE: &str = "https://github.com/estruyf";
pub const RELEASES: &str = "https://github.com/estruyf/tideline/releases";

/// The link behind one of the About tab's buttons, or `None` for a name the
/// window has no business opening.
pub fn link(name: &str) -> Option<&'static str> {
    match name {
        "repository" => Some(REPOSITORY),
        "issues" => Some(ISSUES),
        "new-issue" => Some(NEW_ISSUE),
        "author" => Some(AUTHOR_PROFILE),
        "releases" => Some(RELEASES),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_link_is_one_of_ours() {
        for name in ["repository", "issues", "new-issue", "author", "releases"] {
            let url = link(name).expect("a known name resolves");
            assert!(url.starts_with("https://github.com/estruyf"));
        }
    }

    /// The point of the name-to-URL step: anything the window makes up is
    /// refused rather than handed to the browser.
    #[test]
    fn an_unknown_name_opens_nothing() {
        assert_eq!(link("https://example.com"), None);
        assert_eq!(link(""), None);
        assert_eq!(link("Repository"), None);
    }
}
