# PZWorkspace

Source for my Project Zomboid mods. Built for **Build 42.20**.

Each folder is one mod: its Lua, its Java, its `mod.info` and its Steam listing. The built
versions are on the Workshop; these are the sources behind them.

| mod | what it does | workshop |
|---|---|---|
| [Lugli_FastLoading](Lugli_FastLoading) | Cuts loading time. 129s to 78s to be in the world on a 300+ mod list, 20s to 13s to the menu on vanilla. | [3787104045](https://steamcommunity.com/sharedfiles/filedetails/?id=3787104045) |

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

Jars are shipped **unsigned** for now. ZombieBuddy verifies a signature by fetching the author's
Steam profile page on every launch when the author is not on its bundled list, and any failed
request refuses the mod outright with no way to approve it. Unsigned takes a different branch and
gives the user a normal one-time prompt instead. See the FastLoading README for the detail.

## Licence

MIT, see [LICENSE](LICENSE).
