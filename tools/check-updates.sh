#!/bin/sh
# Notice new upstream releases and propose them as pull requests.
#
# It proposes; it does not publish. This feed's key is a trust anchor for every
# package name on every subscriber's router, so a job that fetched whatever an
# upstream pushed in the last hour and signed it would hand that authority to every
# upstream at once. The checksum pins would stop meaning anything too: recomputed
# from whatever arrived, they would attest to nothing.
#
# What a pull request carries instead is evidence — a diff containing a version and
# its checksums and nothing else, and a run that builds, indexes, checks and
# installs the result on a real OpenWrt image before anyone merges it.
set -eu

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
		if gh pr list --head "$branch" --state open --json number -q '.[0].number' | grep -q .; then
			echo "$name: a pull request for $latest is already open"
			exit 0
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

		git checkout -q -b "$branch"
		git commit -q "$up" -m "$name: $current -> $latest

$evidence

Pins recomputed from the bytes the release served."
		# --force-with-lease, because a run that pushed the branch and then failed before
		# opening the pull request leaves it behind, and the next run's push is a
		# non-fast-forward against it -- so one failure would wedge that package's updates
		# until somebody deleted the branch by hand. The branch belongs to this job, its
		# name carries the version, and its content is derived from the release, so
		# replacing it loses nothing; the lease still refuses if someone else moved it.
		git push -q -u --force-with-lease origin "$branch"

		url="$(gh pr create --title "$name: $current -> $latest" --body "Upstream released \`v$latest\`.

$evidence

The diff is a version and its checksums, recomputed from the bytes the release served. CI builds the
feed, indexes it, runs \`owfeed doctor\`, and installs the result on a real OpenWrt image before this
can be merged.")"
		echo "$name: $url"

		# Start the checks by hand, because GitHub will not start them by itself.
		#
		# `gh pr create` runs under GITHUB_TOKEN, so the pull request's author is
		# `app/github-actions`, and this repository's approval policy
		# (`fork-pr-contributor-approval` = `first_time_contributors`) holds that
		# account's `pull_request` run in `action_required` until a person presses a
		# button. Measured on #45: attempt 1 was created 2026-09-02 and never ran;
		# attempt 2 ran two days later, triggered by a human. With required checks on
		# `main` the pull request is BLOCKED for that whole time, and the automatic
		# update stops being automatic -- which is what issue #11 is about.
		#
		# `workflow_dispatch` is named in GitHub's own exception -- "`workflow_dispatch`
		# and `repository_dispatch` events always create workflow runs" -- so the same
		# token that could not start the `pull_request` run can start this one. Check
		# runs bind to a commit, not to an event, and the head of `$branch` is the pull
		# request's head commit, so the run reports the very contexts the branch
		# protection is waiting for. It publishes nothing: `pr.yml` passes
		# `dry-run: true`, which is what `feed.yml`'s publish job is gated on.
		#
		# Before arming auto-merge below, deliberately: `--auto` refuses a pull request
		# that has nothing left to wait for, and this is what gives it something.
		#
		# NOT ALLOWED TO FAIL THE RUN, for the same reason as auto-merge: the pull
		# request exists by this line and every package after this one still has to be
		# checked. Reported rather than swallowed -- a silent failure here leaves a
		# pull request whose checks nobody will ever start.
		if gh workflow run pr.yml --ref "$branch" >/dev/null 2>&1; then
			echo "$name: checks dispatched on $branch"
		else
			echo "$name: CHECKS NOT DISPATCHED -- the pull request is open and its checks are not running"
			echo "  run 'gh workflow run pr.yml --ref $branch', or approve the waiting run by hand"
		fi

		# Auto-merge is offered only where someone other than this feed vouches for the
		# bytes. This asks GitHub to merge once the checks pass; it does not skip them.
		#
		# Even then it is refused twice over, because a signature answers "did the
		# author publish this" and not "should it go out unread". An upstream whose
		# release key is stolen signs perfectly.
		#
		# ARMING IT IS NOT ALLOWED TO FAIL THE RUN, and that is the whole point of the
		# `||` below. The job's product is the pull request, and by this line it exists:
		# the branch is pushed, the diff is a version and its checksums, the evidence is
		# in the body. Auto-merge is a convenience on top. Under `set -e` a refusal from
		# GitHub took the whole check down AFTER the work had succeeded -- the run went
		# red, which reads as "no update was found" while an update was sitting open, and
		# every package checked after this one was skipped.
		#
		# GitHub refuses for two ordinary reasons, neither of them a problem with the
		# update: the repository does not have "Allow auto-merge" enabled, and a pull
		# request that is ALREADY mergeable with nothing left to wait for cannot be armed
		# -- there is nothing to wait for, so it must simply be merged. Both are reported
		# here rather than swallowed, because a silent `|| true` would leave a pull
		# request nobody knows is waiting.
		if [ "$automerge" = "yes" ]; then
			if gh pr merge --squash --auto --delete-branch "$url" >/dev/null 2>&1; then
				echo "$name: will merge itself once the checks pass"
			else
				echo "$name: AUTO-MERGE NOT ARMED -- the pull request is open and needs merging by hand"
				echo "  either the repository has no 'Allow auto-merge', or the pull request is"
				echo "  already mergeable and GitHub has nothing to wait for"
			fi
		fi
		git checkout -q "$BASE"
		git checkout -q "$up"
	)
done
