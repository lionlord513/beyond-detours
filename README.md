# Beyond Detours 0.1.2 — Experimental

Explore winding side roads with buildings, fields and roadside encounters. Most new routes reconnect with the highway; some end at a turnaround or construction barrier. The game's POI chance slider controls how often new junctions appear. Terrain can prevent a road from spawning.

## Install

Close the game. Import the ZIP into Beyond Mod Manager and select Install. BMM checks for future updates through this mod's GitHub releases.

For manual installation, install UE4SS and extract the ZIP into the game folder containing the `DriveBeyondHorizons` directory. The mod goes in `DriveBeyondHorizons/Binaries/Win64/ue4ss/Mods/BeyondDetours`.

Everyone in co-op needs the same version. Start a game and drive; there is no menu or activation key.

## Saves and removal

Keep the mod's `state` folder when updating or moving a world. It stores your existing road layouts. Lowering the POI slider does not remove saved roads. Do not delete this folder to reroll roads in an established save.

To disable, use Beyond Mod Manager or remove `enabled.txt` while the game is closed. To uninstall manually, remove the `BeyondDetours` folder. Extra locations already saved in your world may remain without their roads. Keep the mod installed for those saves, or restore a save from before installation.

## Status

Experimental, tested against Steam build 26437602. Roads can be hidden when the terrain or nearby objects leave insufficient clearance. Live multiplayer remains unverified: the previous local join test returned to the menu. See TESTING.txt for results and outstanding checks.

## Changes

### 0.1.2
- Shortened the player guide.
- Added a GitHub update feed for Beyond Mod Manager.
- Road generation is unchanged.

### 0.1.1
- Added routes that reconnect with the highway, varied dead ends and more roadside stops.
- Improved road placement around terrain and buildings.
- Kept existing roads and saved locations during upgrades.

## Build from source

Run `lua tests/run.lua .` with Lua 5.4. Package with `python tools/package.py <output-directory>`. The source includes the original detailed design notes in docs/DEVELOPMENT.md.
