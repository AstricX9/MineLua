# World acoustics

Every world filters its own sound. The filter chain is not authored per planet:
it is derived from the three numbers a world profile already declares about its
air — `surfacePressurePa`, `surfaceTemperatureK` and `composition`. Register a
world with an atmosphere and it gets a soundscape to match, for free.

`src/audio_atmosphere.lua` turns those numbers into a mixer-facing profile, and
`src/audio_engine.lua` applies it. Earth is the calibration point of the model,
so it comes out neutral by construction.

## What the air decides

| Property | Derived from | Heard as |
| --- | --- | --- |
| Loudness | acoustic impedance, density x speed of sound | how much a struck block can radiate into the air at all |
| Radiation tilt | speed of sound | how well a block-sized face radiates its low end |
| Footfall energy | surface gravity | how hard the player lands on the ground |
| Conduction floor | nothing — it bypasses the air | your own steps and swings, heard through your body |
| Tone | viscous drag plus molecular relaxation | a one-pole low-pass per voice, at the corner its own travel distance earned |
| Delay | speed of sound | distant events arrive late |
| Reverb | impedance | how much energy a cave can keep ringing |

The first four are the source: what the block and the boot do. The rest is the
trip from there to the listener.

A source only couples fully into the air above `ka = 1`, so it has a radiation
corner at `c / 2*pi*a` — with `a` about a block face — and that corner moves with
the world's speed of sound. Below it, radiated power follows density over speed
instead of density times speed. Expressed against Earth this is a low shelf: on
Mars, whose air is slow, a low-pitched block keeps noticeably more of its level
than a high-pitched one. A 185 Hz wood break survives at 0.44 of its terrestrial
level where a 2.3 kHz glass break survives at 0.27.

Footsteps carry the player's weight into the ground, so their energy scales with
surface gravity — a Martian footfall starts at 0.59 before any of the air is
taken into account. But a player hears their own steps and tool swings through
their legs, arms and helmet as well as through the air, and that path does not
care how thin the atmosphere is. It acts as a floor under contact sounds,
graded by how much of an event actually travels through the body: all of a
footfall, most of a swing that lands, little of the block coming apart
afterwards. On Earth the airborne path wins outright and the floor never
applies, so Earth is unchanged.

Absorption per metre is the classical viscous term, which rises with the square
of frequency, plus one relaxation term per species, which rises with the square
of frequency and then saturates above that species' relaxation frequency — the
shape used by ISO 9613-1. The per-gas constants are calibrated so dry Earth air
lands near the measured 0.005 dB/m at 1 kHz.

Loudness and reverb are the one deliberate departure from physics. A literal
impedance ratio drops Mars about 20 dB and puts anything thinner below the noise
floor, which is accurate and unplayable, so amplitude ratios are compressed by
the `PRESENCE` exponent. The ordering and the character survive; the levels stay
usable.

## Earth and Mars

| | Earth | Mars |
| --- | --- | --- |
| Air | 101.3 kPa N2/O2 at 288 K | 0.61 kPa CO2 at 210 K |
| Density | 1.225 kg/m^3 | 0.0152 kg/m^3 |
| Speed of sound | 341 m/s | 228 m/s |
| Absorption at 1 kHz | 0.006 dB/m | 1.0 dB/m |
| Voice gain | 1.00 | 0.27 |
| Reverb | 1.00 | 0.17 |
| Radiation shelf | flat | +7 dB below 177 Hz |
| Footfall energy | 1.00 | 0.59 |
| Tone corner at 1 m | open | 15.4 kHz |
| Tone corner at 16 m | open | 136 Hz |

Measured through the mixer, against the same event on Earth: a footstep on
Martian sand lands at 0.21, on gravel at 0.33; a pick landing on stone at 0.37;
the block breaking three metres away at 0.35, and sixteen metres away at 0.13
and audibly dulled.

Earth behaves exactly as it always did: a block break sounds the same whether it
is at your feet or sixteen metres away, only quieter. Mars is a different world
to stand in. A break at arm's length is recognisably the same sound at about a
quarter the level; the same break across a crater arrives late, dulled to a
thud, because CO2 vibrational relaxation has eaten everything above a few
hundred hertz on the way. Its caves barely ring. Idle worlds are silent until
an authored ambience system is added.

That 240 Hz knee is real, and it is why Mars sounds the way it does:
[Maurice et al., "In situ recording of Mars soundscape", Nature (2022)](https://www.nature.com/articles/s41586-022-04679-0).

## Adding a world

Declare the atmosphere in `src/world_profiles.lua`; nothing in the audio engine
needs to change:

```lua
atmosphere = {
  surfacePressurePa = 146000.0,
  surfaceTemperatureK = 94.0,
  composition = {nitrogen = 0.95, methane = 0.05}
}
```

Gases the model knows are listed in `GAS` in `src/audio_atmosphere.lua`. An
unlisted gas is ignored and the remaining fractions are renormalised; a world
that declares no atmosphere at all inherits Earth's air. `gravityScale` from the
same profile carries the footfall energy.

Which block sounds like what is separate from all of this: `soundMaterial` in
`src/audio_engine.lua` derives a footstep and break bank from the block key, so
a world sounds like whatever it is built out of. A world with genuinely novel
surfaces can override that per block with `properties.soundMaterial`.

## Not modelled

Air also damps a vibrating block, so in principle a struck surface rings longer
in thin air. For dense blocks in any atmosphere, internal damping dominates
radiation damping by orders of magnitude, so this would be an invented effect
rather than a derived one. It is left out.
