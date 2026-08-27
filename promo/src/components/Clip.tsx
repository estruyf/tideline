import React from "react";
import { Freeze, OffthreadVideo, Sequence, staticFile } from "remotion";
import { SOURCE } from "../theme";

const SRC = staticFile("demo.mp4");

const layer: React.CSSProperties = {
  position: "absolute",
  top: 0,
  left: 0,
  width: SOURCE.width,
  height: SOURCE.height,
};

/// One frame of the recording, held. `Freeze` pins the clock for its children,
/// so the video seeks to `frame` and stays there — the same pixels the moving
/// clip would show, which is what keeps a hold and the play either side of it
/// from flickering as they hand over.
const Held: React.FC<{ frame: number }> = ({ frame }) => (
  <Freeze frame={0}>
    <OffthreadVideo src={SRC} trimBefore={frame} muted style={layer} />
  </Freeze>
);

export type ClipPlan = {
  /// The frame to sit on while the caption is being read, and for how long.
  holdIn: { frame: number; duration: number };
  /// The stretch that actually moves. `rate` below 1 slows it down; the
  /// recording was made at working speed and a promo needs longer to land.
  /// Leave it out for a shot that holds still the whole way through.
  play?: { from: number; duration: number; rate: number };
  /// Where it comes to rest. The duration is whatever is left of the shot.
  holdOut: { frame: number };
  /// Total length of the shot, cross-dissolve included.
  total: number;
};

/// Hold, play, hold. Slowing the whole shot down instead would make the cursor
/// crawl; holding at either end buys reading time without touching the pace of
/// the part where something happens.
export const Clip: React.FC<{ plan: ClipPlan }> = ({ plan }) => {
  const { holdIn, play, holdOut, total } = plan;
  const playFrom = holdIn.duration;
  const restFrom = playFrom + (play?.duration ?? 0);
  return (
    <>
      <Sequence durationInFrames={holdIn.duration} layout="none">
        <Held frame={holdIn.frame} />
      </Sequence>
      {play ? (
        <Sequence from={playFrom} durationInFrames={play.duration} layout="none">
          <OffthreadVideo
            src={SRC}
            trimBefore={play.from}
            playbackRate={play.rate}
            muted
            style={layer}
          />
        </Sequence>
      ) : null}
      <Sequence from={restFrom} durationInFrames={total - restFrom} layout="none">
        <Held frame={holdOut.frame} />
      </Sequence>
    </>
  );
};
