# luci-app-footstrap-cmd — a `:` command line and section search for luci-theme-footstrap,
# and the translation catalogue that goes with it.
#
# Data only. tools/fetch.sh does the work; tools/check-updates.sh rewrites the
# version here and touches nothing else.

# Upstream's CI builds finished packages and signs an inventory of them, so this
# pins a version and a key and no checksum table: every file's size and sha256 come
# out of manifest.txt, under the author's signature, verified before it is read.
#
# One entry, two packages: the plugin and `luci-i18n-footstrap-cmd-ru`, which DEPENDS
# on it. KIND="apk" could only pin one artifact per format, which is why a Russian
# router could install the plugin from this feed and not its own language.
KIND="manifest"

# Upstream publishes both containers, so this package serves both release lines:
# 25.12 installs the .apk, 24.10 the .ipk. They are the same build.

REPO="VizzleTF/luci-app-footstrap-cmd"
VERSION="0.1.0-r1"
TAG="v0.1.0"

# The same author key luci-theme-footstrap is verified with — one author, one key,
# and this feed already pins its public half.
SIG_KEY="keys/vizzletf-release.pub"
SIG_KEY_ID="18c63865e2bcf8d6"

AUTO_MERGE="yes"
