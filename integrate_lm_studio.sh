#!/usr/bin/env bash
# integrate_lm_studio.sh
# Automates moving the AppImage, extracting its icon, creating a launcher,
# and updating your system so LM Studio behaves like a normal app.

set -euo pipefail

# --- Configuration ---
APPIMAGE_SOURCE="${1:-}"
if [ -z "$APPIMAGE_SOURCE" ]; then
    echo "ℹ️  No AppImage path provided, attempting auto-detection..."
    # Auto-detect the newest LM Studio AppImage in current directory
    APPIMAGE_SOURCE=$(ls -t LM-Studio-*.AppImage 2>/dev/null | head -1 || true)
    if [ -z "$APPIMAGE_SOURCE" ]; then
        echo "❌ Error: No AppImage path provided and no LM Studio AppImage found in current directory."
        echo ""
        echo "Usage: $0 <path-to-appimage>"
        echo "Example: $0 ~/Downloads/LM-Studio-0.2.9.AppImage"
        echo ""
        echo "Alternatively, place LM-Studio-*.AppImage in the current directory and run without arguments."
        exit 1
    fi
    echo "✅ Auto-detected: $APPIMAGE_SOURCE"
fi
APPIMAGE_NAME=$(basename "$APPIMAGE_SOURCE")
INSTALL_DIR="$HOME/Applications"
SYMLINK="/usr/local/bin/lm-studio"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
LOCAL_HICOLOR="$HOME/.local/share/icons/hicolor"
SYSTEM_HICOLOR_INDEX="/usr/share/icons/hicolor/index.theme"

echo "This script will need sudo for system changes."
sudo -v   # ask for password up-front

# Check for libfuse2 dependency
echo "Checking for required dependencies..."
if ! dpkg -l | grep -q "^ii  libfuse2"; then
    echo "⚠️  Warning: libfuse2 is not installed. AppImages require FUSE to run."
    echo ""
    read -p "Would you like to install libfuse2 now? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing libfuse2..."
        sudo apt-get update && sudo apt-get install -y libfuse2
        if [ $? -eq 0 ]; then
            echo "✅ libfuse2 installed successfully"
        else
            echo "❌ Failed to install libfuse2. You may need to install it manually."
            echo "Run: sudo apt-get install libfuse2"
            exit 1
        fi
    else
        echo "⚠️  Continuing without libfuse2. The AppImage may not run until you install it."
        echo "To install later, run: sudo apt-get install libfuse2"
    fi
else
    echo "✅ libfuse2 is installed"
fi

# 1. Move AppImage
mkdir -p "$INSTALL_DIR"

# Remove old versions to avoid clutter
echo "[1/7] Cleaning up old LM Studio versions..."
for old_appimage in "$INSTALL_DIR"/LM-Studio-*.AppImage; do
    if [ -f "$old_appimage" ] && [ "$old_appimage" != "$INSTALL_DIR/$APPIMAGE_NAME" ]; then
        echo "  Removing old version: $(basename "$old_appimage")"
        rm -f "$old_appimage"
    fi
done

# Move new AppImage
if [ "$APPIMAGE_SOURCE" != "$INSTALL_DIR/$APPIMAGE_NAME" ]; then
    mv "$APPIMAGE_SOURCE" "$INSTALL_DIR/"
    echo "  Moved $APPIMAGE_NAME to $INSTALL_DIR"
fi
APPIMAGE_PATH="$INSTALL_DIR/$APPIMAGE_NAME"

# 2. Make it executable
chmod +x "$APPIMAGE_PATH"
echo "[2/7] Made AppImage executable"

# 3. Extract embedded files (including icon)
cd "$INSTALL_DIR"
echo "[3/7] Extracting AppImage..."
# Clean up any old extraction directory
[ -d squashfs-root ] && rm -rf squashfs-root
./"$APPIMAGE_NAME" --appimage-extract > /dev/null

# 4. Install icon (using your existing path)
mkdir -p "$ICON_DIR"
echo "[4/7] Installing icon to $ICON_DIR"
cp squashfs-root/usr/share/icons/hicolor/0x0/apps/lm-studio.png "$ICON_DIR/"

# 5. Ensure local index.theme exists
if [ ! -f "$LOCAL_HICOLOR/index.theme" ]; then
  mkdir -p "$LOCAL_HICOLOR"
  echo "[5/7] Copying index.theme to local hicolor"
  cp "$SYSTEM_HICOLOR_INDEX" "$LOCAL_HICOLOR/"
fi

# 6. Create a stable symlink
echo "[6/7] Creating wrapper script at $SYMLINK"
sudo tee "$SYMLINK" > /dev/null <<WRAPPER
#!/bin/bash
exec "$APPIMAGE_PATH" --no-sandbox "\$@"
WRAPPER
sudo chmod +x "$SYMLINK"

# 7. Write desktop entry
mkdir -p "$DESKTOP_DIR"
echo "[7/7] Writing desktop file to $DESKTOP_DIR"
cat > "$DESKTOP_DIR/lm-studio.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=LM Studio
Comment=Lightweight LLM development GUI
Exec=$SYMLINK --no-sandbox %U
Icon=lm-studio
Categories=Development;IDE;
Terminal=false
EOF

# 8. Refresh desktop and icon caches
echo "Refreshing desktop database and icon cache..."
sudo update-desktop-database /usr/share/applications 2>/dev/null || update-desktop-database "$DESKTOP_DIR"
sudo gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || gtk-update-icon-cache "$LOCAL_HICOLOR"

echo -e "\n✅ Integration complete! Launch via your app menu or run 'lm-studio'."
