# CraftCircle for WoW Forever

CraftCircle gives guildmates and Battle.net friends a shared request board and a searchable crafter directory. This release targets **WoW Forever 1.60.1**, interface **16001**.

## Install

1. Fully exit WoW.
2. Extract the `CraftCircle` folder into `World of Warcraft/_forever_/Interface/AddOns/`. The TOC should be at `AddOns/CraftCircle/CraftCircle.toc`.
3. Enable CraftCircle in the character selection **AddOns** menu. Click the **CraftCircle** button near the minimap or type `/craftcircle`. Drag the button anywhere on the screen to save its position for that character.
4. Give your Battle.net friends this release. Existing friends playing Forever are discovered automatically, even in another guild. **My Circle** marks a contact **Synced** after receiving their board. **Not synced** means no reply has arrived yet. Guild sync also works with CraftCircle 1.2.0.

## Request an item

In **Requests**, drag an item from your bags onto the **Item link or ID** field. You can also paste a full item link or type its numeric item ID. Enter a quantity and an optional note, then click **Post request**.

Select your own request to edit or close it. When a matching item tooltip opens on loot, in a bag, or on an item link, CraftCircle shows which synced contacts want it and how many they asked for. Requests match the item's ID, so use the note for details about the version you need. Quantities are maintained by the requester.

## BoE gear upgrades

Open **BoE Gear** to see unbound bind-on-equip equipment in your bags. Select an item to see who might benefit and their potential item-level gain. Item tooltips show the same comparisons.

CraftCircle shares character level and equipped item levels and types through its existing addon-data channels. Comparisons use gear synced in the last seven days, including cached gear for offline contacts. Stats, effects, and build preferences need a manual check.

## Browse and share recipes

In **Crafters**, click a profession to see its crafters. Use **By profession** to switch to **By person**, then click a name to see that person's professions. Previously opened catalogs remain available from a bounded cache while the crafter is offline, and recipe search includes those saved catalogs.

Your profession profile includes learned professions and skill ranks. In **Crafters**, click **Share learned recipes** once to turn on automatic sharing for your current character. CraftCircle reads your known profession spells and refreshes when you learn a recipe. If some recipe details are unavailable at login, it can fill them in when the native profession window loads during normal play.

Synced contacts can select your profession and click **Browse recipes** to load the catalog while you are online. They can search it and inspect spell tooltips. Turning off recipe sharing clears your shared catalogs. `/craftcircle scan` still works as a manual fallback for an open profession.

To search across crafters, type at least three characters of a recipe name or its numeric ID under **Crafters**, then click **Find recipes** or press Enter. Results identify the crafter and show the crafted item's icon when available. Online contacts running version 1.4.0 or later can reply with up to 12 results each. Older versions can still sync boards and browse individual catalogs.

## Sync and resource use

- Board and recipe data use the guild addon channel or Battle.net's separate addon-data API. CraftCircle sends no chat messages or chat whispers. WoW internally labels incoming Battle.net addon data `WHISPER`. Sync may pause in restricted content.
- Guild and Battle.net requests and profession summaries remain cached for up to 14 days while the sender is still in your circle. **My Circle** labels offline contacts with saved data **Offline · Cached**. Full recipe catalogs load when the crafter is online. Each source is capped at 96 profiles.
- CraftCircle creates the window on first open and reuses seven list rows. It has no external libraries, bundled media, or per-frame polling. Each character can post up to 20 active requests. Local catalogs store up to 1,600 recipe IDs per profession. Only the catalog being viewed is kept in memory on the receiving client.

The Forever social, profession, and messaging APIs were checked against the mirrored [Forever 1.60.1.70862 UI source](https://github.com/Gethe/wow-ui-source/tree/9dc84f0d3bbae1768ac3405b3716000bd93eda06). Native rendering, live message delivery, and in-game memory use still need a live-client check.
