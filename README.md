<div align="center">

# ⚡ wswitch Switcher

This is a fork of the [snappy-wswitch](https://github.com/OpalAayan/snappy-switcher).

### A blazing-fast, Alt+Tab window switcher for wayland compositors

[![License](https://img.shields.io/badge/License-GPL3-blue?style=for-the-badge&logo=gnu)](LICENSE)
[![Language](https://img.shields.io/badge/Language-C-orange?style=for-the-badge&logo=c)](https://en.cppreference.com/w/c)
[![Version](https://img.shields.io/badge/Version-1.0-success?style=for-the-badge)]()
[![AUR](https://img.shields.io/aur/version/wswitch?color=blue&label=AUR&logo=arch-linux&style=for-the-badge)](https://aur.archlinux.org/packages/wswitch)

<br/>

<img src="assets/wswitch-slate.png" alt="wswitch Switcher Showcase" width="700"/>

<br/>

*The window switcher that actually understands your workflow.*

</div>

---

## 🖥️ **Compatible Compositors**

**wswitch** works with **any Wayland compositor** that implements the **foreign-toplevel** protocol, such as **Mango**, **Sway**, and more.


## 📦 Installation

### <img src="https://img.shields.io/badge/AUR-1793D1?style=flat&logo=archlinux&logoColor=white" height="20"/> Arch Linux (AUR)

<table>
<tr>
<td>

**Using Yay**
```bash
yay -S wswitch
```

</td>
<td>

**Using Paru**
```bash
paru -S wswitch
```

</td>
</tr>
</table>

<details>
<summary>📦 <b>Build from PKGBUILD</b></summary>

```bash
git clone https://github.com/DreamMaoMao/wswitch.git
cd wswitch
makepkg -si
```

</details>

### Manual Build

<details>
<summary>📋 <b>Dependencies</b></summary>

| Package | Purpose |
|---------|---------|
| `wayland` | Core protocol |
| `cairo` | 2D rendering |
| `pango` | Text layout |
| `json-c` | IPC parsing |
| `libxkbcommon` | Keyboard handling |
| `glib2` | Utilities |
| `librsvg` | SVG icons *(optional)* |

</details>

**Install dependencies (Arch):**
```bash
sudo pacman -S wayland cairo pango json-c libxkbcommon glib2 librsvg
```

```bash
# Build
make

# Install system-wide
sudo make install

# Or install for current user only
make install-user
```

---

## 🚀 Quick Start

### 1️⃣ Setup Configuration

```bash
wswitch-install-config
```

This copies themes and creates `~/.config/wswitch/config.ini`.

### 2️⃣ Add to Sway Config

Add these lines to `~/.config/sway/config`:

```bash
# Start the daemon on login
exec wswitch --daemon

# Keybindings
bindsym Alt+tab exec wswitch next
```

### 3️⃣ You're Done! 🎉

Press <kbd>Alt</kbd> + <kbd>Tab</kbd> to see it in action.

---


### 🎯 Change Theme

Edit `~/.config/wswitch/config.ini`:

```ini
[theme]
name = catppuccin-mocha.ini
```

---

## ⚙️ Configuration

<details>

```ini
# ~/.config/wswitch/config.ini

[general]
# overview = Show all windows individually
# context  = Group tiled windows by workspace + app class
mode = context

[theme]
name = wswitch-slate.ini
border_width = 2
corner_radius = 12

[layout]
card_width = 160
card_height = 140
card_gap = 10
padding = 20
max_cols = 5
icon_size = 56

[icons]
theme = Tela-dracula
fallback = hicolor
show_letter_fallback = true

[font]
family = Sans
weight = Bold
title_size = 10
```
</details>

---

## 🧪 Available Commands

| Command | Description |
|---------|-------------|
| `wswitch --daemon` | Start background daemon |
| `wswitch next` | Cycle to next window |
| `wswitch prev` | Cycle to previous window |
| `wswitch toggle` | Show/hide switcher |
| `wswitch hide` | Force hide overlay |
| `wswitch select` | Confirm current selection |
| `wswitch quit` | Stop the daemon |

---

## 💡 Credits & Inspiration

| Project | Contribution |
|---------|--------------|
| **[hyprshell](https://github.com/OpalAayan/snappy-switcher)** | Massive inspiration for the design of the window switcher |

---

<div align="center">

<sub>Licensed under GPL-3.0</sub>

</div>
