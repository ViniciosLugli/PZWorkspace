# PZWorkspace

Source for my Project Zomboid mods. Built for **Build 42.20**.

Each folder is one mod: its Lua, its Java, its `mod.info` and its Steam listing. The built
versions are on the Workshop; these are the sources behind them.

| mod | what it does | workshop |
|---|---|---|
| [Lugli_FastLoading](Lugli_FastLoading) | Cuts loading time. On a 300+ mod list, 49s to 38s to the menu and 129s to 78s to be in the world. On vanilla, 20s to 13s to the menu. | [3787104045](https://steamcommunity.com/sharedfiles/filedetails/?id=3787104045) |

## Layout

```
<Mod_Id>/
  mod.info          the descriptor as shipped
  workshop.txt      the Steam listing, tracked as source
  lua/              client/ and shared/, mapping to media/lua/... in the built mod
  java/             ZombieBuddy patch sources, compiled into the shipped jar
  art/              preview, icon, and any measurement graphics
```

## ZombieBuddy

The Java parts use [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853)
for bytecode patching. Without it those parts skip themselves and the Lua ones still work, so the
mods degrade rather than break.

Jars are signed. ZombieBuddy verifies a signature against the key published on the author's Steam
profile, fetched on every launch, so a failed request to Steam can refuse a mod that is perfectly
valid. See the FastLoading README for what that looks like and how to work around it.

## Licence

MIT, see [LICENSE](LICENSE).
