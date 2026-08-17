# YugabyteDB for OpenMandriva.
#
# Upstream only ships prebuilt third-party archives and LLVM toolchains for
# AlmaLinux 8/9 and Ubuntu 22.04/24.04. On any other OS the official
# `./yb_build.sh` path dies with:
#   Found no third-party release archives to download for OS type <os>
# because sys_detection reads /etc/os-release (ID=openmandriva) and
# llvm-installer has no URL for that name.
#
# We do not pretend to be AlmaLinux. We:
#   * build yugabyte-db-thirdparty from source with the system Clang
#   * point Yugabyte at that tree (YB_THIRDPARTY_DIR)
#   * set YB_USE_SYSTEM_COMPILER=1 so it never calls llvm-installer
#   * use system Python modules via python%%{pyver}dist(...) — no pip, no venv
#   * vendor C/C++ third-party sources (most are Yugabyte forks)
#   * skip the git clone of yugabyte-bash-common
#
# ABF has no network. Run ./fetch-offline-deps.sh on a networked machine
# and `abb store` the resulting archives before kicking off a build.

Name:		yugabyte
Version:	2026.1.1.0
Release:	1
Summary:	PostgreSQL-compatible distributed SQL database
Group:		Databases
License:	Apache-2.0
URL:		https://www.yugabyte.com/
# Produced by ./fetch-offline-deps.sh (also uploaded with `abb store`).
# Upstream URLs:
#   https://github.com/yugabyte/yugabyte-db/archive/refs/tags/v%%{version}.tar.gz
#   https://github.com/yugabyte/yugabyte-db-thirdparty/archive/<commit>.tar.gz
#   https://github.com/yugabyte/yugabyte-bash-common/archive/<commit>.tar.gz
Source0:	yugabyte-db-%{version}.tar.gz
# Pinned by v2026.1.1.0 build-support/thirdparty_archives.yml
%define thirdparty_commit e42841c02e3e540840ba44ae23cd2adc3c2c245d
Source1:	yugabyte-db-thirdparty-%{thirdparty_commit}.tar.gz
# Pinned by v2026.1.1.0 build-support/yugabyte-bash-common-sha1.txt
%define bashcommon_commit 74793a6e1712ac45dc07cd430da303c95d37f584
Source2:	yugabyte-bash-common-%{bashcommon_commit}.tar.gz
# Third-party C/C++ source archives (same script). No Python wheels.
Source3:	yugabyte-offline-deps-%{version}.tar.xz
Source4:	yugabyte-master.service
Source5:	yugabyte-tserver.service
Source6:	yugabyte.sysusers
Source7:	yugabyte.tmpfiles
Source8:	master.conf
Source9:	tserver.conf
Source10:	yugabyte.logrotate
Source11:	yb-wrapper
Source12:	fetch-offline-deps.sh
Source13:	seed-system-libs.sh
# Yugabyte-only Python helpers that have no OpenMandriva package. Unpacked
# onto PYTHONPATH — they are never pip-installed.
Source14:	https://pypi.io/packages/source/s/sys-detection/sys_detection-1.3.4.tar.gz
Source15:	https://pypi.io/packages/source/c/compiler-identification/compiler-identification-1.0.3.tar.gz
Source16:	https://pypi.io/packages/source/y/yugabyte_pycommon/yugabyte_pycommon-1.9.15.tar.gz
Source17:	https://pypi.io/packages/source/a/argparse_utils/argparse_utils-1.3.0.tar.gz
Source18:	https://pypi.io/packages/source/o/overrides/overrides-7.7.0.tar.gz
Source19:	https://pypi.io/packages/source/a/autorepr/autorepr-0.3.0.tar.gz
# Bazel 5.3.1 — required for the abseil/tcmalloc forks. `abb store` this
# binary; do not hand-edit checksums into .abf.yml.
Source20:	bazel-5.3.1-linux-x86_64

Patch0:		yugabyte-offline-system-compiler.patch
Patch1:		yugabyte-thirdparty-offline.patch
Patch2:		yugabyte-bash-common-offline-venv.patch
Patch3:		yugabyte-system-api.patch
Patch4:		yugabyte-protobuf32.patch

# Upstream only supports x86_64 and aarch64 (CMakeLists fatals otherwise).
ExclusiveArch:	%{x86_64} aarch64

