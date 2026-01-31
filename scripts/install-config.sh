#!/bin/bash
# wswitch Switcher - Configuration Setup Helper
# Sets up user configuration directory with themes

set -e

CONFIG_DIR="$HOME/.config/wswitch"
THEMES_DIR="$CONFIG_DIR/themes"
SYSTEM_THEMES="/usr/local/share/wswitch/themes"
SYSTEM_CONFIG="/usr/local/share/doc/wswitch/config.ini.example"
ALT_SYSTEM_CONFIG="/etc/xdg/wswitch/config.ini"
FORCE=false

# Parse args
for arg in "$@"; do
    case $arg in
        --force|-f) FORCE=true ;;
        --help|-h) 
            echo "Usage: wswitch-install-config [--force]"
            echo "  --force  Overwrite existing config.ini"
            exit 0
            ;;
    esac
done

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           wswitch Switcher Configuration Setup                 ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Remove old user binary if exists (causes conflicts)
if [ -f "$HOME/.local/bin/wswitch" ]; then
    echo "⚠️  Removing old binary from ~/.local/bin/ (conflicts with system install)"
    rm -f "$HOME/.local/bin/wswitch"
fi

# Create directories
echo "📁 Creating config directory: $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$THEMES_DIR"

# Copy themes
if [ -d "$SYSTEM_THEMES" ]; then
    echo "🎨 Copying themes from $SYSTEM_THEMES..."
    cp -n "$SYSTEM_THEMES"/*.ini "$THEMES_DIR/" 2>/dev/null || true
fi

# Copy config
if [ ! -f "$CONFIG_DIR/config.ini" ] || [ "$FORCE" = true ]; then
    if [ -f "$SYSTEM_CONFIG" ]; then
        echo "📝 Creating config from $SYSTEM_CONFIG..."
        cp "$SYSTEM_CONFIG" "$CONFIG_DIR/config.ini"
    elif [ -f "$ALT_SYSTEM_CONFIG" ]; then
        echo "📝 Creating config from $ALT_SYSTEM_CONFIG..."
        cp "$ALT_SYSTEM_CONFIG" "$CONFIG_DIR/config.ini"
    fi
    echo "✅ Config file created!"
else
    echo "ℹ️  Config exists: $CONFIG_DIR/config.ini (use --force to overwrite)"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                     Setup Complete!                           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "📂 Config: $CONFIG_DIR/config.ini"
echo ""
echo "🎨 Available themes:"
for theme in "$THEMES_DIR"/*.ini; do
    [ -f "$theme" ] && echo "   - $(basename "$theme")"
done
echo ""
echo "🚀 Quick start:"
echo "   wswitch --daemon &"
echo "   wswitch toggle"
echo ""
echo "📝 To change theme, edit config.ini:"
echo "   [theme]"
echo "   name = catppuccin-mocha.ini"
echo ""
