# luci-app-podkop-bot — a LuCI application package and the native helpers its release
# ships beside it.
#
# Upstream publishes both OpenWrt package formats together with a signed owfeed manifest.
# The feed therefore verifies the manifest first and ingests the exact release assets.
#
# One entry, three packages: the LuCI page `luci-app-podkop-bot`; `hwelp-proxy`, a
# native package built per architecture from the same repository's `hwelp-proxy/`
# (GPL-2.0, so the tag's archive is served as its source); and `warpscout`, a prebuilt
# MIT binary of vernette/warpscout, mipsel_24kc only. The page depends on neither.
KIND="manifest"

# Renamed upstream from Medvedolog/luci-app-podkop-bot with 0.19.19. The manifest
# names the repository it was released from, and tools/fetch.sh refuses one that names
# another, so the pin follows the rename; the package name and the key stay.
REPO="Medvedolog/luci-app-podkop-bearguard"
VERSION="0.19.24-r1"
TAG="0.19.24-1"

SIG_KEY="keys/luci-app-podkop-bot.pub"
SIG_KEY_ID="d6971b8a1b9a8ba4"

AUTO_MERGE="yes"
