import React from "react";
import { AbsoluteFill, Audio, interpolate, Sequence, staticFile } from "remotion";
import { Backdrop, Tideline as TideMark } from "./components/Backdrop";
import { Caption } from "./components/Caption";
import { ClipPlan } from "./components/Clip";
import { DemoShot } from "./components/DemoShot";
import { aspect, FINDER, Rect, TIDELINE } from "./components/Framed";
import { Scene } from "./components/Scene";
import { Shot } from "./components/Shot";
import { Spotlight } from "./components/Spotlight";
import { Outro } from "./scenes/Outro";
import { Title } from "./scenes/Title";
import { FPS, MUSIC, TOUR_DURATION, XFADE } from "./theme";

// Ninety seconds, and every screen in the app.
//
// Two kinds of picture are cut together here. The screens that hold still —
// the first run, the six settings panes, the menu — are `screencapture -l`
// window captures from public/shots, taken at 2x against a demo folder rather
// than anybody's real Downloads. The two beats where something has to *happen*
// — the sweep, and the duplicates going to the Trash — are the recording, cut
// the same way the short promo cuts them.
//
// `promo/scripts/capture.sh` is what took the stills, and it is repeatable:
// point Tideline at ~/Downloads-demo, run it, and every shot below is replaced
// in one pass.

const XF = XFADE;

/// Scene lengths include the dissolve into the next one, so each `from` sits
/// XFADE frames before the previous scene's end.
const S = {
  title: { from: 0, duration: 100 + XF },
  mess: { from: 100, duration: 150 + XF },
  permission: { from: 250, duration: 200 + XF },
  firstSweep: { from: 450, duration: 190 + XF },
  sweep: { from: 640, duration: 200 + XF },
  overview: { from: 840, duration: 180 + XF },
  schedule: { from: 1020, duration: 170 + XF },
  filing: { from: 1190, duration: 210 + XF },
  types: { from: 1400, duration: 160 + XF },
  clearing: { from: 1560, duration: 170 + XF },
  reclaim: { from: 1730, duration: 170 + XF },
  duplicates: { from: 1900, duration: 200 + XF },
  activity: { from: 2100, duration: 150 + XF },
  general: { from: 2250, duration: 160 + XF },
  menubar: { from: 2410, duration: 150 + XF },
  outro: { from: 2560, duration: 140 },
};

// The recording's own frame numbers, the same ones the short promo uses.
// Nothing happens in this one — it is the folder before anything has been
// asked of it, and the only movement is the card creeping in.
const MESS: ClipPlan = {
  holdIn: { frame: 40, duration: 80 },
  holdOut: { frame: 40 },
  total: S.mess.duration,
};

const SWEEP: ClipPlan = {
  holdIn: { frame: 42, duration: 60 },
  play: { from: 42, duration: 70, rate: 0.55 },
  holdOut: { frame: 80 },
  total: S.sweep.duration,
};

const DUPLICATES: ClipPlan = {
  holdIn: { frame: 165, duration: 40 },
  play: { from: 165, duration: 120, rate: 0.35 },
  holdOut: { frame: 208 },
  total: S.duplicates.duration,
};

/// Settings panes end where their content does; below that the window is empty
/// and putting it on screen is putting nothing on screen. These crop to the
/// part that is written on.
const CROP = {
  schedule: { x: 0, y: 0, w: 1720, h: 780 } as Rect,
  clearing: { x: 0, y: 0, w: 1720, h: 764 } as Rect,
};

/// Controls to point at, measured off the screenshots in their own pixels.
const SPOT = {
  scheduleWatch: { x: 445, y: 255, w: 1235, h: 92 } as Rect,
  filingPreview: { x: 445, y: 735, w: 1235, h: 88 } as Rect,
};

