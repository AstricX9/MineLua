# MineLua roadmap

Written August 2026. Every number here was measured against this repo, not
estimated. Where something is a hypothesis rather than a measurement it says so.

## Where things stand

Per 16x128x16 chunk, after the optimisation work:

| | before | now |
| --- | --- | --- |
| `terrain.fillChunk` | 277 ms | ~90 ms |
| `voxel.meshChunk` | 74 ms | ~30 ms |
| block edit -> visible | ~60 s | ~1 ms light + one remesh |
| frame while streaming | 26 fps, 227 ms spikes | 94-111 fps, capped at 8 ms |

Measured render cost is **1-2 ms** for 2.88M vertices, 153 MB of buffers, the
shadow pass and all post. Rendering has enormous headroom; radius 8 would be
~5 ms and radius 12 ~12 ms. **Nothing in the render path needs work.**

Reference points for parity: vanilla Minecraft generates a chunk in 10-30 ms,
and per-thread figures from Nemez's CPU benchmarks on 1.20.4 range from 22 ms
(Ryzen 9 7900X3D) to 80 ms (FX-8350). MineLua's ~90 ms is the same order of
magnitude for a chunk a third the height, so roughly 2-3x slower per block.
Per-chunk speed is *not* what separates this from Minecraft. Threading is.

---

## 1. Neighbour-aware meshing — do this first

**83.8% of every chunk's geometry is invisible.** `voxel.lua` treats anything
outside local 0..15 as air, so each chunk emits its entire boundary wall even
where the neighbouring chunk is solid, and computes ambient occlusion as if the
neighbour were empty.

Measured over 9 chunks:

| chunk | solid boundary cells | hidden faces | chunk verts | wasted |
| --- | --- | --- | --- | --- |
| -1,-1 | 4785 | 4740 | 34524 | 82.4% |
| 0,0 | 4736 | 4710 | 32604 | 86.7% |
| 0,-1 | 5029 | 5015 | 34176 | 88.0% |
| **total** | | | **306708** | **83.8%** |

Of 4736 solid boundary faces in chunk 0,0, **4710 are completely hidden** by the
neighbour. This one fix addresses four separate things:

- **The ambient lighting artifacts.** `vertexAO` (voxel.lua) samples through
  `blockAtLocal`, which returns 0 outside the chunk. Every boundary vertex is
  therefore lit as though open air sat next to it. This is the reported "ambient
  lighting bug from digging" — it appears on a 16-block grid and is worst
  underground, where AO carries most of the shading.
- **Vertex count and GPU memory**, down ~6x: 2.88M -> ~470k, 153 MB -> ~25 MB.
- **Mesh time**, since most emitted faces stop being emitted.
- **Streaming throughput**, because meshing is roughly a third of per-chunk cost.

Implementation: `meshChunk` already receives a light sampler bound to the 3x3
chunk neighbourhood (`World:skyLightSampler`). Do the same for blocks — pass a
block sampler resolved once per mesh — and use it in `blockAtLocal` and
`occludes_face` instead of the bounds check. Chunks must then be remeshed when a
neighbour's border changes, which `queueLightTouchedRemeshes` already models.

Verify by diffing vertex output against the current mesher for interior faces
only; boundary faces are *expected* to change (that is the fix).

## 2. Snow on beaches

`terrain.columnAt` reclassifies a column to `"beach"` when it sits at or below
sea level, and overrides `topBlock`/`fillerBlock` to sand — but it **returns the
original biome's `profile`**. The snow pass reads `column.profile.snow`, so a
tundra or taiga coast gets snow laid on top of beach sand.

The same mismatch affects tree selection (`chooseTreeGenerator` takes `profile`,
`isTreeCenter` takes `biome`) and foliage, so a "beach" column still generates
its parent biome's trees.

Fix: when `columnAt` changes `biome`, swap `profile` to that biome's profile.
Minecraft does have snowy beaches, but via a dedicated Cold Beach biome — worth
deciding deliberately rather than inheriting it by accident.

## 3. Trees broken across chunk borders

In `fillChunk`'s tree pass, `groundY` is obtained two different ways:

- tree centre **inside** this chunk: scanned downward through the real blocks,
  after caves and surface replacement
- tree centre **outside** (the -3..width+2 border ring): `column.height`

`column.height` is not the surface. `terrainDensityAt` is
`(column.height - y) + noise` with noise up to +/-12, so the actual surface sits
several blocks away from it routinely. A tree straddling a chunk boundary is
therefore generated at **two different heights** by its two chunks — mismatched
canopies, and floating leaf clusters where the neighbour's guess was well off.