# Yugabyte has its own LTO switch. Distro LTO on top of that is a bad idea.
%global _lto_cflags %{nil}

# Private install prefix. The binaries have a tightly coupled layout
# (postgres/, lib/, share/initial_sys_catalog_snapshot).
%define ybhome %{_libdir}/yugabyte

# The private PostgreSQL 15 tree ships libpq/libecpg/libpgtypes. Do not
# advertise them (or depend on them) as system libs — consumers should
# get the postgresql packages. Yugabyte-only names (libpq_utils,
# libyb_pggate, libyb_pgbackend) are left alone.
%global __provides_exclude %{?__provides_exclude:%{__provides_exclude}|}^((devel\\()?lib(pq|ecpg|ecpg_compat|pgtypes|pqwalreceiver)(\\.so|\\())
%global __requires_exclude %{?__requires_exclude:%{__requires_exclude}|}^lib(pq|ecpg|ecpg_compat|pgtypes|pqwalreceiver)(\\.so|\\()

BuildRequires:	clang
BuildRequires:	lld
BuildRequires:	cmake >= 3.31
BuildRequires:	ninja
BuildRequires:	make
BuildRequires:	python >= 3.11
BuildRequires:	python-devel
# Build scripts import these. No venv, no pip.
BuildRequires:	python%{pyver}dist(packaging)
BuildRequires:	python%{pyver}dist(distro)
BuildRequires:	python%{pyver}dist(psutil)
BuildRequires:	python%{pyver}dist(ruamel.yaml)
BuildRequires:	python%{pyver}dist(semantic-version)
BuildRequires:	python%{pyver}dist(six)
BuildRequires:	perl
BuildRequires:	autoconf
BuildRequires:	automake
BuildRequires:	pkgconfig
BuildRequires:	m4
BuildRequires:	bison
BuildRequires:	flex
BuildRequires:	patchelf
BuildRequires:	pkgconfig(ncurses)
BuildRequires:	pkgconfig(protobuf)
BuildRequires:	protobuf-compiler
# Protobuf 32 headers use Abseil types (lts_20260526).
BuildRequires:	lib64absl-devel
BuildRequires:	rsync
BuildRequires:	which
BuildRequires:	gawk
BuildRequires:	file
BuildRequires:	unzip
BuildRequires:	bzip2
BuildRequires:	xz
BuildRequires:	curl
BuildRequires:	git
BuildRequires:	lib64atomic1
BuildRequires:	lib64atomic-devel
# We skip building Yugabyte's own libc++ (it would download a full LLVM
# matching the compiler version, which has no checksum for Clang 23).
BuildRequires:	lib64c++-devel
BuildRequires:	pkgconfig(zlib)
BuildRequires:	pkgconfig(liblz4)
BuildRequires:	pkgconfig(eigen3)
BuildRequires:	pkgconfig(libedit)
BuildRequires:	pkgconfig(libcurl)
BuildRequires:	pkgconfig(libxml-2.0)
BuildRequires:	pkgconfig(libssl)
BuildRequires:	pkgconfig(snappy)
BuildRequires:	pkgconfig(icu-uc)
BuildRequires:	pkgconfig(icu-i18n)
BuildRequires:	pkgconfig(libuv)
BuildRequires:	pkgconfig(krb5)
BuildRequires:	pkgconfig(ldap)
BuildRequires:	pkgconfig(uuid)
BuildRequires:	pkgconfig(libkeyutils)
BuildRequires:	pkgconfig(libverto)
BuildRequires:	pkgconfig(libpcre2-8)
BuildRequires:	lib64aio-devel
BuildRequires:	pkgconfig(libhwy)
BuildRequires:	pkgconfig(libunwind)
# No .pc; Yugabyte only needs backtrace.h + libbacktrace.so.
BuildRequires:	lib64backtrace-devel
BuildRequires:	pkgconfig(hiredis)
BuildRequires:	cargo
BuildRequires:	rust
BuildRequires:	lib64boost-devel
BuildRequires:	lib64boost_thread-devel
BuildRequires:	lib64boost_atomic-devel
BuildRequires:	lib64boost_program_options-devel
BuildRequires:	lib64boost_regex-devel
BuildRequires:	lib64boost_date_time-devel
BuildRequires:	lib64boost_system-devel
BuildRequires:	systemd-rpm-macros

# Runtime bits the ELF generator will not see (python helpers, configs).
Requires:	python
Requires:	logrotate
Requires(pre):	systemd

%description
YugabyteDB is a PostgreSQL-compatible distributed SQL database. It speaks
the PostgreSQL wire protocol on port 5433 (YSQL) and the Cassandra CQL
protocol on port 9042 (YCQL).

This package builds the database and its third-party dependencies from
source with the system Clang. Upstream's default path of downloading
OS-matched prebuilt archives does not work on OpenMandriva.

A single-node cluster is started with:
  systemctl enable --now yugabyte-master yugabyte-tserver
Then connect with:
  ysqlsh -h 127.0.0.1 -p 5433

%prep
%setup -q -n yugabyte-db-%{version}
%patch -P 0 -p1
%patch -P 3 -p1
%patch -P 4 -p1

cd %{_builddir}
tar -xf %{SOURCE1}
cd yugabyte-db-thirdparty-%{thirdparty_commit}
%patch -P 1 -p1

cd %{_builddir}
tar -xf %{SOURCE2}
cd yugabyte-bash-common-%{bashcommon_commit}
%patch -P 2 -p1

cd %{_builddir}
mkdir -p offline-deps
tar -C offline-deps -xf %{SOURCE3}

# Drop the vendored bash-common into the location yb_build.sh expects,
# so we never git clone.
mkdir -p %{_builddir}/yugabyte-db-%{version}/build
cp -a %{_builddir}/yugabyte-bash-common-%{bashcommon_commit} \
	%{_builddir}/yugabyte-db-%{version}/build/yugabyte-bash-common

# Pre-seed the third-party download cache (C/C++ archives only).
mkdir -p %{_builddir}/yugabyte-db-thirdparty-%{thirdparty_commit}/download
cp -a %{_builddir}/offline-deps/download/. \
	%{_builddir}/yugabyte-db-thirdparty-%{thirdparty_commit}/download/

# Yugabyte-only Python helpers → PYTHONPATH. No pip, no venv.
cd %{_builddir}
mkdir -p yb-python-vendor
tar -xf %{SOURCE14}
cp -a sys_detection-1.3.4/src/sys_detection yb-python-vendor/
tar -xf %{SOURCE15}
cp -a compiler-identification-1.0.3/src/compiler_identification yb-python-vendor/
tar -xf %{SOURCE16}
cp -a yugabyte_pycommon-1.9.15/yugabyte_pycommon yb-python-vendor/
tar -xf %{SOURCE17}
cp -a argparse_utils-1.3.0/argparse_utils yb-python-vendor/
tar -xf %{SOURCE18}
cp -a overrides-7.7.0/overrides yb-python-vendor/
tar -xf %{SOURCE19}
cp -a autorepr-0.3.0/autorepr.py yb-python-vendor/

cd %{_builddir}/yugabyte-db-%{version}

%build
# Keep every "download this from GitHub" switch off, and keep /opt/yb-build
# out of the picture. The patches honor these.
export YB_USE_SYSTEM_COMPILER=1
export YB_SKIP_BASH_COMMON_CLONE=1
export YB_SKIP_YSQL_SNAPSHOT_DOWNLOAD=1
# The snapshot target runs a mini-cluster + initdb; skip for the package
# build (YSQL can initdb on first start).
export YB_SKIP_INITIAL_SYS_CATALOG_SNAPSHOT=1
export YB_DOWNLOAD_THIRDPARTY=0
export YB_COMPILER_TYPE=clang
export YB_CLANG_PREFIX=/usr
export YB_PYTHON_VERSION=3
export YB_USE_NINJA=1
export YB_NO_CCACHE=1
export NO_REBUILD_THIRDPARTY=0
# rust openssl-sys 0.9.107 rejects OpenSSL 4.0 (pg_parquet / pgrx).
export YB_SKIP_PG_PARQUET_BUILD=1
export YB_OPT_BUILD_DIR=%{_builddir}/yb-opt-build
export YB_USE_SYSTEM_PYTHON=1
export PYTHONPATH=%{_builddir}/yb-python-vendor${PYTHONPATH:+:$PYTHONPATH}
export YB_VERSION_INFO_GIT_SHA1=%{thirdparty_commit}
# thirdparty's build_thirdparty.sh logs under $HOME/logs
export HOME=%{_builddir}/home
mkdir -p "$HOME/logs" "$YB_OPT_BUILD_DIR"
# Abseil/tcmalloc need Bazel 5.3.1 on PATH.
mkdir -p %{_builddir}/yb-tools
ln -sfn %{_sourcedir}/bazel-5.3.1-linux-x86_64 %{_builddir}/yb-tools/bazel
chmod +x %{_builddir}/yb-tools/bazel
export PATH=%{_builddir}/yb-tools:$PATH

# python3 vs python: OpenMandriva's `python` is the current interpreter.
export PYTHON=python

jobs=${RPM_BUILD_NCPUS:-$(nproc)}
# The official scripts OOM on small builders if they go wide. Cap the
# C++ compile fan-out; link steps are still huge.
if [ -z "$jobs" ] || [ "$jobs" -gt 16 ]; then
	jobs=16
fi

echo "==> Building yugabyte-db-thirdparty with system Clang"
cd %{_builddir}/yugabyte-db-thirdparty-%{thirdparty_commit}
# Some third-party CMake (cassandra-cpp-driver) resolves OpenSSL/libuv
# inside this prefix while it is still building.
mkdir -p installed/common installed/uninstrumented
sh %{SOURCE13} installed/common %{_libdir}
sh %{SOURCE13} installed/uninstrumented %{_libdir}
# Clang never registers bundled patchelf (GCC-only), so it cannot be --skip'd.
./build_thirdparty.sh \
	--compiler-family=clang \
	--compiler-prefix=/usr \
	--skip-sanitizers \
	--skip llvm_libunwind,llvm_libcxx_with_abi,flex,bison,zlib,lz4,eigen,libedit,boost,curl,libxml2,openssl,openssl_fips,snappy,icu4c,libuv,krb5,openldap,libuuid,libkeyutils,libverto,libaio,pcre,hwy,libbacktrace,hiredis,redis_cli,ncurses,protobuf,abseil,tcmalloc,diskann \
	--skip-library-checking \
	--make-parallelism="$jobs"

# The tree we just built is what yb_build.sh will consume.
export YB_THIRDPARTY_DIR=%{_builddir}/yugabyte-db-thirdparty-%{thirdparty_commit}
export NO_REBUILD_THIRDPARTY=1

# Drop system libs into the prefix CMake searches (including OpenSSL,
# which is required to live under YB_THIRDPARTY_DIR).
sh %{SOURCE13} "$YB_THIRDPARTY_DIR/installed/common" %{_libdir}
sh %{SOURCE13} "$YB_THIRDPARTY_DIR/installed/uninstrumented" %{_libdir}
# otel cmake + lib64->lib can leave a circular libopentelemetry_trace.so.
otel_so=$YB_THIRDPARTY_DIR/installed/uninstrumented/lib/libopentelemetry_trace.so
if [ -L "$otel_so" ] && [ ! -e "$otel_so" ]; then
	real=$(find "$YB_THIRDPARTY_DIR/build" -name libopentelemetry_trace.so -type f | head -1)
	if [ -n "$real" ]; then
		rm -f "$otel_so"
		cp -a "$real" "$otel_so"
	fi
fi
export OPENSSL_ROOT_DIR=$YB_THIRDPARTY_DIR/installed/common
export BOOST_ROOT=$YB_THIRDPARTY_DIR/installed/uninstrumented

echo "==> Building YugabyteDB"
cd %{_builddir}/yugabyte-db-%{version}
# --no-download-thirdparty is the flag that turns off the OS-matched
# GitHub archive lookup. Combined with YB_THIRDPARTY_DIR it is the
# whole point of this package.
# Google tcmalloc's public headers use the bundled Abseil LTS. That
# cannot share a TU with protobuf 32 (system Abseil). gperftools
# tcmalloc does not expose Abseil types.
./yb_build.sh release \
	--no-download-thirdparty \
	--no-google-tcmalloc \
	--skip-java \
	--no-yugabyted-ui \
	--no-tests \
	packaged \
	-j"$jobs"

%install
ybhome=%{buildroot}%{ybhome}
build_latest=%{_builddir}/yugabyte-db-%{version}/build/latest
tp=%{_builddir}/yugabyte-db-thirdparty-%{thirdparty_commit}

install -d "$ybhome"/{bin,lib,share,www,postgres}

# Server / tool binaries from the CMake build.
if [ -d "$build_latest/bin" ]; then
	cp -a "$build_latest/bin/." "$ybhome/bin/"
fi

# In-tree helper scripts that are not produced by CMake.
for s in yugabyted yb-ctl; do
	if [ -f %{_builddir}/yugabyte-db-%{version}/bin/$s ]; then
		install -m 755 %{_builddir}/yugabyte-db-%{version}/bin/$s "$ybhome/bin/$s"
	fi
	if [ -f %{_builddir}/yugabyte-db-%{version}/scripts/installation/bin/$s ]; then
		install -m 755 %{_builddir}/yugabyte-db-%{version}/scripts/installation/bin/$s \
			"$ybhome/bin/$s"
	fi
done

# PostgreSQL tree (ysqlsh, postgres, extensions).
if [ -d "$build_latest/postgres" ]; then
	cp -a "$build_latest/postgres/." "$ybhome/postgres/"
fi

# Shared data (initial sys catalog snapshot, sample SQL, migrations).
if [ -d "$build_latest/share" ]; then
	cp -a "$build_latest/share/." "$ybhome/share/"
fi
# Runtime metadata next to YB_HOME (gflag allowlist, flag XML, version).
for meta in auto_flags.json gflag_allowlist.txt master_flags.xml \
	tserver_flags.xml version_metadata.json
do
	if [ -f "$build_latest/$meta" ]; then
		install -m 644 "$build_latest/$meta" "$ybhome/$meta"
	fi
done
if [ -d %{_builddir}/yugabyte-db-%{version}/www ]; then
	cp -a %{_builddir}/yugabyte-db-%{version}/www/. "$ybhome/www/"
fi
if [ -d %{_builddir}/yugabyte-db-%{version}/sample ]; then
	install -d "$ybhome/share/sample"
	cp -a %{_builddir}/yugabyte-db-%{version}/sample/. "$ybhome/share/sample/"
fi

# Third-party shared libraries the binaries are linked against.
# Common + uninstrumented; we never build the ASAN/TSAN variants.
for libdir in \
	"$tp/installed/common/lib" \
	"$tp/installed/uninstrumented/lib" \
	"$build_latest/lib"
do
	if [ -d "$libdir" ]; then
		# Copy bundled libs only. Seeded system libs are /usr symlinks.
		find "$libdir" -maxdepth 1 \( -name '*.so' -o -name '*.so.*' \) -print0 |
		while IFS= read -r -d '' f; do
			real=$(readlink -f "$f" 2>/dev/null || true)
			case "$real" in
			/usr/*|/lib/*|/lib64/*) continue ;;
			esac
			cp -a "$f" "$ybhome/lib/"
		done
	fi
done

# Bundled CLI helpers that live in the third-party prefix.
# redis-cli comes from the system Redis package, not this tree.
for extra in \
	"$tp/installed/common/bin/openssl" \
	"$tp/installed/common/cqlsh/bin/cqlsh" \
	"$tp/installed/common/cqlsh/bin/ycqlsh" \
	"$tp/installed/common/cqlsh/bin/ycqlsh.py"
do
	if [ -e "$extra" ]; then
		real=$(readlink -f "$extra" 2>/dev/null || true)
		case "$real" in
		/usr/*|/bin/*) continue ;;
		esac
		install -m 755 "$extra" "$ybhome/bin/$(basename "$extra")"
	fi
done
if [ -d "$tp/installed/common/cqlsh/lib" ]; then
	install -d "$ybhome/lib/cqlsh"
	cp -a "$tp/installed/common/cqlsh/lib/." "$ybhome/lib/cqlsh/"
fi
if [ -d "$tp/installed/common/cqlsh/pylib" ]; then
	install -d "$ybhome/pylib"
	cp -a "$tp/installed/common/cqlsh/pylib/." "$ybhome/pylib/"
fi

# Point every ELF we just installed at the private lib dir. Upstream's
# rpath is an absolute path into the build root.
rpath='$ORIGIN/../lib:$ORIGIN/../postgres/lib:%{ybhome}/lib:%{ybhome}/postgres/lib'
find "$ybhome" -type f -print0 | while IFS= read -r -d '' f; do
	if file -b "$f" | grep -q 'ELF'; then
		patchelf --set-rpath "$rpath" "$f" 2>/dev/null || :
	fi
done

# Public entry points. The wrapper and units are rewritten to %{ybhome}.
install -d %{buildroot}%{_bindir}
sed 's|^bindir=.*|bindir=%{ybhome}/bin|;s|^export YB_HOME=.*|export YB_HOME=%{ybhome}|' \
	%{SOURCE11} > %{buildroot}%{_bindir}/yb-wrapper
chmod 755 %{buildroot}%{_bindir}/yb-wrapper
for cmd in yb-master yb-tserver yb-admin yb-ts-cli yb-ysck ysqlsh ycqlsh yugabyted yb-ctl; do
	ln -sf yb-wrapper %{buildroot}%{_bindir}/$cmd
done
# ysqlsh lives under postgres/bin; the wrapper looks in bin/. Add a hop.
if [ -x "$ybhome/postgres/bin/ysqlsh" ] && [ ! -e "$ybhome/bin/ysqlsh" ]; then
	ln -sf ../postgres/bin/ysqlsh "$ybhome/bin/ysqlsh"
fi

# Config / units / sysusers / tmpfiles / logrotate.
install -Dpm 644 %{SOURCE8} %{buildroot}%{_sysconfdir}/yugabyte/master.conf
install -Dpm 644 %{SOURCE9} %{buildroot}%{_sysconfdir}/yugabyte/tserver.conf
install -d %{buildroot}%{_unitdir}
sed 's|/usr/lib/yugabyte|%{ybhome}|g' %{SOURCE4} \
	> %{buildroot}%{_unitdir}/yugabyte-master.service
sed 's|/usr/lib/yugabyte|%{ybhome}|g' %{SOURCE5} \
	> %{buildroot}%{_unitdir}/yugabyte-tserver.service
chmod 644 %{buildroot}%{_unitdir}/yugabyte-master.service \
	%{buildroot}%{_unitdir}/yugabyte-tserver.service
install -Dpm 644 %{SOURCE6} %{buildroot}%{_sysusersdir}/yugabyte.conf
install -Dpm 644 %{SOURCE7} %{buildroot}%{_tmpfilesdir}/yugabyte.conf
install -Dpm 644 %{SOURCE10} %{buildroot}%{_sysconfdir}/logrotate.d/yugabyte

install -d %{buildroot}%{_localstatedir}/lib/yugabyte/{master,tserver}
install -d %{buildroot}%{_localstatedir}/log/yugabyte

# Drop compile-time junk that leaked into the install tree.
find %{buildroot} -name '*.la' -delete
find %{buildroot} -name '*.a' -delete

%files
%license LICENSE.md
%doc README.md NOTICE.txt
%config(noreplace) %{_sysconfdir}/yugabyte/master.conf
%config(noreplace) %{_sysconfdir}/yugabyte/tserver.conf
%config(noreplace) %{_sysconfdir}/logrotate.d/yugabyte
%{_unitdir}/yugabyte-master.service
%{_unitdir}/yugabyte-tserver.service
%{_sysusersdir}/yugabyte.conf
%{_tmpfilesdir}/yugabyte.conf
%{_bindir}/yb-wrapper
%{_bindir}/yb-master
%{_bindir}/yb-tserver
%{_bindir}/yb-admin
%{_bindir}/yb-ts-cli
%{_bindir}/yb-ysck
%{_bindir}/ysqlsh
%{_bindir}/ycqlsh
%{_bindir}/yugabyted
%{_bindir}/yb-ctl
%{ybhome}/
%dir %attr(0755,yugabyte,yugabyte) %{_localstatedir}/lib/yugabyte
%dir %attr(0750,yugabyte,yugabyte) %{_localstatedir}/lib/yugabyte/master
%dir %attr(0750,yugabyte,yugabyte) %{_localstatedir}/lib/yugabyte/tserver
%dir %attr(0755,yugabyte,yugabyte) %{_localstatedir}/log/yugabyte
