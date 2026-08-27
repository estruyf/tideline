import React from "react";
import { Easing, interpolate, useCurrentFrame } from "remotion";
import { T } from "../theme";
import { Rect } from "./Framed";

/// Points at one control inside a screenshot. The rect is in the screenshot's
/// own pixels — the numbers you would read off it in Preview — because the
/// whole point is being able to measure once and trust it.
///
/// The dimming is a single enormous spread shadow rather than four panels
/// around the hole, so the lit area and the shadow can never drift apart by a
/// pixel as the card is scaled.
/// Points at one control inside a screenshot. The rect is in the screenshot's
/// own pixels — the numbers you would read off it in Preview — because the
/// whole point is being able to measure once and trust it.
///
/// The dimming is a single enormous spread shadow rather than four panels
/// around the hole, so the lit area and the shadow can never drift apart by a
/// pixel as the card is scaled.
///
/// There is deliberately no label. Every row it can point at already carries
/// its own line of explanation, and a caption sits beside the card saying the
/// same thing in the promo's words — a third copy would only cover the row
/// below the one being pointed at.
export const Spotlight: React.FC<{
  rect: Rect;
  /// Frames into the shot before it appears.
  delay?: number;
}> = ({ rect, delay = 0 }) => {
  const frame = useCurrentFrame();
  const t = interpolate(frame, [delay, delay + 20], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.22, 1, 0.36, 1),
  });

  return (
    <div
      style={{
        position: "absolute",
        left: rect.x,
        top: rect.y,
        width: rect.w,
        height: rect.h,
        borderRadius: 14,
        border: `3px solid ${T.accent}`,
        boxShadow: `0 0 0 9999px rgba(6,8,12,${0.62 * t})`,
        opacity: t,
        transform: `scale(${interpolate(t, [0, 1], [1.06, 1])})`,
      }}
    />
  );
};
