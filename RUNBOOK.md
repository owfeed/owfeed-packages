# Runbook

*[Русская версия](RUNBOOK_ru.md)*

Operating the feed. For adding or updating a package, see [CONTRIBUTING.md](CONTRIBUTING.md).

## What runs when

| when | what | key present? |
|---|---|---|
| pull request | fetch → build → sign → index → check-tree → check-origin → sources → doctor → smoke (both lines) | throwaway ones |
| push to `main` | job 1: fetch → build | **no** |
| | job 2: sign → index → check-tree → check-origin → sources → smoke → verify → publish → Pages | **yes**, behind `environment: feed` |
| hourly | ask each upstream for its latest release; open a pull request if there is one | no |
| | dispatch `Publish` when the head of `main` has no `Publish` run of its own | no |

The split on `main` is the point: the fetch scripts execute values contributed by pull requests, and
that job has no key. The key appears only after the built bytes are already in an artifact.

The pull-request row is not a second pipeline that resembles the first. `pr.yml` calls owfeed's
reusable `feed.yml` with `dry-run: true`, which is the same file the publish path is written from —
the difference being throwaway keys, no environment and no deploy. `publish.yml` is still written out
by hand, for the reason at the top of it; the comment there says what has to be true before it moves
too.

**How owfeed gets here.** `owfeed/owfeed/setup@v0.4.0`, pinned to a release. The action downloads
one binary and checks it against the build attestation from owfeed's own release workflow before
running it — not against a checksum from the same release, which whoever replaced the binary could
replace too. It used to be `go install …@<sha>`, which compiled the tool on every job and verified
nothing: `go install` trusts whatever the module proxy returns for that revision.

**Wait for the owfeed release before moving the pin.** `setup` verifies the binary against the
attestation from owfeed's own release workflow and refuses to install one that does not verify —
including one that does not exist yet. Pushing `setup@vX.Y.Z` here while that release is still
building fails every job with *"does not verify as built by owfeed/owfeed's release workflow"*,
which reads like an attack and is a race. Check the release is published, then move the pin.

**Move the package pins in the same commit as a policy that requires them.** Turning on
`signing.author-keys` while the pins still name unsigned releases would exclude every package the
feed carries and publish an empty tree — the publish would succeed, which is the worst shape that
failure can take.

Moving to a new owfeed release is two lines in `pr.yml`, two in `publish.yml` and two in
`intake.yml` — `grep -rn 'v0\.' .github/workflows` is the check, rather than counting from memory, and it should be a pull request like anything else. The tool that signs this feed should move when someone changes a
line, not whenever an unrelated repository is pushed to.

**Two things about the Pages deploy that are easy to break.** `actions/upload-pages-artifact` needs
`include-hidden-files: true` — from v4 it drops dotfiles, and `.nojekyll` is a dotfile. Without it
Pages runs Jekyll over a tree of binaries and removes every path beginning with a dot or an
underscore, from a tree that was correct when `owfeed publish` checked it. And `actions/deploy-pages`
needs `actions: read`, which a `permissions:` block silently withholds by naming other scopes.
`owfeed verify` reports **OWF514** when the live site has lost `.nojekyll`, because outside the
deploy is the only place that answer exists.

---

## When a package goes missing

`tools/check-tree.sh` runs after `owfeed index` in both workflows and fails the run
if a package this repository ingests is absent from a release line it declares.

It exists because nothing else can see that. `owfeed doctor` reads the tree and asks
whether what is there is correct — a package that failed to fetch is simply not
there, and every check passes. That is how a tree carrying one of three packages on
its 24.10 line once reported itself ready to publish.

```
MISSING luci-theme-footstrap 0.11.6-r1 on 24.10: absent from 36 of 36 architectures (e.g. armeb_xscale)
```

Absent from *all* architectures means the fetch produced nothing: the release has no
such asset, or `ARTIFACT_IPK` is unset in `upstream.sh` for a package that used to
publish one. Absent from *some* means the build ran short — read the build log for a
step that failed without stopping the run.

## A pull request is red

Read the finding. Each says what it costs and what to do. The ones with non-obvious causes:

**`OWF207` — configuration shipped but not declared.** The package installs `/etc/config/foo` and
`conffiles:` does not list it. sysupgrade reads `.conffiles_static` to decide what survives a
firmware upgrade, so the user's settings would be replaced by your defaults on every upgrade, with
nothing reported.

**`smoke` failed but `doctor` passed.** The tree is coherent and a router will not take it. Read the
container output: usually a dependency that does not resolve on a stock image, or a file installed
somewhere nothing looks.

