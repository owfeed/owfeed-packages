#!/bin/sh
# Fast-forward `main` onto the update branches whose checks have already gone green.
#
# The other half of `tools/check-updates.sh`. That script finds a new upstream
# release, pushes `update/<package>-<version>` and dispatches the checks on it; this
# one picks the branch up on a later run and pushes its commit onto `main`.
#
# WHY THERE IS NO PULL REQUEST TO MERGE. Do not "fix" this by changing an approval
# policy -- the policies were measured, twice, and they are not the cause.
#
# GitHub holds the `pull_request` run of a pull request a bot opened: "when a
# workflow using `GITHUB_TOKEN` creates or updates a pull request, the resulting
# `pull_request` event creates workflow runs in an approval-required state". It
# applies to a branch in this repository, not only to a fork, and it reached this
# organisation between 2026-08-30 20:43Z and 2026-09-01 10:08Z -- measured on
# `attempts/1` of the runs on the `update/*` branches either side of that window.
# `fork-pr-contributor-approval` is not it: relaxed to
# `first_time_contributors_new_to_github` at repository and organisation level at the
# same time, the bot's #60 still came back `attempt 1 = action_required` (run
# 33966648498). Both policies were put back.
#
# Removing the pull request removes the hold, and THIS SCRIPT is what keeps the
# checks. Required status checks on `main` were tried for that and removed again:
# with both contexts green on the commit, the push was still refused with "GH006: 2
# of 2 required status checks are expected", because GitHub counts contexts for the
# branch being pushed to rather than for the branch they ran on. So the gate below is
# the whole gate -- every run of both contexts completed/success, no run at all read
# as a refusal, and a path check GitHub never offered.
#
# It waits for nothing. A branch whose checks are still running is left alone and
# read again on a later run, the same shape as `update.yml`'s publish job:
# idempotent, cheap, and correct whether it runs once or twenty times.
set -eu

# Which repository this is, resolved once and named on every `gh` call below. The job
# that runs this has a checkout, but `gh` deciding the repository from `git remote`
# is how the publish job in `update.yml` failed its first run, and a call that has to
# guess is a call that can guess a different repository.
SELF="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

# The contexts this script requires before it pushes, spelled exactly as the check
# runs report them: `pr.yml`'s job is `check` and it calls owfeed's reusable `feed.yml`,
# whose jobs are `build` and `check`, so each name is "<caller job> / <called job>".
# Rename a job in either file and this list has to move with it -- a name that never
# matches reads as "no run" below, which stops everything landing rather than letting
# anything through.
REQUIRED='check / build
check / check'

# Paths an update is allowed to touch, and the reason this script exists at all as
# something separate from a merge button.
#
# `owfeed-packages never lands a diff touching keys/, tools/, .github/ or
# owfeed.yml without a person` (ECOSYSTEM.md, §Invariants). CODEOWNERS states the same rule as a
# review requirement, but CODEOWNERS is not consulted by a push -- so with no pull
# request in the path, THIS is what keeps it true. A new package arrives with a key
# this feed has never pinned, which is a diff under `keys/`; an update to a package
# already carried is one `packages/<name>/upstream.sh` and nothing else.
#
# `check-updates.sh` already refuses to commit anything but pins INSIDE that file.
# This is the coarser gate, on paths rather than on lines, and both are wanted: that
# one trusts its own sed, this one trusts nothing about how the branch was built.
ALLOWED='^packages/[^/]*/upstream\.sh$'

# Compare two dotted versions. Exit 0 when the first is strictly older than the
# second, non-zero for every other answer INCLUDING "these cannot be ordered".
#
# Only plain dotted numbers are ordered. An upstream that versions `1.0-rc2` or by
# date is not something to guess at when the answer decides whether a branch is
# deleted, so anything else falls through to "not older" and the branch survives.
version_older() {
	awk -v a="$1" -v b="$2" 'BEGIN {
		na = split(a, x, "."); nb = split(b, y, ".")
		n = na > nb ? na : nb
		for (i = 1; i <= n; i++) {
			if (x[i] !~ /^[0-9]*$/ || y[i] !~ /^[0-9]*$/) exit 2
			if (x[i] + 0 < y[i] + 0) exit 0
			if (x[i] + 0 > y[i] + 0) exit 1
		}
		exit 1
	}'
}

