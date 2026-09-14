#!/bin/sh
# Refuse to publish a package that does not say where it came from.
#
# LEGAL.md's answer to carrying other people's work is that a user who installs
# something from this feed can always find out whose it is. That rests entirely on
# one field -- `url` under apk, `URL:` or `Source:` under opkg -- which the package
# manager prints on the router, and which nothing here was checking.
#
# `owfeed doctor` asks this question as OWF211, but it asks it of owfeed.yml's
# `packages:` list, and this feed's is empty by design: every package is built and
# signed by its author and ingested unchanged. Zero packages configured, zero
# packages checked. The promise in LEGAL.md was true of a feed that builds, and this
# is not one.
#
# Read from the index rather than from a field in this repository, for the same
# reason tools/sources.sh reads the licence from it: the index is built from the
# metadata inside the package, which its author set. A value kept here would be this
# feed's opinion about someone else's package, and would go stale the first time
# upstream moved. It also means the string checked here is the string the router
# shows.
#
# Nothing this finds can be fixed in this repository, and that is the point of
# failing rather than warning. A package missing its origin is fixed where it is
# built -- `URL:=` in the `define Package/<name>` block of an OpenWrt Makefile, or
# `url:` in the owfeed.yml that builds it -- and until it is, this feed does not
# publish it.
#
# Usage: tools/check-origin.sh [out]
set -eu

OUT="${1:-out}"
TAB="$(printf '\t')"

command -v jq >/dev/null 2>&1 || { echo "tools/check-origin.sh needs jq" >&2; exit 1; }

rows="$(mktemp)"
missing="$(mktemp)"
named="$(mktemp)"
trap 'rm -f "$rows" "$missing" "$named"' EXIT

# apk, from the JSON index owfeed writes beside packages.adb. Its fields are the
# package's own pkginfo, so `.url` is what `apk info` prints. A noarch package
# appears in every architecture's index and is wanted once, which is what the
# sort -u below is for.
#
# No `2>/dev/null || true` on either read. That pair hid a jq or awk that failed on
# one index, and every package in it went unchecked while the rest passed -- a check
# that cannot run counts as failed. `find` matching nothing still exits 0; `find`
# exits non-zero when an `-exec ... {} +` invocation does.
if ! find "$OUT" -name index.json -exec \
	jq -r '.packages[]? | ["apk", .name, .version, (.url // "")] | @tsv' {} + \
	>> "$rows"; then
	echo "tools/check-origin.sh: could not read every index.json under $OUT" >&2
	echo "  failed: find $OUT -name index.json -exec jq -r '.packages[]? | ...' {} +" >&2
	echo "  jq's own error is above; rebuild the index (owfeed index) and re-run" >&2
	exit 1
fi

# opkg, from the text index. Both spellings are read because both appear in
# practice: a package built by OpenWrt's SDK carries the repository in `URL:` and
# puts the feed path it was built from in `Source:`, while one built by owfeed's own
# ipk writer has no `URL:` at all and carries the repository in `Source:`. Preferring
# URL and falling back to Source is what makes the two agree.
#
# Continuation lines cannot be mistaken for fields here: opkg indents them with a
# space, and `Description:` -- the only multi-line field -- is written last.
if ! find "$OUT" -name Packages -type f -exec awk '
	function flush() {
		if (name != "") {
			origin = (url != "") ? url : source
			printf "ipk\t%s\t%s\t%s\n", name, version, origin
		}
		name = ""; version = ""; url = ""; source = ""
	}
	# awk is handed every index at once, and a file whose last stanza is not
	# followed by a blank line would otherwise merge into the first stanza of
	# whichever file comes next. No apostrophes below: this program is a shell
	# single-quoted string, and one would end it mid-parse.
	FNR == 1        { flush() }
	/^$/            { flush(); next }
	/^Package: /    { name    = substr($0, 10) }
	/^Version: /    { version = substr($0, 10) }
	/^URL: /        { url     = substr($0, 6)  }
	/^Source: /     { source  = substr($0, 9)  }
	END             { flush() }
' {} + >> "$rows"; then
	echo "tools/check-origin.sh: could not read every Packages index under $OUT" >&2
	echo "  failed: find $OUT -name Packages -type f -exec awk ... {} +" >&2
	echo "  awk's own error is above; rebuild the index (owfeed index) and re-run" >&2
	exit 1
fi

[ -s "$rows" ] || { echo "tools/check-origin.sh: no package found in any index under $OUT" >&2; exit 1; }

sort -u "$rows" | while IFS="$TAB" read -r format name version origin; do
	[ -n "${name:-}" ] || continue

	case "${origin:-}" in
	*://*)
		printf '%s\t%s\t%s\t%s\n' "$format" "$name" "$version" "$origin" >> "$named"
		continue
		;;
	"")
		echo "NO ORIGIN $name $version ($format): the package names no upstream" >&2
		;;
	*)
		# A value that is set and is not a URL is worse than an empty one: it
		# satisfies any check that asks whether the field is present, and the user
		# reading it on the router still has nowhere to go. `Source: feeds/base/x`
		# is the shape this catches -- it is where the SDK built the package, not
		# where the package comes from.
		echo "NO ORIGIN $name $version ($format): names \`$origin\`, which is not somewhere a user can go" >&2
		;;
	esac
	{
		echo "  this is fixed where the package is built, not here: \`URL:=\` in the"
		echo "  \`define Package/$name\` block of an OpenWrt Makefile, or \`url:\` in the"
		echo "  owfeed.yml that builds it -- see LEGAL.md"
	} >&2
	echo "$name $version $format" >> "$missing"
done

if [ -s "$missing" ]; then
	echo "refusing to publish: $(grep -c '' "$missing") published package(s) that do not say where they come from" >&2
	exit 1
fi

# Counted by package rather than by row: one package published on both release
# lines is one package, and reporting it as two would make the number disagree with
# what the feed carries.
echo "every published package names its upstream ($(cut -f2,3 "$named" | sort -u | grep -c '') package(s))"
