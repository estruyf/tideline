import React from "react";
import { AbsoluteFill, Audio, Easing, interpolate, Sequence, staticFile } from "remotion";
import { Backdrop, Tideline as TideMark } from "./components/Backdrop";
import { Caption } from "./components/Caption";
import { ClipPlan } from "./components/Clip";
import { DemoShot } from "./components/DemoShot";
import { aspect, between, DESKTOP, FINDER, TIDELINE } from "./components/Framed";
import { Scene } from "./components/Scene";
import { Outro } from "./scenes/Outro";
import { Title } from "./scenes/Title";
import { DURATION, FPS, MUSIC, XFADE } from "./theme";

// The recording runs 299 frames and the promo runs 900, so nothing here is
// sped up — every shot picks a stretch of the source, slows it to somewhere
// near two thirds speed, and holds still at either end while the caption is
// read. The source frame numbers below are the events themselves:
//
//   f50  Tideline reports "Filed 14 items"      f157  duplicates sheet opens
//   f54  the Finder list turns into folders     f196  the copies go to the Trash
//   f108 the Reclaim space pane opens           f228  the clearing sheet opens
//   f140 the scan lands on 45,9 MB              f260  the folders go to the Trash
//
// Scene lengths include the cross-dissolve into the next one, which is why
// each `from` sits XFADE frames before the previous scene ends.
const SCENES = {
  title: { from: 0, duration: 108 + XFADE },
  folder: { from: 108, duration: 270 + XFADE },
  reclaim: { from: 378, duration: 205 + XFADE },
  trash: { from: 583, duration: 173 + XFADE },
  outro: { from: 756, duration: 144 },
};

const FOLDER: ClipPlan = {
  holdIn: { frame: 40, duration: 132 },
  play: { from: 40, duration: 66, rate: 0.6 },
  holdOut: { frame: 80 },
  total: SCENES.folder.duration,
};

// The two sheet shots are slowed to about half speed, because the sheet is
// only open for a second and a half in the recording and the promo has to
// leave time to read the file names inside it. Their holds are short at the
// join, where the pane looks the same either side of the cut and a long one
// would read as the video having stalled.
const RECLAIM: ClipPlan = {
  holdIn: { frame: 138, duration: 52 },
  play: { from: 138, duration: 141, rate: 0.511 },
  holdOut: { frame: 210 },
  total: SCENES.reclaim.duration,
};

const TRASH: ClipPlan = {
  holdIn: { frame: 222, duration: 16 },
  play: { from: 222, duration: 134, rate: 0.433 },
  holdOut: { frame: 280 },
  total: SCENES.trash.duration,
};

const ease = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
  easing: Easing.bezier(0.22, 1, 0.36, 1),
} as const;

/// The one camera move in the piece: a beat on the whole desktop to say where
/// we are, then a push into the Finder list, which is the only place the
/// filing is legible.
const pushIntoFinder = (frame: number) =>
  between(DESKTOP, FINDER, interpolate(frame, [12, 72], [0, 1], ease));

/// The Reclaim space shots do not move the crop — a sheet opening inside the
/// window is motion enough — but the mounted card creeps in by a percent and a
/// half so a six-second hold does not go dead. `trash` picks up where
/// `reclaim` leaves off, so the cut between them reads as one slow push.
const creep = (from: number, to: number, over: number) => (frame: number) =>
  interpolate(frame, [0, over], [from, to], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

export const Promo: React.FC = () => (
  <AbsoluteFill>
    <Backdrop />

    {MUSIC ? (
      <Audio
        src={staticFile(MUSIC)}
        volume={(f) =>
          interpolate(f, [0, FPS, DURATION - FPS, DURATION], [0, 1, 1, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          })
        }
      />
    ) : null}

    <Sequence from={SCENES.title.from} durationInFrames={SCENES.title.duration}>
      <Scene duration={SCENES.title.duration}>
        <Title />
      </Scene>
    </Sequence>

    <Sequence from={SCENES.folder.from} durationInFrames={SCENES.folder.duration}>
      <Scene duration={SCENES.folder.duration}>
        <DemoShot plan={FOLDER} stage="top" aspect={aspect(FINDER)} rectAt={pushIntoFinder}>
          <Sequence durationInFrames={130} layout="none">
            <Caption
              kicker="~/Downloads"
              headline="Everything you ever downloaded, in one flat list."
              note="artifact.zip, artifact-1.zip, artifact-2.zip — the name no longer tells you anything."
              outAt={118}
            />
          </Sequence>
          <Sequence from={128} durationInFrames={SCENES.folder.duration - 128} layout="none">
            <Caption
              kicker="One sweep"
              headline="Everything older moves into a folder named for the day it arrived."
              note="Today's downloads stay loose in the root, under their real names, where you expect them."
            />
          </Sequence>
        </DemoShot>
      </Scene>
    </Sequence>

    <Sequence from={SCENES.reclaim.from} durationInFrames={SCENES.reclaim.duration}>
      <Scene duration={SCENES.reclaim.duration}>
        <DemoShot
          plan={RECLAIM}
          stage="side"
          aspect={aspect(TIDELINE)}
          rectAt={() => TIDELINE}
          cardScaleAt={creep(1, 1.012, SCENES.reclaim.duration)}
        >
          <Caption
            where="side"
            kicker="Reclaim space"
            headline="Then it looks for what you no longer need."
            note="Byte-for-byte duplicates, the biggest files, and the dated folders old enough to let go."
          />
        </DemoShot>
      </Scene>
    </Sequence>

    <Sequence from={SCENES.trash.from} durationInFrames={SCENES.trash.duration}>
      <Scene duration={SCENES.trash.duration}>
        <DemoShot
          plan={TRASH}
          stage="side"
          aspect={aspect(TIDELINE)}
          rectAt={() => TIDELINE}
          cardScaleAt={creep(1.012, 1.024, SCENES.trash.duration)}
        >
          <Caption
            where="side"
            kicker="Nothing is ever deleted"
            headline="It all goes to the Trash, and nothing moves until you say so."
            note="A file you want back is a drag out of the Trash, not a restore from a backup."
          />
        </DemoShot>
      </Scene>
    </Sequence>

    <Sequence from={SCENES.outro.from} durationInFrames={SCENES.outro.duration}>
      <Scene duration={SCENES.outro.duration}>
        <Outro />
      </Scene>
    </Sequence>

    <TideMark />
  </AbsoluteFill>
);
