# What is built in this feed, and what is not

*[ECOSYSTEM.md](https://github.com/owfeed/owfeed/blob/main/docs/ECOSYSTEM.md) in
owfeed says where the boundaries between owlab, owfeed and this feed run and why.
This file says how much of this feed's side of that exists, as of 2026-09-06.*

It lives here rather than in the shared document because a shared status file goes
stale on exactly the facts none of its own CI touches. Beside the thing it
describes, a claim that stops being true is a line in the pull request that made
it untrue.

**The feed moved to `https://repo.owfeed.org` on 2026-07-29**, from
`https://vizzletf.github.io/owfeed-packages`. Routers subscribed to the old URL
carry it in `/etc/apk/repositories.d/`, listed in `/etc/sysupgrade.conf` so it
survives a firmware upgrade, and GitHub does not redirect Pages across owners:
they get a 404 from `apk update` and stop receiving updates, with nothing to be
done for them from here. That is the same shape as this feed's own argument about
key revocation -- a router offline when it matters cannot be reached at all. The
move happened now, before any third-party package was carried, because the
population that pays for it will never be smaller. On a domain this project owns,
it is the last time the URL has to move.

## Working, and verified rather than assumed

| | Evidence |
|---|---|
| Feed updates reaching a router | Upstream released 0.14.10 → the update bot opened #51 with the pins recomputed → a maintainer approved the held check and merged it → `Publish` → the served 25.12 index carries `0.14.10-r1`, read from a router. That was the path before #61; the row below is the same journey without a person |
| Publishing through owfeed's reusable workflow | `publish.yml` calls `feed.yml@v0.5.0` with `secrets: inherit`; a probe measured that a called job's `environment: feed` resolves against this repository, and the signing secrets reached it at their real length |
| An author signature inside every package | `signing.author-keys: ./keys` in `owfeed.yml`, one EC public half pinned per package; an unsigned package is dropped from the index (OWF407) and `tools/check-tree.sh` then fails the publish, so a green publish is the evidence |
| Automatic-update tier rules | Six scenarios exercised in a real git repository: manifest/minor merges, major bump holds, `binaries` holds, no `SIG_KEY` holds, a diff touching `SIG_KEY_ID` holds, the daily ceiling holds |
| Verify before read | `tools/fetch.sh` checks the signature before parsing, and cross-checks `repo` and `tag` inside the manifest — the signature says *who*, never *what about* |
| Ingest without a key | The build job runs contributed fetch scripts and never sees the signing key; the key appears only after the bytes are already in an artifact |
| An update landing and publishing with nobody in the loop | `luci-app-footstrap-files 0.1.3`, `luci-theme-footstrap 0.14.11` and `luci-app-gitbackup 0.1.1` each went from an upstream release to `repo.owfeed.org` with no human action: branch pushed, `Check` dispatched, `tools/land-updates.sh` fast-forwarded `main`, `Publish` dispatched |
| The feed on its own domain | `owfeed verify` passes six checks against `https://repo.owfeed.org`, and luci-theme-footstrap installs the published theme by name from it on a real router |

## Built but not yet exercised in anger

- **The intake funnel** (`.github/ISSUE_TEMPLATE/package-request.yml` plus
  `.github/workflows/intake.yml`) answers correctly when run by hand against a
  real release. No third party has used it, so the first genuine request is still
  the first genuine test.

## Not built, and why

**A pull request from this bot that can merge itself.** There is none, and the
automation is built around that rather than against it. GitHub holds the
`pull_request` run of a pull request opened with `GITHUB_TOKEN` in
`action_required` unconditionally — "when a workflow using `GITHUB_TOKEN` creates
or updates a pull request, the resulting `pull_request` event creates workflow runs
in an approval-required state" — and the hold reached this organisation between
2026-08-30 20:43Z and 2026-09-01 10:08Z, measured on `attempts/1` of the runs on
the `update/*` branches either side of it. It is not this repository's
`fork-pr-contributor-approval` policy: relaxed to
`first_time_contributors_new_to_github` at repository and organisation level at
once, the bot's #60 still came back `attempt 1 = action_required` (run
33966648498), and both policies were put back. GitHub names one fix — "use a GitHub
App installation access token or a personal access token instead of `GITHUB_TOKEN`
when creating or updating the pull request" — and this feed declines it: an App or
a personal token is a new credential to store and rotate, and it would also make
every check run under an identity that can write here. Not opening the pull request
costs nothing instead, because the checks were never enforced by the pull request.
They are enforced by `tools/land-updates.sh`, which pushes only when every run of
`check / build` and `check / check` on that commit is `completed/success` and the
diff names nothing but `packages/<name>/upstream.sh`. Required status checks on
`main` were tried for this and removed: with both contexts green on the commit, the
push was still refused with `GH006: 2 of 2 required status checks are expected`,
because GitHub counts contexts for the branch being pushed to rather than for the
branch they ran on.
What still needs a maintainer is a pull request the bot cannot land on its own: an
unsigned or `binaries` package, a major bump, the third update in a day, and
anything touching a path outside `packages/<name>/upstream.sh`.
[Issue #53](https://github.com/owfeed/owfeed-packages/issues/53) is what this
answers. Publishing was the other half of it and is unchanged: `update.yml`
dispatches `Publish` when the head of `main` has no `Publish` run, because a push
made with `GITHUB_TOKEN` raises no push event.

**A consumer job on top of the check.** `owfeed smoke` proves the channel installs
without `--allow-untrusted`; nothing yet proves the package that came through it
works. `owlab test --feed` is the tool and owlab v0.4.0 removed its obstacle — a
`{host}` in the feed URL resolves to whatever address the router's tier reaches
the runner at, instead of a `172.17.0.1` that is right on one machine. What is
missing is where to put it: `feed.yml`'s check job builds the tree and does not
serve it, so this is either a `post-index` script that serves `out/` and runs
owlab, or a job in this repository that follows the reusable one. That is a
decision about whose workflow owns it, not a missing capability.

**CODEOWNERS as a mechanism.** `keys/` is named, and no branch rule enforces the
review. With a single maintainer a required review blocks every key addition
permanently instead of gating it, because the author of a pull request cannot
approve their own. The automation cannot reach `keys/` regardless — the update job
writes one `upstream.sh`, and `tools/land-updates.sh` refuses to push a branch whose
diff against `main` names any other path. The review becomes a mechanism on the day there is a second
maintainer, and until then it is a convention.

## Known contradictions

One key, `keys/vizzletf-release.pub`, covers four upstream repositories while
`keys/README.md` asks for one key per repository. `owfeed verify-artifact` checks
the manifest's `repo` line, so a manifest cannot be lifted from one to the other
and the shared key is tolerable — what separate keys would buy is blast radius,
not correctness. The doctrine says so out loud rather than being quietly
contradicted by the table beneath it.

## Where to look

- [CONTRIBUTING.md](CONTRIBUTING.md) — how a package gets in, and the tiers *([по-русски](CONTRIBUTING_ru.md))*
- [RUNBOOK.md](RUNBOOK.md) — operating it *([по-русски](RUNBOOK_ru.md))*
- [LEGAL.md](LEGAL.md) — what this feed will and will not carry *([по-русски](LEGAL_ru.md))*
