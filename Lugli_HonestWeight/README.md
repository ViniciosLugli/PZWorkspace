# Lugli - Honest Weight

Every item weighs what the real object weighs, times one Scale for the whole game, and never
more than 25% above its unmodded weight. A T-shirt weighs a tenth of a crowbar, not half of one,
while logs, sandbags, stone and ammo, which the game already makes heavy or you carry by the
dozen, stay close to the game's own weight. A typical loadout comes out a little lighter than
unmodded, because clothes and small goods drop to their real weight.

Covers vanilla and the mods in the LugliPack - B42 collection. Items from any other mod keep
their own weight. Every weight it changes is listed in [WEIGHTS.md](WEIGHTS.md), source by source.

## How weights are set

- **Real mass, one Scale.** Each item's reviewed real mass times the Scale option.
- **Max increase.** No item ends more than 25% heavier than in the base game (a sandbox option,
  0 to 400). A real log is 50 kg and a real sandbag 18, and the game's carry limits were never
  built for that, so a log goes from 9 to 11.25 and a sandbag from 2 to 2.5. Lighter is always
  allowed.
- **Bulk floor.** The game has no item volume, so bulky light things (coats, pillows, sleeping
  bags, empty boxes) weigh at least a little per litre they take up. Weight is the only thing
  that stops a bag holding a hundred shirts.
- **Carry limit.** Nothing ends up too heavy to pick up, drop or pull off a car. Up to 25 a
  weight is exact; above that it eases toward 45, under the game's limit of 50, so the heaviest
  objects land near the game's own heaviest items.
- **Containers and liquids.** Bottles, cans and pots weigh their empty mass, and the game adds
  the liquid on top. A sealed box weighs what it holds plus the packaging, unless the game makes
  it lighter on purpose (a tied log stack), and then it keeps the game's share.
- **Guns and attachments.** A gun weighs its real unloaded mass. A scope, suppressor or other
  attachment adds its own new weight when mounted.
- **Vehicle parts in true kilograms.** A part's weight is also the car's driving mass, so Scale
  leaves it at real kilograms rather than multiplying how heavy the car drives. Max increase
  still applies, so a part stays close to the weight the car was tuned with.
- **Melee stamina follows weight**, as it does in the base game: a heavier weapon tires you
  faster. One option restores the base game's swing stamina, counting the game's own minimum
  swing weight of 1.

## Sandbox options

| Option | Default | What it does |
|---|---|---|
| Realism (%) | 100 | How far weights move from the game's values toward the real ones. 0 keeps the game's values with only obvious errors fixed. |
| Bulk floor | Normal | Minimum kilograms per packed litre for bulky light items, before Scale: Off, Light 0.05, Normal 0.10, Strict 0.15. |
| Scale | 1.5 | Game weight per real kilogram, 1.0 to 2.5. 1.0 is true kilograms and makes carrying much easier than the base game. |
| Max increase (%) | 25 | The most an item may weigh above its base game weight. 0 only ever makes items lighter; 400 lets nearly every real mass through. |
| Keep the game's swing stamina | Off | On rescales each melee weapon so a swing or an axe chop costs the stamina it did without this mod. |

Changes take effect the next time the world loads.

## Compatibility

- **True Weight**: incompatible. Honest Weight replaces it and changes nothing while it is on.
- A mod that changes a covered item's weight itself wins: Honest Weight leaves any value it did
  not set alone.
- Safe to add to or remove from an existing save: items take the current weight when the world
  loads. Cooked food and part-used drainables keep their old weight until they are next used.

## Checking that it loaded

The console prints one line at boot, starting `[Lugli/HonestWeight] loaded [build `, then the
build date and each part with its state: `installed` with its counts, `skipped` with the
reason, or `failed` with the error. A failed part leaves the game exactly as it was without this
mod. When a world loads, a second line, `presets applied:`, lists the sandbox values in use and a
hash of every weight written, so two installs can be compared.
