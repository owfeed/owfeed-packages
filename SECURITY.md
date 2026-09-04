# Security and reports

*[Русская версия](SECURITY_ru.md)*

This page says where to send four different things, because they go to different places and only
two of them are this feed's to answer.

## Where to send what

| What you have | Where it goes |
|---|---|
| A bug in a package, or a question about what it does | **The package's author.** Their repository is in the package metadata: `apk info <name>` on the router, or `packages/<name>/upstream.sh` here. |
| A vulnerability in a package | The package's author first. Tell us too if it is already public and should be pulled. |
| A vulnerability in this feed — the key, the index, the ingest, the workflows | [Private advisory](https://github.com/owfeed/owfeed-packages/security/advisories/new) here. Do not open a public issue. |
| A legal complaint: infringement, licence, trademark, unlawful content | The address in [`.well-known/security.txt`](https://owfeed.org/.well-known/security.txt), or a private advisory. See below. |

The distinction is not bureaucracy. This feed did not write any of the software it carries and
cannot fix it. A report sent here about a package's behaviour reaches somebody who can only
forward it, a day later than the author would have got it.

## Reporting something in a package

Include the package name, the version (`apk info -v <name>`), your OpenWrt release, and what you
observed. If the package is still installable from here and should not be, say so explicitly —
that is the part this feed can act on immediately.

## Legal complaints and takedown

Send it to the address in `security.txt`, or open a private advisory.

### What a notice has to contain

These are the elements Article 16 of the EU Digital Services Act requires of a notice, and they
are what makes one actionable rather than a conversation. A notice missing them gets a reply
asking for them, which costs everyone a round trip.

1. **A substantiated explanation** of why you believe the material is unlawful or infringes.
2. **The exact location** — the package name and version, and the URL under
   `https://repo.owfeed.org/` if you have it.
3. **Your name and an email address.** Anonymous notices cannot be acted on, because there is
   nobody to send the outcome to.
4. **A statement that you believe in good faith** that the information in the notice is
   accurate and complete.
5. **What right you hold or represent**, if the claim is about copyright, trademark or licence.

Receipt is confirmed by reply. Notices are handled in the order they arrive; there is one
person doing this, and it is not a 24/7 service.

### What happens next

A notice that identifies a package and states a ground gets that package **suspended from the
feed while it is looked at**. Suspension is cheap and reversible; arguing is neither, and
nothing here is urgent enough to publish through a live dispute.

The author is told, with the notice, and given the chance to respond. If the claim holds, or if
the author does not respond, the package stays out. The reason goes in the commit that removes
it, so the record is public and dated.

This feed does not adjudicate disputes between an author and a claimant. It removes what it is
asked to remove and leaves the merits to the two of them. A counter-statement from the author
is forwarded to the claimant; it does not by itself put the package back.

### Repeat claims end the arrangement

**An author whose packages are removed on repeated substantiated claims is removed from this
feed, and their key is unpinned from `keys/`.** In practice: two upheld claims about different
packages, or two about the same package after the first was resolved, ends the relationship.
This is a policy that is applied, not a paragraph — the removal is a commit like any other and
is visible in the history.

The same applies to an author who ignores forwarded notices. A feed cannot carry software whose
author will not answer for it.

## What this feed does and does not do

It distributes packages other people built. It verifies provenance — that the release came from
the repository it claims, signed by a key pinned here — and that the tree installs. It does not
review code, assess security, or judge whether anything is lawful anywhere. The full statement is
in the [README](README.md#what-this-feeds-signature-means), and the licence and trademark
reasoning is in [LEGAL.md](LEGAL.md).

Responsibility for a package's contents rests with its author.

## Known limits, stated plainly

**A feed key is a trust anchor for every package name.** A key in `/etc/apk/keys` validates an
index claiming *any* name, so a compromise of this feed's key is a compromise of every subscriber
— including for packages this feed does not carry. This is how apk works, not a choice made here.

**apk has no revocation.** No CRL, no expiry, no way to declare a key dead. If this feed's key
leaks, every subscriber has to remove it by hand. A device that is offline when it matters cannot
be reached at all.

**Ingest verifies provenance, not intent.** A signature says the author published these bytes. An
author whose own release key is stolen signs a malicious release perfectly. That is why automatic
merges are capped at two per package per day and refused outright for a major version change or
any diff touching `keys/`.

## Key handling

The signing keys exist only as repository secrets and only in the publish job, which is gated by
an environment and runs after the build. Pull requests build the whole feed with throwaway keys,
so a fork never comes near the real ones. `.gitignore` covers `*.pem`, `*.key` and `*.sec`.

Adding or changing anything under `keys/` is read by a person, because pinning a key is the entire
trust decision compressed into four lines. `.github/CODEOWNERS` requests that review; no branch rule
requires it yet, and with a single maintainer one would block every key addition rather than gate
it. No automatic merge reaches `keys/`: auto-merge is only ever armed on the hourly job's own pull
requests, and those write one `packages/<name>/upstream.sh`.
