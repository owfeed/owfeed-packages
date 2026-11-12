# Runbook

*[Русская версия](RUNBOOK_ru.md)*

What to do when something in this feed's automation breaks. For the maintainer on duty.
For adding or updating a package, see [CONTRIBUTING.md](CONTRIBUTING.md).

- **The signing key** exists only in the second publish job on `main`, behind `environment: feed`.
  Pull requests and `update/*` branches use throwaway keys.
- **A trusted update gets no pull request.** The scheduled job pushes `update/<name>-<version>` and
  dispatches `Check`. A later run of `land-updates.sh` fast-forwards `main` onto it.
- **`land-updates.sh` is the gate.** It lands a branch only when its checks are green and its diff
  names nothing but `packages/<name>/upstream.sh`.
- **Every scheduled step is idempotent.** It picks up whatever the run before it left, so the cron
  interval does not matter.

## Find it fast

| Symptom | Section |
|---|---|
| `MISSING …` from `check-tree.sh` | [When a package goes missing](#when-a-package-goes-missing) |
| A finding or a failed step on a pull request or `update/*` branch | [A check is red](#a-check-is-red) |
| A version you do not recognise on `main` or in a pull request | [An update appeared and I do not recognise the version](#an-update-appeared-and-i-do-not-recognise-the-version) |
| An `update/*` branch that stays unlanded | [An update branch never lands](#an-update-branch-never-lands) |
| The publish job is red, or Pages did not change | [Publishing failed](#publishing-failed) |
| You want to see what routers see | [Checking what subscribers see](#checking-what-subscribers-see) |
| You are moving the owfeed version | [Moving to a new owfeed release](#moving-to-a-new-owfeed-release) |
| A key leaked, or needs rotating | [The signing keys](#the-signing-keys) |
| A pull request adds a file under `keys/` | [Adding a key to `keys/`](#adding-a-key-to-keys) |

## What runs when

| when | what | key present? |
|---|---|---|
| pull request | fetch → build → sign → index → check-tree → check-origin → sources → doctor → smoke (both lines) | throwaway ones |
| push to `main` | job 1: fetch → build | **no** |
| | job 2: sign → index → check-tree → check-origin → sources → smoke → verify → publish → Pages | **yes**, behind `environment: feed` |
| scheduled run | push `main` onto any `update/*` branch whose checks are already green | no |
| | ask each upstream for its latest release; push an update branch if there is one | no |
| | dispatch `Check` on that branch — GitHub starts no run for it by itself | throwaway ones |
| | open a pull request for it, unless the update is one that may land unattended | no |
| | dispatch `Publish` when the head of `main` has no `Publish` run of its own | no |

`update.yml` asks for `cron: '17 * * * *'`. GitHub delivers less: the scheduled runs on
2026-09-04..06 arrived two to five hours apart.

The pull-request row is not a second pipeline. `pr.yml` and `publish.yml` call owfeed's reusable `feed.yml` at the
same pinned tag. `pr.yml` passes `dry-run: true`. `publish.yml` passes `secrets: inherit` and no
dry-run. The difference is throwaway keys, no environment and no deploy.

<details>
<summary>Why <code>main</code> is split into two jobs</summary>

The fetch scripts execute values contributed by pull requests, and that job has no key. The key
appears only after the built bytes are already in an artifact.

</details>

---

## When a package goes missing

`tools/check-tree.sh` runs after `owfeed index` in both workflows. It fails the run if a package this
repository ingests is absent from a release line it declares.

```
MISSING luci-theme-footstrap luci-theme-footstrap_0.11.6-r1_all.ipk on 24.10: absent from 36 of 36 architecture(s) (e.g. armeb_xscale)
```

| The message says | Cause | Do |
|---|---|---|
| absent from *all* architectures | The fetch produced nothing. The release has no such asset, or `ARTIFACT_IPK` is unset in `upstream.sh` for a package that used to publish one. | Check the release assets and `upstream.sh`. |
| absent from *some* architectures | The build ran short. | Read the build log for a step that failed without stopping the run. |

<details>
<summary>Why this check exists</summary>

Nothing else can see a missing package. `owfeed doctor` reads the tree and asks whether what is
there is correct. A package that failed to fetch is not there, and every check passes. That is how
a tree carrying one of three packages on its 24.10 line once reported itself ready to publish.

</details>

## A check is red

The same workflow reports on pull requests and on `update/*` branches. Read the finding: each says
what it costs and what to do. The findings below have causes that are hard to guess.

### `OWF207`: configuration shipped but not declared

- **Cause:** the package installs `/etc/config/foo`, and `conffiles:` does not list it.
- **Cost:** sysupgrade reads `.conffiles_static` to decide what survives a firmware upgrade. Your
  defaults would replace the user's settings on every upgrade, with nothing reported.
- **Do:** list the file under `conffiles:`.

### `smoke` failed but `doctor` passed

The tree is coherent, and a router will not take it. Read the container output. The usual causes:

- a dependency that does not resolve on a stock image;
- a file installed somewhere nothing looks.

### `!! upstream outage: …` and exit code 8 in the fetch step

- **Cause:** GitHub or another upstream answered 5xx or 429, timed out, or could not be reached. It
  kept doing so for five attempts over about 75 seconds. Nothing about the package was found wrong.
- **Do:** once [githubstatus.com](https://www.githubstatus.com) is green, rerun the job.

The same message comes from `check-updates.sh`, `land-updates.sh` and the intake job, all through
`tools/net.sh`. Before this change the symptom was `curl: (22) The requested URL returned error: 500`
repeated six times and `exit code 22`. That is also an outage, and also a rerun.

### `curl: (22) … 404` and exit code 7 in the fetch step

- **Cause:** the asset is not in the release. The tag or the file name in `upstream.sh` is wrong, or
  upstream deleted it.
- **Do:** check the tag and the file name in `upstream.sh`. A rerun gets the same answer.

### `sha256 … pinned …` in the fetch step, exit code 7

- **Cause:** the upstream replaced a release in place.
- **Do:** find out why the bytes changed first. Do not update the pin to make it pass.

### `NO ORIGIN …` from `tools/check-origin.sh`

This runs after the index is built.

- **Cause:** a package reached the tree without saying where it comes from. This feed does not
  publish it.
- **Do:** send a message to upstream. The field is set where the package is built, so nothing here
  fixes it.

A value like `feeds/base/<name>` fails the same way an empty one does. That is the path the SDK
built from, not somewhere a user can go.

### `tools` failed

- **Cause:** a self-test of a script under `tools/` is red, and `check` did not start. The log prints
  `FAIL` beside the broken case.
- **Do:** before you push a change to `tools/`, run the tests locally. They need `git` and `jq` and
  reach no network.

```sh
sh tools/test-sources.sh
sh tools/test-land-updates.sh
sh tools/test-check-updates.sh
sh tools/test-net.sh
```

---

## An update appeared and I do not recognise the version

1. Look at the diff, whether it arrived as a pull request or as a commit on `main`. It must be a
   version and its checksums, nothing else.
2. If it touches anything more, something is wrong with the bot rather than with the release.
   `tools/land-updates.sh` would have refused to push it, so on `main` that shape means a person put
   it there.

To hold an update:

| The update | Do |
|---|---|
| has no pull request (a trusted update) | Set `AUTO_MERGE="no"` in the package's `upstream.sh`. |
| got a pull request | Close it. The bot does not reopen it and does not rebuild the branch. |

`AUTO_MERGE="no"` is the only reliable way to hold a trusted update. It lands on the first scheduled
run after its checks go green, and it has no pull request to close.

## An update branch never lands

An `update/*` branch that never lands is a red check: read the run. Two other shapes appear in the
scheduled job's log:

| Log line | Meaning | Do |
|---|---|---|
| `not green yet`, naming a context that is `cancelled` | A cancelled run is still on the commit. | Delete the branch. The next run rebuilds it with a clean set of runs. |
| `REFUSED` | The branch touches a path an update may not. | This one needs a person. |

---

## Publishing failed

The publish job is a separate job with the key. Common causes:

| Finding | Cause | Do |
|---|---|---|
| `$OWFEED_SIGN_KEY is empty` | The secret is missing, or the run started before it existed. | Re-run the job. |
| `owfeed verify` reports `OWF513` | A version already published has different contents than what is about to replace it. A package changed without a version bump, or a build stopped being reproducible. | Check that `SOURCE_DATE_EPOCH` is still set in the workflow. Do not publish over it: bump the revision instead. |
| Pages did not update | Deployment is `actions/deploy-pages`. | Check that job, not the feed. |

### Pages deploy settings that break the live site

- **`actions/upload-pages-artifact` needs `include-hidden-files: true`.** From v4 it drops dotfiles,
  and `.nojekyll` is a dotfile. Without it Pages runs Jekyll over a tree of binaries. Jekyll removes
  every path beginning with a dot or an underscore, from a tree that was correct when
  `owfeed publish` checked it.
- **`actions/deploy-pages` needs `actions: read`.** A `permissions:` block that names other scopes
  silently withholds it.
- **`owfeed verify` reports OWF514** when the live site has lost `.nojekyll`. Outside the deploy is
  the only place that answer exists.

---

## Checking what subscribers see

```sh
owfeed verify                 # over the documented URL, no local tree needed
owfeed verify out             # also compares what is about to replace what is live
```

`owfeed verify` fetches the published key and index. It reports:

- redirects apk will not follow;
- packages the live index names that are missing or the wrong size;
- versions being republished with different contents.

From a router's point of view, in one command:

```sh
owfeed smoke                  # installs the built feed on a real OpenWrt image
```

---

## Moving to a new owfeed release

1. Check the owfeed release is published. If you push `setup@vX.Y.Z` while that release is still
   building, every job fails with *"does not verify as built by owfeed/owfeed's release workflow"*.
   That reads like an attack and is a race.
2. Move the pin. It is one line in each workflow: `uses: .../feed.yml@v0.5.8` in `pr.yml` and
   `publish.yml`, `uses: owfeed/owfeed/setup@v0.5.8` in `intake.yml`. Do not add
   `owfeed-version:` back: that workflow installs the owfeed release it is tagged with.
3. Check every line moved. Use the grep rather than counting from memory. It also prints
   comments that name a version; leave those.

   ```sh
   grep -rn 'v0\.' .github/workflows
   ```

4. Open a pull request, like anything else.

If the same change turns on a policy that requires package pins, move the package pins in the same
commit. Turning on `signing.author-keys` while the pins still name unsigned releases excludes every
package the feed carries. The publish then succeeds with an empty tree, which is the worst shape
that failure can take.

<details>
<summary>How owfeed gets here, and why the pin is a release</summary>

The workflows use `owfeed/owfeed/setup@v0.5.8`, pinned to a release. The action downloads one binary.
Before running it, the action checks it against the build attestation from owfeed's own release
workflow. A checksum from the same release would not do: whoever replaced the binary could replace
that too.

`setup` refuses to install a binary that does not verify, including one that does not exist yet.
That is why the release must be published before the pin moves.

It used to be `go install …@<sha>`. That compiled the tool on every job and verified nothing:
`go install` trusts whatever the module proxy returns for that revision.

The tool that signs this feed should move when someone changes a line, not whenever an unrelated
repository is pushed to.

</details>

---

## The signing keys

There are two, because each package manager verifies only its own scheme:

| secret | scheme | signs |
|---|---|---|
| `OWFEED_SIGN_KEY` | EC prime256v1 | the apk index |
| `OWFEED_USIGN_KEY` | usign / ed25519 | the opkg index |

- **Both live in repository secrets** and nowhere else here. `.gitignore` covers `*.pem`, `*.key` and `*.sec`,
  so neither can be committed by accident.
- **The opkg key** is published under its own id as a filename: that is how opkg looks it up.
- **The apk key** is published under the feed's name. apk matches on the identity inside the
  signature and ignores the name.

### If a key leaks: there is no revocation

apk has no CRL, no expiry, and no way to say a key is dead. If the key leaks, every subscriber has to
remove it and install a new one by hand. No path reaches a router that is offline when it matters.

### Rotating a key

owfeed does not yet have a command for this; the steps are in its design document. In short:

1. Generate a new key.
2. Publish both public keys for an overlap window.
3. Sign the index with both.
4. Drop the old one.

`apk` matches keys by identity rather than by filename. Several keys can coexist on a device, so the
overlap costs nothing.

<details>
<summary>Why the keys sign indexes only</summary>

`signing.sign-packages` is `false` in `owfeed.yml`. This feed does not put its signature inside a
package somebody else built: what it distributes is the author's file, byte for byte.

A router's trust comes from the signed index either way. Installing, upgrading and removing by name
were measured working with no package signature at all, including through LuCI's own buttons.

What does not work is `apk add ./file.apk` and LuCI's Upload Package. Those already need
`--allow-untrusted` for OpenWrt's own packages.

</details>

---

## Adding a key to `keys/`

That is the one diff in this repository that deserves a second look. A pinned key is what makes a
signature mean anything.

Verify the key out of band, against anything that is not the release you are about to trust it for:

- the author's repository;
- a fingerprint they published somewhere else.

---

## Things that are not automatic, on purpose

**Publishing is not.** The update job proposes; it never signs. It may dispatch `Publish` for a
commit already on `main`. A push made with `GITHUB_TOKEN` raises no push event, so without that the
feed would keep serving the previous version. The key is never in that job; it is in the run it
starts.

A job that fetched whatever an upstream published since the last run and signed it would hand this
feed's key to every upstream at once.

**Landing on `main` is not, unless the author signed, and not more than twice a day.**
`AUTO_MERGE="yes"` is offered only when all of these hold:

- a detached signature is verified against a pinned key;
- the shape's signature covers what changed: `manifest` always, `apk` while the container set holds,
  `binaries` never;
- it is not a third update to the same package inside 24 hours.

A stolen key publishes a chain of releases faster than anyone reads the notifications, and every one
of them verifies. Everything outside that set is a pull request and a maintainer.

**Landing anything but a version bump is not.** `land-updates.sh` refuses to push a branch whose
diff against `main` names any path but `packages/<name>/upstream.sh`. So `keys/`, `tools/` and
`.github/` are unreachable from the automation. That is the invariant `ECOSYSTEM.md` states and
`.github/CODEOWNERS` asks a reviewer for.

**Architecture coverage is not.** `owfeed.lock` records which architectures the feed publishes for.
`--frozen-lock` fails the build when upstream's list moves. Run `owfeed lock --update` and read the
diff: what the feed covers is part of its contract with subscribers.

### Why the update automation is shaped this way

<details>
<summary>Why a trusted update gets no pull request</summary>

Everything the scheduled job does happens under `GITHUB_TOKEN`. Neither event that would normally
start a run does so under that token.

A pull request opened by `app/github-actions` gets a `pull_request` run. The run is created and then
held in `action_required` until a person approves it. GitHub's wording: "when a workflow using
`GITHUB_TOKEN` creates or updates a pull request, the resulting `pull_request` event creates workflow
runs in an approval-required state".

That hold is unconditional for this token. It is **not** this repository's
`fork-pr-contributor-approval` policy. That policy was relaxed to
`first_time_contributors_new_to_github` at repository and organisation level at once. The bot's #60
still came back with `attempt 1 = action_required` (run 33966648498), and both policies were put
back.

The hold reached this organisation between 2026-08-30 20:43Z and 2026-09-01 10:08Z. It was measured
on `attempts/1` of the runs on the `update/*` branches either side of that window. #45 measured the
resulting wait at two days.

A held run is a pull request nothing has checked, so every automatic update waited for a person. So
an update the rules let through gets no pull request.

</details>

<details>
<summary>Why <code>land-updates.sh</code> is the gate, not branch protection</summary>

`land-updates.sh` pushes only when every run of `check / build` and `check / check` on that exact
commit is `completed/success`. A context with no run at all counts as a refusal. The diff may name
nothing but `packages/<name>/upstream.sh`.

Required status checks were configured on `main` for this and removed again. With both contexts green
on the commit, the push was still refused with `GH006: 2 of 2 required status checks are expected`.
GitHub counts contexts for the branch being pushed to rather than for the branch they ran on.

The dispatch of `Check` runs on the head of the update branch. Check runs bind to a commit rather
than to an event. So `land-updates.sh` reads those contexts on the exact commit it is about to push.

The dispatch publishes nothing. `pr.yml` passes `dry-run: true`, and `feed.yml`'s publish job is
gated on that input, not on the event or the ref. No dispatch can reach the `feed` environment.

</details>

<details>
<summary>What still needs a person</summary>

An update that is not eligible is pushed the same way and then gets a pull request, which a
maintainer merges. Not eligible means any of these:

- no upstream signature;
- a `binaries` package;
- a major version bump;
- a third update to one package in a day.

Nothing lands automatically outside `packages/<name>/upstream.sh`. `land-updates.sh` diffs the branch
against `main` and refuses on any other path. A new package brings a key under `keys/`, so it is a
pull request by construction.

</details>

<details>
<summary>Why <code>Check</code> and <code>Publish</code> are dispatched</summary>

A merge or a push made with `GITHUB_TOKEN` raises no `push` event either. That is why `Publish` is
dispatched rather than triggered. `workflow_dispatch` is the documented exception in both cases:
those events always create runs.

</details>

