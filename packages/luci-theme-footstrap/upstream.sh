# luci-theme-footstrap — a LuCI theme, and the translation catalogues that go with it.
#
# Data only. tools/fetch.sh does the work; tools/check-updates.sh rewrites the
# version here and touches nothing else.

# Upstream's CI builds finished packages and signs an inventory of them, so this
# pins a version and a key and no checksum table: every file's size and sha256 come
# out of manifest.txt, under the author's signature, verified before it is read.
#
# One entry, three packages. Since 0.14.4 upstream splits its catalogues out of the
# theme the way luci.mk does — `luci-i18n-footstrap-ru` and `luci-i18n-footstrap-es`,
# each DEPENDS on the theme — and every release names all three in the manifest, in
# both containers. KIND="apk" could only pin one artifact per format, which is why a
# Russian router could install the theme from this feed and not its own language.
KIND="manifest"

# Upstream publishes both containers, so this package serves both release lines:
# 25.12 installs the .apk, 24.10 the .ipk. They are the same build.

REPO="VizzleTF/luci-theme-footstrap"
VERSION="0.14.6-r1"
TAG="v0.14.6"

# The release is verified against this key before it is ingested, so the feed's
# signature means the author signed it. The key id is pinned as well: the id inside
# a signature only says which key to look for, never that the key is the right one.
SIG_KEY="keys/vizzletf-release.pub"
SIG_KEY_ID="18c63865e2bcf8d6"

# Provenance from someone other than this feed, so an update may merge itself once
# the checks pass. See CONTRIBUTING.md.
AUTO_MERGE="yes"
