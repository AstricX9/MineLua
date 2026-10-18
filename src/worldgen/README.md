# MineLua layered world generation

The runtime pipeline is deliberately split from voxel/material generation:

1. `noise.lua` derives deterministic world-space noise from the world seed.
2. `fields.lua` samples independent continental, tectonic, mountain, erosion,
   climate, drainage, age, geology, volcanism, latitude, and detail fields.
3. `geology.lua` classifies rock and landform, then computes hardness-dependent
   erosion. Biome is not considered at this stage.
4. `pipeline.lua:baseElevationAt` combines ocean basin/shelf relief,
   continental uplift, hills, mountain chains, foothills, plateaus, basins,
   volcanoes, calderas, and local relief.
5. `hydrology.lua` builds a cached world-coordinate drainage graph. Every macro
   cell chooses a lower neighbour; recursive upstream accumulation controls
   channel width, tributaries, river carving, and closed-basin lakes.
6. `pipeline.lua:sampleColumn` applies valleys/channels and lake basins, then
   computes temperature, moisture, rainfall, rain shadow, snow, coast type, and
   biome from the resulting geography.
7. `terrain.lua` adapts this semantic column to voxel blocks, soils, caves,
   vegetation, ores, and a chunk-local environment record.
8. `render_effects.lua` builds water surfaces from the per-column water levels
   stored on the chunk, including ocean, lake, and river surfaces.

All stages are pure functions of world seed and world coordinates. Regional
caches contain only reproducible derived data and never depend on chunk creation
order. `terrain.debugFieldsAt` and `terrain.debugColorAt` form the stable debug
interface for F3 data and future map overlays.

## World strategies

`world_profiles.lua` binds a stable world id to a generator module, atmosphere,
physics, and population policy. `terrain.setWorldProfile` loads
`worldgen.<profile.generator>` and consumes the shared semantic methods
(`sampleColumn`, `heightAt`, `macroAt`, chunk/debug sampling). The Earth pipeline
above is `worldgen.pipeline`; Mars is the independent `worldgen.mars` strategy.
Future dimension-like worlds can add a profile and a module without branching
the terrain adapter, save flow, or renderer.
