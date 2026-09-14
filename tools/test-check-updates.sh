#!/bin/sh
# Test `tools/check-updates.sh` against local repositories and a stub `gh`.
#
# Run it from anywhere: `tools/test-check-updates.sh`. It reaches no network, no
# GitHub and nothing outside one temporary directory -- `gh` is replaced on PATH by a
# script that answers out of files this test writes, and the "remote" is a bare
# repository under $TMPDIR. No release is ever downloaded for real; the stub records
# which tag was asked for, which is most of what these cases are about.
#
# WHAT IT PINS. Nine pins the scheduled job meets, and where each has to land:
#
#   a-handmapped   tag 0.19.17-2, VERSION 0.19.17-r2, upstream now 0.19.17-3
#                  -> updated: upstream's -3 becomes the feed's -r3, the tag verbatim
#   a0-unfetchable upstream names a latest release, and downloading it fails
#                  -> this package stops, every package after it is still checked,
#                     and the run is red naming it
#   b0-outage      asking for the latest release fails with an HTTP error
#                  -> stops like a0-unfetchable; never read as "no releases"
#   b1-missing     `release not found`, and the repository itself is gone
#                  -> stops: a REPO to fix, not an upstream with nothing released
#   f-norelease    `release not found` from a repository that exists
#                  -> "upstream has no releases", green
#   b-current      tag 0.19.17-2, VERSION 0.19.17-r2, upstream still 0.19.17-2
#                  -> current; the run must not propose what is already pinned
#   c-noprefix     tag 2026.07 -> 2026.08, no `v` anywhere
#                  -> downloaded and pinned by the tag upstream published
#   d-vprefix      tag v1.0.0 -> v1.1.0
#                  -> the ordinary path, unchanged
#   e-retag        tag v1.0.0, upstream now tags 1.1.0, and a branch built by the
#                  guessing code already claims that version with TAG="v1.1.0"
#                  -> rebuilt, because those two tags are different releases
#
# THE REGRESSIONS. `check-updates.sh` read the latest tag, stripped a leading `v` off
# it, and pasted one back on to download -- so the first upstream in the feed that
# does not prefix its tags was asked for a tag nobody published:
#
#   luci-app-podkop-bot: 0.19.17 -> 0.19.17-2
#   release not found
#
# -- run 34610183122. Two things came out of that one line. The version reconstructed
# from VERSION never matched a tag carrying a suffix, so the package read as updatable
# on every run forever; and the failing subshell ended the whole loop under `set -eu`,
# which left `luci-theme-footstrap` and `podkop-updater` unchecked and unmentioned.
# `a0-unfetchable` sorts before b, c, d and e for exactly that reason: all four have
# to be checked after it fails, and the run has to be red anyway.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
# Overridable so the same cases can be run against another copy of the script -- the
# one from before a change, to see a case go red for the reason it claims to.
script="${CHECK_UPDATES:-$root/tools/check-updates.sh}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

# No user configuration and a fixed identity: a global `commit.gpgsign`, a hook
# template or an `init.defaultBranch` in somebody's home decides otherwise whether
# this passes, and a test that passes for a reason outside the repository is not a
# test of the repository.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_SYSTEM=/dev/null
GIT_AUTHOR_NAME="test"
GIT_AUTHOR_EMAIL=test@example.invalid
GIT_COMMITTER_NAME="test"
GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

result=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; result=1; }

bin="$work/bin"
mkdir -p "$bin"

GH_STATE="$work/state"
export GH_STATE
mkdir -p "$GH_STATE/releases" "$GH_STATE/broken" "$GH_STATE/outage" "$GH_STATE/missing"
: > "$GH_STATE/downloads"

# Stand-in for gh(1). It answers the four calls the script makes and fails on
# anything else: a call this stub silently swallowed would be a call the test is not
# exercising. A download of a tag no release has -- or of a release marked broken --
# is `release not found` on stderr and exit 1, which is what the real `gh` did on the
# run this test is about.
cat >"$bin/gh" <<'STUB'
#!/bin/sh
set -eu
slug() { printf '%s\n' "$1" | tr / _; }
what="${1:-} ${2:-}"
shift 2
case "$what" in
"release view")
	# gh release view --repo <repo> --json tagName -q .tagName
	#
	# The three shapes a failure takes, as measured against gh 2.99.0: an HTTP
	# error names itself; no releases and no repository both say exactly
	# `release not found`.
	s="$(slug "$2")"
	if [ -f "$GH_STATE/outage/$s" ]; then
		echo "HTTP 502: Bad Gateway (https://api.github.com/repos/$2/releases/latest)" >&2
		exit 1
	fi
	f="$GH_STATE/releases/$s"
	[ -f "$f" ] || { echo "release not found" >&2; exit 1; }
	cat "$f"
	;;
