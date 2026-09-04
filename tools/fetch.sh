#!/bin/sh
# Fetch one package's upstream artifacts, verify them, and stage them.
#
# One implementation for every package. A package contributes data — a version, its
# checksums, which architectures each artifact serves — and never a script, so the
# hourly update job rewrites values rather than code, and adding a package does not
# start with copying somebody else's shell.
#
# Usage: tools/fetch.sh packages/<name>
set -eu

DIR="${1:?usage: tools/fetch.sh packages/<name>}"
NAME="$(basename "$DIR")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${DIST:-dist}"
STAGING="${STAGING:-staging}"

. "$ROOT/$DIR/upstream.sh"

# A package can be present and not published — see LEGAL.md for why one is.
if [ "${ENABLED:-yes}" != "yes" ]; then
	echo ">> $NAME: not enabled, skipping"
	exit 0
fi

# Most projects tag releases v<version>; some do not. Overriding the whole tag
# rather than the prefix means a project that tags "release-1.2" or "2026.07" is a
# one-line entry rather than a change here.
TAG="${TAG:-v${VERSION%-r*}}"
base="https://github.com/${REPO}/releases/download/${TAG}"

# get <url> <dest>
#
# --retry, because a release of ninety-odd assets meets a 502 from the CDN sooner or
# later and a whole publish failing on one is noise, not a finding. Retrying is safe
# here for the reason it usually is not: every byte fetched is checked against a hash
# or a signature afterwards, so a retry cannot smuggle anything past.
get() {
	curl -fsSL --proto '=https' --tlsv1.2 \
		--retry 5 --retry-delay 2 --retry-connrefused --retry-all-errors \
		-o "$2" "$1"
}

# download <url> <dest> <sha256>
download() {
	get "$1" "$2"
	got="$(sha256sum "$2" | cut -d' ' -f1)"
	[ "$got" = "$3" ] || { echo "$1: sha256 $got, pinned $3" >&2; rm -f "$2"; exit 1; }
}

