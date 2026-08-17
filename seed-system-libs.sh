#!/bin/sh
# Point Yugabyte's third-party install prefix at system libraries so
# CMake's "must live under YB_THIRDPARTY_DIR" checks still pass.
# Used after --skip of the corresponding third-party deps.
set -eu

dest=${1:?usage: seed-system-libs.sh DESTDIR}
libdir=${2:-/usr/lib64}

mkdir -p "$dest/include" "$dest/lib" "$dest/bin" "$dest/lib/pkgconfig"
# postgres configure requires these dirs to exist even if empty.
for pcdir in /usr/lib64/pkgconfig /usr/share/pkgconfig; do
	[ -d "$pcdir" ] || continue
	for pc in zlib liblz4 libssl libcrypto libcurl libxml-2.0 libedit \
		snappy icu-uc icu-i18n libuv krb5 libkeyutils libverto \
		libpcre2-8 libhwy ldap lber uuid libunwind hiredis \
		ncurses ncursesw tinfo form menu panel formw menuw panelw tinfow \
		protobuf protobuf-lite libtcmalloc libprofiler; do
		if [ -e "$pcdir/$pc.pc" ]; then
			ln -sfn "$pcdir/$pc.pc" "$dest/lib/pkgconfig/$pc.pc"
		fi
	done
done
# YB_SETUP_CLANG requires libc++ under $dest/libcxx/{include/c++/v1,lib}.
if [ -d /usr/include/c++/v1 ]; then
	mkdir -p "$dest/libcxx/include/c++" "$dest/libcxx/lib"
	ln -sfn /usr/include/c++/v1 "$dest/libcxx/include/c++/v1"
	for n in libc++.so libc++abi.so libc++.so.1 libc++abi.so.1; do
		if [ -e "$libdir/$n" ]; then
			ln -sfn "$libdir/$n" "$dest/libcxx/lib/$n"
		fi
	done
	real=$(readlink -f "$libdir/libc++.so" 2>/dev/null || true)
	if [ -n "$real" ] && [ -e "$real" ]; then
		ln -sfn "$real" "$dest/libcxx/lib/$(basename "$real")"
	fi
	real=$(readlink -f "$libdir/libc++abi.so" 2>/dev/null || true)
	if [ -n "$real" ] && [ -e "$real" ]; then
		ln -sfn "$real" "$dest/libcxx/lib/$(basename "$real")"
	fi
fi

link_so() {
	# Prefer the unversioned .so (the -devel symlink); also expose the
	# SONAME file if it sits next to it, so ldd/patchelf stay happy.
	local name=$1
	if [ -e "$libdir/$name" ]; then
		ln -sfn "$libdir/$name" "$dest/lib/$name"
	fi
	local real
	real=$(readlink -f "$libdir/$name" 2>/dev/null || true)
	if [ -n "$real" ] && [ -e "$real" ]; then
		ln -sfn "$real" "$dest/lib/$(basename "$real")"
	fi
}

# zlib 1.3.1
ln -sfn /usr/include/zlib.h "$dest/include/zlib.h"
[ -e /usr/include/zconf.h ] && ln -sfn /usr/include/zconf.h "$dest/include/zconf.h"
ln -sfn "$libdir/libz.so" "$dest/lib/libz.so"
[ -e "$libdir/libz.a" ] && ln -sfn "$libdir/libz.a" "$dest/lib/libz.a"

# lz4 1.10.0
ln -sfn /usr/include/lz4.h "$dest/include/lz4.h"
[ -e /usr/include/lz4frame.h ] && ln -sfn /usr/include/lz4frame.h "$dest/include/lz4frame.h"
[ -e /usr/include/lz4hc.h ] && ln -sfn /usr/include/lz4hc.h "$dest/include/lz4hc.h"
ln -sfn "$libdir/liblz4.so" "$dest/lib/liblz4.so"

# Eigen 5.0.1 (header-only)
if [ -d /usr/include/eigen3/Eigen ]; then
	ln -sfn /usr/include/eigen3/Eigen "$dest/include/Eigen"
	[ -d /usr/include/eigen3/unsupported ] && \
		ln -sfn /usr/include/eigen3/unsupported "$dest/include/unsupported"
	[ -d /usr/include/eigen3/signature_of_eigen3_matrix_library ] && \
		ln -sfn /usr/include/eigen3/signature_of_eigen3_matrix_library \
			"$dest/include/signature_of_eigen3_matrix_library"
fi

# flex / bison live on PATH; also expose them where some scripts look.
for tool in flex bison; do
	if cmd=$(command -v "$tool"); then
		ln -sfn "$cmd" "$dest/bin/$tool"
	fi