Fix: use the same scanned `groundY` for border trees, which requires the
neighbouring chunk's blocks — so this lands naturally alongside item 1. Failing
that, derive a shared surface height function both paths agree on.

## 4. Clouds

The geometry parameters are already right: 12-block cells and a 4-block-thick
slab match Minecraft. The problem is the **density function** —
`sampleFilled` in `game.lua` thresholds noise at `center > 0.26 or (center >
0.12 and neighbours > 0.22)`, which yields many isolated single cells and ragged
edges. Minecraft uses a hand-authored 256x256 `clouds.png` where each texel is
one cell, giving large connected blobs.

Fix: ship a cloud texture and sample it, or bias the noise toward larger
connected regions. Cheap either way and purely cosmetic.

## 5. Section meshing (16x16x16)

Meshing a whole 16x128x16 column for a one-block edit costs ~30 ms. Minecraft
splits chunks into 16-cube sections and rebuilds only the affected one. Takes an
edit from ~4 frames to ~1, and makes item 1 cheaper still. Touches the renderer,
since `terrainMeshes` becomes keyed by section rather than chunk.

## 6. Threading — the parity unlock

This is the only remaining thing standing between MineLua and Minecraft's render
distance. Minecraft 1.8 moved chunk rebuilds onto worker threads and runs world
generation on the server thread; essentially none of that work is inside the
frame. Here, all of it is.

At radius 8 (289 chunks) even Minecraft's own 20 ms/chunk is 5.8 s of CPU —
invisible across four workers, impossible inside a 16 ms frame on one thread.

Requirements, in order:

1. **Chunk storage moves to FFI memory.** Note this contradicts an earlier
   measurement in a useful way: FFI storage buys *nothing* for speed (0.10 ms vs
   0.07 ms per 32k reads), but worker `lua_State`s cannot touch Lua tables, so it
   is the hard prerequisite.
2. Job queue and result buffers in FFI memory.
3. Worker states each `require("terrain")` independently. `macroCache` and
   `activeSeed` are module locals, so they become per-thread for free.
4. Threads via `CreateThread` through `ffi.load`, plus `luaL_newstate`.

Mesh first — it is a pure function of a chunk plus its neighbours' light, and it
is the piece that most directly buys frame time.

## 7. Chunk persistence

`saves.lua` writes only `level.dat`, `mineLua.json` and an empty Minecraft-style
directory tree. **No chunk data is ever stored**, so worlds fully regenerate,
`region/` stays empty, and **placed blocks are lost on exit**. Walking 80 blocks
away and back re-pays full generation cost.

For actual play this probably matters more than any remaining optimisation.

## 8. Smaller items

- **Wall-clock streaming allowance.** `processTerrainMeshQueue` is called once
  per frame with a per-frame budget, so streaming throughput is `8 ms x fps`.
  Turning vsync off measurably speeds up world loading. Movement *is*
  frame-rate independent, so on a slow machine you walk at full speed while
  generating chunks proportionally slower. Fix: accumulate `dt * workRate` and
  spend from that, keeping the per-frame cap as a smoothness ceiling.
- **Noise hash.** `hash2`/`hash3` use `sin(n) * 43758.5453`, 49 ns/call versus
  13 ns for a bit-mix, and it is poorly distributed at large arguments. 3.8x on
  the dominant cost in generation. Changes world output, but since no chunk data
  is persisted, nothing seams.
- **`uploadMesh` retains `data`** on every mesh (game.lua), duplicating in C
  memory what already lives in the VBO.

---

## Suggested order

1. Neighbour-aware meshing (item 1) — fixes the reported lighting bug and 84% of
   the geometry at once, and unblocks item 3.
2. Beach profile and border trees (items 2, 3) — small, diagnosed, visible.
3. Clouds (item 4) — cosmetic, cheap.
4. Chunk persistence (item 7) — the biggest gap in *playing* the game.
5. Threading (item 6) — the parity unlock, worth doing on a clean base.

Section meshing (5) becomes much less urgent once 1 lands, since chunk meshes
get ~6x smaller.

## Working notes

- Every change so far was validated by diffing against the pre-change code for
  bit-identical output (density band: 393,216 voxels; mesher: 4,295,592 floats;
  lighting: 819,200 cells against a full rebuild). Keep doing that — it caught
  real mistakes and made the optimisation work safe.
- Run headless benchmarks with
  `LUA_PATH="src/?.lua;;" lib/luajit.exe <script>` from the repo root.
- Warm the JIT before timing anything. A first-trace compile shows up as a
  single 10 ms step and looks like a real outlier.
- Only the user can drive the app, so visual claims need confirming on screen.
