import React from "react";
import { T, WIDTH } from "../theme";

/// The recording, mounted. The border and the radius are the app's own card
/// treatment at a larger size, so a crop of a window sitting on the promo
/// background still reads as one piece of design rather than a paste-up.
///
/// `left` is optional: leave it out and the card centres, which is what the
/// wide shots want.
export const Card: React.FC<{
  top: number;
  height: number;
  width: number;
  left?: number | null;
  /// A whisper of a push, 1 to about 1.02 across a shot. It scales the mounted
  /// card rather than the crop, so the framing never creeps off the window.
  scale?: number;
  children: React.ReactNode;
}> = ({ top, height, width, left, scale = 1, children }) => (
  <div
    style={{
      position: "absolute",
      top,
      left: left ?? (WIDTH - width) / 2,
      width,
      height,
      transform: `scale(${scale})`,
      transformOrigin: "50% 50%",
    }}
  >
    {/* The glow is what separates the card from the backdrop; a border alone
        leaves it looking pasted on at this size. */}
    <div
      style={{
        position: "absolute",
        inset: -1,
        borderRadius: 17,
        background: `linear-gradient(180deg, rgba(255,255,255,0.10), rgba(255,255,255,0.02))`,
        boxShadow: "0 48px 110px rgba(0,0,0,0.65), 0 6px 24px rgba(0,0,0,0.45)",
      }}
    />
    <div
      style={{
        position: "absolute",
        inset: 0,
        borderRadius: 16,
        overflow: "hidden",
        backgroundColor: T.pane,
      }}
    >
      {children}
    </div>
  </div>
);