done

# libedit 3.1 — the -yb-1 tarball is a 2019 snapshot plus a compile-flag
# tweak, not a functional fork. psql includes <editline/readline.h> and
# optionally <editline/history.h>.
mkdir -p "$dest/include/editline"
[ -e /usr/include/editline/readline.h ] && \
	ln -sfn /usr/include/editline/readline.h "$dest/include/editline/readline.h"
if [ ! -e /usr/include/editline/history.h ]; then
	printf '%s\n' '#include <editline/readline.h>' > "$dest/include/editline/history.h"
else
	ln -sfn /usr/include/editline/history.h "$dest/include/editline/history.h"
fi
[ -e /usr/include/histedit.h ] && ln -sfn /usr/include/histedit.h "$dest/include/histedit.h"
link_so libedit.so

# libxml2 — vanilla 2.13.5 upstream, no Yugabyte patches. System 2.15.x
# has the CVE fixes. Headers live under libxml2/libxml/. FindLibXml2
# looks for include/libxml2 (the directory name), then uses that as -I.
if [ -d /usr/include/libxml2 ]; then
	ln -sfn /usr/include/libxml2 "$dest/include/libxml2"
fi
if [ -d /usr/include/libxml2/libxml ]; then
	ln -sfn /usr/include/libxml2/libxml "$dest/include/libxml"
fi
link_so libxml2.so

# curl — vanilla 8.19.0. System 8.21 is newer. Must share one OpenSSL
# with the rest of the process, so we seed system OpenSSL below too.
if [ -d /usr/include/curl ]; then
	ln -sfn /usr/include/curl "$dest/include/curl"
fi
link_so libcurl.so

# OpenSSL — CMake FATAL_ERRORs unless libssl/libcrypto resolve inside
# YB_THIRDPARTY_DIR. Pairing system curl with a vendored OpenSSL would
# load two libssls into yb-master. Skip their 3.5.7 + FIPS copies.
if [ -d /usr/include/openssl ]; then
	ln -sfn /usr/include/openssl "$dest/include/openssl"
fi
link_so libssl.so
link_so libcrypto.so
if cmd=$(command -v openssl); then
	ln -sfn "$cmd" "$dest/bin/openssl"
fi

# Boost 1.81 vs system 1.92. The only upstream "patch" teaches b2 that
# arm64 exists, which 1.92 already knows. Boost.System is header-only
# now; CMake still looks for libboost_system.{a,so}, so plant stubs.
if [ -d /usr/include/boost ]; then
	ln -sfn /usr/include/boost "$dest/include/boost"
fi
for lib in thread atomic program_options regex date_time; do
	link_so "libboost_${lib}.so"
	[ -e "$libdir/libboost_${lib}.a" ] && \
		ln -sfn "$libdir/libboost_${lib}.a" "$dest/lib/libboost_${lib}.a"
done
if [ ! -e "$dest/lib/libboost_system.so" ]; then
	# Tiny empty PIC objects so FindBoost COMPONENTS system succeeds.
	cc=${CC:-clang}
	stub=$dest/lib/.boost_system_stub.c
	printf '%s\n' 'void yb_boost_system_stub(void) {}' > "$stub"
	"$cc" -fPIC -c "$stub" -o "$dest/lib/.boost_system_stub.o"
	"$cc" -shared -o "$dest/lib/libboost_system.so" "$dest/lib/.boost_system_stub.o"
	if command -v ar >/dev/null; then
		ar rcs "$dest/lib/libboost_system.a" "$dest/lib/.boost_system_stub.o"
	fi
	rm -f "$stub" "$dest/lib/.boost_system_stub.o"
fi

# snappy — yugabyte/snappy 1.1.9-yb-3 only turns DISALLOW_COPY_AND_ASSIGN
# into `= delete`. Distro snappy is 1.2.2 (newer than both).
[ -e /usr/include/snappy.h ] && ln -sfn /usr/include/snappy.h "$dest/include/snappy.h"
[ -e /usr/include/snappy-stubs-public.h ] && \
	ln -sfn /usr/include/snappy-stubs-public.h "$dest/include/snappy-stubs-public.h"
[ -e /usr/include/snappy-c.h ] && ln -sfn /usr/include/snappy-c.h "$dest/include/snappy-c.h"
[ -e /usr/include/snappy-sinksource.h ] && \
	ln -sfn /usr/include/snappy-sinksource.h "$dest/include/snappy-sinksource.h"
link_so libsnappy.so

