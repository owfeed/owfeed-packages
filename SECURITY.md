# Security and reports

*[Русская версия](SECURITY_ru.md)*

This page is for anyone who wants to report a problem with a package or with this feed. It also
states the limits of the feed's trust model.

- Bugs and vulnerabilities in a package go to the package's author. This feed did not write any of
  the software it carries and cannot fix it.
- A vulnerability in the feed itself goes to a [private advisory](https://github.com/owfeed/owfeed-packages/security/advisories/new).
  Do not open a public issue.
- A legal notice that names a package and a ground gets that package suspended while it is looked at.
- Installing the feed's key trusts it for every package name, and apk cannot revoke a key.

## Find it fast

| I want to… | Go to |
|---|---|
| know where a report goes | [Where to send what](#where-to-send-what) |
| report a problem in a package | [Reporting something in a package](#reporting-something-in-a-package) |
| send a legal notice | [What a notice has to contain](#what-a-notice-has-to-contain) |
| know what happens after a notice | [What happens next](#what-happens-next) |
| know what the feed checks | [What this feed does and does not do](#what-this-feed-does-and-does-not-do) |
| know the trust model's limits | [Known limits, stated plainly](#known-limits-stated-plainly) |
| know where the signing keys live | [Key handling](#key-handling) |

## Where to send what

Four kinds of report go to different places. Only two of them are this feed's to answer.

| What you have | Where it goes |
|---|---|
| A bug in a package, or a question about what it does | **The package's author.** Their repository is in the package metadata: `apk info <name>` on the router, or `packages/<name>/upstream.sh` here. |
| A vulnerability in a package | The package's author first. Tell us too if it is already public and should be pulled. |
| A vulnerability in this feed: the key, the index, the ingest, the workflows | [Private advisory](https://github.com/owfeed/owfeed-packages/security/advisories/new) here. Do not open a public issue. |
| A legal complaint: infringement, licence, trademark, unlawful content | The address in [`.well-known/security.txt`](https://owfeed.org/.well-known/security.txt), or a private advisory. See [Legal complaints and takedown](#legal-complaints-and-takedown). |

<details>
<summary>Why package reports go to the author</summary>

This feed did not write any of the software it carries and cannot fix it. A report sent here about a
package's behaviour reaches somebody who can only forward it. The author gets it a day later than if
you had sent it to them.

</details>

## Reporting something in a package

Include:

- the package name;
- the version (`apk info -v <name>`);
- your OpenWrt release;
- what you observed.

If the package is still installable from here and should not be, say so explicitly. That is the part
this feed can act on immediately.

## Legal complaints and takedown

Send the notice to the address in `security.txt`, or open a private advisory.

- Receipt is confirmed by reply.
- Notices are handled in the order they arrive.
- One person handles them. It is not a 24/7 service.

### What a notice has to contain

A notice needs these five elements. They are the elements Article 16 of the EU Digital Services Act
requires of a notice.

1. **A substantiated explanation** of why you believe the material is unlawful or infringes.
2. **The exact location:** the package name and version, and the URL under
   `https://repo.owfeed.org/` if you have it.
3. **Your name and an email address.** Anonymous notices cannot be acted on, because there is
   nobody to send the outcome to.
4. **A statement that you believe in good faith** that the information in the notice is
   accurate and complete.
5. **What right you hold or represent**, if the claim is about copyright, trademark or licence.

A notice missing them gets a reply asking for them. That costs everyone a round trip.

### What happens next

1. A notice that identifies a package and states a ground gets that package **suspended from the
   feed while it is looked at**.
2. The author is told, gets the notice, and is given the chance to respond.
3. If the claim holds, or if the author does not respond, the package stays out.
4. The reason goes in the commit that removes the package, so the record is public and dated.

This feed does not adjudicate disputes between an author and a claimant. It removes what it is asked
to remove and leaves the merits to the two of them.

A counter-statement from the author is forwarded to the claimant. It does not by itself put the
package back.

<details>
<summary>Why the package is suspended first</summary>

Suspension is cheap and reversible. Arguing is neither. Nothing here is urgent enough to publish
through a live dispute.

</details>

### Repeat claims end the arrangement

**An author whose packages are removed on repeated substantiated claims is removed from this
feed, and their key is unpinned from `keys/`.**

| Claims | Result |
|---|---|
| Two upheld claims about different packages | The author is removed |
| Two upheld claims about the same package, the second after the first was resolved | The author is removed |
| Forwarded notices the author ignores | The author is removed |

The removal is a commit like any other and is visible in the history. A feed cannot carry software
whose author will not answer for it.

## What this feed does and does not do

| The feed does | The feed does not |
|---|---|
| Distribute packages other people built | Review code |
| Verify provenance: the release came from the repository it claims, signed by a key pinned here | Assess security |
| Verify that the tree installs | Judge whether anything is lawful anywhere |

Responsibility for a package's contents rests with its author.

The full statement is in the [README](README.md#what-this-feeds-signature-means). The licence and
trademark reasoning is in [LEGAL.md](LEGAL.md).

## Known limits, stated plainly

**A feed key is a trust anchor for every package name.** A key in `/etc/apk/keys` validates an
index claiming *any* name. A compromise of this feed's key is a compromise of every subscriber,
including for packages this feed does not carry. This is how apk works, not a choice made here.

**apk has no revocation.** No CRL, no expiry, no way to declare a key dead. If this feed's key
leaks, every subscriber has to remove it by hand. A device that is offline when it matters cannot
be reached at all.

**Ingest verifies provenance, not intent.** A signature says the author published these bytes. An
author whose own release key is stolen signs a malicious release perfectly. Because of that,
automatic merges are limited:

- at most two per package per day;
- refused outright for a major version change;
- refused outright for any diff touching `keys/`.

## Key handling

- The signing keys exist only as repository secrets, and only in the publish job.
- The publish job is gated by an environment and runs after the build.
- Pull requests build the whole feed with throwaway keys, so a fork never comes near the real ones.
- `.gitignore` covers `*.pem`, `*.key` and `*.sec`.

### Changes under `keys/`

A person reads every addition or change under `keys/`. Pinning a key is the entire trust decision
compressed into four lines.

- `.github/CODEOWNERS` requests that review. No branch rule requires it yet.
- No automatic update reaches `keys/`. The update job writes one `packages/<name>/upstream.sh` and
  nothing else.
- `tools/land-updates.sh` re-checks that against `main` before it pushes. A branch touching any
  other path is refused there and needs a pull request and a person.

<details>
<summary>Why no branch rule requires the review</summary>

With a single maintainer, a required review would block every key addition rather than gate it.

</details>