# fetch_source
#
# The corresponding source, fetched and staged beside the binaries rather than linked
# to. This is what lets the feed carry a copyleft package at all.
#
# GPLv2 §3 conditions distributing a binary on one of three things: the source
# accompanying it, a written offer valid for three years, or -- non-commercially and
# only if you received such an offer -- passing that offer along. Publishing a binary
# and linking to a GitHub repository is none of the three. Upstream's distribution is
# upstream's; a feed re-serving those bytes is a separate act of distribution with its
# own obligation, and "the source is over there somewhere" does not discharge it.
#
# Serving the source from the same origin as the binary is the first option, and it is
# the only one that needs no promise anybody has to remember to keep for three years.
#
# This runs for every package, not only the copyleft ones. Deciding per package would
# mean this repository holding an opinion about someone else's licence; fetching
# always means the source is simply there, and the question never has to be asked at
# contribution time.
#
# What this can and cannot claim: it serves the archive for the pinned tag, and
# records the sha256 of exactly what it served. So the feed offers what upstream
# offers, and what it handed out stays identifiable. Whether that archive is complete
# corresponding source is upstream's assertion, not this feed's -- the same assertion
# every other consumer of that release already relies on.
#
# One tag, and every package built from it. An entry is not a package: KIND="manifest"
# is one release and all the packages in it -- a daemon, the LuCI page that drives it,
# the translation catalogue that goes with both -- and that one archive is the
# corresponding source for each of them. tools/sources.sh asks for source by the
# package name the index carries, never by the directory this repository keeps the
# entry in, so the archive is served under every one of those names. Staging it under
# the entry's name alone published source for whichever package happened to share the
# directory name and left the rest of the release reading as sourceless, which refuses
# the publish of the whole feed as soon as one of them is copyleft.
fetch_source() {
	# Default to the tag's own archive. GitHub generates one for EVERY tag, whether
	# or not the author attached anything to the release -- so a package does not
	# need its upstream to have thought about this, and the two-line-per-package
	# version of this rule was a limitation of the first implementation rather than
	# of the licence. Set SOURCE_URL to override, which is what a project hosted
	# somewhere other than GitHub needs.
	url="${SOURCE_URL:-https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz}"

	# Every package this entry publishes, so that each is served the source of the
	# release it came out of. Set by the KIND branch that can know -- the manifest
	# names them -- and the entry's own name otherwise, which is the one package the
	# other shapes publish.
	published="${PUBLISHED:-$NAME}"

	mkdir -p "$DIST/sources"
	# Named for a package and a version, because that is the pair a user holding a
	# binary has: `apk info` tells them both, and nothing else identifies which
	# source goes with what they installed. The download lands under the entry's own
	# name; the loop at the end of this function gives the release's other packages
	# the same pair.
	case "$url" in
	*.tar.gz|*.tgz) ext="tar.gz" ;;
	*.tar.xz)       ext="tar.xz" ;;
	*.tar.bz2)      ext="tar.bz2" ;;
	*.zip)          ext="zip" ;;
	*)              ext="tar.gz" ;;
	esac
	dest="$DIST/sources/${NAME}-${VERSION}.${ext}"

	if [ -n "${SOURCE_SHA256:-}" ]; then
		# Pinned, for a stable release asset an author attached deliberately.
		download "$url" "$dest" "$SOURCE_SHA256"
	else
		# Unpinned, and that is a considered difference rather than an oversight.
		#
		# Everything else this script fetches gets installed on somebody's router,
		# so a pin is what stands between a replaced artifact and a compromised
		# device. This archive is never installed and never executed: it is served
		# as evidence, to satisfy the licence's source condition. What identifies it
		# is the TAG, and the tag is pinned right here in upstream.sh.
		#
		# Pinning it anyway would cost more than it buys. GitHub's generated tag
		# archives are not promised to be byte-stable over time -- they have been
		# regenerated before -- so a pinned hash turns somebody else's
		# infrastructure change into a red publish for a file nobody runs.
		#
		# The hash of what was actually served is recorded below and published, so
		# the archive this feed hands out is still identifiable and still auditable.
		# A failure here is reported and not fatal, deliberately. Whether this
		# package NEEDS source is decided by its licence, and the licence is not
		# known until the index is built -- so tools/sources.sh is what refuses,
		# per package, once it can read one. Failing here instead would take down
		# the publish of a permissive package whose upstream simply moved a tag.
		if ! get "$url" "$dest"; then
			echo "!! $NAME: no source archive at $url" >&2
			echo "   set SOURCE_URL in packages/$NAME/upstream.sh if the source lives elsewhere;" >&2
			echo "   if this package is copyleft the publish will refuse it later, by name" >&2
			rm -f "$dest"
			# Which packages are now without source, which entry publishes them,
			# and what was tried. The refusal happens in tools/sources.sh, in a
			# later job that knows package names and nothing about entries -- so
			# without this it can only guess an upstream.sh path, and for a package
			# published by an entry of another name that guess is a directory that
			# does not exist.
			for pkg in $published; do
				printf '%s %s %s %s\n' "$pkg" "$VERSION" "$NAME" "$url" \
					>> "$DIST/sources/unstaged.txt"
			done
			return 0
		fi
	fi

	sum="$(sha256sum "$dest" | cut -d' ' -f1)"
	# One archive, one copy and one row per package it is the source for. Copied
	# rather than hard-linked on purpose: the link would not survive either step
	# that carries this file onward -- tools/sources.sh copies dist/sources file by
	# file into the published tree, and the artifact between the fetch job and the
	# signing job is a zip, which has no notion of one file under two names -- so a
	# link buys nothing here and only fails on a filesystem that has none. The
	# recorded sha256 is the same for every row because the bytes are.
	#
	# package version file sha256 url entry -- tools/sources.sh reads the first five
	# to publish a row per package in sources/index.txt, and the sixth to name the
	# entry when it has to report one.
	wanted=""
	for pkg in $published; do
		[ "$pkg" != "$NAME" ] || wanted=yes
		file="${pkg}-${VERSION}.${ext}"
		[ "$file" = "$(basename "$dest")" ] || cp "$dest" "$DIST/sources/$file"
		printf '%s %s %s %s %s %s\n' \
			"$pkg" "$VERSION" "$file" "$sum" "$url" "$NAME" \
			>> "$DIST/sources/staged.txt"
		echo ">> $NAME: staged corresponding source $file"
	done

	# The download landed under the entry's name, and an entry that publishes no
	# package of that name has just left an archive in the tree that no row of
	# sources/index.txt refers to. Every entry here is named after one of its own
	# packages today, so this drops nothing -- it is what keeps the first one that is
	# not from publishing a file whose only meaning is a directory name in this
	# repository.
	[ -n "$wanted" ] || rm -f "$dest"
}

