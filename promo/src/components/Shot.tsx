import React from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import { HEIGHT, WIDTH } from "../theme";
import { fit, Framed, Rect } from "./Framed";

/// The natural pixel size of every capture in public/shots. They come out of
/// `screencapture -l` at 2x, so a 860x620 window is a 1720x1240 file and the
/// app's own text lands well above 1:1 once it is mounted.
export const SHOT_SIZE: Record<string, { w: number; h: number }> = {
  menubar: { w: 588, h: 636 },
};
const WINDOW = { w: 1720, h: 1240 };

/// Where a shot is mounted. `side` puts the caption in a column on the left
/// and gives the picture the height of the frame; `top` puts the caption above
/// and is what a crop wider than it is tall wants.
/// The numbers match `STAGE` in theme.ts, so a screenshot shot and a shot of
/// the recording land in the same place and a cut between them does not shift
/// the picture sideways.
export const STAGES = {
  side: { maxW: 1163, maxH: 900, left: 700, right: 1863 },
  top: { maxW: 1560, maxH: 690 },
} as const;

/// A window capture, mounted.
///
/// Uncropped it is drawn as the PNG it is — `screencapture -o` leaves the real
/// rounded corners and an alpha channel where the desktop was, so the shadow
/// is a filter that follows the corners rather than a box behind them. Cropped,
/// there are no corners left to keep and it goes in a card like the recording
/// does.
export const Shot: React.FC<{
  name: string;
  stage: keyof typeof STAGES;
  /// A region of the screenshot to fill the card with, in its own pixels.
  /// Settings panes that end halfway down the window are mostly empty
  /// otherwise.
  crop?: Rect;
  /// A gentle push, applied to the mounted card so the crop never creeps off
  /// the picture.
  scaleAt?: (frame: number) => number;
  /// Caps the card height. The menu is a 294pt-wide thing captured at 2x, and
  /// filling 900px with it means enlarging past what was captured; 700 keeps
  /// it at about its own pixels and stays sharp.
  heightCap?: number;
  children?: React.ReactNode;
  /// Drawn on top of the picture, in the screenshot's own pixels — spotlights
  /// go here so they scale with it.
  overlay?: React.ReactNode;
}> = ({ name, stage, crop, scaleAt, heightCap, children, overlay }) => {
  const frame = useCurrentFrame();
  const natural = SHOT_SIZE[name] ?? WINDOW;
  const source = crop ?? { x: 0, y: 0, w: natural.w, h: natural.h };
  const geometry = STAGES[stage];
  const box = fit(source.w / source.h, geometry.maxW, Math.min(geometry.maxH, heightCap ?? geometry.maxH));

  // Centred in the space left of it rather than pushed against the right
  // edge: a full window fills that space either way, but the menu is half the
  // width of one and hard against the frame edge it looks like an offcut.
  const left =
    stage === "side"
      ? STAGES.side.left + (STAGES.side.right - STAGES.side.left - box.w) / 2
      : (WIDTH - box.w) / 2;
  const top = stage === "side" ? (HEIGHT - box.h) / 2 : 300 + (690 - box.h) / 2;

  const inner = (
    <>
      <Img
        src={staticFile(`shots/${name}.png`)}
        style={{ position: "absolute", top: 0, left: 0, width: natural.w, height: natural.h }}
      />
      {overlay}
    </>
  );

  return (
    <AbsoluteFill>
      {children}
      <div
        style={{
          position: "absolute",
          left,
          top,
          width: box.w,
          height: box.h,
          transform: `scale(${scaleAt?.(frame) ?? 1})`,
          transformOrigin: "50% 50%",
          filter: crop ? undefined : "drop-shadow(0 40px 90px rgba(0,0,0,0.62))",
          borderRadius: crop ? 16 : undefined,
          overflow: crop ? "hidden" : undefined,
          boxShadow: crop ? "0 44px 100px rgba(0,0,0,0.62)" : undefined,
        }}
      >
        <Framed rect={source} width={box.w} height={box.h} natural={natural}>
          {inner}
        </Framed>
      </div>
    </AbsoluteFill>
  );
};
