#!/usr/bin/env bash
set -euo pipefail

# Build in a fresh checkout; never reset or patch a developer's working tree.
revision=5e96ae20ec73c320248bcf3ff68b330bc1ed4152
native_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
build_dir=$(mktemp -d -t grid-scrolloverview-build.XXXXXXXX)
trap 'rm -rf -- "$build_dir"' EXIT
install_dir=${NATIVE_INSTALL_DIR:-"$HOME/.local/lib/hyprland-grid"}

pkg-config --exists hyprland pixman-1 libdrm pangocairo libinput libudev wayland-server xkbcommon
git -C "$build_dir" init --quiet
git -C "$build_dir" fetch --quiet --depth=1 https://github.com/yayuuu/hyprland-scroll-overview.git "$revision"
git -C "$build_dir" checkout --quiet --detach FETCH_HEAD
git -C "$build_dir" apply "$native_dir/scrolloverview.patch"
make -C "$build_dir" -j"${JOBS:-2}"

# Never overwrite a library already mapped into the running compositor.
digest=$(sha256sum "$build_dir/scrolloverview.so")
library="scrolloverview-${digest:0:16}.so"
mkdir -p -- "$install_dir"
if [[ ! -e "$install_dir/$library" ]]; then
    install -m 755 "$build_dir/scrolloverview.so" "$install_dir/$library"
fi
ln -sfn -- "$library" "$install_dir/scrolloverview.so"
printf 'Installed %s/%s\nRestart Hyprland after rebuilding a plugin already loaded in this session.\n' "$install_dir" "$library"
