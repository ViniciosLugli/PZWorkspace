# Lugli - Dead Man's Stash

Gated scavenging for Project Zomboid **B42**. Some of the dead left something behind: a stash
box tucked into the back corner of an attic, a closet, a storage room or a bedroom, that pays
out a better haul than the containers around it once you get it open. Every way in costs
something: time, noise, tool wear, a key you have to find, or the loot itself.

**On the Workshop:** [Lugli - Dead Man's Stash](https://steamcommunity.com/sharedfiles/filedetails/?id=3842379885).

Work in progress. This build has three stash boxes, the **nailed crate**, the **lockbox** and the
**footlocker**, and two safes, the **dial safe** and the **keypad safe**. Trapped survivor
holdouts follow, played and tuned before they ship.

## Where the boxes are

By default about one building in fourteen hides a stash, a little more often out in the country
and a little less in a crowded city block. A box is never in the open: it sits
against a wall, usually in a corner or beside furniture, away from doors and windows, in a room
the owner kept to themselves. Living rooms, kitchens, halls and bathrooms never hide one. Search
the back rooms.

The room decides the box, the way the game itself furnishes it. Bedrooms, offices, closets,
locker rooms and the pawn shop stockroom hide a lockbox; gun stores and the army, police and
security rooms a military footlocker, and so do attics and basements, where an old army trunk
gets put away, and out in the country the garage, shed or barn, where it holds hunting and camping
gear; in town, garages, sheds, warehouses and every other back room hide a nailed crate. A
footlocker never turns up in a school, clinic or church.

A box in an army, gun store, police, pawn shop or bunker room is one step richer. A richer box is
also rarer: a room that would hide a Good box keeps it only 40 % of the time, a Rich one 20 %,
so a gun store usually hides an ordinary box. Every box also has its own luck: an Ordinary one
comes out Good about one time in six and Rich one time in twenty, a Good one (every safe starts
Good) comes out Rich about one time in eight, and a keypad safe in a bank vault or a jeweller's
back room is always Rich. Across a map that is about six boxes in ten Ordinary, three Good and one
Rich.

Right-click a box and pick how to open it, or inspect it first: the window shows its quality, a
hint of what it holds, any work already done, and every way in with its tool, time and noise. A
way you cannot take right now stays listed, greyed out, with the reason. Work that takes a while
is heard at that range every few seconds for as long as it lasts.

## The nailed crate

| Way in | Tool | Time | Heard up to | What it costs |
|---|---|---|---|---|
| Pry the lid off | crowbar or pry bar | about 12 s | 8 tiles | tool wear; nothing inside is damaged |
| Pull the nails out | hammer | about 20 s | 6 tiles | slow and wears the hammer; you keep the nails |
| Smash it open | sledgehammer or axe | about 4 s | 12 tiles | fragile things inside break, tools inside lose condition |

## The lockbox

| Way in | Tool | Time | Heard up to | What it costs |
|---|---|---|---|---|
| Unlock it with a key | its own key | about 1 s | silent | finding the key |
| Pick the lock | paperclip or screwdriver | about 15 s | 1 tile | Burglar or Locksmith only; it can fail (below) |
| Force the lid | crowbar or pry bar | about 6 s | 9 tiles | tool wear; a few fragile things inside may break |
| Jimmy the latch | screwdriver | about 30 s | 2 tiles | an Ordinary lockbox only; a better lock is too good to jimmy |

Picking succeeds 30 % of the time at Nimble 0, 7 % more per Nimble level, up to 90 %. A failed
try loses the work done, uses up the paperclip if that is what you picked with (a screwdriver
survives), and one time in twenty jams the lock for good: a jammed lock cannot be picked any more, but
the key, forcing and jimmying still work.

## The footlocker

| Way in | Tool | Time | Heard up to | What it costs |
|---|---|---|---|---|
| Unlock it with a key | its own key | about 1 s | silent | finding the key |
| Cut the padlock | bolt cutters | about 3 s | 3 tiles | tool wear |
| Snap the padlock | crowbar | about 8 s | 10 tiles | Strength 4 or more; it can fail |

Snapping succeeds 15 % of the time at Strength 4, 40 % at Strength 5 and 5 % more per level above it. A failed try
loses the work done but never jams, so you can keep trying.

## The safes

A dial safe hides in about one office, pawn shop or family house in ten; a keypad safe in more
than half the banks, police stations, jewellers, pharmacies and gun stores, in the back room: a
pharmacy's holds its medicine, a gun store's its guns and ammunition. Like the stashes, both turn
up a little more often out in the country and less often in a crowded city. Both take a four-digit code, and you type it yourself: on
the keypad's buttons, or by turning the dial right, left, right, left, each change of direction
setting the number under the mark. Five wrong codes lock you out for two in-game hours (a dial
for one), and a keypad lockout sets off its alarm. The code window lists the notes you carry for
that safe and the codes you have already tried.

| Way in | Safe | Tool | Time | Heard up to | What it costs |
|---|---|---|---|---|---|
| Type the code | both | none | as soon as you press OK | silent | finding the notes, and the tries |
| Listen to the dial | dial | stethoscope | about 15 s a try | silent | a try that hears nothing finds nothing; Deaf cannot |
| Drill the lock | both | hand drill | about 2 minutes | 10 tiles | the drill wears every session; ease off before it stays in the red 6 s or it wears once more |
| Torch the door | both | blow torch | about a minute | 6 tiles | Welding 3 or a Welder, propane for the part cut, and some paper, money and food inside burns, less with each Welding level over 3; every second stopped near the end burns less |
| Hotwire the keypad | keypad | screwdriver and electronics scrap | about 30 s | 2 tiles | Electrical 3 (an Electrician: 1), 15 % there and 40 % a level up; the scrap is spent, and a miss sets off the alarm and a lockout |
| Put a battery in | keypad | a charged battery | about 3 s | silent | a keypad with no power, from the grid or a generator, takes no code and cannot be hotwired until it has one |

Listening succeeds 40 % of the time, 5 % more per Nimble level; Keen Hearing adds 15 %, a Burglar
25 %, Hard of Hearing takes away 30 %. Keen Hearing also listens in three quarters of the time,
Hard of Hearing in twice the time. Each success gives you one digit of the code, which the code
window keeps. Drilling and torching keep their progress when you put them down; typing, listening
and hotwiring start over.

While you work, a small panel shows the work: the bit going in and its heat, the seam glowing
down the door, the dial turning. It never takes the controls, and an option hides it.

Tools cool gradually. Ease off or Stop holds the work for as long as you like: Resume takes it up
again, and it resumes by itself once the drill bit is cold (about 5 s from red) or the seam has
fully cooled (8 s). A short rest leaves the bit warm, so the red comes back sooner, and every second
of a torch's stop lowers what burns inside. Walking away cools a tool the same way, so taking it up
after 2 s keeps most of its heat and after 10 s none. A bar under the button shows how long you
have before the drill overheats or the torch cuts out. A torch spends propane only for the part of
the seam it cut.

## Keys

Every lockbox and footlocker has its own key, and no other key opens it. The dead man left it in
another container of the same building, in another room than the box's when he could, and in a
desk, side table, dresser, wardrobe or counter before anything else. A building with no container
at all leaves it to the first zombie killed within 15 tiles of the building, who carries it. The
key works from your main inventory or a key ring, like a door key; not from inside a bag. The box's
window says whether you carry a stash key, and if not, that its key is somewhere close.

A safe's code is on the owner's notes instead: a crumpled note, a torn page, an old notepad, named
for the safe they are about. Each says something plain about the code ("The last number is 2, and
the first and third numbers are the same."), and none gives it away: one note leaves at least a
hundred codes, two leave 3 to 10, few enough to try. The first and third are hidden like a key, in
another room of the building; the second is on the owner, the first zombie killed near the
building. Read one the vanilla way, Read Note; nobody can write on them.

## Skills and traits

- **Strength** makes prying, forcing and smashing faster (Strength 5 is the baseline), and decides
  whether and how often you snap a padlock.
- **Carpentry** and the Carpenter profession make pulling nails faster, and a Carpenter salvages
  every nail.
- **Dextrous** hands are quicker and **All Thumbs** slower at prying, pulling nails, picking and
  jimmying.
- A **Burglar** pries and forces more quietly, and can pick a lock.
- **Locksmith** is the mod's own trait (cost 2), for locks of every kind:
  - picks locked doors in the world (house, double and garage doors) with a paperclip or a
    screwdriver, quietly and without breaking them; a failed try bends the paperclip;
  - picks a stash lock without being a Burglar, and picks and jimmies in 80 % of the time;
  - never jams a lock, and listens to a dial better than a Burglar does (+0.30).
  Burglar and Locksmith exclude each other.
- **Keen Hearing**, **Hard of Hearing**, **Burglar** and **Locksmith** change how well you listen to a dial
  (the two hearing traits also how fast); a **Deaf** survivor cannot. An **Illiterate** survivor
  cannot read a safe's notes.
- An **Electrician** hotwires a keypad at Electrical 1 instead of 3; a **Welder** torches a safe
  without the Welding skill and burns half as much of what is inside.
- Prying, forcing and snapping train Strength, pulling nails trains Carpentry, picking and
  listening train Nimble, hotwiring trains Electrical, torching trains Welding.

Put the work down halfway and the box stays half opened. A sledge used the vanilla way destroys
the box and leaves what was inside on the floor, at brute-force damage. An opened box shows its
lid off, so you can tell from across the room that someone got there first.

A sealed box cannot be picked up or scrapped, and its haul is rolled once: a sealed box is never
refilled. Once opened and emptied, a box opened through its lock (key, pick, pry, claw, force, cut,
snap, code, listening or hotwire) can be picked up and placed as ordinary storage, a safe weighing
25 and needing a hammer. One drilled, torched or smashed open is too wrecked to move or turn.
Any opened box, wrecked or not, can be taken apart with Disassemble, as vanilla furniture of its
material is (a hammer for the wooden crate and footlocker, a blow torch and welding mask for the
metal lockbox and safes), or cleared away with a sledgehammer.
With loot respawn on, an opened box refills like any other container in its room.

## What is inside

Each roll draws from the lists below, so a box can hold any of them and none is promised.

| Box | Can hold |
|---|---|
| Nailed crate | what its room stores: tools, carpentry and metalwork, mechanics, farming, camping gear, and medicine in a pharmacy or clinic storeroom |
| Lockbox | a handgun and its ammunition, medicine, jewellery, smokes and a little cash |
| Footlocker | an army locker's kit, camping and survival gear, ammunition |
| Dial safe | a handgun, ammunition, medicine or jewellery |
| Keypad safe | at a police station its guns, ammunition and evidence; at a gun store its guns and plenty of ammunition; at a pharmacy its medicine; in a bank or a jeweller's, a handgun and its ammunition, medicine, gold and jewellery |

A better box rolls more often: one, two or three rolls at Ordinary, Good and Rich. Gems and cash
are worth little on their own; gold, silver and jewellery melt down at a forge.

The haul follows the server's own loot settings: it is rolled the way vanilla rolls any container,
so per-category loot rarity, the item removal list, the loot rolls multiplier and loot decay over
time all apply. A category set to None never shows up in a box.

## Sandbox options

| Option | Default | What it does |
|---|---|---|
| Stash boxes | on | off: no new box is hidden; boxes already in the world can still be opened |
| Stash chance (%) | 7 | out of every hundred buildings, how many hide a box: up to 1.4 times as often out in the country, down to three quarters as often in a crowded city block, the same overall; 100 is every building; each building is judged once. A richer box is rarer still: a room that would hide one keeps it only 40 % of the time |
| Stash boxes per building | 2 | a building hides one, and one more per 1,000 tiles of floor plan, up to this; one per room |
| Payout rolls | 0 | a box rolls one loot list per step of quality (1, 2, 3); each point adds that many again |
| Brute force damage | Normal | Off, Light, Normal, Heavy. Only Smash it open, Force the lid and a sledgehammer damage what is inside; forcing does so at Light unless this is Off |
| Noise multiplier | 1 | every way in, while the work goes on (every 4 s) and when it ends, and a picked door; 0 is silent; a safe's alarm is not scaled |
| Time multiplier | 1 | scales every way in, and a picked door |
| Safe chance (%) | 10 | out of every hundred offices, pawn shops and big houses, how many hide a dial safe, judged apart from the stash boxes; at most one per building |
| Vault safe chance (%) | 60 | out of every hundred banks, police stations, jewelry stores, pharmacies and gun stores, how many keep a keypad safe; more often in the country, less in a crowded city |
| Safe code tries | 5 | wrong codes a safe takes before it locks you out |
| Safe lockout (hours) | 2 | in-game hours a keypad refuses every code after too many wrong ones; a dial locks for half as long; never under one in-game minute, even at 0 |
| Safe alarm | on | a keypad lockout or a failed hotwire sets off a loud alarm |
| Clues per safe | 2 | notes with a hint to the code, 0 to 3; two together leave 3 to 10 codes to try, and no set gives the whole code |
| Debug log | off | a console line for every box hidden and opened |

## Multiplayer

Everything is decided by the server: where the boxes are, the keys, the haul, every pick and
snap roll, and whether a way in was really finished. A modified client can ask for anything and
still gets only what its survivor could do. Two survivors cannot work the same box at once.

## Compatibility

Build 42.20 and newer. Before 42.22 the game has no ladders, so only stairs lead to an upper floor's
box. Requires [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032),
which draws the inspect window, the same framework Lugli Power Grid uses. Load order does not
matter. The boxes are the mod's own tiles, so no map or loot mod changes where they can go. A
proximity-loot mod or crafting from nearby containers sees a sealed box as empty, because its
haul does not exist until it is opened. Added to an existing save, boxes appear in buildings
the first time you come near them.

With [Neat Lockpicking](https://steamcommunity.com/sharedfiles/filedetails/?id=3783535220), its
lockpicks pick stash locks and locked doors, tried before a paperclip: a failed try uses up a
handmade lockpick and wears a store one down one condition. A store lockpick picks 10 % better,
each Lockpicking level adds 5 %, and every pick trains Lockpicking. A Locksmith learns Neat's
lockpick recipe, so Neat's own lockpicking opens to it as to a Burglar.

Map mods tested in game, boxes placed in their own buildings: Raven Creek, Fort Waterfront, Fort
Benning, Nellis Air Force Base and Dirkerdam Integrated. Rooms a map mod misnames
(`stroge`, `polistorage`, `gunshop` and the like) hide boxes as the room they stand for. Other
map mods work the same way when their rooms carry vanilla names, but are untested.

## Checking that it loaded

The console prints one line when the world starts. It opens with `[Lugli/DeadMansStash] loaded [build `,
then the date the mod was built, where it is running, and every part with its state:
`installed`, `skipped` with the reason, or `failed` with the error.
