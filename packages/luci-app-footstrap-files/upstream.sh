# luci-app-footstrap-files — a file manager for LuCI: browse, upload, download, edit
# with highlighting, and change mode and owner, with the translation catalogue that
# goes with it.
#
# Data only. tools/fetch.sh does the work; tools/check-updates.sh rewrites the
# version here and touches nothing else.

# Upstream's CI builds finished packages and signs an inventory of them, so this
# pins a version and a key and no checksum table: every file's size and sha256 come
# out of manifest.txt, under the author's signature, verified before it is read.
#
# One entry, two packages: the page and `luci-i18n-footstrap-files-ru`, which DEPENDS
# on it. KIND="apk" could only pin one artifact per format, which is why a Russian
# router could install the page from this feed and not its own language.
KIND="manifest"

# Upstream publishes both containers, so this package serves both release lines:
# 25.12 installs the .apk, 24.10 the .ipk. They are the same build.

REPO="VizzleTF/luci-app-footstrap-files"
VERSION="0.1.1-r1"
TAG="v0.1.1"

# The shared usign release key, as for the other three: one release pipeline signs
# them all, and this feed already pins its public half. The EC key the packages
# themselves are signed with is this repository's own — keys/luci-app-footstrap-files.pub.pem.
SIG_KEY="keys/vizzletf-release.pub"
SIG_KEY_ID="18c63865e2bcf8d6"

AUTO_MERGE="yes"
