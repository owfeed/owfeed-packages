#!/bin/sh
# Check a package request before a person spends time on it.
#
# What it can decide: whether the release exists, whether the manifest is signed by
# the key the requester claims is theirs, whether that manifest is a shape this feed
# can read, and which tier the request therefore lands in.
#
# What it cannot decide, and must not appear to: whether the key belongs to who they
# say, or whether this feed should carry the package at all. The key here comes out
# of an issue anybody can open. Using it to verify the manifest proves the release is
# internally coherent — the same key signed the thing it names — and nothing about
# who holds it. Trust happens exactly once, later, when a person commits that key to
# keys/ and their name is on the merge.
#
# Usage: tools/intake-check.sh <issue-body-file> > verdict.md
set -eu

#
# Exit 8: GitHub or the manifest's host did not answer, so nothing was decided and
# intake.yml says that instead of posting a verdict. A 503 read as "no such release"
# would send a requester looking for a mistake they did not make.
BODY="${1:?usage: tools/intake-check.sh <issue-body-file>}"
NET="$(cd "$(dirname "$0")" && pwd)/net.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# GitHub renders an issue form as "### Label" followed by the value. Read the value
# under a heading, stopping at the next one.
field() {
	awk -v want="### $1" '
		$0 == want { collecting = 1; next }
		/^### / { collecting = 0 }
		collecting { print }
	' "$BODY" | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

REPO="$(field 'Repository')"
TAG="$(field 'Release tag to check')"
KIND_RAW="$(field 'What the release publishes')"
MF_URL="$(field 'Manifest URL')"
KEY_ID="$(field 'Key id')"
PUBKEY="$(field 'usign public key')"
LICENCE="$(field 'Licence')"

KIND="${KIND_RAW%% *}"

fail=0
# The format string never starts with a dash: dash's printf reads that as an option
# and exits, which turns every finding into a broken run.
say()  { printf '%s\n' "$*"; }
bad()  { printf '%s\n' "- **${*}**"; fail=1; }
good() { printf '%s\n' "- $*"; }

say "## Automated intake check"
say ""
say "This is a machine reading your release. It decides nothing about whether the feed"
say "will carry the package — that is a person, later, and the key below is not trusted"
say "by anything yet."
say ""
say "\`$REPO\` @ \`$TAG\` — declared shape: \`$KIND\`"
say ""

# The release has to exist before anything else is worth checking.
rc=0
"$NET" gh release view "$TAG" --repo "$REPO" --json tagName >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 8 ] || exit 8
if [ "$rc" -ne 0 ]; then
	bad "No release \`$TAG\` in \`$REPO\`, or the repository is private."
	say ""
	say "Nothing else could be checked."
	exit 0
fi
good "Release \`$TAG\` exists."

[ -n "$LICENCE" ] && good "Licence declared: \`$LICENCE\` (a person still reads LEGAL.md against it)."

case "$KIND" in
manifest)
	if [ -z "$MF_URL" ]; then
		bad "The manifest shape needs a manifest URL, and none was given."
	else
		printf '%s\n' "$PUBKEY" > "$WORK/claimed.pub"
		# 60 s per attempt, as before: the URL is the requester's choice, and a
		# server that trickles bytes must not hold the job for hours.
		rc=0
		NET_MAX_TIME=60 "$NET" get "$MF_URL" "$WORK/manifest.txt" || rc=$?
		[ "$rc" -ne 0 ] || NET_MAX_TIME=60 "$NET" get "$MF_URL.sig" "$WORK/manifest.txt.sig" || rc=$?
		[ "$rc" -ne 8 ] || exit 8
		if [ "$rc" -ne 0 ]; then
			bad "Could not fetch the manifest and its \`.sig\` from that URL."
		else
			# VERIFY BEFORE READING, exactly as ingest does: every value inside
			# steers a download, so parsing first means acting on unvouched text.
			if owfeed verify-artifact --key "$WORK/claimed.pub" --key-id "$KEY_ID" \
				--signature "$WORK/manifest.txt.sig" "$WORK/manifest.txt" >/dev/null 2>&1; then
				good "The manifest verifies against the key in this request, under id \`$KEY_ID\`."
			else
				bad "The manifest does not verify against that key and id."
			fi

			head="$(head -n1 "$WORK/manifest.txt")"
			if [ "$head" = "owfeed-manifest 1" ]; then
				good "Manifest format: \`owfeed-manifest 1\`."
			else
				bad "Manifest says \`$head\`. This feed reads \`owfeed-manifest 1\`, which \`owfeed release\` writes."
			fi

			short="$(awk '$1=="pkg" && NF!=7 {print NR; exit}' "$WORK/manifest.txt")"
			if [ -n "$short" ]; then
				bad "Line $short does not have seven fields. Expected: \`pkg <name> <format> <file> <size> <sha256> <arch>\` — the seventh is the architecture, and hand-written manifests usually lack it."
			else
				good "Every \`pkg\` line has seven fields."
			fi

			got_repo="$(awk '$1=="repo"{print $2; exit}' "$WORK/manifest.txt")"
			if [ "$got_repo" = "$REPO" ]; then
				good "The manifest names \`$got_repo\`, matching this request."
			else
				bad "The manifest names \`$got_repo\`, not \`$REPO\`. A signature says who wrote something, never what it is about."
			fi
		fi
	fi
	;;
