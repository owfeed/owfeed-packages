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
# A held run is a pull request nothing has checked, so every automatic update waited
# for a person -- issue #53.
#
# No pull request, no `pull_request` event, nothing to hold. The checks do not go away
# with it: `tools/land-updates.sh` carries them instead of branch protection, which
# was tried on `main` and removed because GitHub refused the push with GH006 while
# both contexts were green on the commit -- it counts them for the branch being pushed
# to. So this script pushes the update branch and dispatches the checks on it, and
# `tools/land-updates.sh` fast-forwards `main` onto that commit on a later run, once
# every run of `check / build` and `check / check` on it is completed/success.
#
# What did NOT change is which updates may do that. `may_automerge()` below is the
# same set of conditions it was when it armed GitHub's auto-merge.
set -eu

# Which repository this is, resolved once and named on every `gh` call below. `gh`
# falls back to `git remote` to decide that, which is how the neighbouring job in
# `update.yml` failed its first run -- and a call that has to guess is a call that
# can guess a different repository than the one this checkout came from.
SELF="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

# Every read from an upstream release goes through tools/net.sh: it retries an outage
# and exits 8 when one outlasts it, so "GitHub answered 502" never reads as "this
# release is broken". Resolved beside this file, not from the working directory,
# because the tests run this script from inside a repository with no tools/ in it.
NET="$(cd "$(dirname "$0")" && pwd)/net.sh"

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
	#
	# Read first and counted second. This function runs as an `if` condition, where
	# errexit is off, and in `git log | wc -l` a failed git still counts to 0 --
	# under the ceiling, so a failure read as permission. Every failed read in here
	# returns 1: the cost is a pull request, never an unreviewed merge.
	if ! _log="$(git log --since='24 hours ago' --author='owfeed-bot' --oneline -- "$_up")"; then
		echo "  could not count recent automatic updates: 'git log --since=\"24 hours ago\" --author=owfeed-bot -- $_up' failed"
		return 1
	fi
	_recent=0
	[ -z "$_log" ] || _recent="$(printf '%s\n' "$_log" | wc -l | tr -d ' ')"
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
	#
	# The diff is captured on its own for the same reason as the log above: piped
	# straight into the filters, a failed `git diff` is an empty list of changed
	# lines, and the `|| true` the filters need turns that into "only pins moved".
	if ! _diff="$(git diff -U0 -- "$_up")"; then
		echo "  could not read what changed: 'git diff -U0 -- $_up' failed, so it is not merging itself"
		return 1
	fi
	_bad="$(printf '%s\n' "$_diff" \
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

# feed_version <upstream version>
#
# What this feed calls a release of that version. The `-r<n>` on the end is a
# revision of the same upstream bytes, and apk wants that suffix last, so it is the
# only one a version here may carry.
#
# Where upstream already appends a numeric suffix of its own -- OpenWrt's
# PKG_RELEASE, which `Medvedolog/luci-app-podkop-bot` tags as `0.19.17-2` -- that
# suffix means the same thing and maps onto `-r<n>`. Carrying it along instead
# would produce `0.19.17-2-r1`: two revision numbers, the wrong one of them moving
# on the next release, and a version apk orders differently from how whoever wrote
# it meant it.
feed_version() {
	_ver="$1"
	_tail="${_ver##*-}"
	case "$_ver" in
	*-*)
		case "$_tail" in
		''|*[!0-9]*) printf '%s-r1\n' "$_ver" ;;
		*)           printf '%s-r%s\n' "${_ver%-*}" "$_tail" ;;
		esac
		;;
	*)
		printf '%s-r1\n' "$_ver"
		;;
	esac
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

# Packages whose check stopped, reported together once the loop is done. See the end
# of the loop for why one of them must not end it.
failed=""
outages=""

