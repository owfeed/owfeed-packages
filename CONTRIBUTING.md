# Add a package to this feed

*[Русская версия](CONTRIBUTING_ru.md)*

This page is for package authors who want this feed to carry their package. It covers both sides:
what you do in your own repository, and what goes into this one.

- **A package here is a file of values**, `packages/<name>/upstream.sh`. One shared implementation
  fetches every package, so an update rewrites data, not code. Adding a package never starts with
  copying somebody else's shell.
- **Sign every package with your own EC key.** The pipeline refuses a package without it.
- **Publish a signed manifest with `owfeed release` if you can.** Then updates land without a person.
- **Asking for a package to be carried means you accept [the terms](#what-you-are-agreeing-to).**

```
packages/<name>/upstream.sh   the version, the checksums, which key signs it
packages/<name>/files/…       optional: what the feed adds, e.g. an init script
keys/…                        pinned public keys of the people whose packages we carry
owfeed.yml                    a packages: entry, only when owfeed has to build it
```

## What do you want to do?

| I want to | Go to |
|---|---|
| Know what I am responsible for | [What you are agreeing to](#what-you-are-agreeing-to) |
| Set up signing | [Sign every package with your own key](#sign-every-package-with-your-own-key) |
| Create the release key `SIG_KEY` names | [The usign key, for signed releases](#the-usign-key-for-signed-releases) |
| Submit a package | [Request the package, then open a pull request](#request-the-package-then-open-a-pull-request) |
| Add a package | [Add a package](#add-a-package) |
| Publish from my own CI | [I build in my own CI](#i-build-in-my-own-ci-and-want-my-package-in-this-feed) |
| Update a package by hand | [Update a package](#update-a-package) |
| Let updates land on their own | [Let a package update itself](#let-a-package-update-itself) |
| Fix what a check refused | [What the checks will refuse](#what-the-checks-will-refuse) |
| Carry someone else's package | [Carry somebody else's package](#carry-somebody-elses-package) |

---

## What you are agreeing to

Submitting a package here means you assert all of the following, and remain solely responsible for
it. The feed distributes. It does not review, and it cannot answer for any of this.

- **You have the right to have it distributed.** The licence permits redistribution, its conditions
  are met, and no trademark or other right of a third party stands in the way.
- **You are responsible for what is in it.** Its contents, behaviour, security and lawfulness are
  yours. This feed does not audit code, assess security, or judge legality in any jurisdiction.
- **Its metadata is true.** The declared licence, description and upstream URL are assertions you
  make. They are carried through unchanged and shown to users by `apk info`.
- **You will handle reports about it.** Bug reports, security reports and complaints about the
  package go to you. The feed will forward what reaches it and can suspend the package. That is the
  whole of what it can do.

### Suspension, claims and removal

- **Suspension.** A package can be suspended at any time, for any reason, without notice: a credible
  complaint, a licence question, a stale upstream, or no reason given. There is no entitlement to
  remain in this feed and no undertaking to keep carrying anything.
- **Claims.** If a claim is brought about your package, it is yours to answer. You will be told about
  it and given the chance to respond, and the package comes out of the feed while that happens.
- **Cost.** To the extent the law allows, you carry the cost of any claim arising from software you
  asked this feed to distribute. This feed did not write it, does not review it, and is distributing
  it at your request.
- **Removal.** Repeated substantiated claims end the arrangement. After two upheld claims, or if you
  ignore notices forwarded to you, the package is removed and your key is unpinned from `keys/`. The
  removal is an ordinary commit; the reason is in it.

### How you accept

Adding a `packages/<name>/upstream.sh` naming your repository, or asking for one to be added, is how
you accept all of the above. If you do not accept, do not ask for the package to be carried. You lose
nothing by publishing signed releases yourself, which is what
[the cookbook](https://owfeed.org/cookbook/) describes.

### Neutral descriptions only

`description:` says what a package *is* in technical terms. It says nothing about what the package is
for, what it circumvents, or who should want it. LuCI shows this string to users and it travels into
the index. Keep it factual and under 512 bytes. The same applies to anything added to this
repository's documentation.

## Sign every package with your own key

This feed does not publish a package it cannot attribute. `owfeed doctor` fails any package that
carries no signature by a pinned key, and `owfeed publish` refuses the tree. The pipeline enforces
this; it is not a request.

1. Create an EC key once, outside any git working tree, and store it as a CI secret:

   ```sh
   owfeed keygen -o author.pem          # once, outside any git working tree
   gh secret set OWFEED_AUTHOR_KEY < author.pem
   ```

2. In your release job, after the build and before you upload anything, sign the packages:

   ```sh
   owfeed sign --key env:OWFEED_AUTHOR_KEY
   ```

3. Send the **public** half, `author.pub.pem`, with the pull request that adds your package. It is
   pinned as `keys/<package>.pub.pem`.

Use one key per repository. A signature says who wrote something and never what it is about. A key
shared across repositories vouches for all of them at once.

### Which keys you need

| Key | You need it for | Create it with | Files written | Pinned here as |
|---|---|---|---|---|
| EC prime256v1 | every package: `owfeed sign` puts the signature inside it | `owfeed keygen -o author.pem` | `author.pem` (private, mode 0600), `author.pub.pem` (public) | `keys/<package>.pub.pem` |
| usign | signed releases: `owfeed release` and the `.sig` beside each asset | `owfeed keygen -usign -o ~/keys/example-daemon.sec` | `example-daemon.sec` (private, mode 0600), `example-daemon.pub` (public) | `keys/example-daemon.pub`, the file `SIG_KEY` names |

- `-o` sets the private key's path. The public half goes beside it, with the extension replaced.
- `keygen` refuses to write a key inside a git working tree, unless you pass `--force`.
- Send only the public halves. Keep both private keys out of git: neither can be revoked.

### The usign key, for signed releases

You need it for `KIND="manifest"`, and for any package that sets `AUTO_MERGE="yes"`.

1. Create the key once, outside any git working tree, and store it as a CI secret:

   ```sh
   owfeed keygen -usign -o ~/keys/example-daemon.sec
   gh secret set OWFEED_RELEASE_KEY < ~/keys/example-daemon.sec
   ```

   `owfeed release` reads `env:OWFEED_RELEASE_KEY` unless you pass `--key`.

2. Note the `key id:` line `keygen` prints. It is 16 hex digits.
3. Send the public half, `example-daemon.pub`, with the pull request. It is pinned as
   `keys/example-daemon.pub`.
4. In `packages/<name>/upstream.sh`, set both values:

   | Variable | Value |
   |---|---|
   | `SIG_KEY` | the pinned public key, as a path from the repository root: `keys/example-daemon.pub` |
   | `SIG_KEY_ID` | the key id. `tools/fetch.sh` passes it to `owfeed verify-artifact --key-id`, which refuses a signature by any other key. |

To print the id of a `.pub` file later, decode bytes 3 to 10 of its second line:

```sh
sed -n 2p keys/example-daemon.pub | base64 -d | od -An -tx1 -j2 -N8 | tr -d ' \n'
```

One key per repository applies to this key too. One pinned usign key does not meet it yet: see
[Known contradictions in STATUS.md](STATUS.md#known-contradictions).

<details><summary>Why the author signs, and the release signature is not enough</summary>

The usign signature beside a release is checked once, here, at ingest, and then it is gone. The EC
signature is inside the `.apk` and reaches the router. Anyone can take a published package, fetch your
key from somewhere that is not this feed, and confirm you built it. That works a year later, in a
dispute, without trusting anyone here.

The feed's own signature cannot do that. It is on the index, and an index proves only that this feed
published a file.

Your signature also fixes what nothing else can. This feed signs the index and not the packages.
Without your signature, a published `.apk` carries no evidence of origin at all. "The author is
responsible for this package" would be a sentence with nothing behind it.

**The key you send is not what is trusted.** What is trusted is the copy committed to `keys/`,
because a person looked at it and their name is on the merge. A key travelling beside a release
proves nothing on its own: whoever replaced the package would replace the key too. Its use is that it
can disagree with the pin. That is how a rotated or substituted key gets noticed.

</details>

## Add a package

1. Pick the shape by what your upstream publishes, and write `packages/<name>/upstream.sh` for it.
2. If the package has to reach 24.10 routers too, check [both release lines](#serve-both-release-lines).
3. If your source is not at GitHub's archive for your tag, [declare it](#source-is-fetched-for-you).
4. Set [`URL:=` in your package](#say-where-your-package-came-from).
5. [Request the package, then open a pull request](#request-the-package-then-open-a-pull-request).
6. Once it is in the feed, [add the badges to your README](#show-it-in-your-readme).

The three shapes are listed best first. They differ in how much this feed has to be told and how much
it can verify.

| Shape | `KIND` | What you pin | Automatic updates |
|---|---|---|---|
| [Packages and a signed manifest](#packages-and-a-signed-manifest-best) | `manifest` | a version and a key, no checksum table | yes |
| [A built `.apk`](#a-built-apk) | `apk` | the artifact and its sha256 | yes, while the set of containers is unchanged |
| [Binaries or loose files](#binaries-or-loose-files-last-resort) | `binaries` | each artifact, its sha256 and its architectures, plus an `owfeed.yml` entry | never |

### Packages and a signed manifest (best)

Nothing to build, and nothing to transcribe. `owfeed release` writes an inventory of the upstream
release with every package's size and hash, and signs it. This feed verifies that signature and then
trusts what is inside. So the pin here is a version and a key, and no checksum table.

```sh
# packages/example-daemon/upstream.sh
KIND="manifest"
REPO="someone/example-daemon"
VERSION="0.3.5-r1"
TAG="v0.3.5"

SIG_KEY="keys/example-daemon.pub"
SIG_KEY_ID="0123456789abcdef"
AUTO_MERGE="yes"
```

`TAG` is the tag as upstream writes it, `v` or no `v`. It is the thing that exists on the other side.
The update job compares it against what upstream reports, rather than rebuilding it from `VERSION`.

If upstream appends a numeric suffix of its own, such as `0.19.17-2` (OpenWrt's `PKG_RELEASE`), that
suffix is a revision of the same version. It becomes the `-r<n>`:

```sh
VERSION="0.19.17-r2"
TAG="0.19.17-2"
```

apk reads `-r<n>` as the revision and wants it last, so a version never carries both.

If your upstream does not publish a manifest yet,
[that side is one command](#i-build-in-my-own-ci-and-want-my-package-in-this-feed).

<details><summary>Why the manifest is checked against REPO and TAG, and why this shape is best</summary>

The manifest is verified **before** it is read, because every value in it steers a download. Its
`repo` and `tag` lines are checked against `REPO` and `TAG`. A signature proves who wrote something
and never what it is about. Without that check, a manifest lifted from another of the author's
releases would verify perfectly as this one.

Multi-architecture packages are the reason to prefer this shape. An apk's filename carries no
architecture: in a feed the architecture is the directory. So twenty architectures mean twenty assets
with one name, and `owfeed release` appends the architecture where names collide. The manifest says
which is which. A hand-maintained table would have to say it twice and stay right.

</details>

### A built `.apk`

Nothing to build. The feed distributes exactly what the author released, byte for byte.

```sh
# packages/luci-theme-footstrap/upstream.sh
KIND="apk"
REPO="VizzleTF/luci-theme-footstrap"
VERSION="0.11.6-r1"
ARTIFACT="luci-theme-footstrap-0.11.6-r1.apk"
SHA256="e2e7bde2…"

SIG_KEY="keys/vizzletf-release.pub"     # when the author signs releases
SIG_KEY_ID="18c63865e2bcf8d6"
AUTO_MERGE="yes"
```

That is the whole package. There is **no entry in `owfeed.yml`**, because owfeed is not building
anything.

### Binaries or loose files (last resort)

owfeed builds the package here, so there are two files: the values, and an `owfeed.yml` entry
describing what comes out. `AUTO_MERGE` cannot be `yes` for this shape.

```sh
# packages/example-daemon/upstream.sh
KIND="binaries"
REPO="someone/example-daemon"
VERSION="1.2.0-r1"
BINARY_DEST="/usr/bin/example-daemon"

# <artifact>  <sha256>  <the OpenWrt architectures it runs on>
ARTIFACTS="
example-daemon-amd64  2d64d66c…  x86_64
example-daemon-arm64  ba045eaa…  aarch64_cortex-a53 aarch64_cortex-a72 aarch64_generic
"
AUTO_MERGE="no"
```

```yaml
# owfeed.yml
- name: example-daemon
  build: mkpkg
  arch: [x86_64, aarch64_cortex-a53, aarch64_cortex-a72, aarch64_generic]
  version-from: file:./staging/example-daemon.version
  files: ./staging/example-daemon/{arch}
  description: "One line. LuCI truncates past 512 bytes."
```

Anything the feed itself ships, such as an init script or a default config, goes in
`packages/<name>/files/`. It is copied into every architecture.

A static binary needs the right build target and no OpenWrt SDK. So one upstream artifact usually
serves several OpenWrt architectures. Which ones is a judgement about what upstream's builds run on.
That is why the mapping lives beside the package and not inside a tool.

<details><summary>Why this shape is the last resort</summary>

Prefer either shape above it. Building someone's package in this feed:

- ships something they never tested;
- puts the knowledge of how to build it, the architecture mapping and the init script, in a
  repository that is not theirs;
- leaves nothing to verify. A `.sha256` served by the same host as the binary says the download was
  not corrupted, and nothing about who produced it. That is why `AUTO_MERGE` cannot be `yes` for it.

</details>

### Serve both release lines

This feed serves both lines: apk for 25.12 and later, opkg for 24.10 and earlier. Routers stay on a
release for years. Shipping only the newer line leaves most of the installed base where it was.

| Your case | What to do |
|---|---|
| Upstream publishes both containers | Pin the second one too. It then serves both lines from the same build. |
| Upstream publishes a manifest (`KIND="manifest"`) | Nothing. The manifest lists every package it built, in both formats and every architecture, and each one is placed where it belongs. |
| owfeed builds it (`KIND="binaries"`) | Nothing. Both formats come from the same staged payload. |
| It belongs on one line only | Say so in `owfeed.yml`. It is then absent from the other line's index entirely, rather than present and unresolvable. |

Both containers pinned:

```sh
ARTIFACT="luci-theme-footstrap-0.11.6-r1.apk"
SHA256="e2e7bde2…"
ARTIFACT_IPK="luci-theme-footstrap_0.11.6-r1_all.ipk"
SHA256_IPK="3255edc1…"
```

One line only, in `owfeed.yml`:

```yaml
- name: luci-app-mine
  releases: ["25.12"]
```

### Source is fetched for you

Nothing to declare. The feed fetches the archive GitHub generates for your pinned tag. That archive
exists for every tag, whether or not you attached anything to the release. The feed serves it beside
the binary at `https://repo.owfeed.org/sources/`, listed with its sha256 in
[`sources/index.txt`](https://repo.owfeed.org/sources/index.txt).

If your source is not at that address, add one line:

```sh
SOURCE_URL="https://git.example.org/project/snapshot/project-1.2.3.tar.gz"
SOURCE_SHA256="9f2c…"   # optional; pin it when the archive is a stable release asset
```

The licence comes from the metadata inside your package, the same string `apk info` shows on the
router. So there is nothing to declare here, and nothing to keep in sync when you relicense.
`tools/sources.sh` reads the licence out of the built index before the publish. It refuses a copyleft
package that has no source for that exact version, so this is enforced rather than remembered.

One `packages/<name>/` entry can publish several packages. With `KIND="manifest"`, the archive of one
tag is the corresponding source for every package in that release. It is served under each of their
names.

<details><summary>Why the feed serves source itself</summary>

Serving source is what lets this feed carry copyleft packages at all. GPLv2 §3 conditions
distributing a binary on providing source. A feed re-serving upstream's bytes is a second act of
distribution, carrying the obligation again. Linking to a repository satisfies none of the options the
licence gives. Serving the archive from the same origin as the binary does.

</details>

### Say where your package came from

Set one field where your package is built:

```make
define Package/luci-app-mine
  URL:=https://github.com/you/luci-app-mine
endef
```

The URL travels into the index and into what `apk info` prints on the router. In a feed carrying
other people's work, it is the only thing telling a user who published what they installed.

- `tools/check-origin.sh` refuses to publish a package without it.
- The intake check on your issue reads it out of your `.ipk` before anyone spends time on a pull
  request.
- A value that is set and is not a URL fails the same way an absent one does.

Set `URL:=` even when `Source:` already looks filled in. On a package built by OpenWrt's SDK,
`Source:` is the feed path it was built from, not a place anyone can go.

### Request the package, then open a pull request

This is the one way to submit a package.

1. Open a [package request](https://github.com/owfeed/owfeed-packages/issues/new?template=package-request.yml).
   The intake check reads the release and answers on the issue. It re-runs on every edit.
2. Fix what it marks in bold, until it answers **Ready for a person**.
3. Run the checks below locally, then open a pull request. It adds `packages/<name>/upstream.sh`
   and your public keys under `keys/`.

### Run the checks and open a pull request

1. Run the checks:

   ```sh
   ./tools/fetch.sh packages/<name>
   owfeed build && owfeed sign && owfeed index && owfeed doctor --require-origin
   ./tools/check-origin.sh && ./tools/sources.sh
   owfeed smoke                 # 25.12, on a real router
   owfeed smoke --release 24.10 # 24.10, on a real router
   ```

2. Open a pull request. CI runs exactly that with a throwaway key, so nothing from a fork comes near
   the feed's own.

### Show it in your README

Once the package is in the feed, two badges are published for it. They update themselves whenever
the feed does. They are rendered from the freshly built index, so they cannot claim a version
the feed is not serving.

```markdown
[![owfeed](https://img.shields.io/endpoint?url=https://repo.owfeed.org/badge/<name>.json)](https://owfeed.org/install/)
[![owfeed](https://img.shields.io/endpoint?url=https://repo.owfeed.org/badge/<name>-releases.json)](https://owfeed.org/install/)
```

- The first badge shows the version this feed serves.
- The second shows the release lines it serves it on.

Replace `<name>` with your package name.

---

## Update a package

Usually you do not. A scheduled job asks each upstream for its latest release every few hours. It
proposes the update for you, with the checksums recomputed from the bytes that release served. Where
the package allows it, the update is a branch that lands on its own. Otherwise it is a pull request.

To update by hand:

1. Edit `VERSION`, `TAG` and the checksums in `upstream.sh`. Nothing else changes.
2. Fetch the package:

   ```sh
   ./tools/fetch.sh packages/<name>     # fails if a checksum does not match
   ```

---

## Let a package update itself

`AUTO_MERGE="yes"` lets an update reach `main` once the checks pass, with nobody in the loop. The
checks are never skipped either way.

It is offered **only where the upstream publishes a detached signature** beside its artifact. That
signature is verified against a key pinned in `keys/`, which is provenance from someone other than
this feed. Where an upstream publishes checksums alone, an update waits for a person. A checksum
served by the same host as the artifact tells you the download was not corrupted, not that it was not
replaced.

### What your shape earns

How far an update gets on its own follows from what the signature covers. How much work went into
publishing it does not count.

| Shape | What the signature covers | Automatic updates |
|---|---|---|
| `KIND="manifest"` | the whole inventory — every file, size and hash, plus `repo` and `tag` | yes |
| `KIND="apk"` | each asset, but **not** the list of them | yes, while the set of containers is unchanged |
| `KIND="binaries"` | nothing — a checksum says the download was not corrupted, never who produced it | never |

That is the honest reason to publish a manifest: `owfeed release` writes one. An update then lands
on the next scheduled run, which GitHub starts every few hours, and nobody has to read it first.

### How an update lands

There is no pull request for an eligible update.

1. The scheduled job pushes `update/<name>-<version>` and starts the checks on it.
2. A later run pushes that commit onto `main`. It does so only when `check / build` and
   `check / check` are green on it, and the diff touches nothing but one
   `packages/<name>/upstream.sh`.

Otherwise `tools/land-updates.sh` refuses the push, and a context with no run at all counts as a
refusal. Landing takes the checks plus the wait for the next scheduled run, which GitHub spaces a few
hours apart.

An update that is **not** eligible is pushed the same way and then gets a pull request. That pull
request waits for a maintainer.

<details><summary>Why there is no pull request</summary>

A pull request a bot opens cannot merge itself here: GitHub creates its `pull_request` run in an
approval-required state. That is what [issue #53](https://github.com/owfeed/owfeed-packages/issues/53)
was.

</details>

### What an automatic update will not do

`AUTO_MERGE="yes"` never skips the checks, and it is refused outright in the cases below. A signature
answers *did the author publish this* and not *should this go out unread*. An upstream whose release
key is stolen signs perfectly.

A refused update is still pushed and still checked. What it does not get is a landing without a
person: it arrives as a pull request instead.

Refused in every shape:

| Refused | Why |
|---|---|
| A major version change | That is where upstream changes what the package is: architectures dropped, files renamed, a configuration format the routers running the old one do not have. Whatever it turns out to be, it is not a decision to make at 04:00 with nobody watching. |
| A diff touching anything but the pins | The update job rewrites values with `sed`. A changed line anywhere else is either a bug in that job or an `upstream.sh` edited underneath it. It is also the only way `SIG_KEY_ID` could move, and that would be the verification quietly relaxing itself. |
| No `SIG_KEY` | Then nothing but the transport says anything about where the bytes came from. |
| More than two automatic updates to one package in a day | The risk is a run of bad releases, more than one. A stolen key can publish a chain of versions faster than anyone reads the notifications, and every one of them verifies. The third waits for a person. |

**Nothing under `keys/`, `tools/` or `.github/` ever lands this way**, whatever an `AUTO_MERGE` says.
Two independent gates hold that:

- The update job commits nothing but the pins inside one `upstream.sh`.
- `tools/land-updates.sh` compares the branch against `main` before pushing. It refuses on any path
  but `packages/<name>/upstream.sh`.

`.github/CODEOWNERS` names `keys/` as well, so a review is requested there. No branch rule requires it
yet, for the reason in [`keys/README.md`](keys/README.md).

---

## I build in my own CI and want my package in this feed

You publish signed releases in your own repository, and this feed picks them up. You do not push into
this feed, and that is deliberate. Nothing crosses the boundary in either direction:

```
your repository                              this feed
──────────────                               ─────────
owfeed build                                 scheduled: sees your release
owfeed sign          ← your key              verifies your signature against keys/
publish a release    ──────────────────────► signs the index
                                             indexes, publishes
```

- You never hold this feed's key. This feed never holds a token for your repository.
- **Your signature is not stripped.** This feed signs its index and leaves your package byte for
  byte, so the package a router installs carries your signature. A subscriber who installs your public key too can verify
  you directly. One who trusts only this feed still works.

<details><summary>Why you cannot push into this feed</summary>

Publishing here would need either this feed's signing key or write access to it. Either one would let
every contributor publish anything under this feed's name, including a higher version of `dropbear`.

</details>

### On your side

[`examples/gitlab-ci.yml`](examples/gitlab-ci.yml) and [`examples/owfeed.yml`](examples/owfeed.yml)
are a working pair. In short:

```sh
owfeed build
owfeed sign                       # your EC key, from a masked CI variable
owfeed doctor --require-origin    # every package says which repository it is from
owfeed smoke                      # it installs on a real OpenWrt image
owfeed release --repo … --tag …   # signed manifest, and a .sig beside every package
# publish the whole of dist/ as release assets
```

**`owfeed release` is the step this feed reads.** It writes a signed inventory of the release and a
detached signature beside every package. The update job fetches `<asset>.sig` and checks it against
the key pinned in `keys/`. Without it there is nothing to verify. The ingest then stops rather than
carry something whose origin it cannot establish.

A `.sha256` served from the same release does not substitute. It says the download was not corrupted
and nothing about who produced it.

Two keys do different jobs. Keep them separate and keep both out of git: neither can be revoked.

| Command | Key | What it signs |
|---|---|---|
| `owfeed sign` | **EC prime256v1** | the package: the signature goes *inside* it, where apk checks it |
| `owfeed release` | **usign** | the manifest: usign is the scheme OpenWrt already ships, so a router can verify it with nothing installed |

`--require-origin` is there for users. The `url:` is carried into the index and shown by `apk info`
on the router. It is the only thing telling a user who published what they installed.
`repo-commit: env:CI_COMMIT_SHA` records which commit produced it.

<details><summary>Why release renames some assets</summary>

Release assets are flat, and an apk's filename carries no architecture: in a feed the architecture
*is* the directory. So a package built for many architectures would produce many files with one name.
`release` appends the architecture where names collide, and only there. A noarch package keeps the
name it has always had.

</details>

### On this side

Submit once, the [same way as any package](#request-the-package-then-open-a-pull-request): a
package request, then one pull request. The pull request adds `packages/<name>/upstream.sh` with your
repository, your public key and the first pin, plus your key under `keys/`. After that, the update
job follows your releases and opens the updates itself.

Expect your key to be read carefully: adding it is the diff that deserves a second look. That is the
moment this feed decides whose provenance it will carry. It does not endorse your software or take
responsibility for it, which it never does. Everything after it is mechanical.

---

## What the checks will refuse

`owfeed doctor` and `owfeed smoke` gate every pull request. These findings catch most first attempts:

| Finding | What it costs, what to do |
|---|---|
| `arch: all` | apk rejects it as uninstallable. Use `noarch`. |
| `/etc/config/foo` shipped but not in `conffiles:` | sysupgrade replaces the user's settings with your defaults on every firmware upgrade, silently. |
| `.po` files in the payload | LuCI reads compiled `.lmo`. Point `i18n.from:` at them. |
| A version apk cannot parse | after `~` only hex digits; `-r<n>` last. |
| A package that builds and will not install | `smoke` installs the feed on a real OpenWrt image and fails if apk asks for `--allow-untrusted`. |
| A package that names no upstream | `tools/check-origin.sh` reads `url` out of the built index and will not publish a package a user cannot trace back to whoever wrote it. |

Each finding says what it costs and what to do about it.

---

## Carry somebody else's package

Ask them first. A licence usually does not forbid it. But republishing someone's work routes their
bug reports to them from an install path they never tested. A message settles that faster than any
reading of a licence.

Then check three separate things. Usually only the first one gets checked.

- **The licence permits redistribution, and its conditions are met.** GPL asks for source
  availability, not only attribution. Apache-2.0 asks for the NOTICE and a statement of changes.
- **The trademark is a different right.** Open-source licences do not grant it. Some projects
  publish a policy saying what is allowed; read it.
- **There is a licence at all.** A repository with no `LICENSE` grants nothing, however public it
  is. Declaring a permissive one in `upstream.sh` would be inventing permission.

[LEGAL.md](LEGAL.md) works through what this feed already carries, including the two cases where
the answer is not a plain yes.

---

## Why a pin, and why a key

**Everything downloaded is pinned by sha256 in this repository.** A checksum served by the same host
from the same release does not verify it. Whoever can replace one can replace the other. A pin
recorded here does, because it came from a moment a person looked at it.

**Where the author signs, that signature is checked too**, against a key pinned in `keys/`. A pin
proves the bytes have not changed since someone looked. A signature says who produced them. Only the
second can justify an update merging itself.

The index of this feed is signed with **the feed's** key, not the authors'. That is not a
preference. apk takes its trust from the signed index, and only this feed can sign an index
describing everything this feed carries. Signing packages with their authors' keys would mean
installing every author's key on every router. Each one would be a trust anchor for *every* package
name rather than for theirs.

So the feed's signature is worth exactly what was checked before it was applied. That is what these
rules are for.
