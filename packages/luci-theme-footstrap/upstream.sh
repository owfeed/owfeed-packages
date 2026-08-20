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
VERSION="0.13.4-r1"
ARTIFACT="luci-theme-footstrap-0.13.4-r1.apk"
SHA256="095befb9448947b0c4c4277dae810e8bc02396594fea1d44bd1765cc0668aaf1"
ARTIFACT_IPK="luci-theme-footstrap_0.13.4-r1_all.ipk"
SHA256_IPK="e3c39a5adfc8211bf0bd5199ff567e47c1c79037423445023a845ef43a3848c6"

# The release is verified against this key before it is ingested, so the feed's
# signature means the author signed it. The key id is pinned as well: the id inside
# a signature only says which key to look for, never that the key is the right one.
SIG_KEY="keys/vizzletf-release.pub"
SIG_KEY_ID="18c63865e2bcf8d6"

# Provenance from someone other than this feed, so an update may merge itself once
# the checks pass. See CONTRIBUTING.md.
AUTO_MERGE="yes"
