# Adding and updating packages

*[Русская версия](CONTRIBUTING_ru.md)*

A package in this feed is **a file of values**. There is no per-package script: one shared
implementation fetches every package, so an update rewrites data rather than code, and adding a
package does not start with copying somebody else's shell.

```
packages/<name>/upstream.sh   the version, the checksums, which key signs it
packages/<name>/files/…       optional: what the feed adds, e.g. an init script
keys/…                        pinned public keys of the people whose packages we carry
owfeed.yml                    a packages: entry, only when owfeed has to build it
```

---

## What you are agreeing to

Submitting a package here means you assert, and remain solely responsible for, all of the
following. The feed distributes; it does not review, and it cannot answer for any of this.

- **You have the right to have it distributed** — the licence permits redistribution, its
  conditions are met, and no trademark or other right of a third party stands in the way.
- **You are responsible for what is in it.** Its contents, behaviour, security and lawfulness
  are yours. This feed does not audit code, assess security, or judge legality in any
  jurisdiction.
- **Its metadata is true.** The declared licence, description and upstream URL are assertions
  you make; they are carried through unchanged and shown to users by `apk info`.
- **You will handle reports about it.** Bug reports, security reports and complaints about the
  package go to you. The feed will forward what reaches it and can suspend the package, and
  that is the whole of what it can do.

A package can be suspended at any time, for any reason, without notice — a credible complaint,
a licence question, a stale upstream, or no reason given. There is no entitlement to remain in
this feed and no undertaking to keep carrying anything.

**If a claim is brought about your package, it is yours to answer.** You will be told about it
and given the chance to respond, and the package comes out of the feed while that happens. To
the extent the law allows, you carry the cost of any claim arising from software you asked this
feed to distribute — this feed did not write it, does not review it, and is distributing it at
your request.

**Repeated substantiated claims end the arrangement.** Two upheld claims, or ignoring notices
forwarded to you, and the package is removed and your key is unpinned from `keys/`. The removal
is an ordinary commit; the reason is in it.

