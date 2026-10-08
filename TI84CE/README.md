# TI-84 Plus CE Emulator for iPad & iPhone

A native SwiftUI app that emulates the **TI-84 Plus CE** hardware (Zilog eZ80 CPU,
memory, flash, LCD, keypad, timers, interrupts…) so that the calculator's own
operating system, loaded from **your ROM dump**, runs unmodified. Nothing about the
calculator's behaviour (math, graphing, programs, menus) is implemented in Swift;
it all comes from the ROM.

Verified with boot code 5.1.5.0014 and OS 5.3.0.0037: the ROM boots to the home
screen, evaluates expressions, graphs functions, and keeps its memory across launches.

> **ROM images are copyrighted by Texas Instruments.** Use a dump of a calculator
> you own. The repository ignores `*.rom` files, so a ROM is never committed.

## Running it on an iPad (Swift Playgrounds)

1. On the iPad, open this repository on GitHub in Safari → **Code → Download ZIP**.
2. In the **Files** app, tap the ZIP to extract it. Inside `TI84CE/` you will find
   **`TI84CE.swiftpm`**.
3. Tap `TI84CE.swiftpm` (or open it from Swift Playgrounds → *Locations*). It opens
   as an app project.
4. Press **Run** (▶). The first time, the app asks for your ROM: tap
   **Import ROM…** and pick your `.rom` file in Files. The app keeps a private copy.
   *Alternatively* add the ROM to the project's `Resources` folder; any `*.rom`
   there is used automatically.
5. The calculator starts. Tap keys as on the real device.

The same package opens in Xcode on a Mac (File → Open → `TI84CE.swiftpm`).

### Using the app

* **Keys**: touch-down presses, lift releases, so holding works, arrows auto-repeat
  and several keys can be held at once (the ROM sees true key chords).
  Apple Pencil works like a finger; hovering highlights keys.
* **Hardware keyboard**: digits and operators, Return = enter, Delete = del,
  Esc = clear, Tab = 2nd, Option = alpha, arrows, F1–F5 = graph row, F6 = on…
  (full list in Settings).
* **Memory persists automatically**: RAM, archive and the complete machine state are
  saved whenever the app leaves the foreground and restored at launch, so the
  calculator resumes exactly where it was. Settings has three extra snapshot slots
  (Save RAM / Load RAM), *Reset RAM*, and *Erase archive and RAM*.
* **Settings**: speed (50 %…unlimited), haptics, LCD pixel grid, battery level.
* **Debugger** (Settings → Developer): registers, flags, current opcode,
  disassembly, stack, memory and I/O viewers, interrupt / LCD / keypad / timer state,
  Run / Pause / Step / Reset and address breakpoints. On iPad it docks beside the
  calculator.

### Performance note

Swift Playgrounds builds apps without compiler optimisation. The core is written to
stay fast in that mode (raw-pointer hot paths, no per-instruction allocation, no
redundant LCD work) and runs faster than the real calculator even unoptimised on a
cloud CPU; optimised builds (Xcode *Release*) run roughly 10–15× real time.

## Web app (any browser, including iPhone Safari)

`Web/` is the same emulator ported to plain JavaScript (no build step, no
dependencies). It runs the same hardware model, cycle for cycle: the JS and Swift
cores produce identical RAM, flash and screen contents for the same input.

- **Open it**: serve the `Web/` folder over HTTPS (GitHub Pages, Netlify, or
  `python3 -m http.server` for local testing) and open `index.html`. Choose your
  ROM file once; it stays in that browser's storage (IndexedDB) and is never uploaded.
- **iPhone/iPad**: in Safari, tap Share → **Add to Home Screen**. It then opens
  full screen like an app and works offline (a service worker caches the app files).
- **Memory**: RAM, archive and the full machine state are saved automatically
  (when you leave the page, after typing, and every 20 s) and restored on the next
  visit. Settings → Memory has three extra snapshot slots.
- **Keys**: tap the keypad, or use a hardware keyboard (shortcuts are listed in
  Settings). Tapping Shift or Alt alone presses 2nd or alpha.
- The emulator runs in a Web Worker, so the page stays responsive.

```
Web/
├── index.html, style.css, app.js   page, keypad, menus
├── runner.js, worker.js            real-time loop (in a Web Worker), autosave
├── storage.js                      IndexedDB key-value store
├── core/                           cpu, memory, devices, lcd, scheduler, emulator
├── sw.js, manifest.webmanifest     offline support and home-screen install
└── tools/                          headless.mjs (like ce-headless), selftest.mjs,
                                    build-artifact.mjs
```

