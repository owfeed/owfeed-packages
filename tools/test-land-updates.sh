#!/bin/sh
# Test `tools/land-updates.sh` against local repositories and a stub `gh`.
#
# Run it from anywhere: `tools/test-land-updates.sh`. It reaches no network, no
# GitHub and nothing outside one temporary directory -- `gh` is replaced on PATH by a
# script that answers out of files this test writes, and the "remote" is a bare
# repository under $TMPDIR.
#
# WHAT IT PINS. Four branch shapes the hourly job meets, and where each has to fall:
#
#   spent    its bump is already in `main`, history diverged  -> deleted
#   behind   proposes a version `main` has moved past         -> deleted
#   green    fast-forwards, required contexts green           -> landed, deleted
#   ahead    proposes a version newer than `main`'s           -> LEFT ALONE
#
# The last one is the direction that matters most. `check-updates.sh` rebuilds that
# branch on its next run, so a delete rule that also swallowed it would throw away an
# update nobody asked it to throw away -- and a check that fires on healthy work is
# worse than no check.
#
# The first two are the regression. Both branches read as "not green yet: no run"
# once their check runs age out, and both used to be answered with "check-updates.sh
# rebuilds it next run", which for these two shapes is a promise nothing keeps: that
# script exits at "<name>: <version> is current" before it reaches the rebuild.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
# Overridable so the same cases can be run against another copy of the script -- the
# one from before a change, to see a case go red for the reason it claims to.
script="${LAND_UPDATES:-$root/tools/land-updates.sh}"

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

origin="$work/origin.git"
repo="$work/repo"
git init -q --bare -b main "$origin"
git init -q -b main "$repo"
cd "$repo"
git remote add origin "$origin"

# The one file an update is allowed to touch, in the shape `check-updates.sh`
# rewrites: a couple of values, of which VERSION is the one read here.
pin() {
	mkdir -p "packages/$1"
	printf 'REPO="example/%s"\nKIND="manifest"\nVERSION="%s"\nTAG="v%s"\n' \
		"$1" "$2" "${2%-r*}" >"packages/$1/upstream.sh"
}
save() { git add -A && git commit -q -m "$1"; }

pin alpha 1.0.0-r1
pin beta 1.0.0-r1
pin gamma 1.0.0-r1
pin delta 1.0.0-r1
save "packages: initial pins"
base="$(git rev-parse HEAD)"
git push -q origin main

# Three branches built on that head, each one bump, exactly what the bot pushes.
for spec in alpha-1.2.0 beta-1.5.0 delta-3.0.0; do
	name="${spec%-*}"
	version="${spec##*-}"
	git checkout -q -b "update/$spec" "$base"
	pin "$name" "$version-r1"
	save "$name: 1.0.0 -> $version"
	git push -q origin "update/$spec"
done

# `main` then moves, past two of them. It takes alpha 1.2.0 by another route, which
# leaves that branch spent -- the same bytes, a different commit -- and it goes to
# beta 2.0.0, which leaves that branch a downgrade. Neither can fast-forward, and
# `main` differs from both in a file neither branch touched, which is why the check
# is on what the branch changed rather than on the two trees.
git checkout -q main
pin alpha 1.2.0-r1
# A different message on purpose. With the same message, the same parent and the
# same second, git writes the same commit object as the branch has -- the branch
# would then be an ancestor of `main` and the interesting case would not be built.
save "alpha: 1.2.0, landed by another route"
pin beta 2.0.0-r1
save "beta: 1.0.0 -> 2.0.0"
git push -q origin main
before="$(git rev-parse HEAD)"

# And one ordinary branch on the current head, the case that must still land.
git checkout -q -b update/gamma-1.1.0 main
pin gamma 1.1.0-r1
save "gamma: 1.0.0 -> 1.1.0"
git push -q origin update/gamma-1.1.0
gamma="$(git rev-parse HEAD)"
git checkout -q main

GH_STATE="$work/state"
export GH_STATE
mkdir -p "$GH_STATE"

# Stand-in for gh(1). It answers the three calls the script makes, already filtered
# the way the real `-q` expression filters them, and fails on anything else: a call
# this stub silently swallowed would be a call the test is not exercising.
cat >"$work/gh" <<'STUB'
#!/bin/sh
set -eu
case "${1:-} ${2:-}" in
"pr list")
	# gh pr list -R <repo> --head <branch> --state open ...
	#
	# No pull request is open unless `pr-open` names the branch. A call that
	# FAILS must never read as "none is open": `pr-list-fails` makes it fail for
	# the branch it names, or for every branch when it is empty.
	head=""
	prev=""
	for a in "$@"; do
		[ "$prev" != "--head" ] || head="$a"
		prev="$a"
	done
	if [ -f "$GH_STATE/pr-list-fails" ] &&
		{ [ ! -s "$GH_STATE/pr-list-fails" ] || [ "$(cat "$GH_STATE/pr-list-fails")" = "$head" ]; }; then
		echo "HTTP 502: Bad Gateway" >&2
		exit 1
	fi
	if [ -f "$GH_STATE/pr-open" ] && [ "$(cat "$GH_STATE/pr-open")" = "$head" ]; then
		echo 42
	fi
	;;
