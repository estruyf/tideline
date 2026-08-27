import { Config } from "@remotion/cli/config";

// The recording is h264 1080p and the promo is the same shape, so nothing here
// needs to change per render. CRF 17 is high enough that the Finder rows stay
// readable after YouTube re-encodes it.
Config.setVideoImageFormat("jpeg");
Config.setOverwriteOutput(true);
Config.setConcurrency(4);
