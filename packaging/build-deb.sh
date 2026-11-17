#!/bin/sh
# Builds the monitor-control .deb from a compiled binary. The single
# definition of the package: the release workflow
# (.github/workflows/release.yml) and the monorepo's Bazel build both run it.
#
#   packaging/build-deb.sh <binary> <version> <arch> <out.deb>
#
#   <binary>   the compiled program (e.g. core/build/main); it gets stripped.
#   <version>  Debian version, must start with a digit (1.2.0, not v1.2.0).
#   <arch>     Debian architecture the binary was built for
#              (`dpkg --print-architecture`).
#
# Environment:
#   SOURCE_DATE_EPOCH  timestamp for the changelog entry and file mtimes
#                      (default: now).
#   DEB_MAINTAINER     Maintainer field (default below).
#
# Needs dpkg-dev (dpkg-deb, dpkg-shlibdeps), binutils (strip) and gzip.
set -eu

if [ $# -ne 4 ]; then
	echo "usage: $0 <binary> <version> <arch> <out.deb>" >&2
	exit 2
fi
bin=$1
version=$2
arch=$3
out=$4

case $version in
[0-9]*) ;;
*)
	echo "build-deb.sh: version must start with a digit, got '$version'" >&2
	exit 1
	;;
esac

pkg=monitor-control
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
maintainer=${DEB_MAINTAINER:-"Alfonso Villalobos Ulate <alfonsocv12@users.noreply.github.com>"}
epoch=${SOURCE_DATE_EPOCH:-$(date +%s)}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root=$work/root
doc=$root/usr/share/doc/$pkg

install -d "$root/DEBIAN" "$root/usr/bin" "$root/usr/lib/systemd/system" \
	"$root/usr/lib/modules-load.d" "$doc"

# Full strip, as dh_strip does.
strip --strip-unneeded --remove-section=.comment --remove-section=.note \
	-o "$root/usr/bin/$pkg" "$bin"
chmod 0755 "$root/usr/bin/$pkg"

install -m 0644 "$here/monitor-control.service" "$root/usr/lib/systemd/system/$pkg.service"
install -m 0644 "$here/modules-load.conf" "$root/usr/lib/modules-load.d/$pkg.conf"
install -m 0644 "$top/README.md" "$doc/README.md"

# Machine-readable copyright: the header plus LICENSE as the license text
# (indented one space, blank lines as " .").
{
	cat "$here/copyright.header"
	awk '{ print ($0 == "" ? " ." : " " $0) }' "$top/LICENSE"
} >"$doc/copyright"
chmod 0644 "$doc/copyright"

{
	printf '%s (%s) unstable; urgency=medium\n\n' "$pkg" "$version"
	printf '  * Release %s.\n\n' "$version"
	printf ' -- %s  %s\n' "$maintainer" "$(LC_ALL=C date -u -R -d "@$epoch")"
} | gzip -9n >"$doc/changelog.Debian.gz"
chmod 0644 "$doc/changelog.Debian.gz"

for script in postinst prerm postrm; do
	install -m 0755 "$here/$script" "$root/DEBIAN/$script"
done

# Shared-library dependencies of the binary as built on this machine.
# dpkg-shlibdeps wants a debian/control next to it; any source stanza will do.
mkdir "$work/debian"
echo "Source: $pkg" >"$work/debian/control"
depends=$(cd "$work" && dpkg-shlibdeps --warnings=0 -O "root/usr/bin/$pkg" |
	sed -n 's/^shlibs:Depends=//p')

installed_size=$(du -sk --exclude=DEBIAN "$root" | cut -f1)

cat >"$root/DEBIAN/control" <<EOF
Package: $pkg
Version: $version
Architecture: $arch
Maintainer: $maintainer
Installed-Size: $installed_size
Depends: $depends
Section: utils
Priority: optional
Homepage: https://github.com/alfonsocv12/monitor-control
Description: Brightness keys for external monitors over DDC/CI
 Listens for the keyboard brightness keys and adjusts external monitors'
 brightness through ddcutil, like MonitorControl on macOS.
EOF

find "$root" -exec touch -h -d "@$epoch" {} +
dpkg-deb --root-owner-group --build "$root" "$out" >/dev/null
echo "Built $out"
