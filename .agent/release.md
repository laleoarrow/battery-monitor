# Release and deployment

## Deploying locally

To install or update the app locally on the macOS system:
```bash
cd /Users/leoarrow/Project/mypackage/agents/电池功率
bash scripts/install.sh
```
This script performs the following actions:
1. Copies the python script `battery_monitor.py` to `$HOME/.battery_monitor.py`.
2. Creates the app structure at `$HOME/Applications/电池功率.app/`.
3. Compiles `BatteryPowerWidget.swift` to the native executable at `Contents/MacOS/applet`.
4. Builds `BatteryPowerWidgetExtension.xcodeproj` and copies the resulting `BatteryPowerWidgetExtension.appex` to `Contents/PlugIns/` for the macOS widget gallery.
5. Generates the `Contents/Info.plist` with app metadata and hides the Dock icon (`LSUIElement=true`).
6. Copies the custom application icon `design/icon/AppIcon.icns` if present into the app bundle resources.
7. Signs the WidgetKit extension and host app with their sandbox entitlements, then signs the outer app bundle while preserving nested entitlements.
8. Installs a user LaunchAgent at `~/Library/LaunchAgents/com.leoarrow.battery-monitor.agent.plist` so the host app starts at login and restarts after crashes. A normal user quit is not forced to relaunch.

The Python script is still copied to `$HOME/.battery_monitor.py` for compatibility/reference, but the installed app runs the native Swift/AppKit executable.
The installed AppKit app also writes `~/Library/Application Support/电池功率/widget-snapshot.json`; the sandboxed WidgetKit extension reads that snapshot because direct IORegistry access is not available from the extension sandbox. Keep the host app sandbox entitlement and its temporary read/write exceptions, otherwise `chronod` may register the extension but omit it from the Widgets gallery.

After install, verify the system widget extension is visible to macOS:
```bash
pluginkit -m -v -A -D -i com.leoarrow.battery-monitor.widget
```

## Building the release DMG

To build the app and package a user-installable DMG:

```bash
cd /Users/leoarrow/Project/mypackage/agents/电池功率
bash scripts/package_dmg.sh 1.3.0
```

The DMG is written to `dist/电池功率-v1.3.0.dmg` and contains:
- `电池功率.app`
- an `Applications` symlink for drag-and-drop installation

The DMG is suitable for GitHub Releases. The app is ad-hoc signed for local use
unless a Developer ID certificate and notarization flow are added later.

## Building and generating AppIcon.icns

The app icon is designed in the `design/` folder. If you edit or regenerate the icon PNG file:
1. Ensure the icon PNG is exactly 1024x1024 pixels with transparency.
2. If using standard macOS tools to compile `.icns`:
   ```bash
   # Create iconset folder
   mkdir -p AppIcon.iconset
   
   # Generate sizes (e.g. using sips or image conversion tools)
   sips -z 16 16   AppIcon.png --out AppIcon.iconset/icon_16x16.png
   sips -z 32 32   AppIcon.png --out AppIcon.iconset/icon_16x16@2x.png
   sips -z 32 32   AppIcon.png --out AppIcon.iconset/icon_32x32.png
   sips -z 64 64   AppIcon.png --out AppIcon.iconset/icon_32x32@2x.png
   sips -z 128 128 AppIcon.png --out AppIcon.iconset/icon_128x128.png
   sips -z 256 256 AppIcon.png --out AppIcon.iconset/icon_128x128@2x.png
   sips -z 256 256 AppIcon.png --out AppIcon.iconset/icon_256x256.png
   sips -z 512 512 AppIcon.png --out AppIcon.iconset/icon_256x256@2x.png
   sips -z 512 512 AppIcon.png --out AppIcon.iconset/icon_512x512.png
   sips -z 1024 1024 AppIcon.png --out AppIcon.iconset/icon_512x512@2x.png
   
   # Convert iconset to icns
   iconutil -c icns AppIcon.iconset -o design/icon/AppIcon.icns
   rm -rf AppIcon.iconset
   ```
3. Re-run `bash scripts/install.sh` to apply the new icon to the app bundle. You may need to restart Finder or run `killall Finder` if macOS caches the old icon.

## Release tagging and Git management

The project uses git for version control under `/Users/leoarrow/Project/mypackage/agents/电池功率`.

To create a new version release tag:
```bash
git add .
git commit -m "chore: release version v1.2.0"
git tag v1.2.0
```

To sync and push to the remote repository (once origin is set):
```bash
git push origin main --tags
```
