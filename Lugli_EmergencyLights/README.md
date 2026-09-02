# Lugli - Emergency Lights

Glow sticks, chem lights, road flares and a flare gun for Project Zomboid **B42**.

Build 42 has none of them, and a matching hole underneath: a lit item on the ground emits no light
at all, which is why vanilla puts a lamp out *before* it lands. These do not go out. Crack one and
it burns wherever you leave it.

**[Watch the demo](https://youtu.be/uk9aEgyv5wU)**

[![Lugli - Emergency Lights, running in game](https://img.youtube.com/vi/uk9aEgyv5wU/maxresdefault.jpg)](https://youtu.be/uk9aEgyv5wU)

![Every item the mod adds](art/el-items.png)

## No dependencies

Subscribe, enable, play. There is nothing else to install and load order does not matter.

This mod used to need [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853)
and a jar, because `zombie.iso.LightingJNI` is not on the engine's Lua exposer whitelist. It no
longer does: `IsoCell` and `IsoLightSource` are both on that whitelist, so the light goes through
`getCell():addLamppost` and the mod is pure Lua.

## What that costs, stated plainly

`addLamppost` applies two limits the old direct call did not, and one of them is real:

| | effect | what the mod does |
|---|---|---|
| radius | clamped to 20 tiles | accepted. The three ground families are 5, 10 and 15 and are untouched; only a flare overhead lost reach |
| colour | doubled, then clamped | cancelled exactly by halving on the way in, so the whole burn-down colour curve survives |
| cost | a global relight per add and per remove | a light that only changes colour costs neither, which is why moving lights are the only ones rationed |

A held flare's flame is part of the held model: a white-hot core, a plume and three tongues built
into the mesh, so the engine carries it on the rod through every animation, which nothing drawn
from Lua can do because Lua cannot read the hand bone. The flame's colours are painted into the
lit skin and the lit item's tint is white, so the engine shows it as painted. What a mesh cannot
do is flicker; the light it casts does. On the ground, where the rod's pose is known exactly, the
flame stays a drawn, animated sprite.

## What it adds

23 items across four families. Every colour ships sealed and lit, and each family has its own spent
item: a burnt road flare leaves a burnt road flare, not a glow stick.

| Family | Colours | Burn | Radius | Where it spawns |
|---|---|---|---|---|
| Glow stick | green, blue, pink, orange | 4 h | 5, one room | Supermarkets, houses, kids' rooms, camping crates; camper, adventurer and teenagers' vehicles |
| Chem light | green, red, yellow, cyan | 8 h | 10, a house or a street and both pavements | Army surplus, police lockers, tool stores; army, SWAT, police and ranger vehicles |
| Road flare | red | 30 min | 15, hard flickering light plus a sky wash | Car supply shelves, mechanics, every emergency vehicle; a small chance in any boot |
| Flare gun | with its own cartridge | 5 min | 20, overhead | Police and army lockups, camping crates; ranger, fire and survivalist glove boxes |

Radii are in tiles, and **20 is the engine's ceiling for any one light**. A road flare reaches
three quarters of it from your hand; a flare overhead reaches all of it.

**Every duration is in-game time**, read off `getWorldAgeHours`, so all four scale with the day
length setting rather than the wall clock. Every figure in the table is the sandbox default, not a
limit.

## How they behave

- **Cracking is irreversible.** No off switch: a cracked stick is a chemical reaction and a lit
  flare is burning.
- **Dropped items keep burning.** Walk away, come back later, still lit.
- **Throwing uses the real animation and aiming**, and lands where you aimed. The engine's thrown
  object makes a noise identical to a ringing house alarm; these are silent by default.
- **The light dims as it burns down**, then goes out and leaves the spent item.
- **State survives everything.** A lit item is a swapped item plus an absolute timestamp, so it
  reads the same across saves, reloads, containers and multiplayer clients.

## Sandbox options

New Game screen, under `LugliEL`, saved in a preset like any vanilla setting.

| Group | Options |
|---|---|
| Burn time | `GlowStickHours` `ChemLightHours` `RoadFlareHours` |
| Light radius | `GlowStickRadius` `ChemLightRadius` `RoadFlareRadius` |
| Light look | `LightIntensity` `LightSaturation` `LightFlicker` `LightIncidence` |
| Throwing | `ThrowRangeMult` |
| Noise | `CrackNoise` `ThrowNoise` `FlareNoise` `FlareGunNoise` `AerialNoise` |
| Flare gun | `AerialShotRange` `AerialSeconds` `AerialLightRadius` `AerialRange` |
| Road flare | `FlareWash` `FlareFire` `CarriedFlareSound` |
| Map | `MapMarker` `MapRangeCircle` |
| Loot | `LootMultiplier` |
| Performance | `SweepRadius` `SweepSeconds` |
| Diagnostics | `DebugLog` `DebugRanges` |

`SweepRadius` and `SweepSeconds` bound the scan that finds lit items near the player. Lower them to
get the frame time back.

## Compatibility

- Singleplayer, multiplayer and dedicated servers. Cracking a stick and burning one out are swaps
  the server makes in multiplayer, because a client cannot create an item the server will ever
  see: what you hold is what everybody else sees in your hand. A throw is relayed at launch so
  other players watch the arc and its light, and the landed item is placed by the server.
  Items and timers are server side, light is drawn
  per client.
- Safe to add mid-save: items appear in containers the game has not generated yet, so buildings you
  have stripped stay stripped. Safe to remove.
- The *Explosives* mod also has a handheld road flare. Different module, so no conflict, but an
  honest overlap on one family.
- English and Brazilian Portuguese, both complete.

## Credits

**Flare gun model:**
["Low Poly Flare Gun"](https://sketchfab.com/3d-models/low-poly-flare-gun-ccf38c8f0cb74a8cbd237ab4a0ba1467)
by [Naudaff3D](https://sketchfab.com/Naudaff3D), licensed
[CC BY 4.0](http://creativecommons.org/licenses/by/4.0/), attribution required, commercial use
allowed. Converted to PZ's model format with a flat palette texture; geometry unmodified.

**Sound:** seven CC0 clips, no attribution required.

**Everything else** is original work under this mod's licence.

## Layout

```
art/           preview, icon, and the graphics this page uses
assets/media/  textures, models, sounds, shaders, item and sandbox scripts, translations
lua/           client/, server/ and shared/
mod.info       the in-game manifest
workshop.txt   the Steam listing, BBCode
```

MIT. Part of [PZWorkspace](https://github.com/ViniciosLugli/PZWorkspace).