"api repos/"*"/releases?per_page=1")
	# gh api repos/<repo>/releases?per_page=1 -q length -- a missing repository
	# is a 404 here, an existing one with no releases answers 0.
	r="${what#api repos/}"
	r="${r%/releases*}"
	if [ -f "$GH_STATE/missing/$(slug "$r")" ]; then
		echo "gh: Not Found (HTTP 404)" >&2
		exit 1
	fi
	if [ -f "$GH_STATE/releases/$(slug "$r")" ]; then echo 1; else echo 0; fi
	;;
"release download")
	# gh release download <tag> --repo <repo> --dir <dir> --pattern <pattern>
	printf '%s\n' "$1" >>"$GH_STATE/downloads"
	f="$GH_STATE/releases/$(slug "$3")"
	if [ -f "$GH_STATE/broken/$(slug "$3")" ] || [ ! -f "$f" ] || [ "$(cat "$f")" != "$1" ]; then
		echo "release not found" >&2
		exit 1
	fi
	mkdir -p "$5"
	printf 'owfeed-manifest 1\n' >"$5/manifest.txt"
	;;
"pr create")
	echo "pr create" >>"$GH_STATE/calls"
	echo "https://example.invalid/pull/1"
	;;
"workflow run")
	echo "workflow run" >>"$GH_STATE/calls"
	;;
*)
	echo "stub gh: unexpected call: $what $*" >&2
	exit 1
	;;
esac
STUB
chmod +x "$bin/gh"

# GNU `sed -i` takes no argument where BSD's requires one, so the `sed -i "s|...|"
# file` that check-updates.sh runs -- and that GNU sed on the runner performs -- reads
# on a Mac as "keep a backup suffixed s|...|" and then finds no script at all. The
# shim spells the same edit the BSD way so the script under test runs here unmodified;
# without it every case below fails for a reason that has nothing to do with the code.
if ! sed --version >/dev/null 2>&1; then
	realsed="$(command -v sed)"
	cat >"$bin/sed" <<SHIM
#!/bin/sh
if [ "\${1:-}" = "-i" ]; then
	shift
	exec $realsed -i '' "\$@"
fi
exec $realsed "\$@"
SHIM
	chmod +x "$bin/sed"
fi

origin="$work/origin.git"
repo="$work/repo"
git init -q --bare -b main "$origin"
git init -q -b main "$repo"
cd "$repo"
git remote add origin "$origin"

# release <repo> <tag> -- the one release that repository has.
release() { printf '%s\n' "$2" >"$GH_STATE/releases/$(printf '%s\n' "$1" | tr / _)"; }

# pin <name> <version> <tag> -- one package, in the shape check-updates.sh rewrites.
# Signed and AUTO_MERGE="yes" throughout, so every update here takes the path that
# pushes a branch and opens no pull request; the conditions that fork those two paths
# are `may_automerge()`'s and are not what this file is testing.
pin() {
	mkdir -p "packages/$1"
	cat >"packages/$1/upstream.sh" <<EOF
KIND="manifest"
REPO="example/$1"
VERSION="$2"
TAG="$3"
SIG_KEY="keys/$1.pub"
SIG_KEY_ID="0000000000000000"
AUTO_MERGE="yes"
EOF
}

pin a-handmapped   0.19.17-r2 0.19.17-2
pin a0-unfetchable 1.0.0-r1   v1.0.0
pin b-current      0.19.17-r2 0.19.17-2
pin c-noprefix     2026.07-r1 2026.07
pin d-vprefix      1.0.0-r1   v1.0.0
pin e-retag        1.0.0-r1   v1.0.0
pin b0-outage      1.0.0-r1   v1.0.0
pin b1-missing     1.0.0-r1   v1.0.0
pin f-norelease    1.0.0-r1   v1.0.0
git add -A && git commit -q -m "packages: initial pins"
git push -q origin main

