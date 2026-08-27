import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { DURATION, T } from "../theme";

/// The ground the whole promo sits on. It never cuts — scenes dissolve over
/// it — so the accent glow drifting across the 30 seconds is the only thing
/// that tells you the frame is still alive during a long hold.
export const Backdrop: React.FC<{ total?: number }> = ({ total = DURATION }) => {
  const frame = useCurrentFrame();
  const drift = interpolate(frame, [0, total], [0, 1]);
  const glowX = interpolate(drift, [0, 1], [42, 58]);

  return (
    <AbsoluteFill style={{ backgroundColor: T.ground }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(1200px 620px at ${glowX}% -8%, rgba(255,212,59,0.13), transparent 70%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(1000px 700px at ${100 - glowX}% 112%, rgba(42,84,222,0.16), transparent 68%)`,
        }}
      />
      {/* A waterline: the app is named for the mark a tide leaves, and the
          card sits just above it. */}
      <AbsoluteFill
        style={{
          background:
            "linear-gradient(180deg, transparent 0%, transparent 88%, rgba(255,212,59,0.05) 92%, transparent 100%)",
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(1500px 900px at 50% 45%, transparent 40%, rgba(0,0,0,0.55) 100%)",
        }}
      />
    </AbsoluteFill>
  );
};

/// A single hairline filling across the bottom edge over the full runtime. It
/// is the only element that never dissolves, so it doubles as a progress bar
/// and as the tide mark the app is named after.
export const Tideline: React.FC<{ total?: number }> = ({ total = DURATION }) => {
  const frame = useCurrentFrame();
  const pct = interpolate(frame, [0, total - 1], [0, 100], {
    extrapolateRight: "clamp",
  });
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        bottom: 0,
        height: 3,
        backgroundColor: "rgba(255,255,255,0.05)",
      }}
    >
      <div
        style={{
          width: `${pct}%`,
          height: "100%",
          backgroundColor: T.accent,
          boxShadow: `0 0 14px ${T.accent}`,
        }}
      />
    </div>
  );
};
