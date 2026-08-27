import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { SANS, T } from "../theme";

const ease = { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.bezier(0.22, 1, 0.36, 1) } as const;

export const Title: React.FC<{
  tagline?: string;
  note?: string;
}> = ({
  tagline = "A tidy Downloads folder, every morning.",
  note = "Today\u2019s downloads stay put \u00b7 everything older is filed by the day it arrived",
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const pop = spring({ frame, fps, config: { damping: 200, mass: 0.7 } });
  const rule = interpolate(frame, [16, 40], [0, 168], ease);
  const line = (delay: number) => ({
    opacity: interpolate(frame, [delay, delay + 18], [0, 1], ease),
    transform: `translateY(${interpolate(frame, [delay, delay + 18], [18, 0], ease)}px)`,
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
      <div style={{ position: "relative", transform: `scale(${interpolate(pop, [0, 1], [0.86, 1])})` }}>
        <div
          style={{
            position: "absolute",
            inset: -60,
            borderRadius: "50%",
            background: `radial-gradient(closest-side, rgba(42,84,222,0.45), transparent 70%)`,
            filter: "blur(10px)",
          }}
        />
        <Img
          src={staticFile("icon.png")}
          style={{
            position: "relative",
            width: 156,
            height: 156,
            opacity: pop,
            filter: "drop-shadow(0 18px 40px rgba(0,0,0,0.55))",
          }}
        />
      </div>

      <div
        style={{
          ...line(10),
          marginTop: 34,
          fontSize: 104,
          fontWeight: 700,
          letterSpacing: -2.5,
          color: T.bright,
        }}
      >
        Tideline
      </div>

      <div
        style={{
          marginTop: 26,
          width: rule,
          height: 4,
          borderRadius: 2,
          backgroundColor: T.accent,
          boxShadow: `0 0 20px rgba(255,212,59,0.55)`,
        }}
      />

      <div style={{ ...line(26), marginTop: 30, fontSize: 34, color: T.text }}>
        {tagline}
      </div>
      <div style={{ ...line(34), marginTop: 14, fontSize: 25, color: T.faint }}>
        {note}
      </div>
    </AbsoluteFill>
  );
};
