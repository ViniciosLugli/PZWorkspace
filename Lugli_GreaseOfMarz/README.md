# Lugli - Grease of Marz

![Lugli - Grease of Marz](art/gm-preview.gif)

Unofficial fixes for the Gunworks and Guns of Marz gun stack on Build 42. Not made by, or
affiliated with, the authors of those mods. Lua only, no jar, no `require=`.

## What it fixes

| Fix | Turns on when | What it does |
|---|---|---|
| LootIndex | Gunworks (`SWMG`) | Guns of Marz adds its guns to the loot tables through Gunworks' `Distribution.Insert`, which walks every loot table and asks every script item its name on each call. This replaces it with an indexed version that is checked against the original before it installs, and falls back to the original walk if the two ever disagree. |
| ReloadStart | Gunworks and Ultimate Marksman (`UltimateMarksman`) | Ultimate Marksman redefines `ISReloadWeaponAction:start` without calling the previous one, so Gunworks' `onReloadStart` (the reload prop in the off hand) never runs on guns without a magazine. This wraps the final `start` and runs that step only when the chain below did not, so it never runs twice. |
| Headhunter | Guns of Marz (`GunsOfMarz`) and Undead Survivor (`UndeadSuvivor`) | The Headhunter and Deadly Headhunter rifles take `Base.308Bullets`, `Base.M14Clip` and `Base.308Box`, which Guns of Marz converts into its own items. When the world's sandbox settings convert the .308 round or the M14 magazine, both rifles take Guns of Marz's M14 set instead: `SWMG.762x51_Bullet`, `MarzGuns.762x51Magazine20_M14`, `MarzGuns.762x51_Box`. Decided per world, after the sandbox is loaded and before any item is. A gun reads these from its script when it is created or loaded, so rifles already in a save change too. |

`shared/FastLoading_Gunworks.lua` is the same file Lugli - Fast Loading ships, at the same path,
so with both mods active only one copy runs.

## Multiplayer

Every file is `shared/` Lua, so it runs on the server and on each client; install it on both.
Tested in single player only so far.

## Checking that it loaded

The console prints one line at boot:

```
[Lugli/GreaseOfMarz] loaded [build <date> (<files>)], 3 part(s): Headhunter: installed; LootIndex: installed; ReloadStart: installed.
```

Each fix is `installed`, `skipped: <mod> not active`, or `failed: <reason>`. A failed fix leaves
the game as it would be without this mod. Two more lines follow at world load:
`[Lugli/GunworksLoot] ... Insert() replaced, self-test passed` and
`[Lugli/GreaseOfMarz] Headhunter: retargeted ...` (or `stock: ...` when the sandbox leaves the
vanilla ammo alone).

## Licence

MIT. No file from Gunworks, Guns of Marz, Ultimate Marksman or Undead Survivor is included; the
fixes reach their code only through what those mods expose at runtime.
