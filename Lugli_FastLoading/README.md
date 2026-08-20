# Lugli - Fast Loading

Removes loading work Project Zomboid does not need to do.
[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3787104045)

Measured on Build 42.20.3, a 300+ mod list, warm cache, A/B'd against the same save:
**main menu 52s → 23s (−55%)**, **world load 123s → 57s (−54%)**, loot tables byte-identical.

## Boot

All vanilla engine behaviour, not any one mod.

| fix | that phase | running total |
|---|---|---|
| Intro logos skipped — they play after loading has finished | −5.6s | **42.6s** (−18%) |
| Animation meshes queued ahead of the ~8,000 textures starving them | 12.0s → 0.4s (−97%) | **31.2s** (−40%) |
| Lua scan resolves a path once per folder, not once per file | 6.5s → 3.9s (−40%) | **27.5s** (−47%) |
| Tile geometry parsed on a worker thread | −2.4s | **25.5s** (−51%) |
| Mod folder walk on 8 threads, override order unchanged | 678 trees | **24.7s** (−52%) |
| Faster tokenizer, hot-reload watcher skipped, earlier load | 428ms → 76ms (−82%) | **23.3s** (−55%) |

## World load

- **Loot table init** — 7.56s → 2.16s (−71%). The parse is vanilla, but many mods each trigger
  it from their own handler, so on a large list it runs ~9 times and only the last pass
  survives. This runs it once, after them all.
- **SWMG Gunworks loot insert** — 78.3s → 8.1s (−90%), only with that mod. Two Lua-to-Java
  calls per value of every table, hoisted out of the loop.

## Source map

| here | in the built mod |
|---|---|
| `mod.info` | `common/mod.info` |
| `lua/client/`, `lua/shared/` | `42.20/media/lua/...` |
| `java/lugli/fastloading/` | compiled into `42.20/media/java/client/FastLoading.jar` |
| `art/` | `common/preview.png`, `common/icon.png` |

### Java parts

Each is a [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853)
`@Patch` class. Without ZombieBuddy none of them load and the Lua parts still work.

| file | what it patches |
|---|---|
| `LogoSkip` | `TISLogoState.enter` — takes the engine's own skip path |
| `MeshPriority` | `FileSystemImpl.runAsync` — raises mesh tasks above textures |
| `ScriptParse` | `ScriptParser.stripComments` / `parseTokens` — per-call buffer, linear token scan |
| `LuaScan` | `LuaManager.searchFolders` — hoists the path resolve out of the child loop |
| `ModWalkPrefetch` | `ZomboidFileSystem.loadMod` / `searchFolders` — parallel walk, serial merge |
| `TileGeometryPrefetch` | `TileGeometryManager.init` — parses on a worker, joins where the engine would |
| `WatcherGate` | `DebugFileWatcher.registerDirRecursive` — skips media trees outside debug |
| `AssetThrottle` | `TextureIDAssetManager.waitFileTask` — direct-buffer budget, asset pool size |
| `ShaderCache` | `Model.CreateShader` — caches compiled shaders |
| `BootProgress` | `GameWindow.DoLoadingText`, `LuaManager.RunLua` — redraws during load |
| `Tuning` | pure sizing rules, no engine imports, unit-tested |
| `LuaBridge` | exposes status to Lua |

## Correctness

Where engine code is replaced, the replacement runs against the original and switches itself
off on any disagreement, reporting it on the main menu. `TileGeometryPrefetch` refuses to start
unless the thread-safe tokenizer is active, because `ScriptParser` shares one static buffer
between callers and is not safe to call from two threads.

## Turning parts off

JVM properties, so they go in the `vmArgs` list inside `ProjectZomboid64.json` — not Steam
launch options, which never reach the JVM.

```
-Dfastloading.logo=keep          play the intro logos
-Dfastloading.watchergate=off    keep the hot-reload watcher
-Dfastloading.parse=off          use the engine's tokenizer
-Dfastloading.tilegeom=off       parse tile geometry on the main thread
```