"api "*"/git/matching-refs/heads/update/")
	cat "$GH_STATE/refs"
	;;
"api "*"/check-runs"*)
	if [ -f "$GH_STATE/checks-pending" ]; then
		printf 'in_progress/pending\tcheck / build\nqueued/pending\tcheck / check\n'
	else
		printf 'completed/success\tcheck / build\ncompleted/success\tcheck / check\n'
	fi
	;;
*)
	echo "stub gh: unexpected call: $*" >&2
	exit 1
	;;
esac
STUB
mkdir -p "$work/bin"
mv "$work/gh" "$work/bin/gh"
chmod +x "$work/bin/gh"

# What `matching-refs` would answer: "<sha> <ref>", one per line, sorted the way the
# API sorts it. `tr` because ls-remote separates with a tab and `gh -q` with a space.
listing() { git ls-remote --heads origin 'update/*' | tr '\t' ' ' >"$GH_STATE/refs"; }

status=0
run() {
	status=0
	PATH="$work/bin:$PATH" GITHUB_REPOSITORY="owfeed/test" sh "$script" >"$1" 2>&1 || status=$?
	sed 's/^/     | /' "$1"
}

# The run's colour, both ways. Only a step that could not run is red; every ordinary
# reason not to land is green, or the scheduled job is red on a normal hour and
# nobody reads it any more.
green() {
	if [ "$status" = 0 ]; then ok "the run exits 0: $1"; else no "the run exited $status: $1 is not a failure"; fi
}
red() {
	if [ "$status" != 0 ]; then ok "the run is red: $1"; else no "the run exited 0 although $1"; fi
}

logged() {
	if grep -qF "$2" "$1"; then
		ok "said: $2"
	else
		no "never said: $2"
	fi
}
gone() {
	if [ -n "$(git ls-remote --heads origin "$1")" ]; then
		no "$1 is still on the remote"
	else
		ok "$1 deleted"
	fi
}
kept() {
	if [ -n "$(git ls-remote --heads origin "$1")" ]; then
		ok "$1 left alone"
	else
		no "$1 was deleted and should not have been"
	fi
}

echo "--- first run"
listing
run "$work/out"
green "branches deleted, landed and waiting for a rebuild"

gone update/alpha-1.2.0
logged "$work/out" "update/alpha-1.2.0: every file it touches already matches main; deleting it"

gone update/beta-1.5.0
logged "$work/out" "update/beta-1.5.0: it proposes 1.5.0-r1, behind the 2.0.0-r1 main publishes; deleting it"

gone update/gamma-1.1.0
logged "$work/out" "update/gamma-1.1.0: landed on main ($gamma)"

kept update/delta-3.0.0
logged "$work/out" "update/delta-3.0.0: main moved ahead of it; check-updates.sh rebuilds it next run"

# The landing is a fast-forward of `main` onto the green branch, and nothing else
# moved: a delete that had gone through the push path instead would have rolled
# beta's pin back to 1.5.0, which is the failure worth naming explicitly.
head="$(git ls-remote origin refs/heads/main | cut -f1)"
if [ "$head" = "$gamma" ]; then
	ok "main is the green branch's commit"
else
	no "main is $head, expected $gamma (it was $before)"
fi
git fetch -q origin "+refs/heads/main:refs/remotes/origin/main"
beta="$(git show refs/remotes/origin/main:packages/beta/upstream.sh |
	sed -n 's/^VERSION="\([^"]*\)".*/\1/p')"
if [ "$beta" = "2.0.0-r1" ]; then
	ok "beta's pin still reads 2.0.0-r1"
else
	no "beta's pin reads $beta, so something landed a downgrade"
fi

# Convergence is the whole point: an hour later the job has one branch to talk
# about, not four. Before this fix the count never went down.
echo "--- second run"
listing
run "$work/out2"
green "a branch main moved ahead of"
lines="$(wc -l <"$work/out2" | tr -d ' ')"
if [ "$lines" = 1 ] && grep -q '^update/delta-3.0.0: ' "$work/out2"; then
	ok "the second run reports only the branch that is waiting for a rebuild"