release example/a-handmapped   0.19.17-3
release example/a0-unfetchable v1.0.1
: > "$GH_STATE/broken/example_a0-unfetchable"
release example/b-current      0.19.17-2
release example/c-noprefix     2026.08
release example/d-vprefix      v1.1.0
release example/e-retag        1.1.0
release example/b0-outage      v1.0.1
: > "$GH_STATE/outage/example_b0-outage"
: > "$GH_STATE/missing/example_b1-missing"
# f-norelease: no release at all, and the repository is there.

# The branch the guessing code would have left behind for e-retag: the right version
# in its name, the wrong tag in its pin. Its content is what decides whether the next
# run calls the update done.
git checkout -q -b update/e-retag-1.1.0 main
pin e-retag 1.1.0-r1 v1.1.0
git add -A && git commit -q -m "e-retag: 1.0.0 -> 1.1.0"
git push -q origin update/e-retag-1.1.0
git checkout -q main

status=0
run() {
	status=0
	PATH="$bin:$PATH" GITHUB_REPOSITORY="owfeed/test" sh "$script" >"$1" 2>&1 || status=$?
	sed 's/^/     | /' "$1"
}

# said <file> <text>
said() {
	if grep -qF "$2" "$1"; then ok "said: $2"; else no "never said: $2"; fi
}
unsaid() {
	if grep -qF "$2" "$1"; then no "said what it should not: $2"; else ok "silent about: $2"; fi
}

# asked <tag> -- was this tag ever fetched from a release
asked() {
	if grep -qxF "$1" "$GH_STATE/downloads"; then ok "downloaded $1"; else no "never downloaded $1"; fi
}
unasked() {
	if grep -qxF "$1" "$GH_STATE/downloads"; then no "asked for the tag $1, which no release has"
	else ok "never asked for $1"; fi
}

# field <branch> <package> <key> -- one value out of the pin that branch carries
field() {
	git fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
	git show "refs/remotes/origin/$1:packages/$2/upstream.sh" 2>/dev/null |
		sed -n "s/^$3=\"\\([^\"]*\\)\".*/\\1/p"
}
pinned() { # <branch> <package> <key> <expected>
	got="$(field "$1" "$2" "$3")"
	if [ "$got" = "$4" ]; then ok "$1 pins $3=\"$4\""
	else no "$1 pins $3=\"$got\", expected \"$4\""; fi
}

echo "--- first run"
run "$work/out"

# The run is red, and it says which package it could not finish. Anything quieter is
# a scheduled job reporting that nothing was released when it never asked.
if [ "$status" -ne 0 ]; then ok "the run is red"; else no "the run went green with a package it could not check"; fi
said "$work/out" "a0-unfetchable: stopped; the remaining packages are still checked"
said "$work/out" "check stopped for: a0-unfetchable b0-outage b1-missing"

# Not being able to ask is not an answer. Both failures stop their package, and the
# one repository that exists and has released nothing is still the green case.
said "$work/out" "b0-outage: could not read the latest release of example/b0-outage"
said "$work/out" "HTTP 502: Bad Gateway"
unsaid "$work/out" "b0-outage: upstream has no releases"
said "$work/out" "b1-missing: could not read the latest release of example/b1-missing"
unsaid "$work/out" "b1-missing: upstream has no releases"
said "$work/out" "f-norelease: upstream has no releases"
unsaid "$work/out" "f-norelease: stopped"
if [ -z "$(git ls-remote --heads origin 'update/a0-unfetchable-*')" ]; then
	ok "a0-unfetchable pushed nothing"
else
	no "a0-unfetchable pushed a branch for a release it could not download"
fi

# Upstream's own numeric suffix is a revision, and maps onto the feed's `-r<n>`
# rather than being carried along as `0.19.17-3-r1`. The tag stays what upstream
# published, and nobody ever asks for a `v` in front of it.
said "$work/out" "a-handmapped: 0.19.17-2 -> 0.19.17-3"
asked 0.19.17-3
unasked v0.19.17-3
pinned update/a-handmapped-0.19.17-3 a-handmapped VERSION 0.19.17-r3
pinned update/a-handmapped-0.19.17-3 a-handmapped TAG 0.19.17-3

# A tag that is not a version with a `v` in front is still the tag this pin names.
# This is the line the run died on: 0.19.17-2 read as an update to 0.19.17.
said "$work/out" "b-current: 0.19.17-2 is current"
if [ -z "$(git ls-remote --heads origin 'update/b-current-*')" ]; then
	ok "b-current proposed nothing"
else
	no "b-current pushed a branch for a release it already pins"
fi

