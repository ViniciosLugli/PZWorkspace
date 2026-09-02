# PZWorkspace

Source for my Project Zomboid mods. Built for **Build 42.20**.

Each folder is one mod: its Lua, its Java, its `mod.info` and its Steam listing. The built
versions are on the Workshop; these are the sources behind them.

| mod | what it does | workshop |
|---|---|---|
| [Lugli_FastLoading](Lugli_FastLoading) | Cuts loading time. On a 300+ mod list, 47s to 32s to the menu and 130s to 90s to be in the world. On vanilla, 37s to 27s to be in the world. | [3787104045](https://steamcommunity.com/sharedfiles/filedetails/?id=3787104045) |
| [Lugli_Optimizations](Lugli_Optimizations) | Cuts frame time by stopping the engine redrawing what is not moving. In vegetation, -16% at the median and -18% at the 90th percentile. In a city centre, -9% at the 90th and no median gain. | [3790863696](https://steamcommunity.com/sharedfiles/filedetails/?id=3790863696) |
| [Lugli_Achievements](Lugli_Achievements) | 280+ achievements across thirteen categories, earned by what your survivor actually does. Pure Lua, no effect on how the game plays. | [3793988085](https://steamcommunity.com/sharedfiles/filedetails/?id=3793988085) |
| [Lugli_EmergencyLights](Lugli_EmergencyLights) | Glow sticks, chem lights, road flares and a flare gun that keep burning where they land. | [3793988563](https://steamcommunity.com/sharedfiles/filedetails/?id=3793988563) |

Timing numbers were measured on 42.20.4 with 337 mods: same machine, same save, arms interleaved
A,B,A,B, every run checked against its own log, the first pair of each campaign discarded as cold.
Numbers move between releases and each mod's README carries the conditions attached to its own.

## What needs what

```
Lugli_FastLoading      ->  ZombieBuddy
Lugli_Optimizations    ->  ZombieBuddy
Lugli_Achievements     ->  NeatUI Framework
Lugli_EmergencyLights  ->  nothing
```

ZombieBuddy is a hard requirement for both Java mods, not a soft one: without it their jars never
load. Neither declares it in `mod.info`, for the reason below.

## Layout

```
<Mod_Id>/
  mod.info          the descriptor as shipped
  workshop.txt      the Steam listing, tracked as source
  lua/              client/, server/ and shared/, mapping to media/lua/... in the built mod
  java/             ZombieBuddy patch sources, compiled into the shipped jar
  assets/           textures, models, sounds, scripts and translations
  art/              preview, icon, and any listing or measurement graphics
```

## ZombieBuddy

The Java parts use [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853)
for bytecode patching. Without it those parts skip themselves rather than pretending to work.

**Emergency Lights needs nothing.** It was the third Java mod until its light went through
`IsoCell.addLamppost`, which is on the engine's Lua whitelist. It is pure Lua now.

**Neither Fast Loading nor Optimizations declares `require=ZombieBuddy`**, because both still have
something to say alone: Fast Loading keeps running its two Lua loot fixes, and Optimizations reports
on the main menu that it is doing nothing. ZombieBuddy itself never reads `require=`; vanilla's
launcher does, which is the only thing that would make the line bite.

**Jars currently ship unsigned, deliberately.** ZombieBuddy resolves a signer's key from a bundled
author list, and for an author who is not on it, falls back to fetching that author's Steam profile
page on every launch, for every user. Any answer other than the page fails closed and the approval
dialog then refuses the mod with no approve button. With no signature at all the user gets an
ordinary one-time approval prompt instead, which is strictly better than a signature that only
verifies when Steam answers. The cost is preload, which requires a valid signature.

This author's key is queued at [ZombieBuddy PR #44](https://github.com/zed-0xff/ZombieBuddy/pull/44).
When it merges, signing and preload both come back.

## Licence

MIT, see [LICENSE](LICENSE).
