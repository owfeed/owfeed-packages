# luci-theme-footstrap — a LuCI theme.
#
# Data only. tools/fetch.sh does the work; tools/check-updates.sh rewrites the
# version and the checksum here and touches nothing else.

# Upstream's CI builds a finished .apk through the OpenWrt SDK, which compiles its
# CSS and its translation catalogues. Rebuilding it here would ship something the
# maintainer never tested.
KIND="apk"

# Upstream publishes both containers, so this package serves both release lines:
# 25.12 installs the .apk, 24.10 the .ipk. They are the same build.

REPO="VizzleTF/luci-theme-footstrap"
VERSION="0.14.1-r1"
ARTIFACT="luci-theme-footstrap-0.14.1-r1.apk"
SHA256="f9d95ae91a2483ef805bb7e98d761dabda912429bd95947054ccac900c4e9bcd"
ARTIFACT_IPK="luci-theme-footstrap_0.14.1-r1_all.ipk"
SHA256_IPK="c2032822a6b00a2c0c37bb64c350be9c4b26ae586ae9961a5d89179fb8d9e4ed"

# The release is verified against this key before it is ingested, so the feed's
# signature means the author signed it. The key id is pinned as well: the id inside
# a signature only says which key to look for, never that the key is the right one.
SIG_KEY="keys/vizzletf-release.pub"
SIG_KEY_ID="18c63865e2bcf8d6"

# Provenance from someone other than this feed, so an update may merge itself once
# the checks pass. See CONTRIBUTING.md.
AUTO_MERGE="yes"
