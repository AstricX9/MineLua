# MineLua 1.0.0

## Highlights

- Layered deterministic world generation with coherent continents, continental
  shelves, deep oceans, climate, geology, erosion and additive landforms.
- Downhill river drainage with tributaries, flow accumulation, carved valleys,
  variable channel widths and deterministic basin lakes.
- Chunk-owned ocean, river and elevated lake surfaces.
- Generated-chunk distant terrain LOD: missing far chunks use the normal world
  generator, then compact to adaptive 2/4/8-block meshes after completion.
- Render Distance is an exact square chunk radius (up to 128), streamed in
  progressively expanding square rings around a local full-detail center.
- No procedural horizon floor or seed-synthesized far-water tiles; unloaded
  space is never covered by an unrelated underlying mesh.
- Traditional Cartesian Minecraft-style terrain with beaches, trees, clouds,
  grass, flowers and biome-aware vegetation.
- Temperature/elevation snowlines and safer dry-land spawn selection.
- Runtime F3 diagnostics for biome, climate, continentalness, mountains,
  erosion, drainage, geology, hydrology and landform.
- Configurable world-generation controls in `data/config/settings.json`.
- Manual, press-edge jumping with full body-volume wall and ceiling collision.
- Physically based ice and glass with material-specific IOR, Fresnel reflection,
  GGX highlights, refraction and Beer-Lambert absorption.

This release establishes the extensible terrain pipeline for future advanced
features such as canyons, glaciers, deltas, wetlands and regional volcanic
complexes.
