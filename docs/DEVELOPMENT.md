# Beyond Detours 0.1.1

A standalone experimental mod for **Drive Beyond Horizons**. Seeded winding side roads lead to native points of interest. Most new candidates reconnect to the main highway farther along the journey; other routes have round turnarounds or signed construction endings. An arrow-only sign at the exit points toward highway progression.

## What it adds

- Procedural routes determined by the world seed, road location and branch side, with terrain sampling, smooth curves and bounded grades.
- The native POI/building spawn chance also controls new intersection density. Lower settings retain a deterministic subset of junction candidates; zero stops new junctions. Previously cached roads remain eligible. At maximum chance, candidate junctions occur roughly every 1.5 km, subject to safe terrain and POI space.
- About 78% of new candidates attempt forward connections, using existing highway sections as their endpoints. Terrain can reject a candidate, so this is not a guaranteed ratio of completed roads. Existing junctions and saved POIs are retained during upgrades.
- New dead ends and shorter connections require at least two distinct native POIs. Connections over 900 metres require three, and those over 1.1 km attempt four. Buildings, fields and roadside encounters come from the native weighted pool. Saved legacy selections are retained even if adding another safe stop is impossible.
- Native road mesh and separate copies of its active materials, with lengthwise tiling matched to section length. Native materials on the highway are not edited.
- Terrain-following elevations and banking, full-width/inter-node clearance samples and static-object corridor sweeps. Unsafe or unloaded locations are withheld. Roads mask foliage without excavating the surrounding terrain. No game artwork is redistributed.
- The host registers lightweight POI descriptors together to reserve the native minimum spacing; the game's own proximity streamer loads and unloads their actors. Native replication and saving remain responsible for POI state. Road rendering is also proximity controlled.
- Only native procedural foliage instances intersecting an accepted road corridor are cleared. Player structures, ordinary world actors and native POI structures are not removed.
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

The world transform places that authored entry alongside the new road. Its origin can be moved farther outward to accommodate the complete authored footprint, including terrain influence; the native custom-offset fields are preserved. The local transform is composed rather than discarded, preserving rotations such as the native drift circuit's. Eligibility checks use native distance, normalized height and slope limits. One-time progression entries are excluded. Selection avoids repeating a POI within a branch and retains native relative weights among eligible choices that fit safely.

New branches are accepted only with the required number of safe stops. The main highway's spawn probability, pool and loot tables remain untouched. Native footprint metadata currently covers build 26437602; unknown future entries are skipped until their bounds can be verified.

## Saves and removal

Native POIs receive stable names derived from the seed, junction and stop number. Reloading or returning to a branch reuses the same layout and native level identity. Only the host registers POIs; guests receive them through native level replication.

Updating keeps the original v1 layout files and adds v2 records. Existing native POI identities and transforms are preserved. The upgrade resamples elevations and can move a corridor laterally by up to 60 metres while retaining its endpoints. After native POIs load, a final survey checks the settled terrain before the road is displayed. If it still cannot pass the safety checks, its road mesh is withheld; its saved POIs remain. Lowering the spawn slider does not erase saved layouts. Do not delete the state directory to force a reroll in an established save.

Repeat clearance checks are spread over ticks. Finite physics samples cannot prove that every future terrain LOD, displaced material surface or newly placed object will remain clear. Host decisions are sent to guests, but extended driving and streaming tests remain important; see TESTING.txt for the measured evidence and outstanding checks.

To disable the mod, disable Beyond Detours in the manager or remove its `enabled.txt` when the game is closed. To uninstall, remove only the `BeyondDetours` folder. Extra native POIs already recorded in a game save can remain after uninstalling, without their added roads; restoring a save from before the mod was installed removes that history. Keep the mod installed while playing saves that use its roads.

## Status

This is an experimental release for Steam build **26437602 / Unreal 5.2.1**. Live multiplayer remains unverified for 0.1.1: the isolated localhost join returned to the menu, although transport regression tests pass. See `TESTING.txt` for verification and limits. Recheck after updates that change road generation, terrain or level streaming. No FPS improvement is claimed.

## Source layout

`planner.lua` contains deterministic geometry and weighted selection. `native.lua` handles game assets, terrain and POIs. `network.lua` transmits plans using existing native player-controller RPCs. `storage.lua` retains immutable layouts. `main.lua` manages streaming and world transitions. `json.lua` is bundled locally; no other mod supplies code at runtime.

The source archive includes the planner tests and package builder. No test dispatcher, test network DLL, personal save, generated layout cache, or other mod is included in the release ZIP.

From the extracted source directory, run `lua tests/run.lua .` with Lua 5.4 to check the planner, transport and native POI adapter. Run `python tools/package.py <output-directory>` to recreate the install and source ZIPs. The mod itself is Lua and does not need a compiler.
