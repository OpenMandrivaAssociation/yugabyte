#!/bin/bash
# Download everything YugabyteDB's build will want from the network, then pack
# it so the OpenMandriva package can build offline.
#
# Run this from the package directory (next to yugabyte.spec), with network.
# Then `abb store` the resulting archives (do not edit .abf.yml by hand).
#
# Do not add checksums to .abf.yml by hand.

set -euo pipefail

VERSION=2026.1.1.0
# Pinned by v2026.1.1.0 build-support/thirdparty_archives.yml
THIRDPARTY_COMMIT=e42841c02e3e540840ba44ae23cd2adc3c2c245d
# Pinned by v2026.1.1.0 build-support/yugabyte-bash-common-sha1.txt
BASHCOMMON_COMMIT=74793a6e1712ac45dc07cd430da303c95d37f584

WORKDIR=$(pwd)
STAGING=$(mktemp -d -t yugabyte-offline-XXXXXX)
trap 'rm -rf "$STAGING"' EXIT

download() {
	local url=$1 dest=$2
	if [[ -s $dest ]]; then
		echo "Already have $dest"
		return
	fi
	echo "Downloading $url"
	curl -fL --retry 5 --retry-delay 2 -o "$dest" "$url"
}

echo "==> Primary source archives"

download \
	"https://github.com/yugabyte/yugabyte-db/archive/refs/tags/v${VERSION}.tar.gz" \
	"$WORKDIR/yugabyte-db-${VERSION}.tar.gz"

download \
	"https://github.com/yugabyte/yugabyte-db-thirdparty/archive/${THIRDPARTY_COMMIT}.tar.gz" \
	"$WORKDIR/yugabyte-db-thirdparty-${THIRDPARTY_COMMIT}.tar.gz"

download \
	"https://github.com/yugabyte/yugabyte-bash-common/archive/${BASHCOMMON_COMMIT}.tar.gz" \
	"$WORKDIR/yugabyte-bash-common-${BASHCOMMON_COMMIT}.tar.gz"

echo "==> Yugabyte-only Python helpers (no pip; PYTHONPATH only)"

download https://pypi.io/packages/source/s/sys-detection/sys_detection-1.3.4.tar.gz \
	"$WORKDIR/sys_detection-1.3.4.tar.gz"
download https://pypi.io/packages/source/c/compiler-identification/compiler-identification-1.0.3.tar.gz \
	"$WORKDIR/compiler-identification-1.0.3.tar.gz"
download https://pypi.io/packages/source/y/yugabyte_pycommon/yugabyte_pycommon-1.9.15.tar.gz \
	"$WORKDIR/yugabyte_pycommon-1.9.15.tar.gz"
download https://pypi.io/packages/source/a/argparse_utils/argparse_utils-1.3.0.tar.gz \
	"$WORKDIR/argparse_utils-1.3.0.tar.gz"
download https://pypi.io/packages/source/o/overrides/overrides-7.7.0.tar.gz \
	"$WORKDIR/overrides-7.7.0.tar.gz"
download https://pypi.io/packages/source/a/autorepr/autorepr-0.3.0.tar.gz \
	"$WORKDIR/autorepr-0.3.0.tar.gz"

echo "==> Unpack thirdparty so we can harvest C/C++ downloads"

mkdir -p "$STAGING/src" "$STAGING/vendor"
tar -C "$STAGING/src" -xf "$WORKDIR/yugabyte-db-thirdparty-${THIRDPARTY_COMMIT}.tar.gz"
tp="$STAGING/src/yugabyte-db-thirdparty-${THIRDPARTY_COMMIT}"

# Harvest uses the same system-Python path the spec does.
tar -C "$STAGING" -xf "$WORKDIR/sys_detection-1.3.4.tar.gz"
cp -a "$STAGING"/sys_detection-*/src/sys_detection "$STAGING/vendor/"
tar -C "$STAGING" -xf "$WORKDIR/compiler-identification-1.0.3.tar.gz"
cp -a "$STAGING"/compiler-identification-*/src/compiler_identification "$STAGING/vendor/"
tar -C "$STAGING" -xf "$WORKDIR/argparse_utils-1.3.0.tar.gz"
cp -a "$STAGING"/argparse_utils-*/argparse_utils "$STAGING/vendor/"
export YB_USE_SYSTEM_PYTHON=1
export PYTHONPATH="$STAGING/vendor${PYTHONPATH:+:$PYTHONPATH}"

# Keep a persistent download cache so a failed harvest can be resumed.
CACHE=$WORKDIR/.thirdparty-download-cache
mkdir -p "$CACHE" "$tp/download"
cp -a "$CACHE/." "$tp/download/" 2>/dev/null || :

echo "==> Third-party C/C++ source archives (via upstream download-extract-only)"

patch -d "$tp" -p1 < "$WORKDIR/yugabyte-thirdparty-offline.patch"

# HOME is where build_thirdparty.sh writes logs.
export HOME="$STAGING/home"
mkdir -p "$HOME/logs"

# Skip sanitizers, Yugabyte's libc++/libunwind, and the C/C++ bits we
# take from the system.
(
	cd "$tp"
	./build_thirdparty.sh \
		--download-extract-only \
		--skip-sanitizers \
		--skip llvm_libunwind,llvm_libcxx_with_abi,flex,bison,zlib,lz4,eigen,libedit,boost,curl,libxml2,openssl,openssl_fips,snappy,icu4c,libuv,krb5,openldap,libuuid,libkeyutils,libverto,libaio,pcre,hwy,diskann \
		--compiler-family=clang \
		--compiler-prefix=/usr
)

# Remember archives for the next harvest attempt.
mkdir -p "$CACHE"
if [[ -d $tp/download ]]; then
	find "$tp/download" -maxdepth 1 -type f -exec cp -a {} "$CACHE/" \;
fi

if [[ ! -d $tp/download ]] || [[ -z $(ls -A "$tp/download" 2>/dev/null) ]]; then
	echo "ERROR: thirdparty download/ is empty after --download-extract-only" >&2
	exit 1
fi

mkdir -p "$STAGING/offline/download"
# Only the archives themselves; skip extracted src/ and build/ leftovers.
find "$tp/download" -maxdepth 1 -type f -print0 | xargs -0 -I{} cp -a {} "$STAGING/offline/download/"

echo "==> Pack offline-deps tarball"
tar -C "$STAGING/offline" -cJf "$WORKDIR/yugabyte-offline-deps-${VERSION}.tar.xz" download

echo
echo "Wrote:"
ls -lh "$WORKDIR/yugabyte-db-${VERSION}.tar.gz" \
	"$WORKDIR/yugabyte-db-thirdparty-${THIRDPARTY_COMMIT}.tar.gz" \
	"$WORKDIR/yugabyte-bash-common-${BASHCOMMON_COMMIT}.tar.gz" \
	"$WORKDIR/yugabyte-offline-deps-${VERSION}.tar.xz"
echo
echo "Third-party archives: $(find "$STAGING/offline/download" -type f | wc -l)"
echo
echo "Next: abb store the archives (from this directory)."
