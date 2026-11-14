# CraftCircle

CraftCircle is a request board and recipe directory for World of Warcraft: Forever. It shares requests and opt-in recipe catalogs with guildmates and Battle.net friends through addon data.

## What's new in 1.6.0

- **Offline sync.** My Circle keeps previously synced contacts visible as **Offline · Cached**. Requests and profession summaries stay available for up to 14 days while the sender remains in your circle. Full recipe catalogs require the crafter to be online.
- **BoE Gear tab.** Browse unbound bind-on-equip gear in your bags and select an item to see potential item-level upgrades for your circle. Offline matches use gear synced within the last seven days and are marked **cached**.

Read the [full changelog](CHANGELOG.md) or get the [latest release](https://github.com/priitmek/CraftCircle/releases/latest). WowUp shows the GitHub release notes in its changelog.

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

Update `## Version` in `CraftCircle/CraftCircle.toc` and add a matching `## 1.x.y` section to `CHANGELOG.md`. Commit both changes and push the matching version tag. The release workflow publishes that section as the GitHub release notes and attaches the `-forever.zip` asset for WowUp. To retry packaging an existing tag, run **Publish CraftCircle** from **Actions** and enter the tag.