# ICU 70.1 vs system 78. The only upstream patch is a gcc/clang STRICT_ANSI
# workaround in ufile.cpp. C API is stable; use matching system headers+libs.
if [ -d /usr/include/unicode ]; then
	ln -sfn /usr/include/unicode "$dest/include/unicode"
fi
link_so libicuuc.so
link_so libicui18n.so
link_so libicudata.so

# libuv 1.23.0 vs system 1.52 — vanilla pin, no Yugabyte patches. The
# bundled cassandra-cpp-driver looks for LIBUV_ROOT_DIR in this prefix.
[ -e /usr/include/uv.h ] && ln -sfn /usr/include/uv.h "$dest/include/uv.h"
if [ -d /usr/include/uv ]; then
	ln -sfn /usr/include/uv "$dest/include/uv"
fi
link_so libuv.so

# keyutils 1.6.1-yb-1 vs system 1.6.3. Their copy is the stock 1.6.1
# Makefile with -Werror; clang 23 flags unused-but-set-global.
[ -e /usr/include/keyutils.h ] && ln -sfn /usr/include/keyutils.h "$dest/include/keyutils.h"
link_so libkeyutils.so
[ -e "$libdir/libkeyutils.a" ] && ln -sfn "$libdir/libkeyutils.a" "$dest/lib/libkeyutils.a"

# libverto — vanilla 0.3.2, only pulled in as a krb5 helper.
[ -e /usr/include/verto.h ] && ln -sfn /usr/include/verto.h "$dest/include/verto.h"
if [ -d /usr/include/verto ]; then
	ln -sfn /usr/include/verto "$dest/include/verto"
fi
link_so libverto.so
[ -e "$libdir/libverto.a" ] && ln -sfn "$libdir/libverto.a" "$dest/lib/libverto.a"

# libaio 0.3.113 — same version as the system package.
[ -e /usr/include/libaio.h ] && ln -sfn /usr/include/libaio.h "$dest/include/libaio.h"
link_so libaio.so
[ -e "$libdir/libaio.a" ] && ln -sfn "$libdir/libaio.a" "$dest/lib/libaio.a"

# libunwind — we skip llvm_libunwind (it downloads a full LLVM). System
# is the matching LLVM 23 unwind.
[ -e /usr/include/libunwind.h ] && ln -sfn /usr/include/libunwind.h "$dest/include/libunwind.h"
if [ -d /usr/include/libunwind ]; then
	ln -sfn /usr/include/libunwind "$dest/include/libunwind"
fi
link_so libunwind.so
[ -e "$libdir/libunwind.a" ] && ln -sfn "$libdir/libunwind.a" "$dest/lib/libunwind.a"

# libbacktrace — Yugabyte vendors an older Ian Lance Taylor snapshot
# (yugabyte/libbacktrace @ 8602fda, copyright through 2021). The public
# API they call (backtrace_create_state / backtrace_full) is unchanged.
ln -sfn /usr/include/backtrace.h "$dest/include/backtrace.h"
[ -e /usr/include/backtrace-supported.h ] && \
	ln -sfn /usr/include/backtrace-supported.h "$dest/include/backtrace-supported.h"
link_so libbacktrace.so
[ -e "$libdir/libbacktrace.a" ] && \
	ln -sfn "$libdir/libbacktrace.a" "$dest/lib/libbacktrace.a"

# hiredis 0.13.3 vs system 1.4.0. Their Makefile interpolates a broken
# LIBDIR (ends up as .../usr/lib/asmc:...) so the 2015 snapshot does
# not even install. YB only uses redisConnect / AppendCommandArgv /
# GetReply / redisFree.
if [ -d /usr/include/hiredis ]; then
	if [ -d "$dest/include/hiredis" ] && [ ! -L "$dest/include/hiredis" ]; then
		rm -rf "$dest/include/hiredis"
	fi
	ln -sfn /usr/include/hiredis "$dest/include/hiredis"
fi
link_so libhiredis.so
[ -e "$libdir/libhiredis.a" ] && \
	ln -sfn "$libdir/libhiredis.a" "$dest/lib/libhiredis.a"

# ncurses 6.4 vs system 6.5. Postgres/ysqlsh only need -lncurses.
# Their copy is non-widec; distro libncurses.so.6 still satisfies it.
if [ -d "$dest/include/ncurses" ] && [ ! -L "$dest/include/ncurses" ]; then
	rm -rf "$dest/include/ncurses"
fi
if [ -d /usr/include/ncursesw ]; then
	ln -sfn /usr/include/ncursesw "$dest/include/ncurses"
elif [ -d /usr/include/ncurses ]; then
	ln -sfn /usr/include/ncurses "$dest/include/ncurses"
