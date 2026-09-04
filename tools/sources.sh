#!/bin/sh
# Publish corresponding source beside the binaries, and refuse to publish a copyleft
# package without it.
#
# This is the check that decides whether this feed may carry a GPL package at all.
#
# GPLv2 §3 gives three ways to distribute a binary: accompany it with source, make a
# written offer good for three years, or -- non-commercially, and only if you were
# given such an offer -- pass that offer along. A feed that publishes a binary and
# links to a repository has done none of them. Upstream distributing its own work is
# upstream's business; re-serving those bytes is a second, separate act of
# distribution that carries the obligation again.
#
# The first option is the only one that needs nobody to remember anything: the source
# sits at the same origin as the binary, served by the same host, for exactly as long
# as the binary is. So that is the one this feed takes, and this script is what makes
# it true rather than intended -- `owfeed publish` is never reached if a copyleft
# package has no source in the tree.
#
# Why the licence is read from the index rather than from upstream.sh: the index is
# built from the metadata inside the package, which its author set. A field in this
# repository would be this feed's opinion about someone else's licence, and would go
# stale the first time upstream relicensed. `apk info` on the router shows the same
# string this reads.
#
# Usage: tools/sources.sh [out]
set -eu

OUT="${1:-out}"
DIST="${DIST:-dist}"
SRC="$OUT/sources"
TAB="$(printf '\t')"

# What tools/fetch.sh recorded: one row per PACKAGE naming the archive staged for it,
# its sha256 and where it came from. A row per package rather than per entry, because
# one KIND="manifest" entry publishes several packages and one archive is the
# corresponding source for all of them.
STAGED="$DIST/sources/staged.txt"
# The same for a fetch that produced nothing: package, version, the entry that
# publishes it, the URL that was tried. Read only to say what went wrong -- a package
# listed here is served nothing and is still refused below.
UNSTAGED="$DIST/sources/unstaged.txt"

command -v jq >/dev/null 2>&1 || { echo "tools/sources.sh needs jq" >&2; exit 1; }

# Licences whose terms condition distributing a binary on providing source.
#
# Matched as substrings of the declared expression, which is why these are spellings
# rather than SPDX identifiers: "GPL-2.0-or-later", "GPL-2.0-only" and a bare
# "GPL-2.0" all have to hit, while "Apache-2.0 OFL-1.1" must not. LGPL and AGPL are
# covered by the GPL substring and named here so the intent is not an accident of
# spelling.
#
# MPL, EPL and CDDL are included for the same reason as GPL even though their
# copyleft is per-file: each conditions distributing a binary on making source
# available. Whether the copyleft is file-level or project-level changes what
# upstream must publish, not what this feed must serve.
is_copyleft() {
	case "$1" in
	*GPL*|*gpl*|*MPL*|*mpl*|*EPL*|*epl*|*CDDL*|*cddl*) return 0 ;;
	*) return 1 ;;
	esac
}

mkdir -p "$SRC"

# Stage whatever the fetches produced, before the check rather than after: a source
# archive that was fetched and not copied should fail as a missing file, not pass
# because the check looked in the directory it came from.
#
# The bookkeeping is excluded by extension: staged.txt and unstaged.txt are how the
# job that fetches talks to this one, and neither is corresponding source. No archive
# can be caught by that filter -- fetch.sh names every one .tar.gz, .tar.xz, .tar.bz2
# or .zip whatever the URL ended in.
if [ -d "$DIST/sources" ]; then
	find "$DIST/sources" -maxdepth 1 -type f ! -name '*.txt' -exec cp -a {} "$SRC/" \;
fi

# Everything the tree publishes, from the JSON index owfeed writes beside each binary
# one. A noarch package appears in every architecture's index and is wanted once.
packages="$(find "$OUT" -name index.json -exec \
	jq -r '.packages[]? | [.name, .version, (.license // "")] | @tsv' {} + 2>/dev/null \
	| sort -u)"

[ -n "$packages" ] || { echo "tools/sources.sh: no package found in any index.json under $OUT" >&2; exit 1; }

