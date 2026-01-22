# Snappy Switcher Themes

This directory contains color themes for Snappy Switcher.

## Available Themes

| Theme | Description |
|-------|-------------|
| `snappy-slate.ini` | Default dark theme (Catppuccin-inspired) |
| `catppuccin-mocha.ini` | Catppuccin Mocha |
| `catppuccin-latte.ini` | Catppuccin Latte (light theme) |
| `nord.ini` | Nord color scheme |
| `dracula.ini` | Dracula theme |
| `gruvbox-dark.ini` | Gruvbox Dark |
| `tokyo-night.ini` | Tokyo Night |

## How to Use

1. Edit your `~/.config/snappy-switcher/config.ini`
2. Set the theme name:
   ```ini
   [theme]
   name = catppuccin-mocha.ini
   ```
3. Restart the daemon:
   ```bash
   snappy-switcher quit
   snappy-switcher --daemon
   ```

## Theme Locations

Themes are searched in order:
1. `~/.config/snappy-switcher/themes/` (user themes)
2. `/usr/share/snappy-switcher/themes/` (system themes)
3. `/usr/local/share/snappy-switcher/themes/` (local install)

## Creating Custom Themes

Create a new `.ini` file with:

```ini
# My Custom Theme

[colors]
background = #1e1e2e
card_bg = #313244
card_selected = #45475a
text_color = #cdd6f4
subtext_color = #a6adc8
border_color = #89b4fa
```

Save it to `~/.config/snappy-switcher/themes/my-theme.ini` and reference it in your config.

## Overriding Colors

You can override specific colors in your `config.ini` after setting a theme:

```ini
[theme]
name = nord.ini
border_color = #ff0000  # Override just the border
```
