# podkop-updater — a service package, built and signed upstream.
#
# Data only. tools/fetch.sh does the work.

# Upstream builds and signs its own OpenWrt packages and publishes a signed inventory
# of them. That inventory carries every package's size and sha256, and its signature
# is what makes those trustworthy — so this file pins a version and a key and nothing
# else. There is no checksum table here because there is no longer one to maintain.
#
# It used to be KIND="binaries": upstream shipped bare Go binaries and this feed
# rebuilt them into packages, which meant the GOARCH-to-architecture mapping and a
# copy of the init script lived here rather than with the build that produces them.
KIND="manifest"

REPO="VizzleTF/podkop_autoupdater"
VERSION="0.3.6-r1"
TAG="v0.3.6"

# Verified before anything in the manifest is read, because every value in there
# steers a download. The key id is pinned as well: the id inside a signature only
# says which key to look for, never that the key is the right one.
SIG_KEY="keys/podkop-updater.pub"
SIG_KEY_ID="37ddece4c0eef357"

# Provenance from someone other than this feed, so an update may merge itself once
# the checks pass. Under KIND="binaries" it could not: a .sha256 served by the same
# host as the artifact says the download was not corrupted and nothing about who
# produced it.
AUTO_MERGE="yes"
