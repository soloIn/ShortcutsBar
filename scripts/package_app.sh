#!/bin/zsh
set -e

swift build -c release
mkdir -p ShortcutsBar.app/Contents/MacOS
mkdir -p ShortcutsBar.app/Contents/Resources
cp .build/release/ShortcutsBar ShortcutsBar.app/Contents/MacOS/ShortcutsBar

cat << 'EOF' > ShortcutsBar.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ShortcutsBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.shortcutsbar.app</string>
    <key>CFBundleName</key>
    <string>ShortcutsBar</string>
    <key>CFBundleDisplayName</key>
    <string>Shortcuts Bar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Shortcuts Bar. All rights reserved.</string>
</dict>
</plist>
EOF

swift scripts/generate_app_icon.swift
iconutil -c icns AppIcon.iconset -o ShortcutsBar.app/Contents/Resources/AppIcon.icns
rm -rf AppIcon.iconset

codesign --force --deep --sign - ShortcutsBar.app
echo "Packaged and signed ShortcutsBar.app successfully!"
