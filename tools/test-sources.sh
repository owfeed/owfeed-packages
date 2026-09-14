#!/bin/sh
# Self-test for tools/sources.sh, the gate that decides whether a copyleft package
# may be published at all.
#
# It is tested rather than reasoned about because it fails in both directions and
# both are expensive. Refusing a package whose source WAS fetched blocks a release
# for a reason nobody can act on -- that is what a manifest release did, because one
# entry publishes several packages and the source archive was recorded under the
# entry's name only. Accepting a package whose source is absent publishes a GPL
# binary this feed has no right to distribute, which is the failure the script
# exists to prevent and the one no CI run would ever notice.
#
# Every case builds its own dist/ and out/ in a temporary directory: no network, no
# owfeed, and no entry of this repository's packages/, so this runs before anything
# is fetched. The manifest case goes through the real tools/fetch.sh with `curl` and
# `owfeed` stubbed on PATH, because the layout it stages is the other half of the
# contract this script reads -- a hand-written copy of that layout is how this test
# once went on describing a staging scheme fetch.sh no longer used.
#
# Usage: tools/test-sources.sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Overridable so the same cases can be run against another copy of the script -- the
# one from before a change, to see a case go red for the reason it claims to.
SOURCES="${SOURCES:-$ROOT/tools/sources.sh}"
FETCH="${FETCH:-$ROOT/tools/fetch.sh}"

command -v jq >/dev/null 2>&1 || { echo "tools/test-sources.sh needs jq" >&2; exit 1; }

fails=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1: $2" >&2; fails=$((fails + 1)); }

# scenario <name> -- an empty tree shaped like one owfeed leaves behind
scenario() {
	d="$work/$1"
	mkdir -p "$d/dist/sources" "$d/out/releases/25.12/noarch"
	echo "$d"
}

# index <dir> "<package> <version> <licence>"... -- the index.json owfeed writes
# beside the binaries, which is where the licence is read from.
index() {
	d="$1"
	shift
	{
		printf '{"packages":['
		sep=""
		for p in "$@"; do
			# shellcheck disable=SC2086
			set -- $p
			printf '%s{"name":"%s","version":"%s","license":"%s"}' \
				"$sep" "$1" "$2" "$3"
			sep=","
		done
		printf ']}\n'
	} > "$d/out/releases/25.12/noarch/index.json"
}

# run <dir> -- the script under test, from inside that tree
run() {
	( cd "$1" && DIST=dist sh "$SOURCES" out ) > "$1/stdout" 2> "$1/stderr"
}

# says <dir> <text> -- did either stream mention it
says() {
	cat "$1/stdout" "$1/stderr" | grep -qF "$2"
}

# rows <dir> -- packages listed in the published sources/index.txt
rows() {
	grep -vc '^#' "$1/out/sources/index.txt" 2>/dev/null || echo 0
}

# One release, three packages, one archive. The case that was failing: the source
# was fetched and every package of that release except one was reported sourceless.
#
# Staged by tools/fetch.sh itself, from a fake release: `curl` answers out of
# $d/release by the last path segment of the URL, and `owfeed verify-artifact`
# accepts everything -- signatures are not what this file tests. The copy of fetch.sh
# sits in the scenario's own tools/, because fetch.sh reads packages/<name>/ relative
# to the directory it lives in.
d="$(scenario manifest-release)"
url="https://github.com/example/luci-app-example/archive/refs/tags/v1.0.tar.gz"
rel="$d/release"
stub="$d/bin"
mkdir -p "$rel" "$stub" "$d/tools" "$d/packages/luci-app-example" "$d/keys"
cp "$FETCH" "$d/tools/fetch.sh"
cat > "$d/packages/luci-app-example/upstream.sh" <<'EOF'
KIND="manifest"
REPO="example/luci-app-example"
VERSION="1.0-r1"
TAG="v1.0"
SIG_KEY="keys/luci-app-example.pub"
SIG_KEY_ID="0000000000000000"
EOF
: > "$d/keys/luci-app-example.pub"
{
	echo "owfeed-manifest 1"
	echo "repo example/luci-app-example"
	echo "tag v1.0"
	for p in example-daemon luci-app-example luci-i18n-example-ru; do
		f="$p-1.0-r1.apk"
		echo "package $p" > "$rel/$f"
		printf 'pkg %s apk %s %s %s noarch\n' "$p" "$f" \
			"$(wc -c < "$rel/$f" | tr -d ' ')" "$(sha256sum "$rel/$f" | cut -d' ' -f1)"
	done
} > "$rel/manifest.txt"
echo "not really a tarball" > "$rel/v1.0.tar.gz"
sum="$(sha256sum "$rel/v1.0.tar.gz" | cut -d' ' -f1)"
# Any URL whose file the fake release lacks -- every `.sig` -- still answers, because
# fetch.sh only hands those to the `owfeed` stub. A 404 here would be a failure of
# this fixture, not of the code under test.
cat > "$stub/curl" <<'STUB'
#!/bin/sh
out="" url=""
while [ $# -gt 0 ]; do
	case "$1" in
	-o) out="$2"; shift ;;
	-*) ;;
	*) url="$1" ;;
	esac
	shift
done
f="$RELEASE/${url##*/}"
if [ -f "$f" ]; then cp "$f" "$out"; else : > "$out"; fi
STUB
printf '#!/bin/sh\nexit 0\n' > "$stub/owfeed"
chmod +x "$stub/curl" "$stub/owfeed"
if ! ( cd "$d" && PATH="$stub:$PATH" RELEASE="$rel" DIST=dist \
	sh tools/fetch.sh packages/luci-app-example ) > "$d/fetch.log" 2>&1; then
	bad "manifest release" "tools/fetch.sh failed on the fixture: $(cat "$d/fetch.log")"
