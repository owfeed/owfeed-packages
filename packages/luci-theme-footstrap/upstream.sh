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
VERSION="0.12.7-r1"
ARTIFACT="luci-theme-footstrap-0.12.7-r1.apk"
SHA256="3f7c4540d27573efaff390bd8375ecf0c426ec1999c1d4d1d6f211d8b71c889c"
ARTIFACT_IPK="luci-theme-footstrap_0.12.7-r1_all.ipk"
SHA256_IPK="386e729e7a15fdfe9db8522d64ef7f0af99553e6fd0bdfc048338cc1dea3a6d0"

# The release is verified against this key before it is ingested, so the feed's
# signature means the author signed it. The key id is pinned as well: the id inside
# a signature only says which key to look for, never that the key is the right one.
SIG_KEY="keys/vizzletf-release.pub"
SIG_KEY_ID="18c63865e2bcf8d6"

# Provenance from someone other than this feed, so an update may merge itself once
# the checks pass. See CONTRIBUTING.md.
AUTO_MERGE="yes"
