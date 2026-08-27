import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { STAGE } from "../theme";
import { Card } from "./Card";
import { Clip, ClipPlan } from "./Clip";
import { Framed, Rect } from "./Framed";

/// A beat of the demo: a caption, and a framed piece of the recording under
/// it. `rectAt` is the camera — it says what the shot is looking at on any
/// given frame, which is how the opening push in and the still shots that
/// follow come from the same component.
export const DemoShot: React.FC<{
  plan: ClipPlan;
  stage: keyof typeof STAGE;
  /// Every rect `rectAt` returns has to share this aspect, or the crop
  /// stretches on its way between them.
  aspect: number;
  rectAt: (frame: number) => Rect;
  cardScaleAt?: (frame: number) => number;
  children?: React.ReactNode;
}> = ({ plan, stage, aspect, rectAt, cardScaleAt, children }) => {
  const frame = useCurrentFrame();
  const { top, height, left } = STAGE[stage];
  const width = Math.round(height * aspect);

  return (
    <AbsoluteFill>
      {children}
      <Card top={top} height={height} width={width} left={left} scale={cardScaleAt?.(frame)}>
        <Framed rect={rectAt(frame)} width={width} height={height}>
          <Clip plan={plan} />
        </Framed>
      </Card>
    </AbsoluteFill>
  );
};
