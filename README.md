# owfeed community packages

*[Русская версия](README_ru.md)*

An OpenWrt package feed for both release lines: apk for 25.12 and later, opkg for 24.10 and earlier.
[owfeed](https://github.com/owfeed/owfeed) builds and publishes it.

- The feed carries other people's packages, byte for byte as their authors built them.
- A router subscribes with one command. The script reads the router's package manager, architecture and release.
- The feed signs the index. It does not sign the packages.
- Installing the feed's key trusts it for every package name. Read [Before you install the key](#before-you-install-the-key).

## Quick start

1. Download the subscribe script, read it, run it. It runs as root.

   ```sh
   wget -O subscribe.sh https://repo.owfeed.org/subscribe.sh && less subscribe.sh && sh subscribe.sh
   ```

   If `wget` fails on HTTPS, the image lacks two packages. Stock images have them; custom builds
   may not. Install them and run step 1 again: `apk add ca-bundle libustream-mbedtls`. On 24.10,
   use `opkg install` instead of `apk add`.

2. Install a package by name: `apk add <name>` on 25.12, `opkg install <name>` on 24.10. The
   script installs no packages.

The one-line form skips the reading step:

```sh
wget -qO- https://repo.owfeed.org/subscribe.sh | sh
```

## What do you want to do?

| I want to… | Go to |
|---|---|
| subscribe a router | [Quick start](#quick-start) |
| know what the script changes | [What the subscribe script does](#what-the-subscribe-script-does) |
| subscribe without the script, 25.12 and later | [By hand on 25.12](#by-hand-on-openwrt-2512-and-later) |
| subscribe without the script, 24.10 and earlier | [By hand on 24.10](#by-hand-on-openwrt-2410-and-earlier) |
| install a downloaded `.apk` file | [Install by name](#install-by-name-from-the-index) |
| upgrade with Attended Sysupgrade | [Attended Sysupgrade](#attended-sysupgrade-drops-these-packages) |
| decide whether to trust the key | [Before you install the key](#before-you-install-the-key) |
| check the key I downloaded | [Check the key you installed](#check-the-key-you-installed) |
| know what the signature proves | [What this feed's signature means](#what-this-feeds-signature-means) |
| report a bug in a package | [At your own risk](#everything-here-is-used-at-your-own-risk) |
| know how packages get updated | [Staying current](#staying-current) |
| find a package's author, licence or source | [Whose packages these are](#whose-packages-these-are) |
| add my package to the feed | [Adding a package](#adding-a-package) |

## What the subscribe script does

It works on either release line.

1. Reads the router's package manager, architecture and release.
2. On 25.12, installs `ca-bundle` and `libustream-mbedtls`, which HTTPS needs.
3. Installs the key.
4. Adds the repository.
5. Keeps the key and the repository across a firmware upgrade. It writes
   `/lib/upgrade/keep.d/owfeed-packages`, the same file the commands below write.

- Re-running it changes nothing twice. On 24.10 it deletes its old line from
  `/etc/opkg/customfeeds.conf` before it adds the new one.
- It installs no packages. Run `apk add <name>` or `opkg install <name>` after it.
- `owfeed index` generates it from the config that laid this feed out. So it cannot document a URL the
  feed does not serve. Read it anyway: it runs as root.

## By hand on OpenWrt 25.12 and later

```sh
# HTTPS needs these. Stock images have them; custom builds may not.
apk add ca-bundle libustream-mbedtls

wget https://repo.owfeed.org/owfeed-packages.pem -O /etc/apk/keys/owfeed-packages.pem
echo "https://repo.owfeed.org/releases/25.12/$(cat /etc/apk/arch)/packages.adb" > /etc/apk/repositories.d/owfeed-packages.list

# Keep the key and the repository across a firmware upgrade.
mkdir -p /lib/upgrade/keep.d
printf '%s\n' /etc/apk/keys/owfeed-packages.pem /etc/apk/repositories.d/owfeed-packages.list > /lib/upgrade/keep.d/owfeed-packages

apk update && apk add luci-theme-footstrap
```

`luci-theme-footstrap` is one package this feed carries. Put the name of the package you want.

## By hand on OpenWrt 24.10 and earlier

```sh
# The key file's NAME is its id — opkg looks it up by that.
mkdir -p /etc/opkg/keys
wget https://repo.owfeed.org/9040356b214084da -O /etc/opkg/keys/9040356b214084da

echo "src/gz owfeed-packages https://repo.owfeed.org/releases/24.10/$(. /etc/openwrt_release; echo $DISTRIB_ARCH)" >> /etc/opkg/customfeeds.conf

# Keep the key and the repository across a firmware upgrade.
mkdir -p /lib/upgrade/keep.d
printf '%s\n' /etc/opkg/keys/9040356b214084da /etc/opkg/customfeeds.conf > /lib/upgrade/keep.d/owfeed-packages

opkg update && opkg install luci-theme-footstrap
```

- Run this block once. `>>` appends, so a second run adds a second `src/gz owfeed-packages` line.
  The subscribe script deletes the old line first, so it is safe to re-run.
- `luci-theme-footstrap` is one package this feed carries. Put the name of the package you want.

## Install by name from the index

Add the repository and install by name. Do not install the package file directly.

- On 25.12, `apk add ./file.apk` writes a pin on the package's content hash into `/etc/apk/world`.
  That file survives sysupgrade, so the package never upgrades from this feed again.
- `apk add ./file.apk` and LuCI's *Upload Package* need `--allow-untrusted` for packages from here.
- Installing by name out of the index is the documented way and the only one that upgrades.

## Attended Sysupgrade drops these packages

Attended Sysupgrade does not carry these packages across.

- `owut` forwards no custom repositories.
- The sysupgrade server's `repository_allow_list` is empty by default, which denies everything.

## Before you install the key

Install the key because you trust who publishes it. A page telling you to is not a reason.

- A key in `/etc/apk/keys` is trusted for **every package name**, not only the ones this feed carries.
- It validates an index claiming any name at all. So this feed, or anyone holding a compromised key,
  could offer a higher version of a base package such as `dropbear` or `base-files` and win the resolution.
- apk has no revocation: no CRL, no expiry, no way to say a key is dead.

## Check the key you installed

Compare the key on your router with a copy fetched another way. The same hash means the same file.

| Release line | Key file on the router | Published at |
|---|---|---|
| 25.12 and later | `/etc/apk/keys/owfeed-packages.pem` | `https://repo.owfeed.org/owfeed-packages.pem` |
| 24.10 and earlier | `/etc/opkg/keys/9040356b214084da` | `https://repo.owfeed.org/9040356b214084da` |

1. On the router, print the hash of the key file:

   ```sh
   sha256sum /etc/apk/keys/owfeed-packages.pem
   ```

2. On another machine, on another network, fetch the published key and print its hash:

   ```sh
   curl -s https://repo.owfeed.org/owfeed-packages.pem | sha256sum
   ```

3. Compare the two hashes. For the opkg key, use its path and URL from the table.

- The opkg key's id is `9040356b214084da`. The key file's name is that id.
- This repository holds no copy of the feed's own public key. The feed root is the only place it is
  published, so the cross-check is a second fetch over a path you trust.

## What this feed's signature means

**This feed signs the index. It does not sign the packages.**

The signature means one thing: these are the bytes this feed published, and they came from the
author whose key is pinned here. It is a statement about the channel and about provenance. It makes
no statement about content, quality, safety, legality or suitability. Do not read it as one.

Nothing in this repository is rebuilt or modified. You install the author's own file, byte for byte.

### What this feed checks

- The release exists at the repository and tag pinned in `packages/<name>/upstream.sh`.
- The author's detached signature over it verifies against a public key pinned in
  [`keys/`](keys/), and the manifest names the repository and tag it claims to be from.
- The bytes match the `sha256` recorded here, so they have not changed since a person looked.
- The resulting tree is internally coherent (`owfeed doctor`) and installs on a stock OpenWrt
  image without `--allow-untrusted` (`owfeed smoke`).

### What this feed does not check

- What the code does. No review, no audit, no analysis, of the source or of the binary.
- Whether it is safe. No security assessment of any package, its dependencies, or what it does once
  running.
- Whether it works, or is fit for anything. `smoke` proves a package installs. It says nothing about
  whether it does what its author says.
- Whether it is lawful where you are. Software legal in one country is not in another. This feed
  makes no assessment of any jurisdiction, including yours.
- Whether its declared licence, description or metadata are true. Those are the author's assertions,
  carried through unchanged.

<details>
<summary>Why the feed signs the index and not the packages</summary>

The distinction is the whole of what the signature claims. The signature can read as a
broader claim than it is.

- apk takes its trust from the index. The index is signed, and apk checks every package against the
  hash recorded in it. Signing the index is what makes the feed installable at all.
- Only this feed can produce an index describing everything it carries. The authors' keys cannot sign
  it, so the feed cannot avoid signing it.
- Signing each package as well would put this feed's signature inside a file somebody else built.
  That is a claim about an artifact. The feed makes claims only about the channel that carried it. It
  did not write these packages and does not review them.
- A package that arrives signed by its author keeps that signature. apk signature blocks are
  additive, and nothing here strips them. You install the author's file, distributed through a
  signed channel.
- Two keys sign the indexes, because each package manager verifies only its own scheme: apk checks
  EC prime256v1, opkg checks usign.
- The `--allow-untrusted` requirement for `apk add ./file.apk` and *Upload Package* puts this feed in
  the same position as OpenWrt itself. Its own 25.12 packages are unsigned individually, so that path
  already requires the flag for everything in the official feeds. Installing by name is unaffected.

</details>

### Everything here is used at your own risk

The packages are other people's software, distributed as-is with no warranty of any kind. Their
author is responsible for them. Send questions, bug reports and complaints about a package to its
author. `apk info <name>` on the router shows the author's repository.

<details>
<summary>The full terms</summary>

- This feed did not write any of the packages and does not review them. It knows nothing of what a
  package does beyond what its author declares.
- No warranty of any kind: the same terms every package's own licence already states.
- Responsibility for a package rests entirely with its author: its contents, its behaviour, its
  security, its lawfulness, and the truth of everything it declares about itself.
- The author's repository is in the package metadata. Questions, bug reports and complaints go to
  the author, not here.
- Installing a package from this feed means running software written by a third party that neither
  you nor this feed has audited. That decision is yours, and so are its consequences.
- If you believe something here is unlawful or infringes your rights, [SECURITY.md](SECURITY.md)
  says where to send that. Such a report is acted on, without argument.

</details>

## Staying current

A scheduled job proposes updates. CI checks each one on a real OpenWrt image before it reaches `main`.

1. Every few hours, the job asks each upstream for its latest release.
2. When one appears, it pushes a branch with the new version and its checksums. It recomputes the
   checksums from the bytes the release served. The branch contains nothing else.
3. CI builds the feed, indexes it, checks it and installs it on a real OpenWrt image.
4. The branch reaches `main` automatically or through a pull request, as the table shows.

| Update | Lands |
|---|---|
| Upstream publishes a detached signature, package sets `AUTO_MERGE="yes"` | automatically, once checks pass |
| A new package | pull request, waits for a maintainer |
| An unsigned release | pull request, waits for a maintainer |
| A major version bump | pull request, waits for a maintainer |
| A third update to the same package in a day | pull request, waits for a maintainer |
| A diff touching more than one `packages/<name>/upstream.sh` | pull request, waits for a maintainer |

- An automatic update needs no person. A later run fast-forwards `main` onto the branch once
  `check / build` and `check / check` are green on that exact commit.
- `tools/land-updates.sh` refuses the push when they are not. A context with no run at all counts as
  a refusal. The checks are never skipped.

<details>
<summary>Why the job proposes and does not publish</summary>

- Picture a job that fetched whatever an upstream published since the last run and signed it with
  this feed's key. It would hand that key's authority to every upstream.
- It would also make the checksum pins decoration. Recomputed from whatever arrived, they would
  attest to nothing.
- A detached signature beside an upstream's artifact is provenance from someone other than this
  feed. That is why such a package may set `AUTO_MERGE="yes"`.
- A package this feed has never carried arrives with a key it has never pinned. That is a change
  under `keys/`, and nothing lands there unattended.

</details>

## Whose packages these are

Every package declares its licence and its upstream. Both travel into the index and into `apk info`
on the router, so a user can always find out whose software they installed.

- Where a package is copyleft, its corresponding source is served from this feed, at
  [`/sources/`](https://repo.owfeed.org/sources/index.txt).
- That is the same origin as the binary, which is what GPLv2 §3 asks of anyone distributing one.
- A copyleft package with no source in the tree fails the publish. This is a gate, enforced on every
  publish.
- Redistributing someone else's work needs more than a licence that allows it.
  [LEGAL.md](LEGAL.md) records what this feed read and what it decided.
  *([Русский](LEGAL_ru.md))*

## Adding a package

A package here is a file of values: a version, its checksums, which key signs it. There is no
per-package script.

- New to publishing? Start with the [cookbook](https://owfeed.org/cookbook/). It covers building and
  signing a package, which has to happen before this feed can carry it.
  *([Русский](https://owfeed.org/cookbook/ru/))*
- [CONTRIBUTING.md](CONTRIBUTING.md): adding a package, updating one, letting it update itself.
  *([Русский](CONTRIBUTING_ru.md))*
- [RUNBOOK.md](RUNBOOK.md): what runs when, and what to do when something is red.
  *([Русский](RUNBOOK_ru.md))*
- Pull requests run the whole pipeline with a throwaway key, so a fork never comes near the feed's own.

<details>
<summary>Where this feed sits among owlab and owfeed</summary>

This feed is one end of a longer lifecycle.

| Project | Role |
|---|---|
| [owlab](https://github.com/owfeed/owlab) | develops a package and proves it works |
| [owfeed](https://github.com/owfeed/owfeed) | signs and indexes it |
| this repository | decides whose keys it trusts and hands the result to routers |

[ECOSYSTEM.md](https://github.com/owfeed/owfeed/blob/main/docs/ECOSYSTEM.md) writes down the
boundary between the three, including why nothing is ever built here.
[STATUS.md](STATUS.md) says how much of this feed's side exists, and what is still open.

</details>
