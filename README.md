# PZWorkspace

Source for my Project Zomboid mods. Built for **Build 42**; each `mod.info` names the oldest
build it supports.

Each folder is one mod: its Lua, its Java, its `mod.info` and its Steam listing. The built
versions are on the Workshop; these are the sources behind them.

| mod | what it does | workshop |
|---|---|---|
| [Lugli_FastLoading](Lugli_FastLoading) | Cuts loading time. On a 300+ mod list, 47s to 32s to the menu and 130s to 90s to be in the world. On vanilla, 37s to 27s to be in the world. | [3787104045](https://steamcommunity.com/sharedfiles/filedetails/?id=3787104045) |
| [Lugli_Optimizations](Lugli_Optimizations) | Cuts frame time by stopping the engine redrawing what is not moving. In vegetation, -16% at the median and -18% at the 90th percentile. In a city centre, -9% at the 90th and no median gain. | [3790863696](https://steamcommunity.com/sharedfiles/filedetails/?id=3790863696) |
| [Lugli_Achievements](Lugli_Achievements) | 280+ achievements across thirteen categories, earned by what your survivor actually does. Pure Lua, no effect on how the game plays. | [3793988085](https://steamcommunity.com/sharedfiles/filedetails/?id=3793988085) |
| [Lugli_EmergencyLights](Lugli_EmergencyLights) | Glow sticks, chem lights, road flares and a flare gun that keep burning where they land. | [3793988563](https://steamcommunity.com/sharedfiles/filedetails/?id=3793988563) |
| [Lugli_GreaseOfMarz](Lugli_GreaseOfMarz) | Unofficial fixes for the Gunworks and Guns of Marz gun stack: a faster loot pass at world load, the reload props Ultimate Marksman drops, and Headhunter rifles that take Guns of Marz ammo. | upload pending |
| [Lugli_HonestWeight](Lugli_HonestWeight) | Every item weighs what the real object weighs, times one Scale for the whole game. Clothes and small goods get lighter, tools and guns heavier, and nothing becomes too heavy to carry. | upload pending |
| [Lugli_ModpackFixes](Lugli_ModpackFixes) | Fixes for conflicts between popular Build 42 mods and for bugs inside some of them: SwapIt with Fancy Handwork, H.E.C.U. and Better Pause, Super Gore with the Special Zombies Tank, loot in Specific Loot's trucks, tile properties under More Damaged Objects and Raven Creek, and more. | upload pending |

Timing numbers were measured on 42.20.4 with 337 mods: same machine, same save, arms interleaved
A,B,A,B, every run checked against its own log, the first pair of each campaign discarded as cold.
Numbers move between releases and each mod's README carries the conditions attached to its own.

## What needs what

```
Lugli_FastLoading      ->  ZombieBuddy
Lugli_Optimizations    ->  ZombieBuddy
Lugli_Achievements     ->  NeatUI Framework
Lugli_EmergencyLights  ->  nothing
Lugli_GreaseOfMarz     ->  nothing; each fix turns on only beside the mods it fixes
Lugli_HonestWeight     ->  nothing
Lugli_ModpackFixes     ->  nothing; each fix turns on only beside the mods it fixes
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
  assets/           textures, models, sounds, scripts, sandbox options, translations and data files
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

**The jars are signed**, and the signing key is in ZombieBuddy's own signed author list
([`authors/ViniciosLugli.json`](https://github.com/zed-0xff/ZombieBuddy/tree/master/authors)), so
ZombieBuddy verifies them offline: no web request at launch, the author name in the approval dialog,
and preload eligibility. ZombieBuddy still asks once before it runs Java code you have not approved.

## Licence

MIT, see [LICENSE](LICENSE).