for up in packages/*/upstream.sh; do
	dir="$(dirname "$up")"
	name="$(basename "$dir")"

	# A subshell per package: one package's variables never leak into the next.
	#
	# Its status is read with `set +e` around it, NOT with `( ... ) || handler`.
	# POSIX ignores `set -e` for every command inside the left side of `||`, subshell
	# included, and the `set -e` inside does not turn it back on. Measured with
	# #68's `|| {` handler: `gh release download` printed "release not found",
	# the body carried on, rewrote the pin to the tag it never downloaded, pushed
	# the branch and dispatched checks on it -- and the run went green. Only the
	# explicit `exit 1`s still stopped a package. Reproduced in dash and in bash's
	# sh mode; tools/test-check-updates.sh (a0-unfetchable) is the case.
	set +e
	(
		set -e
		. "./$up"

		# Compared as tags, because the tag is what exists upstream and the version
		# is derived from it here. Deriving the tag back from the version assumed
		# every project tags `v<version>`: `luci-app-podkop-bot` tags `0.19.17-2`,
		# so the reconstruction asked for `v0.19.17-2`, got "release not found",
		# and under `set -e` took the run down on the fourth of six packages --
		# the two after it were never checked at all. The default below is
		# fetch.sh's, so a package that pins no tag is still compared against
		# exactly the tag fetch.sh would download for it.
		current_tag="${TAG:-v${VERSION%-r*}}"
		# Scratch space for this package, removed however the subshell ends. Made
		# before the first `gh` call, whose stderr is read below.
		tmp="$(mktemp -d)"
		trap 'rm -rf "$tmp"' EXIT

		# "Upstream has no releases" and "could not ask" are different answers, and
		# only the first is green. This was `2>/dev/null || true`, which read a 401,
		# a 502 or a dropped connection as "no releases" and left the run green with
		# the package never checked -- a check that cannot run counts as failed.
		#
		# gh does not tell them apart by exit code. Measured with gh 2.99.0: a
		# repository with no releases (octocat/Hello-World), a repository that does
		# not exist, a bad token and an unreachable proxy all exit 1. The first two
		# print exactly `release not found` -- both are a 404 on /releases/latest --
		# and the others print the HTTP or transport error. So `release not found` is
		# confirmed with a question an existing repository answers and a missing one
		# fails, the release list; a renamed or deleted upstream is a REPO to fix,
		# not a quiet hour. Every other failure stops this package through the
		# handler after the subshell.
		#
		# tools/net.sh passes gh's stderr through verbatim when the answer is definite,
		# so the `release not found` comparison still sees exactly what gh printed.
		rc=0
		latest_tag="$("$NET" gh release view --repo "$REPO" --json tagName -q .tagName 2>"$tmp/view.err")" || rc=$?
		if [ "$rc" -ne 0 ]; then
			if [ "$rc" -ne 8 ] && [ "$(cat "$tmp/view.err")" = "release not found" ]; then
				rc=0
				"$NET" gh api "repos/$REPO/releases?per_page=1" -q length >/dev/null 2>"$tmp/list.err" || rc=$?
				if [ "$rc" -eq 0 ]; then
					echo "$name: upstream has no releases"
					exit 0
				fi
			fi
			{
				echo "$name: could not read the latest release of $REPO"
				cat "$tmp/view.err" "$tmp/list.err" 2>/dev/null | sed 's/^/  /'
				echo "  failed: gh release view --repo $REPO --json tagName, then gh api repos/$REPO/releases"
				if [ "$rc" -eq 8 ]; then
					echo "  GitHub did not answer after retries: an outage, not a finding; a later run checks it again"
				else
					echo "  a renamed or deleted repository needs REPO fixed in $up"
				fi
			} >&2
			[ "$rc" -ne 8 ] || exit 8
			exit 1
		fi
		[ -n "$latest_tag" ] || { echo "$name: gh release view answered an empty tag for $REPO" >&2; exit 1; }

		# Versions, for what reads a version rather than a tag: the major-bump
		# refusal, an `apk` shape's artifact names, and anyone reading the branch.
		current="${current_tag#v}"
		latest="${latest_tag#v}"

		[ "$current_tag" != "$latest_tag" ] || { echo "$name: $current is current"; exit 0; }

		branch="update/${name}-${latest}"

		# Has this update already been proposed? Ask the remote branch, not the
		# pull request list. A trusted update no longer opens one, so
		# `gh pr list --head` would answer "nothing here" on every run and this job
		# would rebuild, force-push and re-dispatch the same update forever --
		# a runner bill on every run and a branch whose checks never finish before they
		# are replaced.
		#
		# Three conditions, and the third is what stops a branch wedging: it
		# exists, it already records this version, and `main` is an ancestor of
		# it. A branch built on a `main` that has since moved can never be
		# fast-forwarded onto it, so calling that one done would leave the update
		# stuck until somebody deleted the branch; rebuilding it is how this
		# converges with nobody looking.
		#
		# The version and the tag are the identity here, not the checksums: the
		# branch name carries the version and the pins are derived from the release
		# that tag names. An upstream that replaces a release in place is caught where
		# the bytes are read -- `tools/fetch.sh` compares them against the pin --
		# rather than by downloading ninety assets on every run to compare them with
		# themselves.
		#
		# The tag has to match as well as the version, because two tags can share
		# one version: `v1.1.0` and `1.1.0` both strip to 1.1.0 and both become
		# `update/<name>-1.1.0`. A branch pinned to the tag upstream did not publish
		# -- left by the code that pasted a `v` onto every tag, or by an upstream that
		# re-tagged -- compared by VERSION alone read as this update already done,
		# and on every run after that the job reported it current while the branch
		# could only ever fail to fetch. Exact lines, not substrings: `TAG="1.1.0"`
		# must not be found inside some other assignment. A branch that pins no TAG
		# at all predates this script writing one, and is rebuilt once.
		#
		# A failing `git ls-remote` reads as "no branch" and costs a rebuild, not
		# a wrong merge: the push below is `--force-with-lease` and refuses if the
		# branch turns out to be there and moved.
		remote_sha="$(git ls-remote --heads origin "$branch" | cut -f1)"
		if [ -n "$remote_sha" ]; then
			git fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch"
			have="$(git show "refs/remotes/origin/$branch:$up" 2>/dev/null || true)"
			if printf '%s\n' "$have" | grep -qxF "VERSION=\"$(feed_version "$latest")\""; then
				if ! printf '%s\n' "$have" | grep -qxF "TAG=\"$latest_tag\""; then
					echo "$name: $branch carries $latest pinned to a tag other than $latest_tag: rebuilding it"
				elif git merge-base --is-ancestor HEAD "refs/remotes/origin/$branch"; then
					echo "$name: $branch already carries $latest"
					exit 0
				else
					echo "$name: $branch carries $latest but predates main: rebuilding it"
				fi
			fi
		fi
		echo "$name: $current -> $latest"

		# Only what this shape needs to recompute its pins. A manifest package pins
		# no checksums at all -- they are in the manifest, under the author's
		# signature -- so downloading its ninety-odd assets on every run to look at
		# none of them would be pure waste.
		pattern='*'
		[ "$KIND" = "manifest" ] && pattern='manifest.txt'
		"$NET" gh release download "$latest_tag" --repo "$REPO" --dir "$tmp" --pattern "$pattern" >/dev/null

		# Recompute the pins from the bytes the release actually served, rewriting
		# values in place. Nothing but data changes, so the diff is readable.
		sed -i "s|^VERSION=.*|VERSION=\"$(feed_version "$latest")\"|" "$up"

		# The tag is a pin in every shape, not only in `manifest`. fetch.sh defaults
		# it to `v<version>`, and that default is wrong for an upstream tagging
		# `0.19.17-2` -- the more so once that `-2` has become the `-r2` above,
		# where the default can no longer see it. A package that pinned no tag gets
		# one written here, beside the version it belongs with.
		if grep -q '^TAG=' "$up"; then
			sed -i "s|^TAG=.*|TAG=\"${latest_tag}\"|" "$up"
		else
			sed -i "s|^VERSION=.*|&\nTAG=\"${latest_tag}\"|" "$up"
		fi

		case "$KIND" in
		manifest)
			# The tag pinned above is the whole update. There are no checksums here
			# to recompute: they are in the manifest, and the author's signature is
			# what makes them worth anything -- which is why this shape can be
			# trusted to merge itself.
			:
			;;
		apk)
			file="$(echo "$ARTIFACT" | sed "s/${current}/${latest}/g")"
			[ -f "$tmp/$file" ] || { echo "$name: $latest_tag publishes no $file" >&2; exit 1; }
			# The sum is taken into a variable before it goes near `sed`. Inside the
			# sed argument a failed `sha256sum` is invisible -- the command's status
			# is sed's -- and the pin is committed as an empty checksum.
			sum="$(sha256sum "$tmp/$file")"
			sed -i "s|^ARTIFACT=.*|ARTIFACT=\"${file}\"|" "$up"
			sed -i "s|^SHA256=.*|SHA256=\"${sum%% *}\"|" "$up"

			# The 24.10 container, when upstream ships one. Leaving it pinned to the
			# previous version does not fail here -- it fails later, when fetch.sh asks
			# the new release for a filename only the old one had, and every automatic
			# update of a package serving both lines arrives broken.
			if [ -n "${ARTIFACT_IPK:-}" ]; then
				file_ipk="$(echo "$ARTIFACT_IPK" | sed "s/${current}/${latest}/g")"
				[ -f "$tmp/$file_ipk" ] || { echo "$name: $latest_tag publishes no $file_ipk" >&2; exit 1; }
				sum="$(sha256sum "$tmp/$file_ipk")"
				sed -i "s|^ARTIFACT_IPK=.*|ARTIFACT_IPK=\"${file_ipk}\"|" "$up"
				sed -i "s|^SHA256_IPK=.*|SHA256_IPK=\"${sum%% *}\"|" "$up"
			fi
			;;
		binaries)
			# Rewrite only the checksum column, so the architecture mapping — which is
			# a human decision about what upstream's builds actually run on — survives
			# untouched.
			echo "$ARTIFACTS" | while read -r artifact _ arches; do
				[ -n "$artifact" ] || continue
				[ -f "$tmp/$artifact" ] || { echo "$name: $latest_tag publishes no $artifact" >&2; exit 1; }
				sum="$(sha256sum "$tmp/$artifact")"
				printf '%s  %s  %s\n' "$artifact" "${sum%% *}" "$arches"
			done > "$tmp/table"
			# `|| exit 1`, not `&& mv`. The left side of `&&` is exempt from errexit,
			# so a failing awk -- BSD awk refuses the newlines in this `-v` -- left
			# the package running with VERSION and TAG already rewritten above and
			# the old checksums still in place, and that half-pin was committed,
			# pushed and sent to the checks.
			awk -v table="$(cat "$tmp/table")" '
				/^ARTIFACTS="/ { print; print table; inside = 1; next }
				inside && /^"/ { print; inside = 0; next }
				!inside        { print }
			' "$up" > "$tmp/new" || {
				echo "$name: could not rewrite the checksum table in $up; nothing is committed" >&2
				echo "  failed: awk -v table=... $up (its own error is above)" >&2
				exit 1
			}
			mv "$tmp/new" "$up"
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
			if url="$(gh pr create -R "$SELF" --title "$name: $current -> $latest" --body "Upstream released \`$latest_tag\`.

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
		# `tools/land-updates.sh` reads on that same commit before it pushes it.
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
		# there reporting "waiting" on every run until somebody dispatches the run.
		if gh workflow run pr.yml -R "$SELF" --ref "$branch" >/dev/null 2>&1; then
			echo "$name: checks dispatched on $branch"
		else
			echo "$name: CHECKS NOT DISPATCHED -- $branch has no run and cannot land"
			echo "  run 'gh workflow run pr.yml -R $SELF --ref $branch'"
		fi
		git checkout -q "$BASE"
		git checkout -q "$up"
	)
	stopped=$?
	set -e
	if [ "$stopped" -ne 0 ]; then
		# One package stopping must not stop the others. The body runs in a
		# subshell, and under `set -eu` a subshell that exits non-zero ends the
		# `for` itself -- so an `exit 1` above for one release took every package
		# after it out of the run. Measured on 2026-09-11: `luci-app-podkop-bot`
		# failed fourth of six, and `luci-theme-footstrap` and `podkop-updater`
		# were never asked about at all. Reproduced in dash: without this handler
		# the loop ends at the failing item; with it the next item is checked.
		#
		# The stop can come after `sed` has already rewritten this package's
		# upstream.sh, or after the update branch was checked out, so the next
		# package would start from a dirty tree or the wrong branch. `-f` puts
		# both back: the branch and every tracked file.
		echo "$name: stopped; the remaining packages are still checked" >&2
		git checkout -q -f "$BASE"
		# Exit 8 is tools/net.sh saying GitHub did not answer. Kept apart so the end
		# of the run can say which of the two it was.
		if [ "$stopped" -eq 8 ]; then
			outages="$outages $name"
		else
			failed="$failed $name"
		fi
	fi
done

# Still red when anything stopped. Continuing past a failure is about checking the
# rest, not about hiding this one: a check that could not run counts as failed.
#
# Exit 8 only when an outage is the whole story. One real failure beside it makes the
# run a 1, because exit 8 tells whoever reads it that a rerun is all it needs.
if [ -n "$failed" ]; then
	echo "check stopped for:$failed" >&2
	[ -z "$outages" ] || echo "and GitHub did not answer for:$outages" >&2
	exit 1
fi
if [ -n "$outages" ]; then
	echo "check stopped because GitHub did not answer for:$outages" >&2
	echo "  an upstream outage, not a finding; the next scheduled run checks them again" >&2
	exit 8
fi
