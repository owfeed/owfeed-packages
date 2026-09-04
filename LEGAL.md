# Redistributing other people's packages

*[Русская версия](LEGAL_ru.md)*

**This is not legal advice.** It is what was read in the licences and policies of the packages this
feed carries, written down so the decisions are reviewable rather than assumed.

## What this repository's own licence covers

`LICENSE` is MIT, and it covers **this repository's own content** — the scripts under `tools/`, the
workflows, the package definitions in `packages/`, and the documentation.

It does not cover the packages this feed publishes. Those are other people's work, carried under
their own terms, and each one declares its licence in the index and in `apk info` on the router.
That distinction used to be written as a preamble above the MIT text in `LICENSE` itself, which had
a cost worth more than the convenience: GitHub's licence detector reported the repository as
`NOASSERTION`, so a feed that asks people to install a signing key showed no licence at all on its
own front page. The caveat lives here instead, where the rest of the answer already was.

## The short version

A licence that permits redistribution is not permission to do anything you like. Three separate
things have to hold, and only the first is usually checked:

1. **The copyright licence** must permit redistribution — and its conditions have to be met, which
   for GPL means source availability, not just attribution.
2. **The trademark** is a different right. Open-source licences do not grant it; Apache-2.0 says so
   explicitly, and GPL's silence does not make trademark law go away.
3. **The author's willingness** is neither of those, and is the one that decides whether
   redistributing is a courtesy or a nuisance. A feed that republishes someone's work sends their
   bug reports to them, from an install path they never tested.

## What this feed carries, and under what

| package | licence | redistribution | trademark policy |
|---|---|---|---|
| `luci-theme-footstrap` | Apache-2.0 | permitted, with NOTICE and change statements | none published |
| `luci-app-footstrap-cmd` | Apache-2.0 | same | none published |
| `luci-app-footstrap-files` | Apache-2.0 | same | none published |
| `luci-app-gitbackup` | GPL-2.0-only | permitted, with corresponding source served from this feed | none published |
| `podkop-updater` | MIT | permitted | none published |

Each row is one `packages/<name>/` entry. An entry whose upstream publishes a signed manifest
publishes several packages — a backend, the LuCI page, a translation catalogue — out of one tagged
release, and they share that release's source archive.

### `podkop-updater` declared a licence it did not have

`VizzleTF/podkop_autoupdater` published no `LICENSE` file while this feed declared
`license: MIT` for it. Without one, default copyright applies: nobody has redistribution
rights at all, whatever the repository's visibility suggests — and the claim was already in
the index and read back by `apk info` on every router that installed it.

Fixed upstream rather than in the feed's metadata, because there was no reality for the
metadata to match: `podkop_autoupdater` now carries the MIT licence it was being described
under. Adding the file makes the published claim true; editing the feed would only have made
it quieter.

The general form is worth keeping: a `license:` field is an assertion about someone else's
intentions, and it is trivially possible to publish one nobody made.

## `podkop`, and why it is not enabled