apk)
	good "Finished artifacts. Updates land automatically while the set of containers holds."
	say "  Attach a detached \`.sig\` beside every \`.apk\` and \`.ipk\`; ingest checks each one."
	;;
binaries)
	good "Raw binaries. This shape is carried, but nothing about it is ever merged without a person."
	;;
*)
	bad "Unrecognised shape \`$KIND\`."
	;;
esac

# Does the package say where it comes from?
#
# Read out of the package rather than asked for in the form. A field in the issue
# would be the requester's claim about their own package, and the string that decides
# anything is the one the package manager prints on the router. `tools/check-origin.sh`
# refuses to publish a package without it, and learning that here costs a minute
# instead of a pull request.
#
# The .ipk is what gets read, because it can be: it is a tar holding a tar, and
# `tar -xzO` streams the control file to stdout without writing anything to disk --
# which is what makes reading a stranger's archive in a workflow like this one safe.
# The .apk is an ADB container and needs the apk tool, which is not installed here.
# A release with no .ipk therefore goes unchecked and says so, rather than passing
# quietly.
if [ "$KIND" = "binaries" ]; then
	say "- Origin not checked here: this feed builds the package, so its upstream comes from \`url:\` in \`owfeed.yml\` and is written in the pull request."
else
	ipk="$(gh release view "$TAG" --repo "$REPO" --json assets \
		-q '[.assets[].name | select(endswith(".ipk"))] | first // empty' 2>/dev/null || true)"

	if [ -z "$ipk" ]; then
		say "- Origin not checked: the release publishes no \`.ipk\`, and the \`.apk\` container cannot be read here. \`tools/check-origin.sh\` reads it at build time."
	elif ! gh release download "$TAG" --repo "$REPO" --pattern "$ipk" --dir "$WORK" --clobber >/dev/null 2>&1; then
		say "- Origin not checked: \`$ipk\` could not be downloaded."
	else
		# URL first, Source as the fallback: a package built by OpenWrt's SDK puts
		# the repository in URL and the feed path it was built from in Source, while
		# one built by owfeed has no URL at all and carries the repository in Source.
		origin="$(tar -xzOf "$WORK/$ipk" --wildcards '*control.tar.gz' 2>/dev/null \
			| tar -xzO --wildcards '*control' 2>/dev/null \
			| awk '/^URL: /{u=substr($0,6)} /^Source: /{s=substr($0,9)} END{print (u!="")?u:s}')"

		case "$origin" in
		*://*)
			good "The package names its upstream: \`$origin\`."
			;;
		"")
			bad "The package names no upstream. Set \`URL:=\` in the \`define Package/\` block that builds it — \`tools/check-origin.sh\` refuses to publish a package a user cannot trace."
			;;
		*)
			bad "The package names \`$origin\`, which is not somewhere a user can go. That is usually the feed path the SDK built from; set \`URL:=\` in the \`define Package/\` block as well."
			;;
		esac
	fi
fi

say ""
if [ "$fail" -ne 0 ]; then
	say "### Not ready"
	say ""
	say "Fix the points in bold and edit the issue — this re-runs on every edit."
	exit 0
fi

case "$KIND" in
manifest) tier="A — updates land within the hour, unattended" ;;
apk)      tier="B — updates land automatically while the container set is unchanged" ;;
*)        tier="C — every update waits for a person" ;;
esac
say "### Ready for a person"
say ""
say "Conformance: **$tier**."
say ""
say "What happens next is a pull request adding \`packages/$(basename "$REPO")/upstream.sh\` and"
say "your public key under \`keys/\`. The key is the whole trust decision, so it is read by a"
say "human and merged by hand. Nothing here has trusted it."
