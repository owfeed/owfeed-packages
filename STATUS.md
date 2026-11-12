# What is built in this feed, and what is not

*This file says how much of this feed's side exists, as of 2026-11-12. It is for anyone deciding
what the feed can be relied on for today. [ECOSYSTEM.md](https://github.com/owfeed/owfeed/blob/main/docs/ECOSYSTEM.md)
in owfeed says where the boundaries between owlab, owfeed and this feed run and why.*

- The feed is served from `https://repo.owfeed.org` since 2026-07-29. Routers on the old URL get a 404.
- Updates go from an upstream release to `repo.owfeed.org` with nobody in the loop.
- The intake funnel is built. No third party has used it yet: the one third-party package so far
  came as a pull request.
- Not built: a bot pull request that merges itself, a consumer job on top of the check, and
  CODEOWNERS as a mechanism.
- One known contradiction: one key covers four upstream repositories.

## Find it fast

| I want to… | Go to |
|---|---|
| know about the URL move | [The feed moved to repo.owfeed.org](#the-feed-moved-to-repoowfeedorg-on-2026-07-29) |
| see what works and the evidence | [Working, and verified rather than assumed](#working-and-verified-rather-than-assumed) |
| see what is built but untested | [Built but not yet exercised in anger](#built-but-not-yet-exercised-in-anger) |
| see what is missing and why | [Not built, and why](#not-built-and-why) |
| see where the docs contradict the setup | [Known contradictions](#known-contradictions) |
| find the other docs | [Where to look](#where-to-look) |

<details>
<summary>Why this file lives here and not in the shared document</summary>

A shared status file goes stale on exactly the facts none of its own CI touches. Beside the thing it
describes, a claim that stops being true is a line in the pull request that made it untrue.

</details>

## The feed moved to repo.owfeed.org on 2026-07-29

- **New URL:** `https://repo.owfeed.org`.
- **Old URL:** `https://vizzletf.github.io/owfeed-packages`.
- Routers subscribed to the old URL carry it in `/etc/apk/repositories.d/`. The install snippet they
  ran listed it in `/etc/sysupgrade.conf`, so it survives a firmware upgrade.
- From owfeed v0.3.1, released after the move, the subscribe script writes
  `/lib/upgrade/keep.d/owfeed-packages` instead, as [README.md](README.md) shows.
- GitHub does not redirect Pages across owners. Those routers get a 404 from `apk update` and stop
  receiving updates. Nothing can be done for them from here.
- The domain is owned by this project. This is the last time the URL has to move.

<details>
<summary>Why the move happened now</summary>

The move happened before any third-party package was carried, because the population that pays for
it will never be smaller.

It has the same shape as this feed's own argument about key revocation: a router offline when it
matters cannot be reached at all.

</details>

## Working, and verified rather than assumed

| What | Evidence |
|---|---|
| Feed updates reaching a router | Upstream released 0.14.10 → the update bot opened [#51](https://github.com/owfeed/owfeed-packages/pull/51) with the pins recomputed → a maintainer approved the held check and merged it → `Publish` → the served 25.12 index carries `0.14.10-r1`, read from a router. That was the path before [#61](https://github.com/owfeed/owfeed-packages/pull/61). The row "An update landing and publishing with nobody in the loop" is the same journey without a person |
| Publishing through owfeed's reusable workflow | `publish.yml` calls `feed.yml@v0.5.8` with `secrets: inherit`. A probe (at v0.5.0) measured that a called job's `environment: feed` resolves against this repository, and the signing secrets reached it at their real length |
| An author signature inside every package | `signing.author-keys: ./keys` in `owfeed.yml`, one EC public half pinned per package. An unsigned package is dropped from the index (OWF407), and `tools/check-tree.sh` then fails the publish. A green publish is the evidence |
| Automatic-update tier rules | Six scenarios exercised in a real git repository: manifest/minor merges, major bump holds, `binaries` holds, no `SIG_KEY` holds, a diff touching `SIG_KEY_ID` holds, the daily ceiling holds |
| Verify before read | `tools/fetch.sh` checks the signature before parsing, and cross-checks `repo` and `tag` inside the manifest. The signature says *who*, never *what about* |
| Ingest without a key | The build job runs contributed fetch scripts and never sees the signing key. The key appears only after the bytes are already in an artifact |
| An update landing and publishing with nobody in the loop | `luci-app-footstrap-files 0.1.3`, `luci-theme-footstrap 0.14.11` and `luci-app-gitbackup 0.1.1` each went from an upstream release to `repo.owfeed.org` with no human action: branch pushed, `Check` dispatched, `tools/land-updates.sh` fast-forwarded `main`, `Publish` dispatched. Since then the same path landed `luci-app-footstrap-files 0.1.4` and `luci-theme-footstrap` 0.14.12 to 0.14.20, the last on 2026-11-02, each as an `owfeed-bot` commit on `main` with no pull request. The bot has opened no pull request since [#60](https://github.com/owfeed/owfeed-packages/pull/60) |
| The feed on its own domain | `owfeed verify` passed 17 checks against `https://repo.owfeed.org` on 2026-11-12. luci-theme-footstrap installed the published theme by name from it on a real router, as recorded on 2026-09-06 |

## Built but not yet exercised in anger

**The intake funnel:** `.github/ISSUE_TEMPLATE/package-request.yml` plus
`.github/workflows/intake.yml`.

- It answers correctly when run by hand against a real release.
- No third party has used it: the repository has no `package-request` issue. The first genuine
  request is still the first genuine test.
- The one third-party package so far, `luci-app-podkop-bot`, arrived as a pull request,
  [#66](https://github.com/owfeed/owfeed-packages/pull/66).

## Not built, and why

### A pull request from this bot that can merge itself

There is none. The automation is built around that rather than against it.

- The checks are enforced by `tools/land-updates.sh`, never by the pull request. The script pushes
  only when both conditions hold:
  - every run of `check / build` and `check / check` on that commit is `completed/success`;
  - the diff names nothing but `packages/<name>/upstream.sh`.
- Publishing is unchanged. `update.yml` dispatches `Publish` when the head of `main` has no
  `Publish` run, because a push made with `GITHUB_TOKEN` raises no push event.
- [Issue #53](https://github.com/owfeed/owfeed-packages/issues/53) is what this answers.
  Publishing was the other half of it.

A maintainer is still needed for a pull request the bot cannot land on its own:

- an unsigned or `binaries` package;
- a major bump;
- the third update in a day;
- anything touching a path outside `packages/<name>/upstream.sh`.

<details>
<summary>Why the bot does not open a pull request</summary>

GitHub holds the `pull_request` run of a pull request opened with `GITHUB_TOKEN` in
`action_required` unconditionally: "when a workflow using `GITHUB_TOKEN` creates
or updates a pull request, the resulting `pull_request` event creates workflow runs
in an approval-required state".

The hold reached this organisation between 2026-08-30 20:43Z and 2026-09-01 10:08Z. It was measured
on `attempts/1` of the runs on the `update/*` branches either side of it.

It is not this repository's `fork-pr-contributor-approval` policy. That policy was relaxed to
`first_time_contributors_new_to_github` at repository and organisation level at once. The bot's [#60](https://github.com/owfeed/owfeed-packages/pull/60)
still came back `attempt 1 = action_required` (run 33966648498). Both policies were put back.

GitHub names one fix: "use a GitHub
App installation access token or a personal access token instead of `GITHUB_TOKEN`
when creating or updating the pull request". This feed declines it. An App or a personal token is a
new credential to store and rotate. It would also make every check run under an identity that can
write here.

Not opening the pull request costs nothing instead, because the checks were never enforced by the
pull request.

Required status checks on `main` were tried for this and removed. With both contexts green on the
commit, the push was still refused with `GH006: 2 of 2 required status checks are expected`. GitHub
counts contexts for the branch being pushed to rather than for the branch they ran on.

</details>

### A consumer job on top of the check

`owfeed smoke` proves the channel installs without `--allow-untrusted`. Nothing yet proves the
package that came through it works.

- **The tool exists:** `owlab test --feed`.
- **Its obstacle is gone:** owlab v0.4.0 resolves a `{host}` in the feed URL to whatever address the
  router's tier reaches the runner at. Before, it was a `172.17.0.1` that is right on one machine.
- **Missing:** where to put it. `feed.yml`'s check job builds the tree and does not serve it.

The two options:

- a `post-index` script that serves `out/` and runs owlab;
- a job in this repository that follows the reusable one.

That is a decision about whose workflow owns it, not a missing capability.

### CODEOWNERS as a mechanism

`keys/` is named in CODEOWNERS, and no branch rule enforces the review.

- With a single maintainer, a required review blocks every key addition permanently instead of
  gating it. The author of a pull request cannot approve their own.
- The automation cannot reach `keys/` regardless. The update job writes one `upstream.sh`.
  `tools/land-updates.sh` refuses to push a branch whose diff against `main` names any other path.
- The review becomes a mechanism on the day there is a second maintainer. Until then it is a
  convention.

## Known contradictions

**One key, `keys/vizzletf-release.pub`, covers four upstream repositories.** `keys/README.md` asks
for one key per repository.

- `owfeed verify-artifact` checks the manifest's `repo` line. A manifest cannot be lifted from one
  repository to another, so the shared key is tolerable.
- Separate keys would buy blast radius, not correctness.
- The doctrine says so out loud rather than being quietly contradicted by the table beneath it.
- [CONTRIBUTING.md](CONTRIBUTING.md#sign-every-package-with-your-own-key) asks authors for one key
  per repository too.

## Where to look

- [CONTRIBUTING.md](CONTRIBUTING.md) — how a package gets in, and the tiers *([по-русски](CONTRIBUTING_ru.md))*
- [RUNBOOK.md](RUNBOOK.md) — operating it *([по-русски](RUNBOOK_ru.md))*
- [LEGAL.md](LEGAL.md) — what this feed will and will not carry *([по-русски](LEGAL_ru.md))*
