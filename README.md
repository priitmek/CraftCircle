# CraftCircle

CraftCircle is a request board and recipe directory for World of Warcraft: Forever. It shares requests and opt-in recipe catalogs with guildmates and Battle.net friends through addon data.

## Install and update

In WowUp, select **WoW Forever** and use **Get Addons → Install from URL** with the [CraftCircle repository](https://github.com/priitmek/CraftCircle). Enable **Auto Update** in WowUp to install future releases. The WowUp notification addon can show available updates in-game. [WowUp installation guide](https://wowup.io/guide/get-addons/overview) · [WowUp in-game notifications](https://wowup.io/guide/wowup/addon)

For manual installation, download the `-forever.zip` asset from [Releases](https://github.com/priitmek/CraftCircle/releases) and extract its `CraftCircle` folder into `_forever_/Interface/AddOns/`. Restart WoW and click the CraftCircle launcher or type `/craftcircle`.

See the [in-game usage guide](CraftCircle/README.md).

## Release a version

Update `## Version` in `CraftCircle/CraftCircle.toc`, commit the change, and push a matching version tag such as `v1.4.0`. The GitHub release workflow creates the `-forever.zip` asset that WowUp tracks. To retry packaging an existing tag, run **Publish CraftCircle** from the repository's **Actions** tab and enter the tag.
