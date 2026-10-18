"""Build the small PCM sound bank consumed by MineLua's Lua mixer.

The source pack is Ogg Vorbis, while the runtime intentionally depends only on
WinMM.  Keeping conversion as a build-time step gives the game real samples
without shipping an additional decoder DLL.
"""

from pathlib import Path

import soundfile as sf


ROOT = Path(__file__).resolve().parents[1]
SOUNDS = ROOT / "assets" / "sounds"
OUTPUT = SOUNDS / "runtime"
MATERIALS = ("stone", "wood", "grass", "gravel", "sand", "snow", "cloth")


def convert(source: Path, destination: Path) -> None:
    audio, sample_rate = sf.read(source, dtype="float32", always_2d=True)
    mono = audio.mean(axis=1)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sf.write(destination, mono, sample_rate, subtype="PCM_16", format="WAV")


def main() -> None:
    jobs: list[tuple[Path, Path]] = []
    for material in MATERIALS:
        for variant in range(1, 5):
            jobs.append((
                SOUNDS / "dig" / f"{material}{variant}.ogg",
                OUTPUT / f"break_{material}_{variant}.wav",
            ))
            jobs.append((
                SOUNDS / "step" / f"{material}{variant}.ogg",
                OUTPUT / f"step_{material}_{variant}.wav",
            ))
    for variant in range(1, 4):
        jobs.append((
            SOUNDS / "random" / f"glass{variant}.ogg",
            OUTPUT / f"break_glass_{variant}.wav",
        ))
    for source, destination in jobs:
        if not source.is_file():
            raise FileNotFoundError(source)
        convert(source, destination)
    print(f"Wrote {len(jobs)} sounds to {OUTPUT}")


if __name__ == "__main__":
    main()
