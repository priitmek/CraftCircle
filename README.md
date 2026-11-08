# CraftCircle

CraftCircle is a request board and recipe directory for World of Warcraft: Forever. It shares requests and opt-in recipe catalogs with guildmates and Battle.net friends through addon data.

## Install with WowUp (automatic updates)

**Set up once:**

1. Install or update [WowUp](https://wowup.io/) (**2.24.0 or newer**) and select **World of Warcraft: Forever** at the top.
2. Click **Get Addons → Install from URL**. Paste **`https://github.com/priitmek/CraftCircle`** and click **Install**.
3. Go to **My Addons**, right-click **CraftCircle**, and check **Auto Update**.
4. Open WoW Forever, enable **CraftCircle** on the character-selection **AddOns** screen, and type **`/craftcircle`** in game.

From now on, opening WowUp lets it check for new GitHub releases and automatically update CraftCircle. **Use the GitHub repository URL, not a ZIP link**, so updates stay tracked.

**[Full beginner-friendly WowUp setup and troubleshooting →](WOWUP-SETUP.md)**

**Manual install (no automatic updates):** Download the `-forever.zip` file from [GitHub Releases](https://github.com/priitmek/CraftCircle/releases), extract the `CraftCircle` folder to `_forever_/Interface/AddOns/`, and restart WoW.

See the [in-game usage guide](CraftCircle/README.md).

## Release a version

Update `## Version` in `CraftCircle/CraftCircle.toc`, commit the change, and push a matching version tag such as `v1.4.0`. The GitHub release workflow creates the `-forever.zip` asset that WowUp tracks. To retry packaging an existing tag, run **Publish CraftCircle** from the repository's **Actions** tab and enter the tag.
