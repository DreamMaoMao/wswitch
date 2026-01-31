# Maintainer: DreamMaoMao <maoopzopaasnmakslpo@gmail.com>
pkgname=wswitch
pkgver=1.0.0
pkgrel=1
pkgdesc="A fast, Alt+Tab window switcher for wayland compositors with MRU sorting and context grouping"
arch=('x86_64')
url="https://github.com/OpalAayan/wswitch"
license=('GPL3')
depends=(
  'wayland'
  'cairo'
  'pango'
  'json-c'
  'libxkbcommon'
  'glib2'
  'librsvg'
)
makedepends=(
  'wayland-protocols'
  'pkgconf'
  'gcc'
  'make'
)
optdepends=(
  'tela-icon-theme: Recommended icon theme'
)
provides=("$pkgname")
conflicts=("$pkgname-git")
# Use this for release versions. For now, we SKIP the check.
source=("$url/archive/v$pkgver.tar.gz")
sha256sums=('a3e9d527f1598c0ad59b22a9a7f52bc4f8c0ed690a3a22d0fc75d5afc6df24f1')

build() {
  cd "$pkgname-$pkgver"
  # Ensure we use standard paths
  make PREFIX=/usr
}

package() {
  cd "$pkgname-$pkgver"

  # 1. Binaries
  install -Dm755 wswitch "$pkgdir/usr/bin/wswitch"
  install -Dm755 scripts/install-config.sh "$pkgdir/usr/bin/wswitch-install-config"

  # 2. Themes
  install -d "$pkgdir/usr/share/wswitch/themes"
  install -Dm644 themes/*.ini "$pkgdir/usr/share/wswitch/themes/"

  # 3. System Config Defaults
  install -Dm644 config.ini.example "$pkgdir/etc/xdg/wswitch/config.ini"

  # 4. Documentation
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
  install -Dm644 docs/ARCHITECTURE.md "$pkgdir/usr/share/doc/$pkgname/ARCHITECTURE.md"
  install -Dm644 docs/CONFIGURATION.md "$pkgdir/usr/share/doc/$pkgname/CONFIGURATION.md"
  install -Dm644 config.ini.example "$pkgdir/usr/share/doc/$pkgname/config.ini.example"

  # 5. Systemd Service (Optional, but good to include if available)
  if [ -f "wswitch.service" ]; then
    install -Dm644 wswitch.service "$pkgdir/usr/lib/systemd/user/wswitch.service"
  fi
}
