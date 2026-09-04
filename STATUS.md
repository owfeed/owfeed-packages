# What is built in this feed, and what is not

*[ECOSYSTEM.md](https://github.com/owfeed/owfeed/blob/main/docs/ECOSYSTEM.md) in
owfeed says where the boundaries between owlab, owfeed and this feed run and why.
This file says how much of this feed's side of that exists, as of 2026-09-04.*

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
| Feed updates reaching a router | Upstream released 0.14.10 → the hourly bot opened #51 with the pins recomputed → a maintainer approved the held check → merge → `Publish` → the served 25.12 index carries `0.14.10-r1`, read from a router |
| Publishing through owfeed's reusable workflow | `publish.yml` calls `feed.yml@v0.5.0` with `secrets: inherit`; a probe measured that a called job's `environment: feed` resolves against this repository, and the signing secrets reached it at their real length |
| An author signature inside every package | `signing.author-keys: ./keys` in `owfeed.yml`, one EC public half pinned per package; an unsigned package is dropped from the index (OWF407) and `tools/check-tree.sh` then fails the publish, so a green publish is the evidence |
| Auto-merge tier rules | Six scenarios exercised in a real git repository: manifest/minor merges, major bump holds, `binaries` holds, no `SIG_KEY` holds, a diff touching `SIG_KEY_ID` holds, the daily ceiling holds |
| Verify before read | `tools/fetch.sh` checks the signature before parsing, and cross-checks `repo` and `tag` inside the manifest — the signature says *who*, never *what about* |
| Ingest without a key | The build job runs contributed fetch scripts and never sees the signing key; the key appears only after the bytes are already in an artifact |
| The feed on its own domain | `owfeed verify` passes six checks against `https://repo.owfeed.org`, and luci-theme-footstrap installs the published theme by name from it on a real router |

## Built but not yet exercised in anger

- **The intake funnel** (`.github/ISSUE_TEMPLATE/package-request.yml` plus
  `.github/workflows/intake.yml`) answers correctly when run by hand against a
  real release. No third party has used it, so the first genuine request is still
  the first genuine test.

## Not built, and why

**An update that merges and publishes unattended.** `AUTO_MERGE="yes"` arms
GitHub's auto-merge, and it still waits for a person. The hourly job opens its
pull requests as `app/github-actions`, and this repository's
`fork-pr-contributor-approval` policy is `first_time_contributors`, so that
account's `pull_request` run is held in `action_required`. `check-updates.sh`
dispatches `Check` on the update branch, which reports the contexts the branch
protection requires, but auto-merge waits for the held run rather than for the
dispatched one — measured on #51, where the dispatched run was green and the pull
request stayed open until the held one was approved. Publishing after the merge is
answered: `update.yml` dispatches `Publish` when the head of `main` has no
`Publish` run, because a merge made with `GITHUB_TOKEN` raises no push event. Both
halves are [issue #53](https://github.com/owfeed/owfeed-packages/issues/53); the
fix for the first is a pull-request author the approval policy does not hold.

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
approve their own. Auto-merge cannot reach `keys/` regardless — it is only ever
requested on pull requests the update job itself opened, and that job writes one
`upstream.sh`. The review becomes a mechanism on the day there is a second
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
