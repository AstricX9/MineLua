# Release obfuscation

A release package ships no readable Lua source and no loose assets. Every
module is stripped LuaJIT bytecode, and every texture, sound, model, shader,
blockstate and JSON definition lives inside one encrypted container that the
game mounts at startup.

```text
MineLua-1.0.0-windows-x64/
  MineLua.exe                 launcher, unchanged
  lib/minelua.pak             the container: ~115 MiB, 4 400+ entries
  lib/*.dll, luajit.exe       runtime, unchanged
  src/main.lua                7 KB bytecode stub
  src/chunk_worker.lua        7 KB bytecode stub
  data/config/settings.json   deliberately left loose and editable
  README.md, SHA256SUMS.txt, BUILD_MANIFEST.json, ...
```

## What this is worth

The key travels inside the bytecode stub, because the game has to open its own
data with nothing to ask. Anyone willing to read that bytecode recovers the key
and can run `unpack.lua` exactly the way the build does.

So this raises the cost of ripping the game's art and reading its source from
"open the folder" to "reverse engineer the loader", and that is the entire
claim. It is not DRM, and no client-side container can be. Treat it as the lock
on a garden shed: it stops the casual passer-by, and it is not what keeps a
determined one out.

What it does defeat, which is most of what actually happens in practice:
archive browsers, `strings`, thumbnail extractors, texture rippers pointed at a
folder of PNGs, and anyone who would have opened `src/game.lua` in Notepad.

## Building

```powershell
.\build_release.ps1 -Version 1.0.0
```

The packer runs as part of the build and the build refuses to finish if
anything readable reached the package: a `.lua` file that is not bytecode, a
surviving `assets/` directory, or a stray `.png`/`.wav`/`.json` in the archive
all fail the build.

Each build generates a fresh random key and salt. They are written to
`build/public/<package>.container-key.txt`, **beside** the archive rather than
inside it. Keep that file if you may need to open the shipped container later;
it is the only copy.

To reproduce a package byte for byte, or to build one whose container you can
open later without keeping the sidecar, pass a fixed key to the packer:

```powershell
lib\luajit.exe scripts\obfuscate\pack.lua --root . --out build\public\MineLua --key deadbeefcafebabe0123456789abcdef
```

## Debugging a packed build

- `.\build_release.ps1 -PlainAssets` builds the old way: loose assets, readable
  source, no container. Bisect against it when a packaged build misbehaves.
- **Loose files win.** The container only answers where the working tree has
  nothing, so dropping `assets/textures/blocks/dirt.png` next to `MineLua.exe`
  overrides the packed copy without rebuilding. This is also what lets players
  replace a texture.
- `scripts/obfuscate/unpack.lua --pack lib\minelua.pak --key <hex> --list`
  lists the container; `--out <dir>` extracts it. Extracted modules come out as
  bytecode, since the container never held source.
- `tests/test_pack_vfs.lua` packs a miniature project, mounts it, and asserts
  the round trip plus the absence of plaintext. Run it after touching anything
  in this document's blast radius.

## How it works

**Packing** (`scripts/obfuscate/pack.lua`). Compiles every `src/**/*.lua` with
`string.dump(chunk, true)` -- the same output `luajit -b -s` writes, with no
line table, local names or upvalue names -- then writes those and every file
under `assets/` and `data/` into the container. A compile error fails the
build, so the packer doubles as a syntax check over the whole tree. After
writing, it mounts what it produced and compares every entry against its
source before the build is allowed to continue.

**The container** (`src/vfs.lua` documents the byte layout). A 24 byte header,
an encrypted index, and a payload region. Both the index and every entry are
XOR-streamed with an xorshift128 keystream seeded from the key, a per-build
salt, and a per-entry nonce. The nonce is the entry's own offset: guessing one
entry's plaintext -- a PNG header, say -- reveals nothing about its neighbours.
Nothing readable survives, including the paths, which live in the encrypted
index rather than in the clear.

**Booting.** The launcher still runs `src\main.lua`, but that file is now a
bytecode stub holding an inlined copy of `vfs.lua` and the key, split across
two tables that are xored back together at runtime. It mounts the container,
installs the shims, and calls `require("main")`, which comes out of the
container. `src\chunk_worker.lua` gets the same stub because the chunk pipeline
spawns it as a separate process.

**Reading.** `vfs.install()` replaces `io.open` for read modes and adds a
`package.loaders` entry ahead of the file searcher. Three call sites needed
more than that:

| Call site | Why |
| --- | --- |
| `src/texture.lua` | `stbi_load` only takes a real path, so packed PNGs decode through `stbi_load_from_memory` |
| `src/blocks.lua` | block tint sampling now goes through `texture.loadPng` instead of calling stb itself |
| `src/filesystem.lua` | directory walks merge the container's index, since `assets/` does not exist on disk |

In a source checkout nothing is ever mounted: every one of those paths answers
nil or false and the game reads loose files exactly as before.

## Working on this later

- **New asset roots** must be added to `DEFAULTS.assetRoots` in `pack.lua`, or
  they will not ship at all.
- **Anything the game writes** must stay outside the container. Write modes go
  straight to the real `io.open`; the packer leaves `data/config` loose and
  creates empty `data/cache` and `saves` directories for the runtime.
- **New process entry points** need their own stub in `DEFAULTS.entries`.
  Anything a `CreateProcess` call names has to exist on disk.
- **Reading a file from C** bypasses every shim. Route new file access through
  `io.open`, `filesystem`, or `texture`.
- **String constants survive `string.dump`** -- the interpreter needs them, so
  texture paths and error messages are still legible in a disassembly. Renaming
  identifiers or encrypting literals would need a source-level pass, which is
  considerably more fragile than what is here.
