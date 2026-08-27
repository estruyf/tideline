import React from "react";
import { Composition } from "remotion";
import { Promo } from "./Promo";
import { Tour } from "./Tour";
import { DURATION, FPS, HEIGHT, TOUR_DURATION, WIDTH } from "./theme";

export const RemotionRoot: React.FC = () => (
  <>
    {/* Thirty seconds, cut from the screen recording. */}
    <Composition
      id="Promo"
      component={Promo}
      durationInFrames={DURATION}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
    />
    {/* Ninety seconds, and every screen in the app. */}
    <Composition
      id="Tour"
      component={Tour}
      durationInFrames={TOUR_DURATION}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
    />
  </>
);
