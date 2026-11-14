# CraftCircle: install once, update automatically with WowUp

This guide is for **World of Warcraft: Forever**. You do **not** need Git, a terminal, or a GitHub account.

## One-time setup

1. **Close World of Warcraft.**
2. **Install or update [WowUp](https://wowup.io/)**, then open it. Use version **2.24.0 or newer** so that WoW Forever is supported.
3. **Select "World of Warcraft: Forever"** in the game-version selector near the top of WowUp. If it is missing, open **Options → Clients → Re-Scan**. If it is still missing, choose **Add New** and locate the WoW Forever game application inside your `_forever_` installation.
4. **Add CraftCircle from GitHub:** in WowUp, click **Get Addons → Install from URL**. Paste this exact repository address and choose **Install**:

   ```text
   https://github.com/priitmek/CraftCircle
   ```

5. **Enable automatic updates:** open **My Addons**, make sure **WoW Forever** is selected, right-click **CraftCircle**, and tick **Auto Update**.
6. **Start WoW Forever.** At character selection, open **AddOns**, make sure **CraftCircle** is enabled, then enter the game and type `/craftcircle` to open it.

**That's it.** For future versions, open WowUp with the game closed. While WowUp is running, it checks for updates approximately once an hour and installs new CraftCircle GitHub releases when **Auto Update** is enabled. Start or restart WoW to use the updated addon. You do not have to visit GitHub or download another ZIP.

> **Important:** Paste the **repository URL** above, not the URL of a ZIP file or GitHub's **Code → Download ZIP**. A direct ZIP installation cannot be tracked for updates by WowUp.

## Optional: automatically update all Forever addons

In WowUp, go to **Options → Clients**, select **WoW Forever**, click **Edit**, and enable **Auto Update**. This also applies automatic updates to other existing and future addons for that game version.

## Troubleshooting

**WoW Forever is missing from WowUp:** Update WowUp to at least 2.24.0, then choose **Options → Clients → Re-Scan**, or use **Add New** to locate the Forever game application.

**CraftCircle is not offered or "Install from URL" fails:** Check [CraftCircle Releases](https://github.com/priitmek/CraftCircle/releases). WowUp needs a published GitHub Release containing a file named like `CraftCircle-1.4.0-forever.zip` (the number will change with updates). The repository's release workflow creates these files when the author publishes a version tag. GitHub's automatic **Source code (zip)** is not the addon release file.

**CraftCircle is installed but not visible in game:** In WowUp, verify the selected game is **WoW Forever**, not Retail or Classic Era. The final addon path should look like `World of Warcraft/_forever_/Interface/AddOns/CraftCircle/CraftCircle.toc`. Restart the game completely and check **AddOns** at character selection.

**WowUp is not updating it:** In **My Addons**, right-click **CraftCircle**, confirm **Auto Update** is checked and **Ignore** is not checked. Check that the author has published a newer [GitHub Release](https://github.com/priitmek/CraftCircle/releases). Run WowUp while WoW is closed.

**WowUp's changelog is empty:** Refresh **My Addons** and check that CraftCircle is tracked through GitHub. The first install from a repository URL may show an empty changelog until WowUp fetches the release during its update check. You can read the same notes immediately on the [latest GitHub release](https://github.com/priitmek/CraftCircle/releases/latest).

**You previously copied CraftCircle manually:** Install it through WowUp using the **repository URL** so WowUp can track the release. Avoid leaving duplicate `CraftCircle` folders in the Forever AddOns directory.

## For the addon author: publishing an update

1. Update the addon files and change `## Version` in `CraftCircle/CraftCircle.toc` to the new number (for example, `1.4.1`).
2. Commit and push the changes to GitHub.
3. Create and push a **matching version tag** (for example, `v1.4.1`) on that commit.
4. The existing **Publish CraftCircle** GitHub Actions workflow packages the `CraftCircle` folder into `CraftCircle-1.4.1-forever.zip` and adds it to a GitHub Release.
5. Check the [Releases page](https://github.com/priitmek/CraftCircle/releases) for the ZIP. WowUp can then detect the new release on its normal update check.

The version number in the tag and `.toc` **must match** or the release workflow will fail. Ordinary pushes to `main` do **not** create a new WowUp update; publish a version tag.

Official references: [WowUp: Install from URL](https://wowup.io/guide/get-addons/overview) · [WowUp: Auto Update](https://wowup.io/guide/my-addons/addons) · [WowUp: Game clients](https://wowup.io/guide/options/wow-clients) · [WowUp: GitHub release packaging](https://wowup.io/guide/wowup/hub)
