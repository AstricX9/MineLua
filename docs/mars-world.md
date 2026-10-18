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

The same atmosphere is audible as well as visible. 0.6 kPa of cold CO2 radiates
far less than sea-level air, so Mars is markedly quieter; its vibrational
relaxation swallows everything above a few hundred hertz within metres, so
anything at a distance arrives late and dulled to a thud; and its caves barely
ring. Its slower air favours the low end of every block it does carry. Walking
is quieter again, because a third of Earth's gravity puts a third of the weight
into each footfall — though the player still hears their own steps and tool
swings through their body, which no atmosphere can take away. None of that is
authored for Mars specifically: it is derived from the atmosphere and gravity
already in the world profile. See [World acoustics](world-acoustics.md).

Scientific references:

- [NASA Mars facts](https://science.nasa.gov/mars/facts/)
- [NASA: what sunrises and sunsets look like on Mars](https://science.nasa.gov/solar-system/planets/mars/what-does-a-sunrise-sunset-look-like-on-mars/)
- [NASA: why Mars is red](https://www.nasa.gov/solar-system/nasa-new-study-on-why-mars-is-red-supports-potentially-habitable-past/)
- [USGS morphology of the Martian surface](https://www.usgs.gov/publications/morphology-martian-surface)
- [USGS MOLA topographic map of Mars](https://pubs.usgs.gov/imap/i2782/)
- [Maurice et al., in situ recording of the Mars soundscape](https://www.nature.com/articles/s41586-022-04679-0)