else
	no "the second run reports $lines line(s); it should report delta and nothing else"
fi

# FAILURES THAT MUST NOT LAND OR DELETE. `land` runs as the left side of `|| echo`,
# and POSIX switches errexit off for every command inside it, so a step that fails
# carries on with an empty answer unless it checks its own status. Each empty answer
# below is the one that does damage: no pull request (push past a person), nothing
# changed (delete the branch), refs that were never refreshed (push on stale state).
#
# One green, landable branch throughout, re-pushed before each run so a case does not
# depend on how the previous one ended. The last run lands it with nothing failing,
# which is what makes "it was kept" mean the failure kept it.
git checkout -q -b update/gamma-1.2.0 refs/remotes/origin/main
pin gamma 1.2.0-r1
save "gamma: 1.1.0 -> 1.2.0"
gamma2="$(git rev-parse HEAD)"
git checkout -q main
offer() { git push -q origin "$gamma2:refs/heads/update/gamma-1.2.0"; }

unmoved() {
	head="$(git ls-remote origin refs/heads/main | cut -f1)"
	if [ "$head" = "$gamma" ]; then
		ok "main did not move"
	else
		no "main moved to $head; it had to stay at $gamma"
	fi
}

# A git that refuses one kind of call, for the run that sets the flag. Only the
# script under test sees it: run() is the one place $work/bin goes on PATH.
realgit="$(command -v git)"
cat >"$work/bin/git" <<SHIM
#!/bin/sh
if [ -f "\$GH_STATE/git-fails" ]; then
	want="\$(cat "\$GH_STATE/git-fails")"
	case " \$* " in
	*" \$want "*)
		echo "fatal: stub git refused: git \$*" >&2
		exit 128
		;;
	esac
fi
exec "$realgit" "\$@"
SHIM
chmod +x "$work/bin/git"

echo "--- third run: gh pr list fails"
offer
: >"$GH_STATE/pr-list-fails"
listing
run "$work/out3"
rm -f "$GH_STATE/pr-list-fails"
red "gh pr list failed"
kept update/gamma-1.2.0
unmoved
logged "$work/out3" "update/gamma-1.2.0: could not read its pull requests"

echo "--- fourth run: git diff --name-only fails"
offer
echo "--name-only" >"$GH_STATE/git-fails"
listing
run "$work/out4"
rm -f "$GH_STATE/git-fails"
red "git diff failed"
kept update/gamma-1.2.0
kept update/delta-3.0.0
unmoved
logged "$work/out4" "cannot tell what"
logged "$work/out4" "update/delta-3.0.0: main moved ahead of it"

echo "--- fifth run: git fetch fails"
offer
echo "fetch" >"$GH_STATE/git-fails"
listing
run "$work/out5"
rm -f "$GH_STATE/git-fails"
red "git fetch failed"
kept update/gamma-1.2.0
unmoved
logged "$work/out5" "update/gamma-1.2.0: could not fetch"

# One branch fails and the one after it is still read. delta sorts first, so gamma
# landing is the proof the loop went on -- and that the branch kept by every failure
# above was landable all along.
echo "--- sixth run: gh pr list fails for the first branch only"
offer
echo update/delta-3.0.0 >"$GH_STATE/pr-list-fails"
listing
run "$work/out6"
rm -f "$GH_STATE/pr-list-fails"
red "one branch could not be read"
logged "$work/out6" "update/delta-3.0.0: could not read its pull requests"
logged "$work/out6" "not landed because a step failed: update/delta-3.0.0"
head="$(git ls-remote origin refs/heads/main | cut -f1)"
if [ "$head" = "$gamma2" ]; then
	ok "the branch after the failure was still read, and landed"
else
	no "main is $head, expected $gamma2: the loop stopped at the failure, or the branch was not landable"
fi

# The ordinary reasons not to land stay green.
echo "--- seventh run: checks still running"
: >"$GH_STATE/checks-pending"
listing
run "$work/out7"
rm -f "$GH_STATE/checks-pending"
green "checks still running"
logged "$work/out7" "update/delta-3.0.0: not green yet"
kept update/delta-3.0.0

echo "--- eighth run: a pull request is open"
echo update/delta-3.0.0 >"$GH_STATE/pr-open"
listing
run "$work/out8"
rm -f "$GH_STATE/pr-open"
green "a pull request waiting for a person"
logged "$work/out8" "update/delta-3.0.0: pull request #42 is open"
kept update/delta-3.0.0

if [ "$result" = 0 ]; then
	echo "PASS"
else
	echo "FAILED"
fi
exit "$result"