# check_signature <file>
#
# A pin proves the bytes have not changed since someone looked at them. The author's
# signature says who produced them, and only that can justify an update merging
# itself. The key is pinned in this repository: whoever can replace an artifact can
# replace the signature beside it and the key it names.
# staged <package> <arch> <file>
#
# What this fetch actually put in the tree, so tools/check-tree.sh can compare the
# built feed against it rather than re-deriving each package's shape. A fetch that
# half-succeeds is otherwise invisible: `owfeed doctor` reads what is there and
# cannot see what is missing.
#
# Not a dotfile, and that is not cosmetic. This was `.staged` for one commit, and it
# never crossed the boundary between the job that fetches and the job that signs:
# actions/upload-artifact excludes hidden files by default, the same way
# actions/upload-pages-artifact does. A name without a leading dot works whether or
# not someone remembered the flag.
staged() {
	mkdir -p "$DIST"
	printf '%s %s %s\n' "$1" "$2" "$3" >> "$DIST/staged.txt"
}

# check_signature <local file> [remote asset name]
#
# The remote name is given separately because a package can arrive under one name and
# be stored under another: release assets are flat, so an apk built for many
# architectures carries one in its filename that the published package does not.
check_signature() {
	[ -n "${SIG_KEY:-}" ] || return 0
	remote="${2:-$(basename "$1")}"
	get "$base/$remote.sig" "$1.sig"
	owfeed verify-artifact --key "$ROOT/$SIG_KEY" --key-id "$SIG_KEY_ID" \
		--signature "$1.sig" "$1"
	# Evidence for this step, not something to publish: apk has no idea what to do
	# with a detached usign signature.
	rm -f "$1.sig"
}

# The package names this entry publishes, for fetch_source. Empty here so that a
# variable of this name in the environment cannot decide it; the branch below sets it
# where it knows more than the entry's own directory name.
PUBLISHED=""

case "${KIND:?upstream.sh must set KIND}" in
apk)
	# Upstream publishes a finished package. Its own CI built it; rebuilding here
	# would ship something the maintainer never tested. It goes where owfeed puts a
	# build of that architecture and is signed and indexed unchanged.
	dest="$DIST/noarch"
	mkdir -p "$dest"
	echo ">> $NAME $VERSION (25.12)"
	download "$base/$ARTIFACT" "$dest/$ARTIFACT" "$SHA256"
	check_signature "$dest/$ARTIFACT"
	staged "$NAME" noarch "$ARTIFACT"

	# The 24.10 container, when upstream builds one. opkg calls the
	# architecture-independent package "all" where apk calls it noarch, so it goes
	# in the directory named for what it says it is.
	if [ -n "${ARTIFACT_IPK:-}" ]; then
		dest="$DIST/all"
		mkdir -p "$dest"
		echo ">> $NAME $VERSION (24.10)"
		download "$base/$ARTIFACT_IPK" "$dest/$ARTIFACT_IPK" "$SHA256_IPK"
		check_signature "$dest/$ARTIFACT_IPK"
		staged "$NAME" all "$ARTIFACT_IPK"
	fi
	;;

