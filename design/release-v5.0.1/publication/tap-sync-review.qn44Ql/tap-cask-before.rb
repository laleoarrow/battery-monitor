cask "wattson" do
  version "5.0.0"
  sha256 "d47c879002070761a4952c01484a5ee9a38370e4dc22b1bd0619b8afac94ece7"

  url "https://github.com/laleoarrow/battery-monitor/releases/download/v#{version}/Wattson-v#{version}-macos-universal.pkg"
  name "Wattson"
  desc "Real-time menu-bar power-flow monitor"
  homepage "https://github.com/laleoarrow/battery-monitor"

  depends_on macos: :monterey

  pkg "Wattson-v#{version}-macos-universal.pkg"

  uninstall launchctl: [
              "com.leoarrow.wattson.helper",
              "com.leoarrow.wattson.login",
            ],
            quit:      "com.leoarrow.wattson",
            pkgutil:   "com.leoarrow.wattson.pkg",
            delete:    [
              "/Applications/Wattson.app",
              "/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist",
              "/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper",
              "/var/run/wattson-helper.sock",
              "~/Library/LaunchAgents/com.leoarrow.wattson.login.plist",
            ]

  zap trash: [
    "~/Library/Application Support/Wattson",
    "~/Library/Caches/com.leoarrow.wattson",
    "~/Library/Containers/com.leoarrow.wattson",
    "~/Library/Preferences/com.leoarrow.wattson.plist",
    "~/Library/Saved Application State/com.leoarrow.wattson.savedState",
  ]
end
