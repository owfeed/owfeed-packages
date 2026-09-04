# gitbackup — commits an OpenWrt router's configuration into a Git repository on a
# schedule, with the LuCI interface and the translation catalogue that go with it.
#
# Data only. tools/fetch.sh does the work; tools/check-updates.sh rewrites the
# version here and touches nothing else.

# Upstream's CI builds finished packages and signs an inventory of them, so this
# pins a version and a key and no checksum table: every file's size and sha256 come
# out of manifest.txt, under the author's signature, verified before it is read.
#
# One entry, three packages: the backend `gitbackup`, the LuCI page
# `luci-app-gitbackup`, which DEPENDS on it, and `luci-i18n-gitbackup-ru`, which
# DEPENDS on the page. KIND="apk" could only pin one artifact per format, which is
# why a Russian router could install the page from this feed and not its own
# language.
KIND="manifest"

# 25.12 and later only. The package needs apk: /etc/apk/repositories.d, `apk add` by
# name and the default_postinst wrapper its uci-defaults script depends on are all
# 25.12-era, and upstream builds no ipk.

REPO="VizzleTF/luci-app-gitbackup"
VERSION="0.1.0-r1"
TAG="v0.1.0"

# The shared usign release key, as for this author's other packages: one release
# pipeline signs them all, and this feed already pins its public half. The EC key the
# packages themselves are signed with is this repository's own —
# keys/luci-app-gitbackup.pub.pem.
SIG_KEY="keys/vizzletf-release.pub"
SIG_KEY_ID="18c63865e2bcf8d6"

AUTO_MERGE="yes"