# Print why this branch has nothing left to offer, or print nothing.
#
# Two ways that happens, and both end in the same sweep:
#
#   its work is in `main` already -- every file it touched now matches `main`;
#   `main` has moved past it -- it proposes a version older than the published one,
#   which is not a pending update but a rollback, and must never land.
#
# Asked of the files the BRANCH changed since it left `main`, never of the two trees.
# `main` moving on another package is ordinary, and a tree diff would blame this
# branch for those files and keep it alive forever.
#
# Every uncertain answer is "keep": a wrong deletion loses work, a wrong keep costs
# one line in a scheduled run's log.
superseded() {
	_sha="$1"

	_base="$(git merge-base "refs/remotes/origin/main" "$_sha" 2>/dev/null || true)"
	[ -n "$_base" ] || return 0
	_own="$(git diff --name-only "$_base..$_sha")"
	[ -n "$_own" ] || { echo "it adds nothing on top of where it left main"; return 0; }

	# One `git diff` per path, not one call with the whole list: an unquoted list
	# splits a path containing a space into two pathspecs, and a pathspec matching
	# nothing answers "no difference" -- which here would read as spent and delete
	# a branch that was not.
	_differs=no
	_ifs="$IFS"
	IFS='
'
	for _f in $_own; do
		if ! git diff --quiet "refs/remotes/origin/main..$_sha" -- "$_f"; then
			_differs=yes
			break
		fi
	done
	IFS="$_ifs"
	[ "$_differs" = yes ] || { echo "every file it touches already matches main"; return 0; }

	# It still differs. The one remaining sweep is the rollback: a single pin file
	# naming a version older than the one `main` publishes. Read out of the file
	# rather than out of the branch name, because the file is what would land.
	[ "$(printf '%s\n' "$_own" | wc -l | tr -d ' ')" = 1 ] || return 0
	printf '%s\n' "$_own" | grep -q "$ALLOWED" || return 0

	_theirs="$(git show "$_sha:$_own" 2>/dev/null | sed -n 's/^VERSION="\([^"]*\)".*/\1/p')"
	_ours="$(git show "refs/remotes/origin/main:$_own" 2>/dev/null | sed -n 's/^VERSION="\([^"]*\)".*/\1/p')"
	[ -n "$_theirs" ] && [ -n "$_ours" ] || return 0

	# `-r1` is this feed's packaging revision, not upstream's version, and it is
	# not what makes an update a rollback.
	version_older "${_theirs%-r*}" "${_ours%-r*}" || return 0
	echo "it proposes $_theirs, behind the $_ours main publishes"
}

# Land one branch, or say why not and return. Never fails the run: one branch that
# cannot land must not stop the next one, and none of the reasons below is an error
# in the first place -- a check still running, a `main` that moved, a human's branch
# that is none of this script's business.
land() {
	branch="$1"
	sha="$2"

	# An open pull request means a person is the gate for this one: either
	# `check-updates.sh` judged the update untrusted, or somebody opened it by
	# hand. Merging it from here would route around exactly the review that
	# opening it asked for.
	#
	# Captured, never piped into a test: a pipeline reports its last command, so a
	# failing `gh pr list` reaching `grep` reads as "no pull request is open" --
	# the one answer that makes this script push.
	pr="$(gh pr list -R "$SELF" --head "$branch" --state open --json number -q '.[0].number')"
	if [ -n "$pr" ]; then
		echo "$branch: pull request #$pr is open; a person merges that one"
		return 0
	fi

	# Is there anything left in this branch at all? Asked BEFORE the checks,
	# deliberately: a branch with nothing to land does not need green contexts to
	# be swept up, and asking in the other order strands the oldest branches
	# forever. Measured -- `update/luci-theme-footstrap-0.11.7` and `-0.12.9` were
	# reported "not green yet" on every scheduled run for weeks, each proposing a
	# version this feed had passed long ago, because no run had ever been
	# dispatched on them and the sweep sat behind that verdict.
	if reason="$(superseded "$sha")" && [ -n "$reason" ]; then
		echo "$branch: $reason; deleting it"
		git push -q origin ":refs/heads/$branch" ||
			echo "  branch not deleted; harmless, the next run tries again"
		return 0
	fi

	# What the required contexts say about THIS commit. Check runs bind to a
	# commit rather than to an event, so the run `check-updates.sh` dispatched on
	# the branch reports against the same sha that is about to be pushed.
	checks="$(gh api "repos/$SELF/commits/$sha/check-runs?per_page=100" \
		-q '.check_runs[] | "\(.status)/\(.conclusion // "pending")\t\(.name)"')"

	# Every run of a required name has to be completed and successful, not just
	# the newest one. A cancelled run stays on the commit and GitHub has been
	# measured counting it -- on #49 a green dispatch and the cancelled run it
	# superseded read as `check / build fail`. Being stricter here than the push
	# is deliberate: the failure it produces is a branch that waits and says so,
	# and the recovery is in RUNBOOK.md -- delete the branch, a later run
	# rebuilds it and dispatches a clean set of runs.
	#
	# One awk per context, each told the name through `-v` as a plain string.
	# Passing the whole list in one variable was tried and is a trap: BSD awk
	# refuses a newline inside `-v` ("newline in string"), the awk exits non-zero,
	# the substitution comes back EMPTY -- and empty reads as "nothing is wrong",
	# which landed a branch whose checks had not started. Every failure below has
	# to fall the other way: no output from awk means no state was seen, which is
	# "no run", which does not land.
	verdict="$(printf '%s\n' "$REQUIRED" | while IFS= read -r ctx; do
		states="$(printf '%s\n' "$checks" | awk -F'\t' -v n="$ctx" '$2 == n { print $1 }')"
		if [ -z "$states" ]; then
			echo "$ctx: no run"
			continue
		fi
		printf '%s\n' "$states" | grep -v '^completed/success$' | sed "s|^|$ctx: |" || true
	done)"
	if [ -n "$verdict" ]; then
		echo "$branch: not green yet"
		printf '%s\n' "$verdict" | sed 's/^/  /'
		return 0
	fi

	# `main` is read per branch, not once per run: an earlier branch in this same
	# loop may already have landed, and the fast-forward test below has to be
	# against where `main` is now rather than where it was when the job started.
	git fetch -q origin "+refs/heads/main:refs/remotes/origin/main"
	git fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch"
	head="$(git rev-parse "refs/remotes/origin/$branch")"
	if [ "$head" != "$sha" ]; then
		# The branch moved between the listing and the fetch. The green contexts
		# were reported for $sha and say nothing about $head, so this one waits
		# for the next run rather than pushing bytes nothing has checked.
		echo "$branch: moved while this ran ($sha -> $head); it waits for the next run"
		return 0
	fi

	# Fast-forward only. `main` having moved is ordinary -- a human merged
	# something while this branch was in the checks -- and rebasing is not this
	# script's job: `check-updates.sh` sees that the branch no longer
	# fast-forwards, rebuilds it on the current `main` and dispatches the checks
	# again, against what would actually be published.
	#
	# Asked BEFORE the path gate below, and that order is not cosmetic.
	# `git diff main..branch` also lists what `main` gained and the branch never
	# had, so a branch that merely predates a human commit reported THAT commit's
	# file as a path violation -- measured in the dry run, where an ordinary race
	# printed "REFUSED" and named a file the branch had never touched. With the
	# fast-forward established first, the list below is exactly what this branch
	# adds on top of `main`.
	# Behind `main` and still carrying something `main` does not have: an ordinary
	# race, and rebasing is not this script's job. `check-updates.sh` sees the
	# branch no longer fast-forwards, rebuilds it on the current `main` and
	# dispatches the checks again, against what would actually be published.
	#
	# A branch behind `main` with nothing left in it never reaches here -- the
	# sweep above deleted it.
	if ! git merge-base --is-ancestor "refs/remotes/origin/main" "$sha"; then
		echo "$branch: main moved ahead of it; check-updates.sh rebuilds it next run"
		return 0
	fi

	# THE PATH GATE. Everything above proves the tree builds, indexes, passes
	# doctor and installs on a real image. None of that is an argument for
	# letting an unattended job rewrite `keys/`, `tools/` or `.github/` -- the
	# checks would be just as green for a branch that repointed a pinned key or
	# edited the workflow that decides what runs. A new package needs a person
	# and this is where that stays true.
	# An empty list never reaches here either -- the sweep above catches it and
	# deletes the branch. Kept as a guard rather than as a branch of logic: an
	# empty `files` would make the pattern check below vacuously true, and "no
	# paths to object to" must never read as "allowed".
	files="$(git diff --name-only "refs/remotes/origin/main..$sha")"
	if [ -z "$files" ]; then
		echo "$branch: nothing to land against main"
		return 0
	fi
	stray="$(printf '%s\n' "$files" | grep -v "$ALLOWED" || true)"
	if [ -n "$stray" ]; then
		echo "$branch: REFUSED -- an update may only touch packages/<name>/upstream.sh"
		printf '%s\n' "$stray" | sed 's/^/  /'
		echo "  this branch needs a pull request and a person; nothing was pushed"
		return 0
	fi

	# GitHub still has the last word on the shape of the push: `main` refuses a
	# non-fast-forward whatever this checkout believed a moment ago. It says
	# nothing about the contexts -- no required status check is configured on
	# `main`, for the reason at the head of this file -- so a race is the only
	# thing left to lose here, and losing it means the branch waits.
	if git push -q origin "$sha:refs/heads/main"; then
		echo "$branch: landed on main ($sha)"
		# Delete it, or the next run reads it again and reports "no change
		# against main" forever. Not fatal if it fails: that message is noise,
		# not a wrong merge.
		git push -q origin ":refs/heads/$branch" ||
			echo "  branch not deleted; harmless, the next run finds nothing to land on it"
	else
		echo "$branch: push refused (main moved under it); it waits for the next run"
	fi
}

# `matching-refs` rather than `gh pr list`: these branches have no pull request, and
# it answers with the head sha in the same call, so nothing is read twice from a
# repository that may change between calls. An empty result is `[]` and a normal day.
refs="$(gh api "repos/$SELF/git/matching-refs/heads/update/" \
	-q '.[] | "\(.object.sha) \(.ref)"')"
if [ -z "$refs" ]; then
	echo "no update branches"
	exit 0
fi

# `|| echo` on the call, not `set +e` around the loop: an unexpected failure inside
# `land` -- a `gh` outage, a git object that is not there -- must cost that one
# branch and not every branch after it. Under plain `set -eu` the first one would
# take the job down with the rest unread, which is the failure mode this repository
# keeps re-learning (see the `checkout -` note in check-updates.sh).
printf '%s\n' "$refs" | while read -r sha ref; do
	branch="${ref#refs/heads/}"
	land "$branch" "$sha" || echo "$branch: not landed this run (the step above failed)"
done
