import React from "react";
import { interpolate } from "remotion";
import { SOURCE } from "../theme";

/// A rectangle in the coordinates of the recording itself — 1920x1080, the
/// same numbers you would read off a screenshot in Preview. Every shot says
/// what part of the desktop it is looking at in these terms, and `Framed`
/// works out the scale.
export type Rect = { x: number; y: number; w: number; h: number };

/// The whole recording. Anything narrower clips the edge off one window or
/// the other — the Finder starts at x=10 and Tideline ends at x=1878 — and a
/// window with a sliced-off border reads as a mistake rather than a crop.
export const DESKTOP: Rect = { x: 0, y: 0, w: 1920, h: 1080 };

/// The Finder list on its own: the columns from Name through Kind, and every
/// row of them, both before the sweep and after. Every edge falls *inside* the
/// window, so it reads as a zoom rather than a badly framed screenshot, and it
/// shares 16:9 with `DESKTOP` so the push between them does not squash.
export const FINDER: Rect = { x: 14, y: 152, w: 864, h: 486 };

/// The Tideline window, to its own edges — traffic lights, footer and all, so
/// a sheet opening inside it is never clipped.
export const TIDELINE: Rect = { x: 906, y: 98, w: 974, h: 754 };

export const aspect = (r: Rect) => r.w / r.h;

/// Moves between two crops. The width eases and the rest follows it, so a push
/// in reads as one continuous move rather than four numbers sliding apart.
export const between = (a: Rect, b: Rect, t: number): Rect => ({
  x: interpolate(t, [0, 1], [a.x, b.x]),
  y: interpolate(t, [0, 1], [a.y, b.y]),
  w: interpolate(t, [0, 1], [a.w, b.w]),
  h: interpolate(t, [0, 1], [a.h, b.h]),
});

/// Shows `rect` of the source at `width` x `height`. The child is laid out at
/// the source's full size and then scaled and shifted underneath a window that
/// clips it, which is why a crop can move without the video ever being
/// re-encoded.
export const Framed: React.FC<{
  rect: Rect;
  width: number;
  height: number;
  /// The natural size of what is being cropped. The recording by default; a
  /// window screenshot is 1720x1240 and says so.
  natural?: { w: number; h: number };
  children: React.ReactNode;
}> = ({ rect, width, height, natural, children }) => {
  const full = natural ?? { w: SOURCE.width, h: SOURCE.height };
  const scale = width / rect.w;
  return (
    <div style={{ width, height, overflow: "hidden", position: "relative" }}>
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          width: full.w,
          height: full.h,
          transformOrigin: "0 0",
          transform: `scale(${scale}) translate(${-rect.x}px, ${-rect.y}px)`,
        }}
      >
        {children}
      </div>
    </div>
  );
};

/// The largest box of this aspect that fits inside `maxW` x `maxH`. Shots come
/// in shapes the app chose, not shapes the promo did — a window is 1.39:1, a
/// menu is taller than it is wide, a settings pane cropped to its content is
/// nearly 2.5:1 — and a stage that fits each of them rather than stretching
/// them is what lets one layout carry all three.
export const fit = (ratio: number, maxW: number, maxH: number) => {
  const byHeight = { w: maxH * ratio, h: maxH };
  return byHeight.w <= maxW ? byHeight : { w: maxW, h: maxW / ratio };
};