Adding a `packages/<name>/upstream.sh` naming your repository, or asking for one to be added, is
how you accept all of the above. If you do not, do not ask for the package to be carried — you
lose nothing by publishing signed releases yourself, which is what
[the cookbook](https://owfeed.org/cookbook/) describes.

**Neutral descriptions only.** `description:` says what a package *is* in technical terms and
nothing about what it is for, what it circumvents, or who should want it. LuCI shows this
string to users and it travels into the index; keep it factual and under 512 bytes. The same
applies to anything added to this repository's documentation.

## Every package must be signed by its author

**A package this feed cannot attribute is a package this feed will not publish.** Sign it with
your own EC key before you release it, and pin the public half here. `owfeed doctor` fails any
package that carries no signature by a pinned key, and `owfeed publish` refuses the tree — so
this is enforced by the pipeline rather than asked for in prose.

```sh
owfeed keygen -o author.pem          # once, outside any git working tree
gh secret set OWFEED_AUTHOR_KEY < author.pem
```

Then in your release job, after the build and before you upload anything:

```sh
owfeed sign --key env:OWFEED_AUTHOR_KEY
```

Send the **public** half — `author.pub.pem` — with the pull request that adds your package. It
is pinned as `keys/<package>.pub.pem`.

**Why this and not just the release signature.** The usign signature beside a release is checked
once, here, at ingest, and then it is gone. The EC signature is inside the `.apk` and reaches the
router, so anyone can take a published package, fetch your key from somewhere that is not this
feed, and confirm you built it — a year later, in a dispute, without trusting anyone here. The
feed's own signature cannot do that: it is on the index, and an index proves only that this feed
published a file.

It also fixes what nothing else can. This feed signs the index and not the packages, so without
your signature a published `.apk` carries no evidence of origin at all, and "the author is
responsible for this package" would be a sentence with nothing behind it.

**The key you send is not what is trusted.** What is trusted is the copy committed to `keys/`,
because a person looked at it and their name is on the merge. A key travelling beside a release
proves nothing on its own — whoever replaced the package would replace the key too. Its use is
that it can disagree with the pin, which is how a rotated or substituted key gets noticed.

One key per repository. A signature says who wrote something and never what it is about, so a key
shared across repositories is one that vouches for all of them at once.

## I want to add a package

Which of three shapes it is depends on what the upstream publishes. They are listed best first, and
the difference is how much this feed has to be told and how much it can verify.

### It publishes packages and a signed manifest — best

Nothing to build, and nothing to transcribe. `owfeed release` writes an inventory of the upstream
release with every package's size and hash, and signs it; this feed verifies that signature and
then trusts what is inside. So the pin here is a version and a key, and no checksum table.

```sh
# packages/example-daemon/upstream.sh
KIND="manifest"
REPO="someone/example-daemon"
VERSION="0.3.5-r1"
TAG="v0.3.5"

SIG_KEY="keys/example-daemon.pub"
SIG_KEY_ID="37ddece4c0eef357"
AUTO_MERGE="yes"
```

The manifest is verified **before** it is read, because every value in it steers a download. Its
`repo` and `tag` lines are checked against the two above: a signature proves who wrote something and
never what it is about, so without that a manifest lifted from another of the author's releases
would verify perfectly as this one.

Multi-architecture packages are the reason to prefer this shape. An apk's filename carries no
architecture — in a feed the architecture is the directory — so twenty architectures mean twenty
assets with one name, and `owfeed release` appends the architecture where names collide. The
manifest says which is which; a hand-maintained table would have to say it twice and stay right.

If your upstream does not do this yet, [that side is one command](#i-build-in-my-own-ci-and-want-my-package-in-this-feed).

### It publishes a built `.apk`

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

That is the whole package. **No entry in `owfeed.yml`** — owfeed is not building anything.

### It publishes binaries or loose files — last resort

owfeed builds the package here, so there are two files: the values, and an `owfeed.yml` entry
describing what comes out.

Prefer either shape above it. Building someone's package in this feed ships something they never
tested, puts the knowledge of how to build it in a repository that is not theirs — the architecture
mapping, the init script — and leaves nothing to verify: a `.sha256` served by the same host as the
binary says the download was not corrupted and nothing about who produced it, which is why
`AUTO_MERGE` cannot be `yes` for it.

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

Anything the feed itself ships — an init script, a default config — goes in
`packages/<name>/files/` and is copied into every architecture.

A static binary needs the right build target and no OpenWrt SDK, so one upstream artifact usually
serves several OpenWrt architectures. Which ones is a judgement about what upstream's builds
actually run on, which is why it lives beside the package and not inside a tool.

### Which release lines

This feed serves both: apk for 25.12 and later, opkg for 24.10 and earlier. Routers stay on a
release for years, so shipping only the newer line leaves most of the installed base where it was.

**Upstream publishes both containers.** Pin the second one too, and it serves both lines from the
same build:

```sh
ARTIFACT="luci-theme-footstrap-0.11.6-r1.apk"
SHA256="e2e7bde2…"
ARTIFACT_IPK="luci-theme-footstrap_0.11.6-r1_all.ipk"
SHA256_IPK="3255edc1…"
```

**Upstream publishes a manifest** (`KIND="manifest"`). Nothing to do: the manifest lists every
package it built, in both formats and every architecture, and each one is placed where it belongs.

**owfeed builds it** (`KIND="binaries"`). Nothing to do: both formats come from the same staged
payload.

**It belongs on one line only.** Say so in `owfeed.yml`, and it is absent from the other line's
index entirely rather than present and unresolvable:

```yaml
- name: luci-app-mine
  releases: ["25.12"]
```

### Source is fetched for you

Nothing to declare. The feed fetches the archive GitHub generates for your pinned tag — which
exists for every tag, whether or not you attached anything to the release — and serves it beside
the binary at `https://repo.owfeed.org/sources/`, listed with its sha256 in
[`sources/index.txt`](https://repo.owfeed.org/sources/index.txt).

That is what lets this feed carry copyleft packages at all. GPLv2 §3 conditions distributing a
binary on providing source, and a feed re-serving upstream's bytes is a second act of distribution
carrying the obligation again; linking to a repository satisfies none of the options the licence
gives. Serving the archive from the same origin as the binary does.

One line, only if your source is not at that address:

```sh
SOURCE_URL="https://git.example.org/project/snapshot/project-1.2.3.tar.gz"
SOURCE_SHA256="9f2c…"   # optional; pin it when the archive is a stable release asset
```

The licence itself comes from the metadata inside your package — the same string `apk info` shows
on the router — so there is nothing to declare here and nothing to keep in sync when you
relicense. `tools/sources.sh` reads it out of the built index before the publish and refuses a
copyleft package that has no source for that exact version, so this is enforced rather than
remembered.

One `packages/<name>/` entry can publish several packages: with `KIND="manifest"` the archive of one
tag is the corresponding source for every package in that release, and it is served under each of
their names.

### Your package says where it came from

One field, set where your package is built:

```make
define Package/luci-app-mine
  URL:=https://github.com/you/luci-app-mine
endef
```

It travels into the index and into what `apk info` prints on the router, and in a feed carrying
other people's work it is the only thing telling a user who published what they just installed.
`tools/check-origin.sh` refuses to publish a package without it, and the intake check on your issue
reads it out of your `.ipk` before anyone spends time on a pull request.

A value that is set and is not a URL fails the same way an absent one does. `Source:` on a
package built by OpenWrt's SDK is the feed path it was built from, not a place anyone can go —
which is why `URL:=` is the field to set even when `Source:` already looks filled in.

### Then

```sh
./tools/fetch.sh packages/<name>
owfeed build && owfeed sign && owfeed index && owfeed doctor --require-origin
./tools/check-origin.sh && ./tools/sources.sh
owfeed smoke                 # 25.12, on a real router
owfeed smoke --release 24.10 # 24.10, on a real router
```

Open a pull request. CI runs exactly that with a throwaway key, so nothing from a fork comes near
the feed's own.

### Show it in your README

Once the package is in the feed, two badges are published for it and update themselves
whenever the feed does. They are rendered from the index that was just built, so they cannot
claim a version the feed is not serving.

```markdown
[![owfeed](https://img.shields.io/endpoint?url=https://repo.owfeed.org/badge/<name>.json)](https://owfeed.org/install/)
[![owfeed](https://img.shields.io/endpoint?url=https://repo.owfeed.org/badge/<name>-releases.json)](https://owfeed.org/install/)
```

The first shows the version this feed serves; the second, the release lines it serves it on.
Replace `<name>` with your package name.


---

## I want to update a package

Usually you do not. An hourly job asks each upstream for its latest release and opens the pull
request for you, with the checksums recomputed from the bytes that release served.

By hand: edit `VERSION` and the checksums in `upstream.sh`. Nothing else changes.

```sh
./tools/fetch.sh packages/<name>     # fails if a checksum does not match
```

---

## I want it to update itself

`AUTO_MERGE="yes"` asks GitHub to merge an update once the checks pass.

It is offered **only where the upstream publishes a detached signature** beside its artifact, and
that signature is verified against a key pinned in `keys/`. That is provenance from someone other
than this feed. Where an upstream publishes checksums alone, an update waits for a person: a
checksum served by the same host as the artifact tells you the download was not corrupted, not that
it was not replaced.

The checks are never skipped either way.

**It does not merge unattended today.** The hourly job opens its pull requests as
`app/github-actions`, and this repository holds that account's checks until a maintainer approves
them, so an armed auto-merge waits for that approval — [issue
#53](https://github.com/owfeed/owfeed-packages/issues/53). What `AUTO_MERGE="yes"` buys right now is
one click instead of a review of the diff.

---

## I build in my own CI and want my package in this feed

You do not push into this feed, and that is deliberate. Publishing here would need either this
feed's signing key or write access to it, and either one would let every contributor publish
anything under this feed's name — including a higher version of `dropbear`.

So nothing crosses the boundary in either direction:

```
your repository                              this feed
──────────────                               ─────────
owfeed build                                 hourly: sees your release
owfeed sign          ← your key              verifies your signature against keys/
publish a release    ──────────────────────► signs the index
                                             indexes, publishes
```

You never hold this feed's key. This feed never holds a token for your repository.

**Your signature is not stripped.** apk signature blocks are additive, so the package a router
installs carries yours *and* this feed's. A subscriber who installs your public key too can verify
you directly; one who trusts only this feed still works.

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
detached signature beside every package, and the hourly job fetches `<asset>.sig` and checks it
against the key pinned in `keys/`. Without it there is nothing to verify, and the ingest stops
rather than carrying something whose origin it cannot establish. A `.sha256` served from the same release does
not substitute: it says the download was not corrupted and nothing about who produced it.

Two keys, doing different jobs. `owfeed sign` uses an **EC prime256v1** key and the signature goes
*inside* the package, where apk checks it. `owfeed release` uses a **usign** key and signs the
manifest, because usign is the scheme OpenWrt already ships and a router can verify it with nothing
installed. Keep them separate and keep both out of git — neither can be revoked.

Release assets are flat, and an apk's filename carries no architecture: in a feed the architecture
*is* the directory. So a package built for many architectures would produce many files with one
name. `release` appends the architecture where names collide, and only there, so a noarch package
keeps the name it has always had.

`--require-origin` is not ceremony. The `url:` is carried into the index and shown by `apk info` on
the router, so it is the only thing telling a user who published what they installed. `repo-commit:
env:CI_COMMIT_SHA` records which commit produced it.

### On this side

One pull request, once, adding `packages/<name>/upstream.sh` with your repository, your public key
and the first pin — plus your key under `keys/`. After that the hourly job follows your releases and
opens the updates itself.

Adding your key is the diff that deserves a second look, so expect it to be read carefully. That is
the moment this feed decides whose provenance it will carry — not that it endorses your software or
takes responsibility for it, which it never does. Everything after it is mechanical.

---

## What the checks will refuse

`owfeed doctor` and `owfeed smoke` gate every pull request. The findings that catch most first
attempts:

| | |
|---|---|
| `arch: all` | apk rejects it as uninstallable. Use `noarch`. |
| `/etc/config/foo` shipped but not in `conffiles:` | sysupgrade replaces the user's settings with your defaults on every firmware upgrade, silently. |
| `.po` files in the payload | LuCI reads compiled `.lmo`. Point `i18n.from:` at them. |
| A version apk cannot parse | after `~` only hex digits; `-r<n>` last. |
| A package that builds and will not install | `smoke` installs the feed on a real OpenWrt image and fails if apk asks for `--allow-untrusted`. |
| A package that names no upstream | `tools/check-origin.sh` reads `url` out of the built index and will not publish a package a user cannot trace back to whoever wrote it. |

Each finding says what it costs and what to do about it.

---

## Somebody else's package

Ask them first. Not because a licence necessarily forbids it — usually it does not — but because
republishing someone's work routes their bug reports to them from an install path they never tested,
and a message settles that faster than any reading of a licence.

Then check three separate things, of which only the first is usually checked:

- **The licence permits redistribution, and its conditions are met.** GPL asks for source
  availability, not just attribution. Apache-2.0 asks for the NOTICE and a statement of changes.
- **The trademark is a different right.** Open-source licences do not grant it. Some projects
  publish a policy saying what is allowed; read it.
- **There is a licence at all.** A repository with no `LICENSE` grants nothing, however public it
  is, and declaring a permissive one in `upstream.sh` would be inventing permission.

[LEGAL.md](LEGAL.md) works through what this feed already carries, including the two cases where
the answer is not simply yes.

## What auto-merge will not do

`AUTO_MERGE="yes"` asks GitHub to merge once the checks pass. It never skips them, and it is refused
outright in the cases below, because a signature answers *did the author publish this* and not
*should this go out unread* — an upstream whose release key is stolen signs perfectly.

**What your shape earns.** How far an update gets on its own follows from what the signature
covers, not from how much work went into publishing it.

| Shape | What the signature covers | Automatic updates |
|---|---|---|
| `KIND="manifest"` | the whole inventory — every file, size and hash, plus `repo` and `tag` | yes |
| `KIND="apk"` | each asset, but **not** the list of them | yes, while the set of containers is unchanged |
| `KIND="binaries"` | nothing — a checksum says the download was not corrupted, never who produced it | never |

That is the honest reason to publish a manifest: `owfeed release` writes one, and an update lands
within the hour instead of waiting for someone to read it.

Refused in every shape:

- **A major version change.** That is where upstream changes what the package is: architectures
  dropped, files renamed, a configuration format the routers running the old one do not have.
  Whatever it turns out to be, it is not a decision to make at 04:00 with nobody watching.
- **A diff touching anything but the pins.** The hourly job rewrites values with `sed`, so a changed
  line anywhere else is either a bug in that job or an `upstream.sh` edited underneath it. It is
  also the only way `SIG_KEY_ID` could move, and that would be the verification quietly relaxing
  itself.
- **No `SIG_KEY`.** Then nothing but the transport says anything about where the bytes came from.
- **More than two automatic updates to one package in a day.** The risk is not one bad release but
  a run of them: a stolen key can publish a chain of versions faster than anyone reads the
  notifications, and every one of them verifies. The third waits for a person.

A pull request that adds or changes anything under `keys/` is never merged automatically, whatever
its `AUTO_MERGE` says. Auto-merge is only ever armed on a pull request the hourly job opened, and
that job writes one `packages/<name>/upstream.sh` and nothing else. `.github/CODEOWNERS` names
`keys/`, so a review is requested there — no branch rule requires it yet, for the reason in
[`keys/README.md`](keys/README.md).

Both still open the pull request. They decline to merge it.

## Why a pin, and why a key

**Everything downloaded is pinned by sha256 in this repository.** A checksum served by the same host
from the same release is not a verification of it — whoever can replace one can replace the other. A
pin recorded here is, because it came from a moment a person looked at it.

**Where the author signs, that signature is checked too**, against a key pinned in `keys/`. A pin
proves the bytes have not changed since someone looked; a signature says who produced them. Only the
second can justify an update merging itself.

Everything in this feed is signed with **the feed's** key, not the authors'. That is not a
preference: apk takes its trust from the signed index, and only this feed can sign an index
describing everything this feed carries. Signing packages with their authors' keys would mean
installing every author's key on every router, each one a trust anchor for *every* package name
rather than for theirs.

So the feed's signature is worth exactly what was checked before it was applied. That is what these
rules are for.