# Isolation: c, d and e come after the package that failed, and all three were checked.
said "$work/out" "c-noprefix: 2026.07 -> 2026.08"
asked 2026.08
unasked v2026.08
pinned update/c-noprefix-2026.08 c-noprefix TAG 2026.08
pinned update/c-noprefix-2026.08 c-noprefix VERSION 2026.08-r1

said "$work/out" "d-vprefix: 1.0.0 -> 1.1.0"
asked v1.1.0
pinned update/d-vprefix-1.1.0 d-vprefix TAG v1.1.0
pinned update/d-vprefix-1.1.0 d-vprefix VERSION 1.1.0-r1

# `v1.1.0` and `1.1.0` are two tags, and only one of them exists upstream. A branch
# holding the other one is not this update already done.
said "$work/out" "e-retag: 1.0.0 -> 1.1.0"
unsaid "$work/out" "e-retag: update/e-retag-1.1.0 already carries"
asked 1.1.0
pinned update/e-retag-1.1.0 e-retag TAG 1.1.0

# A package that failed mid-way must not hand the next one a rewritten pin or a HEAD
# parked on an update branch: every package after it is read out of that tree.
if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]; then ok "HEAD is back on main"
else no "HEAD is left on $(git rev-parse --abbrev-ref HEAD)"; fi
if [ -z "$(git status --porcelain)" ]; then ok "the working tree is clean"
else no "the working tree still carries: $(git status --porcelain | tr '\n' ' ')"; fi

echo "--- second run"
before="$(wc -l <"$GH_STATE/downloads" | tr -d ' ')"
run "$work/out2"

# Convergence. An update that is already proposed is proposed once: the branch is
# there, it names this tag, and it still fast-forwards onto main.
said "$work/out2" "a-handmapped: update/a-handmapped-0.19.17-3 already carries 0.19.17-3"
said "$work/out2" "c-noprefix: update/c-noprefix-2026.08 already carries 2026.08"
said "$work/out2" "d-vprefix: update/d-vprefix-1.1.0 already carries 1.1.0"
said "$work/out2" "e-retag: update/e-retag-1.1.0 already carries 1.1.0"
unsaid "$work/out2" "2026.07 -> 2026.08"
after="$(wc -l <"$GH_STATE/downloads" | tr -d ' ')"
# One download on the second run: the release that still cannot be fetched is asked
# for again, and nothing that was already correct is rebuilt.
if [ "$((after - before))" = 1 ]; then ok "the second run downloaded only what failed before"
else no "the second run downloaded $((after - before)) release(s); only a0-unfetchable should be retried"; fi

# And it is still red, because the release it cannot fetch is still there. A failure
# that goes green on the next run is a failure nobody ever sees.
if [ "$status" -ne 0 ]; then ok "the second run is red too"; else no "the failure stopped being reported"; fi

# `may_automerge` runs as an `if` condition, where POSIX switches errexit off. A git
# call inside it that fails hands the next line an empty answer, and both empty
# answers there mean "yes": no recent updates (under the daily ceiling), no diff
# outside the pins. A failed read has to be a pull request instead.
realgit="$(command -v git)"
cat >"$bin/git" <<SHIM
#!/bin/sh
if [ -f "\$GH_STATE/git-fails" ] && [ "\${1:-}" = "\$(cat "\$GH_STATE/git-fails")" ]; then
	echo "fatal: stub git refused: git \$*" >&2
	exit 128
fi
exec "$realgit" "\$@"
SHIM
chmod +x "$bin/git"

echo "--- third run: git log fails while counting recent updates"
release example/d-vprefix v1.2.0
echo log >"$GH_STATE/git-fails"
run "$work/out3"
rm -f "$GH_STATE/git-fails"
said "$work/out3" "d-vprefix: https://example.invalid/pull/1"
unsaid "$work/out3" "d-vprefix: update/d-vprefix-1.2.0 pushed, no pull request"

echo "--- fourth run: git diff fails while reading what moved"
release example/c-noprefix 2026.09
echo diff >"$GH_STATE/git-fails"
run "$work/out4"
rm -f "$GH_STATE/git-fails"
said "$work/out4" "c-noprefix: https://example.invalid/pull/1"
unsaid "$work/out4" "c-noprefix: update/c-noprefix-2026.09 pushed, no pull request"

if [ "$result" = 0 ]; then
	echo "PASS"
else
	echo "tools/check-updates.sh: case(s) failed" >&2
fi
exit "$result"