missing="$(mktemp)"
listed="$(mktemp)"
trap 'rm -f "$missing" "$listed"' EXIT

printf '%s\n' "$packages" | while IFS="$TAB" read -r name version licence; do
	[ -n "${name:-}" ] || continue
	src="$(find "$SRC" -maxdepth 1 -type f -name "${name}-${version}.*" ! -name '*.txt' | head -1)"

	if [ -n "$src" ]; then
		# The sha256 of what was actually served, and the URL it came from. The
		# archive itself is fetched unpinned -- see tools/fetch.sh for why -- so
		# recording what was handed out is what keeps it identifiable afterwards.
		sum="$(sha256sum "$src" | cut -d' ' -f1)"
		origin="$(awk -v n="$name" -v v="$version" '$1==n && $2==v {print $5; exit}' \
			"$STAGED" 2>/dev/null || true)"
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$name" "$version" "${licence:-unstated}" "$(basename "$src")" \
			"$sum" "${origin:-unrecorded}" >> "$listed"
		continue
	fi

	is_copyleft "${licence:-}" || continue

	# Name a file that exists and a failure that happened. This used to report every
	# miss as "the tag's own archive could not be fetched" and send the reader to
	# packages/<package>/upstream.sh -- but an entry publishes several packages, so
	# for all but one of them that directory is not there to edit, and the archive
	# had in fact been fetched under another name. A true symptom with a false cause
	# and an unusable instruction costs more than no second line would.
	entry="$(awk -v n="$name" -v v="$version" '$1==n && $2==v {print $3; exit}' \
		"$UNSTAGED" 2>/dev/null || true)"
	tried="$(awk -v n="$name" -v v="$version" '$1==n && $2==v {print $4; exit}' \
		"$UNSTAGED" 2>/dev/null || true)"
	# Staged and then not in the tree is a third thing again: the fetch job and this
	# one disagree, and no upstream.sh can fix it.
	held="$(awk -v n="$name" -v v="$version" '$1==n && $2==v {print $3; exit}' \
		"$STAGED" 2>/dev/null || true)"
	holder="$(awk -v n="$name" -v v="$version" '$1==n && $2==v {print $6; exit}' \
		"$STAGED" 2>/dev/null || true)"
	{
		echo "NO SOURCE $name $version: declares \`$licence\`, and this feed serves no source for it"
		if [ -n "$entry" ]; then
			echo "  packages/$entry/upstream.sh publishes it, and its source fetch failed:"
			echo "    curl $tried"
			echo "  set SOURCE_URL there if the source lives somewhere else, then re-run"
			echo "  tools/fetch.sh packages/$entry -- see LEGAL.md"
		elif [ -n "$held" ]; then
			echo "  packages/${holder:-<entry>}/upstream.sh staged $held for it and"
			echo "  that file is not in $SRC: the job that fetched and the job that"
			echo "  publishes disagree, so re-run tools/fetch.sh packages/${holder:-<entry>}"
			echo "  in this tree -- see LEGAL.md"
		else
			echo "  no fetch staged an archive under this name: it is in the index"
			echo "  and not in $STAGED, so no entry published"
			echo "  source under this name -- find the entry in the fetch log and"
			echo "  re-run tools/fetch.sh for it -- see LEGAL.md"
		fi
	} >&2
	echo "$name $version" >> "$missing"
done

{
	echo "# Corresponding source for the packages this feed publishes, served from the"
	echo "# same origin as the binaries so that GPLv2 §3(a) is satisfied by the feed"
	echo "# itself rather than by a link to somewhere else. See LEGAL.md."
	echo "#"
	echo "# package${TAB}version${TAB}licence${TAB}file${TAB}sha256${TAB}origin"
	sort "$listed"
} > "$SRC/index.txt"

if [ -s "$missing" ]; then
	echo "refusing to publish: $(grep -c '' "$missing") copyleft package(s) without corresponding source" >&2
	exit 1
fi

echo "corresponding source served for $(grep -c '' "$listed") package(s); no copyleft package is missing one"
