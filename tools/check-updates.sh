#!/bin/sh
# Notice new upstream releases and land them: straight onto `main` when the package
# file says somebody other than this feed vouches for the bytes, as a pull request
# when it does not.
#
# It never publishes and it never signs. This feed's key is a trust anchor for every
# package name on every subscriber's router, so a job that fetched whatever an
# upstream pushed in the last hour and signed it would hand that authority to every
# upstream at once. The checksum pins would stop meaning anything too: recomputed
# from whatever arrived, they would attest to nothing.
#
# What carries the evidence is the branch, either way: a diff containing a version
# and its checksums and nothing else, and a run that builds, indexes, checks and
# installs the result on a real OpenWrt image before anything reaches `main`.
#
# WHY A TRUSTED UPDATE OPENS NO PULL REQUEST. Read this before "fixing" an approval
# policy: the policies were measured, twice, and they are not the cause.
#
# GitHub holds the `pull_request` run of a pull request a bot opened -- "when a
# workflow using `GITHUB_TOKEN` creates or updates a pull request, the resulting
# `pull_request` event creates workflow runs in an approval-required state" -- and
# it applies to a branch in this repository, not only to a fork. It reached this
# organisation between 2026-08-30 20:43Z and 2026-09-01 10:08Z, measured on
# `attempts/1` of the runs on the `update/*` branches either side of that window.
# `fork-pr-contributor-approval` is not it: relaxed to
# `first_time_contributors_new_to_github` at repository and organisation level at
# the same time, the bot's #60 still came back `attempt 1 = action_required` (run
# 33966648498). Both policies were put back.
#
# With required checks on `main`, a held run is a pull request that cannot merge
# itself, so every automatic update waited for a person -- issue #53.
#
# No pull request, no `pull_request` event, nothing to hold. The checks do not go
# away with it, because branch protection is enforced on `main` and not on the pull
# request: GitHub documents the push path through it -- "After all required status
# checks pass, any commits must either be pushed to another branch and then merged
# or pushed directly to the protected branch" -- and a push whose contexts are not
# green is rejected with GH006. So this script pushes the update branch and
# dispatches the checks on it, and `tools/land-updates.sh` fast-forwards `main` onto
# that commit on a later run, once `check / build` and `check / check` are green.
#
# What did NOT change is which updates may do that. `may_automerge()` below is the
# same set of conditions it was when it armed GitHub's auto-merge.
set -eu

# Which repository this is, resolved once and named on every `gh` call below. `gh`
# falls back to `git remote` to decide that, which is how the neighbouring job in
# `update.yml` failed its first run -- and a call that has to guess is a call that
# can guess a different repository than the one this checkout came from.
SELF="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

