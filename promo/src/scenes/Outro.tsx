import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";
import { MONO, SANS, T } from "../theme";

const ease = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
  easing: Easing.bezier(0.22, 1, 0.36, 1),
} as const;

export const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const line = (delay: number) => ({
    opacity: interpolate(frame, [delay, delay + 18], [0, 1], ease),
    transform: `translateY(${interpolate(frame, [delay, delay + 18], [16, 0], ease)}px)`,
  });

  return (
    <AbsoluteFill
      style={{
        justifyContent: "center",
        alignItems: "center",
        fontFamily: SANS,
        textAlign: "center",
      }}
    >
      <div style={{ ...line(0), display: "flex", alignItems: "center", gap: 22 }}>
        <Img src={staticFile("icon.png")} style={{ width: 84, height: 84 }} />
        <span style={{ fontSize: 68, fontWeight: 700, letterSpacing: -1.6, color: T.bright }}>
          Tideline
        </span>
      </div>

      <div style={{ ...line(8), marginTop: 30, fontSize: 44, fontWeight: 600, color: T.bright }}>
        Free, open source, no account, no telemetry.
      </div>

      {/* The install line is the one thing anyone needs to copy, so it gets the
          app's own card treatment and the accent border rather than a bullet. */}
      <div
        style={{
          ...line(16),
          marginTop: 42,
          padding: "22px 38px",
          borderRadius: 12,
          backgroundColor: T.card,
          border: `1px solid ${T.border}`,
          boxShadow: "0 24px 60px rgba(0,0,0,0.5)",
          fontFamily: MONO,
          fontSize: 32,
          color: T.text,
        }}
      >
        <span style={{ color: T.accent }}>brew</span> install --cask estruyf/tap/tideline
      </div>

      <div style={{ ...line(24), marginTop: 26, fontSize: 25, color: T.muted }}>
        or download the zip &mdash; macOS 14 or later
      </div>

      <div style={{ ...line(30), marginTop: 44, fontSize: 27, color: T.accent, fontWeight: 500 }}>
        github.com/estruyf/tideline
      </div>

      <div style={{ ...line(36), marginTop: 16, fontSize: 22, color: T.faint }}>
        Native Swift &middot; no dependencies &middot; 1.7 MB to download
      </div>
    </AbsoluteFill>
  );
};
