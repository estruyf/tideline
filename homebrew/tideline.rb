cask "tideline" do
  version "1.8.0"
  sha256 "630860178a49934e60f3b7bfb578995f91c8b2bcd6f7e53f8747f3b9c61fd39f"

  url "https://github.com/estruyf/tideline/releases/download/v#{version}/Tideline-#{version}-macos-universal.zip"
  name "Tideline"
  desc "Menu bar app that files older downloads into folders by arrival date"
  homepage "https://github.com/estruyf/tideline"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Tideline looks for a newer release once a day and installs it itself, so
  # `brew upgrade` should leave it alone rather than race the in-app updater.
  # The tap still moves on every release, which is what `--greedy` and a fresh
  # `brew install` read.
  auto_updates true

  # The in-app updater has no floor of its own, so this is the only thing
  # standing between someone on macOS 13 and a bundle that will not launch.
  depends_on macos: ">= :sonoma"

  app "Tideline.app"

  # It is a background app with no Dock icon, so an upgrade would otherwise
  # replace the bundle out from under a copy that is still running.
  uninstall quit: "be.eliostruyf.Tideline"

  # The same three paths the app's own Uninstall sheet names. Nothing here is
  # in the Downloads folder: `brew uninstall --zap` removes Tideline, never
  # anything Tideline filed.
  zap trash: [
    "~/Library/Application Support/Tideline",
    "~/Library/Logs/Tideline.log",
    "~/Library/Preferences/be.eliostruyf.Tideline.plist",
  ]
end