# may_automerge <upstream.sh> <current version> <latest version> <package name>
#
# A signature says the author published these bytes. It does not say the release is
# one this feed should carry without anybody reading it, and the cases where that
# gap matters are cheap to name.
#
# What a package is allowed depends on what its signature covers, not on how much
# its author tried. A manifest is signed over the whole inventory -- every file,
# every size, every hash -- so an update is mechanical and nothing here has to be
# transcribed. Finished artifacts are each signed, but the list of them is not, so
# a change in what a release ships is a change nothing vouches for. Unsigned
# binaries are vouched for by nobody at all.
may_automerge() {
	_up="$1"; _cur="$2"; _new="$3"; _name="$4"

	# The package has to ask, in its own file, and the file is reviewed by a person
	# when it lands.
	if [ "${AUTO_MERGE:-no}" != "yes" ]; then
		echo "  AUTO_MERGE is not yes"
		return 1
	fi

	# Nothing merges itself on the strength of a download completing.
	if [ -z "${SIG_KEY:-}" ]; then
		echo "  no SIG_KEY: nobody but the transport vouches for these bytes"
		return 1
	fi

	case "$KIND" in
	manifest)
		: ;;
	apk)
		# Tier B. The per-asset signatures do not cover the set of assets, so a
		# release that starts or stops shipping a container is a change in what the
		# package IS, and the signatures would still verify. The pin rewrite above
		# fails loudly when a named artifact is missing; this refuses the quieter
		# case, where the file set changed in a way that still resolves.
		if [ -n "${ARTIFACT_IPK:-}" ] && ! grep -q '^ARTIFACT_IPK=' "$_up"; then
			echo "  the ipk container disappeared from this upstream.sh"
			return 1
		fi
		;;
	*)
		echo "  KIND=$KIND carries no signature over anything: this needs a person"
		return 1
		;;
	esac

	# A ceiling, because the failure this guards against is not one bad release but
	# a run of them: an upstream whose key is stolen can publish a chain of versions
	# faster than anyone reads the notifications, and every one of them verifies.
	# Two in a day is already unusual for a package; the third waits for a human.
	# Only this job's own commits count. Counting every commit that touched the file
	# counts the one that added the package, and every hand edit to it since --
	# which in a young repository is enough to refuse the first real update.
	_recent="$(git log --since='24 hours ago' --author='owfeed-bot' --oneline -- "$_up" | wc -l | tr -d ' ')"
	if [ "$_recent" -ge 2 ]; then
		echo "  $_recent automatic updates to $_name in the last day: the next one wants a person"
		return 1
	fi

	# A major bump is where upstream changes what the package is: dropped
	# architectures, renamed files, a configuration format that no longer matches
	# what is on the routers running the old one. Whatever it turns out to be, it is
	# not a decision to make at 04:00 with nobody watching.
	if [ "${_cur%%.*}" != "${_new%%.*}" ]; then
		echo "  major version change ${_cur%%.*} -> ${_new%%.*}: this one wants a person"
		return 1
	fi

	# Nothing but the pins may have moved. This job rewrites values with sed, so a
	# changed line anywhere else means either a bug here or an upstream.sh that was
	# edited between the checkout and now -- and SIG_KEY_ID moving would be the
	# whole verification quietly relaxing itself.
	_bad="$(git diff -U0 -- "$_up" \
		| grep -E '^[+-][^+-]' \
		| grep -vE '^[+-](VERSION|TAG|ARTIFACT|ARTIFACT_IPK|SHA256|SHA256_IPK)=' \
		| grep -vE '^[+-][a-zA-Z0-9_.-]+ +[0-9a-f]{64} +' || true)"
	if [ -n "$_bad" ]; then
		echo "  the diff touches more than the pins, so it is not merging itself:"
		echo "$_bad" | sed 's/^/    /'
		return 1
	fi
	return 0
}

# The branch to return to after each package, taken by name rather than by history.
# `git checkout -` is `@{-1}`, which needs a branch switch recorded in the HEAD
# reflog. In the clone the job works in that record is not there, so the first
# `checkout -b` of a run leaves nothing to go back to and `-` is read as a pathspec:
#
#   error: pathspec '-' did not match any file(s) known to git
#
# Under `set -e` that failed the run after the pull request was already open -- which
# reads as "no update was found" -- and skipped every package after this one.
# Reproduced by emulating the job's clone with `core.logAllRefUpdates false`; a plain
# local `git checkout -b x` does write the reflog and does not show it.
BASE="$(git rev-parse --abbrev-ref HEAD)"