```sh
node Web/tools/selftest.mjs                                    # ROM-free checks
node Web/tools/headless.mjs --rom ti84ce.rom --seconds 12 \
    --keys "9.0:clear,10.0:k2,10.5:add,11.0:k3,11.5:enter" --hash --screenshot out.ppm
```

## What is emulated

The ROM file turned out to be a **TI-84 Plus CE**, not the monochrome Z80-based
TI-84 Plus, so the emulator targets that hardware:

| Component | Implementation |
|---|---|
| CPU | eZ80: Z80 and ADL (24-bit) modes, `.SIS/.LIS/.SIL/.LIL` suffixes, MBASE, SPS/SPL, mixed-mode CALL/RET/RST, IM 0/1/2, NMI, HALT/SLP, all eZ80 additions (LEA, PEA, MLT, TST, TSTIO, IN0/OUT0, LD rr,(HL), block I/O `INIM`/`OTIMR`/`INI2`/`OTIRX`…). Unknown opcodes are reported (`Unsupported opcode: 0xED 0x77 / PC: 0x…`). |
| Memory map | 4 MiB flash at 000000, 406 KiB RAM+VRAM at D00000 (mirrored), memory-mapped I/O at E00000–E3FFFF / F00000–FAFFFF, configurable in `MemoryMapper`. |
| Flash | AMD/JEDEC command set (program, sector/chip erase, autoselect, CFI, status polling); the OS writes its archive through it. The ROM file itself is never modified. |
| LCD | PL111 controller (all bpp modes, palette, BGR, interrupts, timing) streaming into an ST7789 panel model (9-bit SPI command stream, MADCTL, window, sleep/on/invert). |
| Keypad | Keypad controller with idle / any-key / single / continuous scan modes and row timing, driven by an 8×8 key matrix; ON key on its own interrupt line. |
| Timers | 3 general-purpose timers (CPU or 32 kHz clock, match/overflow), OS tick timer, RTC, watchdog. |
| Other | Interrupt controller (latch/invert/mask), control ports (CPU speed, battery comparator), SPI, SHA-256 accelerator, USB/link port (idle, no cable), backlight. |
| Timing | Deterministic scheduler on a 1.536 GHz base clock (exact for 6/12/24/48 MHz and 32768 Hz); wait states per memory region. |

## Project layout

```
TI84CE/
├── TI84CE.swiftpm/            ← the app (Swift Playgrounds / Xcode)
│   ├── Package.swift
│   ├── App/                   SwiftUI app, EmulatorController (UI ↔ emulator bridge)
│   ├── EmulatorCore/          platform-independent emulator (Foundation only)
│   │   ├── CPU/               CPU, Registers, Instructions, Disassembler
│   │   ├── Memory/            MemoryBus, MemoryMapper, ROM, RAM, Flash
│   │   ├── Hardware/          LCD+panel+SPI, Keyboard, Timer, RTC, Interrupts, …
│   │   ├── Scheduler.swift    timing
│   │   ├── Emulator.swift     wires the machine together
│   │   ├── EmulatorState.swift save states
│   │   ├── EmulatorRunner.swift emulation thread
│   │   └── DebugSnapshot.swift debugger data
│   ├── Platform/              ROM library, persistent storage (Foundation only)
│   ├── UI/                    calculator, LCD renderer, keypad, settings, debugger
│   └── Resources/             optional: put your *.rom here
├── Package.swift              dev package: builds + tests the core on macOS/Linux
├── Tests/EmulatorCoreTests/   CPU, memory, hardware, platform and ROM boot tests
└── Tools/                     ce-headless (run / trace / screenshot), ce-dis
```

The emulator core never imports SwiftUI or UIKit.

## Developing on a Mac or Linux

```sh
cd TI84CE
swift test                                   # 74 tests; ROM tests need a ROM:
TI84CE_ROM=/path/to/ti84ce.rom swift test    # (or put it in TI84CE.swiftpm/Resources)
swift run -c release ce-headless --rom /path/to/ti84ce.rom --seconds 12 \
    --keys "9.0:clear,10.0:k2,10.5:add,11.0:k3,11.5:enter" --screenshot out.ppm
```

`ce-headless` also supports `--trace N`, `--hotspots`, `--io`, `--break ADDR`,
`--stop-nops`, `--dis ADDR:N`, `--dump ADDR:N`, `--panel`, `--save-state` and
`--state` for debugging.
