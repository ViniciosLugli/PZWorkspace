# PZWorkspace

Source for my Project Zomboid mods. Built for **Build 42.20**.

Each folder is one mod: its Lua, its Java, and its `mod.info`. The built and signed versions
are on the Steam Workshop — these are the sources behind them.

| mod | what it does | workshop |
|---|---|---|
| [Lugli_FastLoading](Lugli_FastLoading) | Cuts launch-to-menu and world load. Launch to playing 129s → 78s on a 300+ mod list; 20s → 13s to the menu on vanilla. | [3787104045](https://steamcommunity.com/sharedfiles/filedetails/?id=3787104045) |

## Layout

```
<Mod_Id>/
  mod.info          the mod descriptor as shipped
  lua/              client/ and shared/, mapping to media/lua/... in the built mod
  java/             ZombieBuddy patch sources, compiled into the shipped jar
  art/              preview and icon
```

Java parts use [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853)
for bytecode patching and are optional at runtime: without it those parts skip themselves and
the Lua ones still work.

## Licence

MIT, see [LICENSE](LICENSE).
