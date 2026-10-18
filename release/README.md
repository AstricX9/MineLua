# MineLua

MineLua is a standalone voxel sandbox for Windows x64, powered by LuaJIT and
OpenGL.

## Start

Double-click `MineLua.exe`. Saves are stored in the `saves` folder beside the
game, so keep the extracted folder somewhere writable.

Requirements:

- Windows 10 or Windows 11, 64-bit
- A GPU and driver supporting OpenGL 4.6
- Approximately 1 GB free memory for normal play

This is a portable build: no installation or separate runtime is required.
Extract the complete ZIP before launching. The executable is currently
unsigned, so Windows SmartScreen may ask for confirmation on first run.

Command-line smoke/test options remain available, for example:

```text
MineLua.exe --world 1 --time 10
```

See `RELEASE_NOTES.md` for highlights and `THIRD_PARTY_NOTICES.md` for bundled
component notices.