fi
index "$d" "example-daemon 1.0-r1 GPL-2.0-only" \
	"luci-app-example 1.0-r1 GPL-2.0-only" \
	"luci-i18n-example-ru 1.0-r1 GPL-2.0-only"
if ! run "$d"; then
	bad "manifest release" "refused a release whose source was staged: $(cat "$d/stderr")"
elif [ "$(rows "$d")" -ne 3 ]; then
	bad "manifest release" "sources/index.txt lists $(rows "$d") package(s), not 3"
elif ! grep -q "^example-daemon.*$sum.*$url" "$d/out/sources/index.txt" ||
	! grep -q "^luci-i18n-example-ru.*$sum.*$url" "$d/out/sources/index.txt"; then
	bad "manifest release" "a package's row lost its sha256 or its origin"
else
	ok "manifest release: one archive is the source of every package it built"
fi

# The gate itself. A copyleft package nothing staged source for must still stop the
# publish -- if this passes, the fix above has turned the check into decoration.
d="$(scenario no-source)"
index "$d" "example-daemon 1.0-r1 GPL-2.0-only"
if run "$d"; then
	bad "no source" "published a copyleft package with no source at all"
elif ! says "$d" "NO SOURCE example-daemon" || ! says "$d" "refusing to publish"; then
	bad "no source" "refused without naming the package"
else
	ok "no source: a copyleft package without source still refuses the publish"
fi

# Staged and then lost. The archive is named in the record and absent from the tree,
# which is a fetch that half-succeeded, not a source that was served.
d="$(scenario staged-not-served)"
printf '%s %s %s %s %s %s\n' \
	"example-daemon" "1.0-r1" "example-1.0-r1.tar.gz" "deadbeef" "$url" "luci-app-example" \
	> "$d/dist/sources/staged.txt"
index "$d" "example-daemon 1.0-r1 GPL-2.0-only"
if run "$d"; then
	bad "staged not served" "counted a record as if it were the archive"
elif ! says "$d" "packages/luci-app-example/upstream.sh"; then
	bad "staged not served" "did not name the entry that staged it"
else
	ok "staged not served: a record without the file is not source"
fi

# The message the failure prints. This is the half that was wrong: every miss was
# reported as "the tag's own archive could not be fetched" pointing at
# packages/<package>/, a directory that does not exist for a package published by an
# entry of another name.
d="$(scenario fetch-failed)"
printf '%s %s %s %s\n' "example-daemon" "1.0-r1" "luci-app-example" "$url" \
	> "$d/dist/sources/unstaged.txt"
index "$d" "example-daemon 1.0-r1 GPL-2.0-only"
if run "$d"; then
	bad "fetch failed" "published a copyleft package whose source fetch failed"
elif ! says "$d" "packages/luci-app-example/upstream.sh" || ! says "$d" "$url"; then
	bad "fetch failed" "did not name the entry and the URL that failed"
elif says "$d" "packages/example-daemon/upstream.sh"; then
	bad "fetch failed" "sent the reader to a directory that does not exist"
else
	ok "fetch failed: the refusal names the entry and the URL it tried"
fi

# A permissive package without source is not a finding. A check that fires on a
# healthy feed is worse than no check: every publish would need somebody to decide
# it was the harmless kind of red.
d="$(scenario permissive)"
index "$d" "example-daemon 1.0-r1 Apache-2.0"
if ! run "$d"; then
	bad "permissive" "refused a package whose licence asks for no source"
else
	ok "permissive: no source, no finding"
fi

# No record at all, and a correctly named archive beside the binaries. Older trees
# and hand-assembled ones still have to pass: the gate asks whether source is
# served, and staged.txt is evidence about that, not the definition of it.
d="$(scenario no-record)"
echo "not really a tarball" > "$d/dist/sources/example-daemon-1.0-r1.tar.gz"
index "$d" "example-daemon 1.0-r1 GPL-2.0-only"
if ! run "$d"; then
	bad "no record" "refused a package whose archive is right there: $(cat "$d/stderr")"
elif ! grep -q "^example-daemon.*unrecorded" "$d/out/sources/index.txt"; then
	bad "no record" "did not say the origin was unrecorded"
else
	ok "no record: an archive found by name is still source, with no origin claimed"
fi

# An index this cannot parse. Its packages are packages whose licence nobody read, so
# the publish has to stop -- the readable index beside it passing on its own is
# exactly how a copyleft package in the broken one used to go out without source.
d="$(scenario unreadable-index)"
index "$d" "example-daemon 1.0-r1 Apache-2.0"
mkdir -p "$d/out/releases/25.12/aarch64_generic"
printf '{"packages":[{"name":"luci-app-example",' \
	> "$d/out/releases/25.12/aarch64_generic/index.json"
if run "$d"; then
	bad "unreadable index" "published past an index.json it could not parse"
elif ! says "$d" "could not read every index.json"; then
	bad "unreadable index" "refused without saying which step failed: $(cat "$d/stderr")"
else
	ok "unreadable index: an index that cannot be read refuses the publish"
fi

[ "$fails" -eq 0 ] || { echo "tools/sources.sh: $fails case(s) failed" >&2; exit 1; }
echo "tools/sources.sh: every case passed"
