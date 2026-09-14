# luci-app-podkop-bot — a LuCI application package.
#
# Upstream publishes both OpenWrt package formats together with a signed owfeed manifest.
# The feed therefore verifies the manifest first and ingests the exact release assets.
KIND="manifest"

REPO="Medvedolog/luci-app-podkop-bot"
VERSION="0.19.17-r2"
TAG="0.19.17-2"

SIG_KEY="keys/luci-app-podkop-bot.pub"
SIG_KEY_ID="d6971b8a1b9a8ba4"

AUTO_MERGE="yes"