**`sha256 … pinned …`** in the fetch step. The upstream replaced a release in place. Do not update
the pin to make it pass — find out why the bytes changed first.

**`NO ORIGIN …`** from `tools/check-origin.sh`, after the index is built. A package reached the tree
without saying where it comes from, and this feed does not publish it. Nothing here fixes that: the
field is set where the package is built, so the answer is a message to upstream. A value like
`feeds/base/<name>` fails the same way an empty one does — that is the path the SDK built from, not
somewhere a user can go.

---

## An update pull request appeared and I do not recognise the version

The bot opens one for any upstream release. Look at the diff: it must be a version and its
checksums, nothing else. If it touches anything more, something is wrong with the bot rather than
with the release.

To hold an update, close the pull request; the bot will not reopen the same one. To stop a package
updating itself, set `AUTO_MERGE="no"` in its `upstream.sh`.

---

## Publishing failed

The publish job is a separate job with the key. Common causes:

**`$OWFEED_SIGN_KEY is empty`.** The secret is missing, or the run started before it existed.
Re-run the job.

**`owfeed verify` reports `OWF513`.** A version already published has different contents than what
is about to replace it. Either a package changed without a version bump, or a build stopped being
reproducible — check that `SOURCE_DATE_EPOCH` is still set in the workflow. Do not publish over it:
bump the revision instead.

**Pages did not update.** Deployment is `actions/deploy-pages`; check that job, not the feed.

---

## Checking what subscribers actually see

```sh
owfeed verify                 # over the documented URL, no local tree needed
owfeed verify out             # also compares what is about to replace what is live
```

It fetches the published key and index and reports redirects apk will not follow, packages the live
index names that are missing or the wrong size, and versions being republished with different
contents.

From a router's point of view, in one command:

```sh
owfeed smoke                  # installs the built feed on a real OpenWrt image
```

---

## The signing keys

There are two, because each package manager verifies only its own scheme:

| secret | scheme | signs |
|---|---|---|
| `OWFEED_SIGN_KEY` | EC prime256v1 | the apk index |
| `OWFEED_USIGN_KEY` | usign / ed25519 | the opkg index |

Both sign **indexes only**. `signing.sign-packages` is `false` in `owfeed.yml`, so this feed does
not put its signature inside a package somebody else built — what it distributes is the author's
file, byte for byte. A router's trust comes from the signed index either way; installing, upgrading
and removing by name were measured working with no package signature at all, including through
LuCI's own buttons. What does not work is `apk add ./file.apk` and LuCI's Upload Package, which
already need `--allow-untrusted` for OpenWrt's own packages.

Both live in repository secrets and nowhere else here. `.gitignore` covers `*.pem` and `*.sec` so
neither can be committed by accident.

The opkg key is published under its own id as a filename — that is how opkg looks it up. The apk key
is published under the feed's name, because apk matches on the identity inside the signature and
ignores the name.

**There is no revocation.** apk has no CRL, no expiry, and no way to say a key is dead. If the key
leaks, every subscriber has to install a new one by hand — there is no path that reaches a router
which is offline when it matters.

To rotate: generate a new key, publish both public keys for an overlap window, sign the index with
both, then drop the old one. `apk` matches keys by identity rather than by filename, so several can
coexist on a device and the overlap costs nothing. owfeed does not yet have a command for this; the
steps are in its design document.

---

## Adding a key to `keys/`

That is the one diff in this repository that deserves a second look. A pinned key is what makes a
signature mean anything, so verify it out of band — against the author's repository, a fingerprint
they published somewhere else, anything that is not the release you are about to trust it for.

---

## Things that are not automatic, on purpose

**Publishing is not.** The hourly job proposes; it never signs. What it may do is dispatch
`Publish` for a commit already on `main` — a merge made with `GITHUB_TOKEN` raises no push event,
so without that the feed would keep serving the previous version. The key is never in that job; it
is in the run it starts. A job that fetched whatever an upstream pushed in the last hour and signed
it would hand this feed's key to every upstream at once.

**Merging is not, unless the author signed — and not more than twice a day.** `AUTO_MERGE="yes"` is
offered only where a detached signature is verified against a pinned key, only for shapes whose
signature covers what changed (`manifest` always, `apk` while the container set holds, `binaries`
never), and never for a third update to the same package inside 24 hours. A stolen key publishes a
chain of releases faster than anyone reads the notifications, and every one of them verifies.

**Architecture coverage is not.** `owfeed.lock` records which architectures the feed publishes for,
and `--frozen-lock` fails the build when upstream's list moves. Run `owfeed lock --update` and read
the diff — what the feed covers is part of its contract with subscribers.
