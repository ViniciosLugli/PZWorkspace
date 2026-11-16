# LugliPack server config

The server settings for the [LugliPack Steam collection](https://steamcommunity.com/sharedfiles/filedetails/?id=3839272101),
for anyone who wants to host it. Build 42, dedicated server.

| File | What it is |
|---|---|
| `LugliPack.ini` | Server settings, with the collection's `WorkshopItems=`, `Mods=` (in load order) and `Map=` |
| `LugliPack_SandboxVars.lua` | World and mod options |
| `LugliPack_spawnregions.lua` | Spawn towns offered to new characters |

## Setup

1. Install the Project Zomboid Dedicated Server (Steam: Library > Tools, or SteamCMD app `380870`).
2. Copy the three files into your `Zomboid/Server/` folder
   (Windows `%UserProfile%\Zomboid\Server`, Linux `~/Zomboid/Server`).
3. Open `LugliPack.ini` and fill in `Password=` (to join), `PublicName=`, and `RCONPassword=` if you use RCON.
4. Start the server with the name `LugliPack`, so it reads these files:
   `StartServer64.bat -servername LugliPack` (Windows) or `./start-server.sh -servername LugliPack` (Linux).
   The first start asks you to create the admin password.

The first start downloads about 300 Workshop items and takes a while. If one download fails the
server stops booting; start it again and it resumes.

## Good to know

- **Memory:** the mod list needs a big heap. Our server runs with `-Xms8g -Xmx24g`. Set `-Xmx` in
  `StartServer64.bat` (Windows) or `ProjectZomboid64.json` (Linux), and check it again after a game
  update, which can reset it.
- **Edit settings only while the server is stopped.** It rewrites `LugliPack.ini` when it exits.
- **Adding a mod:** add its Workshop ID to `WorkshopItems=` and its mod ID (with a leading `\`) to
  `Mods=`. Keep `\Lugli_ModpackFixes` last.
- **Players** just join; the server tells their game which mods to download. Subscribing to the
  collection first makes the first join faster.
