# Pinned upstream keys

This directory holds the public keys of the people whose packages this feed carries.

- Two kinds of key, for two jobs: `*.pub` (usign) and `*.pem` (EC prime256v1).
- Both are pinned in this repository for the same reason: whoever replaces an artifact could also replace a key fetched beside it.
- Adding or changing a key is the one diff in this repository that deserves a second look.

## What do you want to do?

| I want to… | Go to |
|---|---|
| know what each kind of key does | [Two kinds of key](#two-kinds-of-key) |
| find the key for a package | [usign keys](#usign-release-signatures-checked-at-ingest), [EC keys](#ec-package-signatures-checked-on-the-router-by-anyone-who-wants-to) |
| add or change a key | [Adding or changing a key](#adding-or-changing-a-key) |
| know how the tools read this directory | [How the tools use these keys](#how-the-tools-use-these-keys) |

## Two kinds of key

| | `*.pub`, usign | `*.pem`, EC prime256v1 |
|---|---|---|
| verifies | the detached signature beside a release | the author's signature on the package itself |
| checked | at ingest, before this feed reads or unpacks anything | on the router, by anyone, at any time |
| signature travels | never leaves this repository | inside the `.apk`, all the way to the router |

- The usign check answers *did the author publish these bytes*, at ingest time, and then it is done.
- The EC signature can be checked against a copy of the key obtained from somewhere other than this
  feed. It is the only claim about a package that survives the feed. This feed signs the index, and
  an index proves only that this feed published a file.

<details>
<summary>Why the keys are pinned here and not fetched</summary>

Whoever can replace an artifact can replace the signature beside it and the key it names. A key is
a check only once it comes from somewhere the attacker does not control. Here that place is this
repository's history.

</details>

## Adding or changing a key

Verify the key out of band before you add it.

- Check it against the author's repository, a fingerprint they published elsewhere, anything that is
  not the release you are about to trust it for.
- Adding or changing a key is the diff `.github/CODEOWNERS` names.
- A key arrives in a pull request a person opened. Nothing pushes those.

<details>
<summary>Why the automation cannot reach this directory</summary>

- The update job writes one file, `packages/<name>/upstream.sh`. It refuses even that when the diff
  moves anything but the version and its checksums.
- `tools/land-updates.sh` pushes an update onto `main`. It refuses any branch whose diff names another
  path.
- No branch rule enforces the code-owner review. That needs a reviewer who is not the author. With a
  single maintainer it would block every key addition permanently. Turn it on when there is a second
  maintainer.

</details>

## usign: release signatures, checked at ingest

| key | id | covers |
|---|---|---|
| `vizzletf-release.pub` | `18c63865e2bcf8d6` | `luci-theme-footstrap`, `luci-app-footstrap-cmd`, `luci-app-footstrap-files`, `luci-app-gitbackup` |
| `podkop-updater.pub` | `37ddece4c0eef357` | `podkop-updater` |
| `luci-app-podkop-bot.pub` | `d6971b8a1b9a8ba4` | `luci-app-podkop-bot` |

This feed wants a key per upstream repository. A key per person does not meet that, and this table does not meet that
yet: `vizzletf-release.pub` covers four repositories, because one release pipeline signs them all.

<details>
<summary>Why one key per repository, and why the shared key is tolerable</summary>

- A signature says who wrote something and never what it is about. So with one key across several
  repositories, a manifest lifted from one of them verifies perfectly as another.
- `owfeed` checks the `repo` line in the manifest as well, and that closes the hole on its own. So
  the shared key is tolerable, and splitting it is not urgent.
- Separate keys would limit the blast radius: a compromise of one would reach nothing else.

</details>

## EC: package signatures, checked on the router by anyone who wants to

One key per repository, which is what the note above asks for and what these meet.

| key | identity | covers |
|---|---|---|
| `luci-theme-footstrap.pub.pem` | `9bdfe74fb2b896642afbdebd9a4d653c` | `luci-theme-footstrap` |
| `luci-app-footstrap-cmd.pub.pem` | `89d0f51c214fb6d9aeb71558ec3dddf4` | `luci-app-footstrap-cmd` |
| `luci-app-footstrap-files.pub.pem` | `b965f2fd1eb4a823b2e1f98736ce8572` | `luci-app-footstrap-files` |
| `luci-app-gitbackup.pub.pem` | `ed03b80eb79ce317685eb5edc6b23dd0` | `luci-app-gitbackup` |
| `podkop-updater.pub.pem` | `2e6784ccfa5af1f908b5904d26067249` | `podkop-updater` |
| `luci-app-podkop-bot.pub.pem` | `d4627673734fe2b54f54770c2c1d3c6c` | `luci-app-podkop-bot` |

## How the tools use these keys

- `signing.author-keys` in `owfeed.yml` points at this directory.
- `owfeed doctor` fails any package that carries no signature by one of these. It reads only files
  ending in `.pem` for that.
- The usign keys sit alongside. `tools/fetch.sh` uses them.