for up in packages/*/upstream.sh; do
	dir="$(dirname "$up")"
	name="$(basename "$dir")"

	# A subshell per package: one package's variables never leak into the next.
	(
		. "./$up"
		current="${VERSION%-r*}"
		latest="$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null | sed 's/^v//')"

		[ -n "$latest" ] || { echo "$name: upstream has no releases"; exit 0; }
		[ "$current" != "$latest" ] || { echo "$name: $current is current"; exit 0; }

		branch="update/${name}-${latest}"

		# Has this update already been proposed? Ask the remote branch, not the
		# pull request list. A trusted update no longer opens one, so
		# `gh pr list --head` would answer "nothing here" every hour and this job
		# would rebuild, force-push and re-dispatch the same update forever --
		# an hourly runner bill and a branch whose checks never finish before they
		# are replaced.
		#
		# Three conditions, and the third is what stops a branch wedging: it
		# exists, it already records this version, and `main` is an ancestor of
		# it. A branch built on a `main` that has since moved can never be
		# fast-forwarded onto it, so calling that one done would leave the update
		# stuck until somebody deleted the branch; rebuilding it is how this
		# converges with nobody looking.
		#
		# The version is the identity here, not the checksums: the branch name
		# carries it and the pins are derived from the release that tag names. An
		# upstream that replaces a release in place is caught where the bytes are
		# read -- `tools/fetch.sh` compares them against the pin -- rather than by
		# downloading ninety assets every hour to compare them with themselves.
		#
		# A failing `git ls-remote` reads as "no branch" and costs a rebuild, not
		# a wrong merge: the push below is `--force-with-lease` and refuses if the
		# branch turns out to be there and moved.
		remote_sha="$(git ls-remote --heads origin "$branch" | cut -f1)"
		if [ -n "$remote_sha" ]; then
			git fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch"
			have="$(git show "refs/remotes/origin/$branch:$up" 2>/dev/null || true)"
			want="VERSION=\"${latest}-r1\""
			case "$have" in
			*"$want"*)
				if git merge-base --is-ancestor HEAD "refs/remotes/origin/$branch"; then
					echo "$name: $branch already carries $latest"
					exit 0
				fi
				echo "$name: $branch carries $latest but predates main: rebuilding it"
				;;
			esac
		fi
		echo "$name: $current -> $latest"

		tmp="$(mktemp -d)"
		trap 'rm -rf "$tmp"' EXIT

		# Only what this shape needs to recompute its pins. A manifest package pins
		# no checksums at all -- they are in the manifest, under the author's
		# signature -- so downloading its ninety-odd assets every hour to look at
		# none of them would be pure waste.
		pattern='*'
		[ "$KIND" = "manifest" ] && pattern='manifest.txt'
		gh release download "v$latest" --repo "$REPO" --dir "$tmp" --pattern "$pattern" >/dev/null

		# Recompute the pins from the bytes the release actually served, rewriting
		# values in place. Nothing but data changes, so the diff is readable.
		sed -i "s|^VERSION=.*|VERSION=\"${latest}-r1\"|" "$up"

		case "$KIND" in
		manifest)
			# The tag is the pin. There are no checksums here to recompute: they are
			# in the manifest, and the author's signature is what makes them worth
			# anything -- which is why this shape can be trusted to merge itself.
			sed -i "s|^TAG=.*|TAG=\"v${latest}\"|" "$up"
			;;
		apk)
			file="$(echo "$ARTIFACT" | sed "s/${current}/${latest}/g")"
			[ -f "$tmp/$file" ] || { echo "$name: v$latest publishes no $file" >&2; exit 1; }
			sed -i "s|^ARTIFACT=.*|ARTIFACT=\"${file}\"|" "$up"
			sed -i "s|^SHA256=.*|SHA256=\"$(sha256sum "$tmp/$file" | cut -d' ' -f1)\"|" "$up"

			# The 24.10 container, when upstream ships one. Leaving it pinned to the
			# previous version does not fail here -- it fails later, when fetch.sh asks
			# the new release for a filename only the old one had, and every automatic
			# update of a package serving both lines arrives broken.
			if [ -n "${ARTIFACT_IPK:-}" ]; then
				file_ipk="$(echo "$ARTIFACT_IPK" | sed "s/${current}/${latest}/g")"
				[ -f "$tmp/$file_ipk" ] || { echo "$name: v$latest publishes no $file_ipk" >&2; exit 1; }
				sed -i "s|^ARTIFACT_IPK=.*|ARTIFACT_IPK=\"${file_ipk}\"|" "$up"
				sed -i "s|^SHA256_IPK=.*|SHA256_IPK=\"$(sha256sum "$tmp/$file_ipk" | cut -d' ' -f1)\"|" "$up"
			fi
			;;
		binaries)
			# Rewrite only the checksum column, so the architecture mapping — which is
			# a human decision about what upstream's builds actually run on — survives
			# untouched.
			echo "$ARTIFACTS" | while read -r artifact _ arches; do
				[ -n "$artifact" ] || continue
				[ -f "$tmp/$artifact" ] || { echo "$name: v$latest publishes no $artifact" >&2; exit 1; }
				printf '%s  %s  %s\n' "$artifact" "$(sha256sum "$tmp/$artifact" | cut -d' ' -f1)" "$arches"
			done > "$tmp/table"
			awk -v table="$(cat "$tmp/table")" '
				/^ARTIFACTS="/ { print; print table; inside = 1; next }
				inside && /^"/ { print; inside = 0; next }
				!inside        { print }
			' "$up" > "$tmp/new" && mv "$tmp/new" "$up"
			;;
		esac

		# Decided here, not after the commit: this reads the working-tree diff, and
		# once committed there is nothing left to read.
		automerge=no
		if may_automerge "$up" "$current" "$latest" "$name"; then
			automerge=yes
		fi

		if [ -n "${SIG_KEY:-}" ]; then
			evidence="Upstream publishes a detached signature; it is verified against the pinned key before this is ingested."
		else
			evidence="Upstream publishes no signature, so the checksums below are all there is. This needs a person."
		fi

		# `-B` rather than `-b`: reaching this line means the branch is being
		# built or rebuilt, and in a clone that already ran this once -- someone
		# running it by hand -- `-b` fails with "a branch named ... already
		# exists" and takes the rest of the packages down with it.
		git checkout -q -B "$branch"
		git commit -q "$up" -m "$name: $current -> $latest

$evidence

Pins recomputed from the bytes the release served."
		# --force-with-lease, because reaching this line means the branch is either
		# absent or stale -- the dedup above returned only for a branch that already
		# carries this version AND still fast-forwards onto `main`. Both other cases
		# need the branch replaced: a run that pushed it and then failed left it
		# behind, and one built on a `main` that has moved can never land. A plain
		# push is a non-fast-forward against either, which would wedge that package's
		# updates until somebody deleted the branch by hand. The branch belongs to
		# this job, its name carries the version and its content is derived from the
		# release, so replacing it loses nothing; the lease still refuses if someone
		# else moved it.
		git push -q -u --force-with-lease origin "$branch"

		# The fork in the road, and the only difference between the two paths.
		#
		# A trusted update gets no pull request: the head of this file records the
		# measurement that makes a bot's pull request unmergeable without a person.
		# The branch is pushed, the checks are dispatched on it below, and
		# `tools/land-updates.sh` fast-forwards `main` onto it on a later run once
		# those checks are green -- through the same required contexts a merge
		# would have had to satisfy.
		#
		# An untrusted update gets exactly what every update used to get: a pull
		# request, a dispatched run, and a maintainer who reads the diff. Nothing
		# about that path is relaxed here, and `may_automerge()` above decides
		# which one this is.
		if [ "$automerge" = "yes" ]; then
			echo "$name: $branch pushed, no pull request; it lands on main once its checks are green"
		else
			# NOT ALLOWED TO FAIL THE RUN. The branch exists by this line and
			# every package after this one still has to be checked. Reported
			# rather than swallowed: an update whose pull request never opened
			# is an update nobody is looking at.
			if url="$(gh pr create -R "$SELF" --title "$name: $current -> $latest" --body "Upstream released \`v$latest\`.

$evidence

The diff is a version and its checksums, recomputed from the bytes the release served. CI builds the
feed, indexes it, runs \`owfeed doctor\`, and installs the result on a real OpenWrt image before this
can be merged.")"; then
				echo "$name: $url"
			else
				echo "$name: PULL REQUEST NOT OPENED -- $branch is pushed and nothing tracks it"
				echo "  run 'gh pr create -R $SELF --head $branch', or delete the branch and let the next run rebuild it"
			fi
		fi

		# Start the checks by hand, because GitHub will not start them by itself.
		#
		# For a trusted update this dispatch is the ONLY run the commit ever gets:
		# there is no pull request, so no `pull_request` event exists to hold or to
		# approve. Check runs bind to a commit rather than to an event, so the
		# contexts it reports -- `check / build`, `check / check` -- are the ones
		# `main`'s branch protection reads when `tools/land-updates.sh` pushes that
		# commit, and the ones that script reads before it tries.
		#
		# For an untrusted update it is what it always was: the pull request's own
		# `pull_request` run is created in `action_required` (see the head of this
		# file), and this is what makes the checks report anyway.
		#
		# `workflow_dispatch` is named in GitHub's own exception -- "`workflow_dispatch`
		# and `repository_dispatch` events always create workflow runs" -- so the same
		# token that could not start the `pull_request` run can start this one. It
		# publishes nothing: `pr.yml` passes `dry-run: true`, which is what `feed.yml`'s
		# publish job is gated on, so no dispatch reaches the `feed` environment.
		#
		# NOT ALLOWED TO FAIL THE RUN, for the same reason as above -- and it is the
		# one failure that leaves a trusted update stopped rather than late: a branch
		# with no checks has nothing for `land-updates.sh` to read, and it will sit
		# there reporting "waiting" every hour until somebody dispatches the run.
		if gh workflow run pr.yml -R "$SELF" --ref "$branch" >/dev/null 2>&1; then
			echo "$name: checks dispatched on $branch"
		else
			echo "$name: CHECKS NOT DISPATCHED -- $branch has no run and cannot land"
			echo "  run 'gh workflow run pr.yml -R $SELF --ref $branch'"
		fi
		git checkout -q "$BASE"
		git checkout -q "$up"
	)
done