fi
for hdr in ncurses.h curses.h term.h form.h menu.h panel.h termcap.h \
	unctrl.h ncurses_dll.h; do
	[ -e "/usr/include/$hdr" ] && ln -sfn "/usr/include/$hdr" "$dest/include/$hdr"
done
for n in libncurses libncursesw libtinfo libform libmenu libpanel \
	libformw libmenuw libpanelw libtinfow libncurses++; do
	# Drop leftover bundled 6.4 objects / dangling SONAME links.
	rm -f "$dest/lib/${n}.a" "$dest/lib/${n}_g.a"
	if [ -d "$dest/lib" ]; then
		find "$dest/lib" -maxdepth 1 -name "${n}.so.*" -print | while read -r f; do
			if [ -L "$f" ]; then
				tgt=$(readlink -f "$f" 2>/dev/null || true)
				case "$tgt" in
				/usr/*|/lib/*|/lib64/*) continue ;;
				esac
			fi
			rm -f "$f"
		done
	fi
	link_so "${n}.so"
done

# patchelf 0.17.2 vs system 0.19.1. Their rpath helper already picks
# the newest patchelf on PATH; seed the prefix too.
if cmd=$(command -v patchelf); then
	ln -sfn "$cmd" "$dest/bin/patchelf"
fi

# protobuf 21.12-yb-1 vs system 32.1. Generate .pb.cc with system protoc.
# Protobuf 32 public headers use Abseil types (absl::string_view, Span, …)
# namespaced lts_20260526. YB's Bazel-combined libabsl is lts_20240722, so
# the two cannot be mixed in one TU. Overlay system Abseil and hide the
# combined library; CMake still looks for a single libabsl.so, so emit a
# GNU ld script that pulls in the split system libs.
if [ -d /usr/include/google/protobuf ]; then
	mkdir -p "$dest/include/google"
	if [ -d "$dest/include/google/protobuf" ] && \
	   [ ! -L "$dest/include/google/protobuf" ]; then
		rm -rf "$dest/include/google/protobuf"
	fi
	ln -sfn /usr/include/google/protobuf "$dest/include/google/protobuf"
fi
for n in libprotobuf libprotobuf-lite libprotoc; do
	rm -f "$dest/lib/${n}.a"
	if [ -d "$dest/lib" ]; then
		find "$dest/lib" -maxdepth 1 -name "${n}.so.*" -print | while read -r f; do
			if [ -L "$f" ]; then
				tgt=$(readlink -f "$f" 2>/dev/null || true)
				case "$tgt" in
				/usr/*|/lib/*|/lib64/*) continue ;;
				esac
			fi
			rm -f "$f"
		done
	fi
	link_so "${n}.so"
done
if cmd=$(command -v protoc); then
	ln -sfn "$cmd" "$dest/bin/protoc"
fi
if [ -d /usr/lib64/cmake/protobuf ]; then
	mkdir -p "$dest/lib/cmake"
	if [ -d "$dest/lib/cmake/protobuf" ] && \
	   [ ! -L "$dest/lib/cmake/protobuf" ]; then
		rm -rf "$dest/lib/cmake/protobuf"
	fi
	ln -sfn /usr/lib64/cmake/protobuf "$dest/lib/cmake/protobuf"
fi
if [ -d /usr/include/absl ]; then
	if [ -d "$dest/include/absl" ] && [ ! -L "$dest/include/absl" ]; then
		rm -rf "$dest/include/absl"
	fi
	ln -sfn /usr/include/absl "$dest/include/absl"
fi
rm -f "$dest/lib/libabsl.a" "$dest/lib/libabsl.so"
if ls "$libdir"/libabsl_*.so >/dev/null 2>&1; then
	{
		echo "INPUT ("
		for s in "$libdir"/libabsl_*.so; do
			[ -e "$s" ] || continue
			echo "  $s"
		done
		[ -e "$libdir/libutf8_validity.so" ] && echo "  $libdir/libutf8_validity.so"
		[ -e "$libdir/libutf8_range.so" ] && echo "  $libdir/libutf8_range.so"
		echo ")"
	} > "$dest/lib/libabsl.so"
fi
# Google tcmalloc is a Bazel fork of Abseil lts_20240722. Its public
# headers and libgoogletcmalloc.a cannot share a process with protobuf 32
# (system Abseil lts_20260526). Drop the leftovers so FindGPerf binds
# gperftools libtcmalloc instead.
rm -f "$dest/lib/libgoogletcmalloc.so" "$dest/lib/libgoogletcmalloc.a"
if [ -f "$dest/include/tcmalloc/malloc_extension.h" ]; then
	rm -rf "$dest/include/tcmalloc"
fi
# Bundled gperftools 2.8.1 has no aarch64 stack walker. Use the system
# 2.15 libs. FindGPerf still looks for libtcmalloc.a; GNU ld INPUT() is
# enough because we link shared.
link_so libtcmalloc.so
link_so libprofiler.so
if [ ! -e "$dest/lib/libtcmalloc.a" ] && [ -e "$libdir/libtcmalloc.so" ]; then
	printf 'INPUT ( %s )\n' "$libdir/libtcmalloc.so" > "$dest/lib/libtcmalloc.a"
fi
if [ ! -e "$dest/lib/libprofiler.a" ] && [ -e "$libdir/libprofiler.so" ]; then
	printf 'INPUT ( %s )\n' "$libdir/libprofiler.so" > "$dest/lib/libprofiler.a"
fi
if [ -d /usr/include/gperftools ]; then
	ln -sfn /usr/include/gperftools "$dest/include/gperftools"
fi
if [ -d /usr/include/google ]; then
	ln -sfn /usr/include/google "$dest/include/google"
fi

# Highway 1.3.0 vs system 1.4.0. Their 1.3.0 fails on clang 23
# (AVX512 builtins need explicit target features).
if [ -d /usr/include/hwy ]; then
	ln -sfn /usr/include/hwy "$dest/include/hwy"
fi
link_so libhwy.so
link_so libhwy_contrib.so
[ -e "$libdir/libhwy.a" ] && ln -sfn "$libdir/libhwy.a" "$dest/lib/libhwy.a"
[ -e "$libdir/libhwy_contrib.a" ] && \
	ln -sfn "$libdir/libhwy_contrib.a" "$dest/lib/libhwy_contrib.a"

# PCRE2 10.40 vs system 10.47. FindPcre looks for include/libpcre2-8/.
if [ -e /usr/include/pcre2.h ]; then
	mkdir -p "$dest/include/libpcre2-8"
	ln -sfn /usr/include/pcre2.h "$dest/include/pcre2.h"
	ln -sfn /usr/include/pcre2.h "$dest/include/libpcre2-8/pcre2.h"
	[ -e /usr/include/pcre2posix.h ] && \
		ln -sfn /usr/include/pcre2posix.h "$dest/include/pcre2posix.h"
fi
link_so libpcre2-8.so
[ -e "$libdir/libpcre2-8.a" ] && ln -sfn "$libdir/libpcre2-8.a" "$dest/lib/libpcre2-8.a"

# libuuid 1.0.3 vs util-linux 2.42. Their copy is the old standalone
# e2fsprogs extract; configure/make dies under clang 23 + libtool -j.
if [ -d /usr/include/uuid ]; then
	ln -sfn /usr/include/uuid "$dest/include/uuid"
fi
link_so libuuid.so
[ -e "$libdir/libuuid.a" ] && ln -sfn "$libdir/libuuid.a" "$dest/lib/libuuid.a"

# OpenLDAP 2.4.54 vs system 2.7. Their copy is client-only (--disable-slapd)
# plus a docs-off patch; configure dies on clang 23 ("broken POSIX regex").
# YCQL LDAP auth just needs <ldap.h> and libldap/liblber.
for hdr in ldap.h lber.h lber_types.h ldap_cdefs.h ldap_features.h \
	ldap_schema.h ldap_utf8.h ldif.h openldap.h; do
	[ -e "/usr/include/$hdr" ] && ln -sfn "/usr/include/$hdr" "$dest/include/$hdr"
done
link_so libldap.so
link_so liblber.so

# krb5 1.20.1 vs system 1.21.3. The only patch is $(LDFLAGS) on a test
# binary. Postgres is built --with-gssapi against this prefix.
[ -e /usr/include/krb5.h ] && ln -sfn /usr/include/krb5.h "$dest/include/krb5.h"
if [ -d /usr/include/krb5 ]; then
	ln -sfn /usr/include/krb5 "$dest/include/krb5"
fi
if [ -d /usr/include/gssapi ]; then
	ln -sfn /usr/include/gssapi "$dest/include/gssapi"
fi
[ -e /usr/include/gssapi.h ] && ln -sfn /usr/include/gssapi.h "$dest/include/gssapi.h"
link_so libkrb5.so
link_so libgssapi_krb5.so
link_so libk5crypto.so
link_so libcom_err.so
link_so libkrb5support.so
# krb5-config so postgres configure can find the system install.
if cmd=$(command -v krb5-config); then
	ln -sfn "$cmd" "$dest/bin/krb5-config"
fi