manifest)
	# Upstream publishes finished packages and a signed inventory of them.
	#
	# The strongest shape there is, and the one that needs the least maintained by
	# hand here: the manifest carries every package's size and sha256, and its
	# signature is what makes those trustworthy. So this repository pins the version
	# and the key, and nothing else -- the checksum table that KIND="apk" needs is
	# the manifest, verified rather than transcribed.
	[ -n "${SIG_KEY:-}" ] || { echo "$NAME: KIND=manifest requires SIG_KEY" >&2; exit 1; }

	work="$(mktemp -d)"
	get "$base/manifest.txt"     "$work/manifest.txt"
	get "$base/manifest.txt.sig" "$work/manifest.txt.sig"

	# VERIFY BEFORE READING. Every value below steers a download, so parsing first
	# would mean acting on text nobody has vouched for.
	owfeed verify-artifact --key "$ROOT/$SIG_KEY" --key-id "$SIG_KEY_ID" \
		--signature "$work/manifest.txt.sig" "$work/manifest.txt"

	# Refuse a shape we do not know, by name, before reading a single field out of
	# it. Other projects ship their own manifests with their own first line and six
	# fields per package instead of seven -- parsed positionally that reads as a
	# valid manifest with an empty architecture, and the failure surfaces much later
	# as a download into "$DIST/" with no directory at all.
	got_format="$(head -n1 "$work/manifest.txt")"
	[ "$got_format" = "owfeed-manifest 1" ] || {
		echo "$NAME: manifest says \"$got_format\"; this reads \"owfeed-manifest 1\"" >&2
		echo "$NAME: it is written by \`owfeed release\` -- see docs/manifest-format.md in owfeed" >&2
		exit 1
	}

	# A signature proves who wrote something, never what it is about. One key often
	# signs several repositories, so without these two checks a manifest lifted from
	# another of this author's releases would verify perfectly as this one.
	got_repo="$(awk '$1=="repo"{print $2; exit}' "$work/manifest.txt")"
	got_tag="$(awk '$1=="tag"{print $2; exit}' "$work/manifest.txt")"
	[ "$got_repo" = "$REPO" ] || { echo "$NAME: manifest is for $got_repo, not $REPO" >&2; exit 1; }
	[ "$got_tag" = "$TAG" ] || { echo "$NAME: manifest is for $got_tag, not $TAG" >&2; exit 1; }

	# Seven fields, every line. The format identifier above says the shape should be
	# right; this says this particular file is.
	bad="$(awk '$1=="pkg" && NF!=7 {print NR; exit}' "$work/manifest.txt")"
	if [ -n "$bad" ]; then
		echo "$NAME: manifest line $bad does not have seven fields" >&2
		echo "$NAME: expected: pkg <name> <format> <file> <size> <sha256> <arch>" >&2
		exit 1
	fi

	# A manifest with no packages is not a release, and reading one as success would
	# publish nothing while reporting that it worked.
	[ "$(awk '$1=="pkg"' "$work/manifest.txt" | wc -l)" -gt 0 ] || {
		echo "$NAME: manifest names no packages" >&2
		exit 1
	}

	# The names this release publishes, out of the manifest that was just verified --
	# the same names the index will carry and `apk info` will print. fetch_source
	# needs them: one tag's archive is the corresponding source for every package
	# built from that tag, and tools/sources.sh refuses to publish a copyleft package
	# it cannot find source for BY PACKAGE NAME.
	#
	# Only lines whose own asset is named for the package are read, and that filter is
	# not defensive tidiness. `owfeed release` derives this field from the asset
	# filename and gets it wrong where the architecture itself contains an underscore:
	# VizzleTF/podkop_autoupdater v0.3.6 has `pkg podkop-updater_0.3.6-r1_mips ipk
	# podkop-updater_0.3.6-r1_mips_24kc.ipk`, a name no index carries and no router
	# ever asks for. Serving a source archive under it would put a file in
	# https://repo.owfeed.org/sources/ that nothing in sources/index.txt refers to.
	# An asset is named <package>-<version> (apk) or <package>_<version> (ipk), so a
	# name that does not begin its own filename is not a package name.
	PUBLISHED="$(awk -v v="$VERSION" \
		'$1=="pkg" && (index($4, $2 "-" v) == 1 || index($4, $2 "_" v) == 1) {print $2}' \
		"$work/manifest.txt" | sort -u)"

	# pkg <name> <format> <file> <size> <sha256> <arch>
	awk '$1=="pkg"{print $3, $4, $5, $6, $7}' "$work/manifest.txt" | while read -r fmt file size sum arch; do
		# opkg calls the architecture-independent package "all" where apk calls it
		# noarch, so each goes in the directory named for what it says it is.
		dest="$DIST/$arch"
		mkdir -p "$dest"

		# The asset name is not the name this gets published under. An apk's
		# filename carries no architecture -- in a feed the architecture is the
		# directory -- but release assets are flat, so `owfeed release` appended the
		# architecture where names collided. Taking it back off restores the name
		# the index derives, and is exactly the inverse of what put it there.
		out="$file"
		case "$fmt" in
		apk) out="$(printf '%s' "$file" | sed "s/_${arch}\.apk$/.apk/")" ;;
		esac

		echo ">> $NAME $VERSION $arch ($fmt)"
		download "$base/$file" "$dest/$out" "$sum"

		got_size="$(wc -c < "$dest/$out" | tr -d ' ')"
		[ "$got_size" = "$size" ] || { echo "$file: $got_size bytes, manifest says $size" >&2; exit 1; }

		# The manifest's signature already covers this file's hash, so a detached
		# signature beside it adds nothing here -- it exists for consumers that know
		# nothing about manifests. Checked when present, not required: an upstream
		# that publishes a manifest has no reason to also publish ninety signatures
		# nobody reads.
		if [ -n "${SIG_PER_PACKAGE:-yes}" ] && [ "${SIG_PER_PACKAGE:-yes}" = "yes" ]; then
			check_signature "$dest/$out" "$file"
		fi
		staged "$NAME" "$arch" "$out"
	done
	rm -rf "$work"
	;;