const creep = (from: number, to: number, over: number) => (frame: number) =>
  interpolate(frame, [0, over], [from, to], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

export const Tour: React.FC = () => (
  <AbsoluteFill>
    <Backdrop total={TOUR_DURATION} />

    {MUSIC ? (
      <Audio
        src={staticFile(MUSIC)}
        volume={(f) =>
          interpolate(f, [0, FPS, TOUR_DURATION - FPS, TOUR_DURATION], [0, 1, 1, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          })
        }
      />
    ) : null}

    <Sequence from={S.title.from} durationInFrames={S.title.duration}>
      <Scene duration={S.title.duration}>
        <Title
          tagline="A closer look"
          note="Every screen, from the first run to the menu bar"
        />
      </Scene>
    </Sequence>

    <Sequence from={S.mess.from} durationInFrames={S.mess.duration}>
      <Scene duration={S.mess.duration}>
        <DemoShot
          plan={MESS}
          stage="top"
          aspect={aspect(FINDER)}
          rectAt={() => FINDER}
          cardScaleAt={creep(1, 1.02, S.mess.duration)}
        >
          <Caption
            kicker="The folder"
            headline="This is the folder it is for."
            note="Three months of downloads in one flat list — with artifact.zip, artifact-1.zip and artifact-2.zip somewhere in the middle of it."
          />
        </DemoShot>
      </Scene>
    </Sequence>

    <Sequence from={S.permission.from} durationInFrames={S.permission.duration}>
      <Scene duration={S.permission.duration}>
        <Shot name="welcome-permission" stage="side" scaleAt={creep(1, 1.015, S.permission.duration)}>
          <Caption
            where="side"
            kicker="First run"
            headline="It asks before it reads anything."
            note="The window opens on “not filing yet”. macOS is not asked for the folder until you press the button, and that prompt is scoped to the one folder."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.firstSweep.from} durationInFrames={S.firstSweep.duration}>
      <Scene duration={S.firstSweep.duration}>
        <Shot name="welcome-first-sweep" stage="side" scaleAt={creep(1, 1.015, S.firstSweep.duration)}>
          <Caption
            where="side"
            kicker="First run"
            headline="Then it says what the first sweep would do."
            note="15 items into 10 folders, 4 left loose — worked out on the folder as it stands, before anything has moved."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.sweep.from} durationInFrames={S.sweep.duration}>
      <Scene duration={S.sweep.duration}>
        <DemoShot plan={SWEEP} stage="top" aspect={aspect(FINDER)} rectAt={() => FINDER}>
          <Caption
            kicker="The sweep"
            headline="Everything older moves into a folder named for the day it arrived."
            note="Today's downloads stay loose in the root, under their real names."
          />
        </DemoShot>
      </Scene>
    </Sequence>

    <Sequence from={S.overview.from} durationInFrames={S.overview.duration}>
      <Scene duration={S.overview.duration}>
        <Shot name="overview" stage="side" scaleAt={creep(1, 1.015, S.overview.duration)}>
          <Caption
            where="side"
            kicker="Overview"
            headline="What it is doing, and what is due next."
            note="Every item in the root, when it arrived, and whether it stays put or moves on the next sweep."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.schedule.from} durationInFrames={S.schedule.duration}>
      <Scene duration={S.schedule.duration}>
        <Shot
          name="schedule"
          stage="top"
          crop={CROP.schedule}
          overlay={
            <Spotlight rect={SPOT.scheduleWatch} delay={70} />
          }
        >
          <Caption
            kicker="Schedule"
            headline="When it runs."
            note="As soon as the folder changes, once a day at a time you set, and again when the app starts after the Mac was off at that time."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.filing.from} durationInFrames={S.filing.duration}>
      <Scene duration={S.filing.duration}>
        <Shot
          name="filing"
          stage="side"
          overlay={
            <Spotlight rect={SPOT.filingPreview} delay={95} />
          }
        >
          <Caption
            where="side"
            kicker="Filing"
            headline="What gets filed, and what never does."
            note="The window that stays loose, the folder name, which date it sorts by — and a skip list for the folders you keep yourself."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.types.from} durationInFrames={S.types.duration}>
      <Scene duration={S.types.duration}>
        <Shot name="type-folders" stage="side" scaleAt={creep(1, 1.015, S.types.duration)}>
          <Caption
            where="side"
            kicker="Type folders"
            headline="Or by what a thing is, rather than when it came."
            note="Installers, archives, images — each with its own list of extensions, and each off until you switch it on."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.clearing.from} durationInFrames={S.clearing.duration}>
      <Scene duration={S.clearing.duration}>
        <Shot name="clearing" stage="top" crop={CROP.clearing}>
          <Caption
            kicker="Clearing"
            headline="And when the old folders go."
            note="Dated folders past an age you set — to the Trash, never straight to delete, and the newest few are always kept."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.reclaim.from} durationInFrames={S.reclaim.duration}>
      <Scene duration={S.reclaim.duration}>
        <Shot name="reclaim" stage="side" scaleAt={creep(1, 1.015, S.reclaim.duration)}>
          <Caption
            where="side"
            kicker="Reclaim space"
            headline="What is safe to let go."
            note="Duplicates, the biggest files, and the folders old enough to clear. A scan only reads — nothing moves until you tick it."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.duplicates.from} durationInFrames={S.duplicates.duration}>
      <Scene duration={S.duplicates.duration}>
        <DemoShot plan={DUPLICATES} stage="side" aspect={aspect(TIDELINE)} rectAt={() => TIDELINE}>
          <Caption
            where="side"
            kicker="Reclaim space"
            headline="The same file, more than once."
            note="Same name bar a copy suffix, and byte-for-byte the same contents. The newest is kept, and the one that stays gets its plain name back."
          />
        </DemoShot>
      </Scene>
    </Sequence>

    <Sequence from={S.activity.from} durationInFrames={S.activity.duration}>
      <Scene duration={S.activity.duration}>
        <Shot name="activity" stage="side" scaleAt={creep(1, 1.015, S.activity.duration)}>
          <Caption
            where="side"
            kicker="Activity log"
            headline="Every move, written down."
            note="What moved and where it went, so a file you cannot find is a list away rather than a search."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.general.from} durationInFrames={S.general.duration}>
      <Scene duration={S.general.duration}>
        <Shot name="general" stage="side" scaleAt={creep(1, 1.015, S.general.duration)}>
          <Caption
            where="side"
            kicker="General"
            headline="Updates, and the way back out."
            note="It checks the releases page once a day and downloads nothing without asking. Uninstall undoes the app and leaves every folder where it is."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.menubar.from} durationInFrames={S.menubar.duration}>
      <Scene duration={S.menubar.duration}>
        <Shot name="menubar" stage="side" heightCap={700} scaleAt={creep(1, 1.02, S.menubar.duration)}>
          <Caption
            where="side"
            kicker="The menu bar"
            headline="The rest of the time it is one icon."
            note="No Dock icon, no helper process, no window until you open one. Quitting it really is the end of it."
          />
        </Shot>
      </Scene>
    </Sequence>

    <Sequence from={S.outro.from} durationInFrames={S.outro.duration}>
      <Scene duration={S.outro.duration}>
        <Outro />
      </Scene>
    </Sequence>

    <TideMark total={TOUR_DURATION} />
  </AbsoluteFill>
);
