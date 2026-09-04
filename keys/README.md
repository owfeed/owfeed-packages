# Pinned upstream keys

The public keys of the people whose packages this feed carries. Two kinds, doing two different
jobs, and both are pinned here for the same reason.

**`*.pub` — usign.** Verifies the detached signature beside a release, before this feed reads or
unpacks anything. It answers *did the author publish these bytes*, at ingest time, and then it is
done: the signature it checks never leaves this repository.

**`*.pem` — EC prime256v1.** The key an author signs the package itself with. That signature is
inside the `.apk` and travels all the way to the router, so it can be checked by anyone, at any
time, against a copy of the key obtained from somewhere that is not this feed. It is the only
claim about a package that survives the feed — this feed signs the index, and an index proves only
that this feed published a file.

Pinned rather than fetched: whoever can replace an artifact can replace the signature beside it and
the key it names. A key is only a check once it comes from somewhere the attacker does not control,
and here that is this repository's history.

Adding or changing a key is the one diff in this repository that deserves a second look. Verify the
key out of band — against the author's repository, a fingerprint they published elsewhere, anything
that is not the release you are about to trust it for.

### usign — release signatures, checked at ingest

| key | id | covers |
|---|---|---|
| `vizzletf-release.pub` | `18c63865e2bcf8d6` | `luci-theme-footstrap`, `luci-app-footstrap-cmd`, `luci-app-footstrap-files`, `luci-app-gitbackup` |
| `podkop-updater.pub` | `37ddece4c0eef357` | `podkop-updater` |

### EC — package signatures, checked on the router by anyone who wants to

One per repository, which is what the note below asks for and what these meet.

| key | identity | covers |
|---|---|---|
| `luci-theme-footstrap.pub.pem` | `9bdfe74fb2b896642afbdebd9a4d653c` | `luci-theme-footstrap` |
| `luci-app-footstrap-cmd.pub.pem` | `89d0f51c214fb6d9aeb71558ec3dddf4` | `luci-app-footstrap-cmd` |
| `luci-app-footstrap-files.pub.pem` | `b965f2fd1eb4a823b2e1f98736ce8572` | `luci-app-footstrap-files` |
| `luci-app-gitbackup.pub.pem` | `ed03b80eb79ce317685eb5edc6b23dd0` | `luci-app-gitbackup` |
| `podkop-updater.pub.pem` | `2e6784ccfa5af1f908b5904d26067249` | `podkop-updater` |

`signing.author-keys` in `owfeed.yml` points at this directory, and `owfeed doctor` fails any
package that carries no signature by one of these. Only files ending in `.pem` are read for that; the usign
keys sit alongside and are used by `tools/fetch.sh`.

A key per upstream repository rather than one per person is what this feed wants, and the table
above does not yet meet it: `vizzletf-release.pub` covers four repositories, because one release
pipeline signs them all.

The reason to want it: a signature says who wrote something and never what it is about, so one key
across several repositories is how a manifest lifted from one of them verifies perfectly as
another. `owfeed` checks the `repo` line in the manifest as well, and that closes the hole on its
own — which is why the shared key is tolerable rather than urgent. What separate keys would add is
blast radius: a compromise of one would reach nothing else.

Adding or changing a key is the diff `.github/CODEOWNERS` names. Auto-merge cannot reach it by
construction rather than by a check: it is only ever requested on a pull request the hourly job
itself opened, and that job writes one file — `packages/<name>/upstream.sh` — refusing even that
when the diff moves anything but the version and its checksums. A key arrives in a pull request a
person opened, and those are never auto-merged.

The code-owner review is not enforced by a branch rule. That needs a reviewer who is not the
author, and with a single maintainer it would block every key addition permanently rather than
gate it. Turn it on when there is a second maintainer.