binaries)
	# Upstream publishes raw artifacts. Each one serves the architectures listed
	# beside it — a static binary needs the right target and no OpenWrt SDK, and one
	# build usually covers several OpenWrt architectures that share it.
	mkdir -p "$STAGING"
	echo "$VERSION" > "$STAGING/$NAME.version"
	rm -rf "${STAGING:?}/$NAME"

	echo "$ARTIFACTS" | while read -r artifact sha arches; do
		[ -n "$artifact" ] || continue
		echo ">> $NAME $VERSION $artifact"
		tmp="$(mktemp)"
		download "$base/$artifact" "$tmp" "$sha"
		check_signature "$tmp"

		for arch in $arches; do
			mkdir -p "$STAGING/$NAME/$arch$(dirname "${BINARY_DEST:?upstream.sh must set BINARY_DEST}")"
			install -m 0755 "$tmp" "$STAGING/$NAME/$arch$BINARY_DEST"
			# Anything the feed itself adds — an init script, a default config.
			[ -d "$ROOT/$DIR/files" ] && cp -a "$ROOT/$DIR/files/." "$STAGING/$NAME/$arch/"
		done
		rm -f "$tmp"
	done
	;;

*)
	echo "$NAME: KIND=$KIND is not a shape this feed knows" >&2
	exit 1
	;;
esac

# After the artifacts, so a package whose binaries failed never leaves a source
# archive behind suggesting it was carried.
fetch_source
