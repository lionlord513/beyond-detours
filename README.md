# Beyond Detours 0.1.0

A standalone experimental mod for **Drive Beyond Horizons**. Winding side roads branch off the main highway, lead to native points of interest, and end with space to turn around. Return to the same junction to continue the trip.

## What it adds

- Procedural routes determined by the world seed, road location and branch side, with terrain sampling, smooth curves and bounded grades.
- Irregularly positioned junctions roughly every 1.5 km where the terrain permits. Some junctions have detours on both sides.
- Roads generally around 200–900 metres long. Difficult terrain can shorten a route or rule out a location.
- One or two native POI selections on the current game's default settings. A stop may be a building, field, roadside encounter or other entry from the game's own pool.
- Rounded turnaround areas or hammerheads. Side roads never become a second progression highway.
- Native road mesh, materials, collision and terrain/foliage spline influencers. No game artwork is redistributed.
- Host-selected layouts transmitted to guests. Every player must have the same mod version.

This mod requires **UE4SS**, but does not require Beyond Apocalypse, Beyond Tuning, MixTape Maker, a private developer menu, an account ID, or a separate network service. It does not patch those mods or their configuration.

## Install

1. Close the game and ensure UE4SS is installed for the current game build.
2. Extract the release ZIP into the game installation folder containing the `DriveBeyondHorizons` directory. Alternatively, import the ZIP into Beyond Mod Manager.
3. Confirm that `DriveBeyondHorizons/Binaries/Win64/ue4ss/Mods/BeyondDetours/Scripts/main.lua` exists. The included `enabled.txt` enables this mod without editing the existing `mods.txt`.
4. Install the same version on the host and all guests, then start a game and drive. There is no menu or activation hotkey.

Keep the mod's `state` directory when updating or reinstalling. It stores immutable layout records by seed and road location. These records contain geometry and POI choices, never a player's inventory or account information. The native game owns POI actors, loot and save state.

## Developer's POI parameters

The mod reads the installed **`DARoadLevelTest_3`** data asset without modifying it. It uses the valid native entries and their relative `RandomWeight`, preserves each entry's authored transform and soft world reference, applies its custom side offset, and passes its visibility and creation-time values through the native **`LSLevelSpawnerComponent:AddLevel`** interface.

For the developer's **`L_CowField_B`** example, the installed entry was checked against the supplied screenshot:

| Parameter | Preserved value |
|---|---:|
| Always Visible | false |
| Use Custom Side Offset | true |
| Custom Side Offset | -7000 |
| Creation Time | -1 |
| Random Weight | 0.5 |
| Min Spawn Distance | 0 |
| Min / Max Spawn Height | 0 / 1 |
| Min / Max Slope Angle | -180 / 180 |
| Spawn One Time at Distance | 0 |

The world transform places that authored entry alongside the new road. The underlying local transform is composed rather than discarded; this also preserves non-identity transforms such as the native drift circuit's rotation. Eligibility checks use the native distance, normalized height and slope limits. Entries reserved for one-time progression are excluded from extra detours to avoid duplicating them. Selection avoids repeating the same POI within one branch while retaining native relative weights among eligible choices.

The mod guarantees a native stop on an accepted branch; the main highway's original spawn probability and selection pool remain untouched. It does not replace native loot with a custom loot table.

## Saves and removal

Native POIs receive stable names derived from the seed, junction and stop number. Reloading or returning to a branch reuses the same layout and native level identity. Only the host registers POIs; guests receive them through native level replication.

To disable the mod, disable Beyond Detours in the manager or remove its `enabled.txt` when the game is closed. To uninstall, remove only the `BeyondDetours` folder. Extra native POIs already recorded in a game save can remain after uninstalling, without their added roads; restoring a save from before the mod was installed removes that history. Keep the mod installed while playing saves that use its roads.

## Status

This is an experimental first release for Steam build **26437602 / Unreal 5.2.1**, not a claim of compatibility with every future game update. See `TESTING.txt` for the concrete verification and its limits. Recheck after game updates that change road generation, terrain or level streaming.

## Source layout

`planner.lua` contains deterministic geometry and weighted selection. `native.lua` handles game assets, terrain and POIs. `network.lua` transmits plans using existing native player-controller RPCs. `storage.lua` retains immutable layouts. `main.lua` manages streaming and world transitions. `json.lua` is bundled locally; no other mod supplies code at runtime.

The source archive includes the planner tests and package builder. No test dispatcher, test network DLL, personal save, generated layout cache, or other mod is included in the release ZIP.

From the extracted source directory, run `lua tests/run.lua .` with Lua 5.4 to check the planner, transport and native POI adapter. Run `python tools/package.py <output-directory>` to recreate the install and source ZIPs. The mod itself is Lua and does not need a compiler.