[`itdoginfo/podkop`](https://github.com/itdoginfo/podkop) is GPL-2.0-or-later and publishes a
[trademark policy](https://github.com/itdoginfo/podkop/blob/main/TRADEMARK.md). Both matter, in
different ways.

### The trademark policy permits this, and constrains it

Read plainly, the policy allows what a feed does:

> You can, however, say that you like the Podkop project, that you participate in the Podkop
> community, or that you are providing an unmodified version of the Podkop software.

> When you redistribute an unmodified copy of Podkop software, you must not remove any Podkop
> trademarks, notices, or branding included in the original distribution.

So an unmodified copy, under its own name, with its notices intact, is within the policy. What is
not: presenting it as official or endorsed, and using the name for anything modified.

**Where that used to bite owfeed.** `owfeed sign` appends a signature to the package file, so the
artifact's bytes would not have been the ones upstream published. `owfeed.yml` now sets
`signing.sign-packages: false`: this feed signs the index and nothing else, and what it distributes
is the author's file byte for byte. An unmodified copy is unmodified in the sense a user comparing
checksums can check.

Rebuilding a package from source would be a further step again. That artifact is this feed's build,
not upstream's, and publishing it under the upstream name is much closer to what the policy
forbids.

### GPL-2.0 asks for something Apache-2.0 does not, and the feed now answers it

GPLv2 §3 conditions binary distribution on source: accompanying it, or a written offer valid for
three years, or — for non-commercial distribution only — passing along the offer you received.

A feed that publishes a GPL binary and links to a GitHub repository has not satisfied any of the
three. Upstream's own distribution is fine; ours is a separate act of distribution with its own
obligations.

**This is answered now, and mechanically.** The feed takes the first option: the corresponding
source is fetched, checksum-pinned and served from the same origin as the binary, at
`https://repo.owfeed.org/sources/`, listed in
[`sources/index.txt`](https://repo.owfeed.org/sources/index.txt). Of the three options it is the
only one that depends on nobody remembering anything — the source is there for exactly as long as
the binary is, because the same publish puts both there.

`tools/sources.sh` runs between `owfeed index` and `owfeed publish` and reads each package's
declared licence out of the built index. If a package declares a copyleft licence and no source is
served for that exact name and version, the run fails and nothing is published. So the answer is
not a policy anybody has to apply — a GPL package without source cannot reach the feed.

The licence is read from the index rather than from a field in this repository on purpose. The
index is built from the metadata inside the package, which its author set, and it is the same
string `apk info` shows on the router. A field here would be this feed's opinion about someone
else's licence, and it would go stale the first time upstream relicensed.

**What the feed does and does not claim.** It serves exactly the archive upstream published for the
pinned tag, verified by hash, so what the feed offers is what upstream offers and cannot drift from
it. Whether that archive is *complete corresponding source* is upstream's assertion — the same one
every other consumer of that release already relies on. Where a project ships no source archive
with its release, the feed cannot carry it: there is nothing to serve.

**So: can this feed carry GPL packages?** Yes, and nothing has to be declared per package to make
it so. The source archive defaults to the one GitHub generates for the pinned tag, which exists for
every tag whether or not its author attached anything, so the fetch finds source for essentially
any GitHub-hosted project on its own. `SOURCE_URL` exists for a project hosted elsewhere.

The earlier version of this asked each package to pin `SOURCE_URL` and `SOURCE_SHA256` by hand,
and read as though the licence imposed that. It did not — the licence asks for source alongside
the binary, and where the source is fetched from was this repository's choice. The condition that
remains is the licence's own and cannot be engineered away: **a copyleft binary may only be
redistributed with source.** What is gone is the paperwork around it.

The source obligation was the blocker and it no longer is: source is fetched for every package
automatically, and the publish refuses a copyleft package that ended up without one. What remains before
podkop could be carried is the part no script settles — asking the author. The contribution flow
was exercised against it on a branch, which is how the `v`-tag assumption in `tools/fetch.sh` was
found and fixed, and the branch was not merged.

## What we do about it

**Ask.** Every consideration above is cheaper to resolve with a message than with a reading of
GPLv2 §3. An author who says yes has also told you where to send bug reports; one who says no has
saved everyone a dispute. Nothing here is urgent enough to skip that.

**Record what we know.** Every package declares its licence and its URL, both of which travel from
the package into the index and into what `apk info` prints on the router. `tools/check-origin.sh`
refuses to publish one that does not name its upstream. A user who installs something from this
feed can always find out whose it is.

That is a separate script rather than `owfeed doctor` because doctor asks the question of
`owfeed.yml`, and this feed's `packages:` list is empty by design — every package is built and
signed by its author and ingested unchanged, so the field lives inside the package. Doctor was
checking the origin of zero packages, and this paragraph described a feed that builds rather than
this one. The URL is read from the index for the same reason the licence is: it is the author's
own metadata, and a value kept in this repository would be our opinion about someone else's
package.

**Do not claim what was not granted.** A licence field is an assertion about someone else's
intentions. Where the upstream has published none, the honest thing is to say so and not publish,
rather than to guess a permissive one.
