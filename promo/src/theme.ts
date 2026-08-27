// The promo borrows the app's own palette rather than inventing one, so the
// title card and the recording inside it are lit the same way. The values are
// the dark side of `app/Sources/Tideline/Views/Theme.swift`; `ground` is the
// one addition, a step below `pane` so the recording reads as the brightest
// thing in the frame.
export const T = {
  accent: "#ffd43b",
  onAccent: "#15181f",
  ground: "#0d1016",
  pane: "#15181f",
  card: "#202736",
  hover: "#2d3142",
  border: "#374151",
  text: "#d9dbe1",
  bright: "#f2f4f8",
  muted: "#9ba4b7",
  faint: "#6b7280",
  link: "#74c0fc",
  /// The blue of the app icon, used only for the glow behind it.
  iconBlue: "#2a54de",
} as const;

export const SANS =
  '-apple-system, "SF Pro Display", "SF Pro Text", system-ui, "Helvetica Neue", Arial, sans-serif';
export const MONO = '"SF Mono", ui-monospace, Menlo, "Roboto Mono", monospace';

export const WIDTH = 1920;
export const HEIGHT = 1080;
export const FPS = 30;
export const DURATION = 900; // the short promo, 30 seconds
export const TOUR_DURATION = 2700; // the tour, 90 seconds

/// Scenes overlap by this much and cross-dissolve through it.
export const XFADE = 12;

/// The recording is 1920x1080 at 30 fps, so a source frame number and a
/// composition frame number are the same unit and no conversion is needed.
export const SOURCE = { width: 1920, height: 1080 } as const;

/// Every shot is framed into a card of this height, centred horizontally. The
/// width follows from the aspect of whatever the shot is looking at, so a
/// window-shaped crop and a desktop-shaped crop share a baseline and a top.
export const CARD_TOP = 300;
export const CARD_H = 690;

/// The caption block is bottom-aligned to this line, so a headline that wraps
/// to two lines grows upwards and the gap above the card never changes.
export const CAPTION_BASELINE = 262;

/// The two stages a shot can be mounted on.
///
/// Wide shots — the desktop, the Finder list — are laid out with the caption
/// above them, which is the layout the piece opens with. The Tideline window
/// is nearly square, and on that stage it would come out at 0.9x of the
/// recording: smaller than the app really is, and the pane text stops being
/// readable. It gets a column beside it and the full height of the frame
/// instead, which puts it back to about 1.2x.
export const STAGE = {
  top: { top: CARD_TOP, height: CARD_H, left: null },
  side: { top: 90, height: 900, left: 700 },
} as const;

/// The left-hand caption column of the `side` stage.
export const COLUMN = { left: 80, width: 560 };

/// A file in `public/` to play under the whole thing, or `null` for silence.
/// The piece is cut to read without sound — every claim it makes is on screen —
/// so music is a choice rather than a dependency. Drop a track in and set the
/// name; it fades out over the last second either way.
export const MUSIC: string | null = null;
