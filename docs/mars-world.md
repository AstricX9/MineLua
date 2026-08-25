# Mars world

Mars is implemented as a first-class world profile, MineLua's analogue for a
dimension. A profile owns its terrain generator, atmosphere, sunlight, gravity,
surface-water policy, and population switches. `src/world_profiles.lua` is the
registry seam for future worlds; terrain implementations share the semantic
generator interface used by `src/worldgen/pipeline.lua` and
`src/worldgen/mars.lua`.

The Mars generator is a scientifically grounded procedural analogue rather than
an exact MOLA heightmap. It compresses global-scale relief into playable space:

- the smoother, lower northern plains and older, crater-rich southern highlands;
- overlapping impact basins, raised rims, and ejecta blankets;
- broad basaltic shield volcanoes with summit calderas;
- long fault-controlled canyon terrain;
- iron-rich ochre dust, darker exposed basalt, wind-shaped dunes, and polar ice;
- no stable open surface water or terrestrial vegetation.

The atmosphere is thin and dust dominated. Daylight is ochre, the low-Sun
aureole is blue-grey, sunlight is scaled for Mars' average distance from the
Sun, the sol is 24 h 39 m 35 s, and player gravity uses the Mars/Earth surface
gravity ratio.

Scientific references:

- [NASA Mars facts](https://science.nasa.gov/mars/facts/)
- [NASA: what sunrises and sunsets look like on Mars](https://science.nasa.gov/solar-system/planets/mars/what-does-a-sunrise-sunset-look-like-on-mars/)
- [NASA: why Mars is red](https://www.nasa.gov/solar-system/nasa-new-study-on-why-mars-is-red-supports-potentially-habitable-past/)
- [USGS morphology of the Martian surface](https://www.usgs.gov/publications/morphology-martian-surface)
- [USGS MOLA topographic map of Mars](https://pubs.usgs.gov/imap/i2782/)
