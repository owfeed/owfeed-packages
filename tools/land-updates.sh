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
# Removing the pull request removes the hold and keeps the checks. Branch protection
# is enforced on `main` rather than on a pull request, and GitHub documents the push
# path through it: "After all required status checks pass, any commits must either be
# pushed to another branch and then merged or pushed directly to the protected
# branch". A push whose required contexts are not green is refused with GH006, so
# `main` is guarded by the same two contexts a merge would have had to satisfy --
# with GitHub, not this script, as the last word.
#
# It waits for nothing. A branch whose checks are still running is left alone and
# read again on the next hourly run, the same shape as `update.yml`'s publish job:
# idempotent, cheap, and correct whether it runs once or twenty times.
set -eu

# Which repository this is, resolved once and named on every `gh` call below. The job
# that runs this has a checkout, but `gh` deciding the repository from `git remote`
# is how the publish job in `update.yml` failed its first run, and a call that has to
# guess is a call that can guess a different repository.
SELF="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

# The contexts `main`'s branch protection requires, spelled exactly as the check runs
# report them: `pr.yml`'s job is `check` and it calls owfeed's reusable `feed.yml`,
# whose jobs are `build` and `check`, so each name is "<caller job> / <called job>".
# Rename a job in either file and this list has to move with it -- a name that never
# matches reads as "no run" below, which stops everything landing rather than letting
# anything through.
REQUIRED='check / build
check / check'

# Paths an update is allowed to touch, and the reason this script exists at all as
# something separate from a merge button.
#
# `owfeed-packages never auto-merges a diff touching keys/, tools/, .github/ or
# owfeed.yml` (ECOSYSTEM.md, §Invariants). CODEOWNERS states the same rule as a
# review requirement, but CODEOWNERS is not consulted by a push -- so with no pull
# request in the path, THIS is what keeps it true. A new package arrives with a key
# this feed has never pinned, which is a diff under `keys/`; an update to a package
# already carried is one `packages/<name>/upstream.sh` and nothing else.
#
# `check-updates.sh` already refuses to commit anything but pins INSIDE that file.
# This is the coarser gate, on paths rather than on lines, and both are wanted: that
# one trusts its own sed, this one trusts nothing about how the branch was built.
ALLOWED='^packages/[^/]*/upstream\.sh$'

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
	# and the recovery is in RUNBOOK.md -- delete the branch, the next hourly run
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
	files="$(git diff --name-only "refs/remotes/origin/main..$sha")"
	if [ -z "$files" ]; then
		# Already in `main`, byte for byte: the branch is spent, not pending.
		# Deleting it is the whole point -- left alone it comes back every hour,
		# reads "nothing to land" forever, and buries the branches that do need
		# looking at. Measured: `0.1.3` landed and was immediately rebuilt on a
		# stale head by the same run, leaving exactly such a branch behind.
		echo "$branch: already in main; deleting the spent branch"
		git push -q origin ":refs/heads/$branch" ||
			echo "  branch not deleted; harmless, the next run tries again"
		return 0
	fi
	stray="$(printf '%s\n' "$files" | grep -v "$ALLOWED" || true)"
	if [ -n "$stray" ]; then
		echo "$branch: REFUSED -- an update may only touch packages/<name>/upstream.sh"
		printf '%s\n' "$stray" | sed 's/^/  /'
		echo "  this branch needs a pull request and a person; nothing was pushed"
		return 0
	fi

	# The push is the real gate, not this script. GitHub re-evaluates the required
	# contexts and refuses with GH006 if they do not hold, and refuses a
	# non-fast-forward whatever this checkout believed a moment ago. Both are
	# ordinary outcomes of a race, so they are reported and the branch waits.
	if git push -q origin "$sha:refs/heads/main"; then
		echo "$branch: landed on main ($sha)"
		# Delete it, or the next run reads it again and reports "no change
		# against main" forever. Not fatal if it fails: that message is noise,
		# not a wrong merge.
		git push -q origin ":refs/heads/$branch" ||
			echo "  branch not deleted; harmless, the next run finds nothing to land on it"
	else
		echo "$branch: push refused (main moved, or GitHub still counts a context red); it waits for the next run"
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
