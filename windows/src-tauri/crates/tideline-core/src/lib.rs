//! The filing engine, shared by every front end.
//!
//! The rules live in [`organizer::plan`], which is pure: it is handed a list of
//! [`Entry`] values and answers what would move and where to. Reading those
//! entries off disk, and carrying the moves out, are separate — so the rules can
//! be tested against the same fixtures the macOS app uses, with no filesystem
//! involved.
//!
//! The behaviour this implements is written down in `docs/behaviour.md`.

pub mod organizer;
pub mod rule;
pub mod settings;
pub mod skip;
pub mod sweep;
pub mod typefolder;

pub use organizer::{Entry, PlannedMove, SweepPlan};
pub use rule::{Field, Rule, RuleRouter, RuleTest};
pub use settings::{DateBasis, FolderFormat, RunConfiguration, TypeRule};
pub use sweep::{preview, run, scan, MoveRecord, RunResult, SweepError};
pub use typefolder::TypeRouter;
