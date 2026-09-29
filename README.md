# TI-84 Plus Emulator for iOS and iPadOS

A native Swift emulator for the Z80-based **TI-84 Plus** family. It emulates the
calculator's hardware (CPU, memory controller, Flash chip, LCD driver, key
matrix, timers, interrupts, link port) and boots the **ROM you supply**. All
calculator behaviour (math, graphing, programs, menus) comes from TI-OS running
inside the emulator. The app itself implements none of it.

**Verified with a real TI-84 Plus ROM running TI-OS 2.55MP.** The boot code
unlocks Flash through the privileged sequence, validates the OS and hands over.
TI-OS then clears RAM and waits for ON. After that it evaluates expressions
(`2+3*4` → 14, `√(2)` → 1.414213562), opens the STAT/APPS/Y= menus and graphs
functions. All of this is the ROM's own code running on the emulated hardware.

> The repository does not include a ROM. TI's ROM images are copyrighted; use a
> dump of a calculator you own.

## Supported ROMs

| Image size | Model | Status |
|---|---|---|
| 1 MB (`0x100000`) | TI-84 Plus | Supported (auto-detected) |
| 2 MB (`0x200000`) | TI-84 Plus Silver Edition | Supported (default for 2 MB) |
| 2 MB | TI-83 Plus Silver Edition | Supported (pass `model: .ti83PlusSE`) |
| 512 KB | TI-83 Plus | Rejected: different ASIC |
| 4 MB | TI-84 Plus CE / 83 Premium CE | Rejected: eZ80 CPU, different hardware |

The loader checks the size and makes sure the boot page is present. It warns
when no OS is installed and computes SHA-256 and CRC-32 checksums for debugging.

## Adding the ROM

Copy your dump to:

```
Sources/TI84EmulatorCore/Resources/ti84rom.rom
```

It ships as a Swift Package resource and is loaded at runtime with
`Bundle.module.url(forResource: "ti84rom", withExtension: "rom")`. It is never
compiled into Swift source. `.gitignore` excludes `*.rom` so the image doesn't
get committed by accident.

Other ways to supply a ROM:
- **At runtime:** if the app bundle has no ROM, the app shows an **Import ROM…** button (Files picker). The imported file is copied to Application Support.
- **Environment variable:** `TI84_ROM_PATH=/path/to/rom` overrides the bundled resource (useful for tests and the CLI).
- **In code:** `ROMLoader.load(.file(url))` or `ROMLoader.load(.data(data))`.

## Running on an iPad without a Mac (Swift Playgrounds)

`Playground/TI84Emulator.swiftpm` is a ready-made **Swift Playgrounds** app
project containing the same emulator and UI.

1. Install **Swift Playgrounds** from the App Store on your iPad.
2. Download this branch as a ZIP (GitHub ▸ Code ▸ Download ZIP), open it in
   the Files app to unzip, and tap `Playground/TI84Emulator.swiftpm`. It opens
   in Swift Playgrounds.
3. Tap ▶︎ Run. The first time, tap **Import ROM…** and pick your ROM file
   from Files. It is saved inside the app, so you only do this once.
4. Press **ON**. After a reset TI-OS stays off until ON is pressed, just like
   the real calculator after new batteries.

The playground is generated from `Sources/` by `Scripts/make-playground.sh`
(Swift Playgrounds needs a single module). Re-run the script after changing
the package sources.

## Building and running the app with Xcode

The emulator is a Swift package with three products:

| Product | Contents |
|---|---|
| `TI84EmulatorCore` | Hardware emulation. Foundation only, no SwiftUI. Builds on Linux. |
| `TI84EmulatorUI` | SwiftUI calculator, LCD renderer, keypad, settings, debugger |
| `ti84-cli` | Headless developer tool |

A SwiftPM package cannot produce an iOS `.app` by itself. The thin app shell in
`App/` pulls in the package:

```sh
brew install xcodegen
cd App && xcodegen          # creates TI84Emulator.xcodeproj
open TI84Emulator.xcodeproj
```

Or set it up by hand: create a new iOS App project in Xcode, add this folder as
a local package (File ▸ Add Package Dependencies ▸ Add Local…), link
`TI84EmulatorUI`, and use `App/TI84EmulatorApp.swift` as the app entry point.

The generated scheme **runs in the Release configuration** because the CPU
core needs optimisation. A release build runs roughly 10× faster than real
time; an unoptimised debug build barely keeps up.

## Architecture

```
TI84EmulatorCore (no UI imports)
├── CPU/           Z80 core: Registers, CPU (step/run/interrupts), Instructions
│                  (all prefixes), ALU (exact flags incl. X/Y + MEMPTR),
│                  Disassembler, CPMHarness (ZEXDOC/ZEXALL runner)
├── Memory/        MemoryBus (4 × 16 KB banks, direct-pointer fast path),
│                  RAM, Flash (AMD command set), MemoryMapper (ports 04–07,
│                  0E/0F, 27/28, certificate protection, privileged unlock
│                  detection), ROM (loader, validation, checksums),
│                  HardwareProfile (per-model constants)
├── IO/            IOBus (port → device routing, access trace)
├── Hardware/      ASIC (system ports 02–04, 14–2F, MD5, RTC, USB stubs),
│                  InterruptController, Timer (hardware + crystal timers),
│                  LCD (T6A04 controller + frame builder), LCDRenderer,
│                  Keyboard (key matrix), LinkPort
├── Timing/        EmulatorClock (30 MHz master timebase across 6/15 MHz),
│                  Scheduler (deterministic hardware events)
├── Emulator.swift          wires everything together; run/step/keys
├── EmulatorState.swift     complete save states (binary plist)
├── EmulatorRunner.swift    dedicated emulation thread, real-time pacing
├── PersistentStorage.swift Application Support files (autosave, RAM, Flash)
└── Debugger.swift          breakpoints, history, snapshots

TI84EmulatorUI (SwiftUI + UIKit)
├── CalculatorView   root view, ROM import, portrait/landscape/iPad layouts
├── LCDView          one CGImage per changed frame, nearest-neighbour scaled
├── KeyboardView / KeyView / KeyLayout   TI-84 Plus keypad with 2ND/ALPHA legends
├── HardwareKeyboard physical keyboard → key matrix (press + release)
├── SettingsView     speed, LCD response, memory save/load/reset, ROM info
└── DebuggerView     registers, disassembly, breakpoints, memory, ports, interrupts
```

### Data flow

```
Touch / hardware key ──▶ KeypadSink ──▶ EmulatorRunner queue ──▶ KeyboardMatrix (port 01h)
                                                                     │
                     emulation thread: CPU ⇄ MemoryBus / IOBus ◀─────┘  ROM scans the matrix
                                        │
                     Scheduler: timers, crystal timers, 60 Hz LCD sampling
                                        │
                        LCDFrame (only when changed) ──▶ main thread ──▶ LCDView
```

- **Key presses** only change the emulated key matrix. When you press 2ND, the
  ROM's keyboard scan sees the matrix bit and the OS decides what happens.
  A quick tap is held for at least 60 ms of emulated time so the OS's scan
  can't miss it.
- **Timing:** the CPU counts T-states. Hardware events (timer interrupts at
  about 108 Hz by default, crystal timers, LCD refresh) are scheduled
  deterministically on a master clock that stays correct across 6 MHz and
  15 MHz switches. The runner paces emulated time to wall-clock time
  (1×, 2×, 4×, or unlimited). While the CPU is halted with nothing pending,
  time jumps ahead instead of spinning, so an idle calculator uses almost
  no power.
- **Persistence:** the full machine state is autosaved to
  `Application Support/TI84Emulator/<rom-hash>/` when the app goes to the
  background (and every 30 s), then restored on launch. Save/Load RAM, Reset
  RAM, Erase Archive and save-state slots are in Settings. Archived variables
  live in the emulated Flash, which is persisted separately from the ROM
  image; the ROM resource itself is never modified.

## Hardware fidelity notes

Emulated as the hardware does it:
- Z80: every documented and undocumented opcode, the undocumented X/Y flags and
  MEMPTR, IM 0/1/2, NMI, the one-instruction interrupt delay after EI, HALT,
  the R register and cycle-exact instruction timings. The core **passes ZEXDOC
  and ZEXALL** (all 67 tests).
- Reset starts in the boot page at 8000h in memory mode 1, as on real hardware.
  The certificate page reads back FFh until Flash is unlocked.
- Port 14h (Flash unlock) only accepts writes from the privileged
  `nop/nop/im 1/di/out (14h),a` sequence executed from protected Flash pages.
- Flash program and erase follow the chip's command state machine. Programming
  can only clear bits, protected sectors are enforced, and status polling works.
- T6A04: 8-bit and 6-bit modes, all four auto-increment directions, Z-address
  scrolling, contrast, display on/off, and the dummy-read latch.
- Key matrix with ghosting. The ON key is wired to the interrupt controller.
- Hardware timers at the four 84+ rates, the three crystal timers, the MD5
  accelerator and the real-time clock (which advances while the app is closed).

Simplified or not yet emulated:
- USB is inert: the ports report "no cable", which is what the OS sees with
  nothing plugged in.
- The link port models line levels and has a `LinkPeer` hook, but no
  file-transfer protocol yet.
- Flash/RAM wait states at 15 MHz aren't modelled (LCD port delays are).
- Execution-protection limits (ports 22h–26h) are stored but not enforced.
- LCD busy timing is reported. Accesses made while busy are only dropped when
  `EmulatorConfiguration.enforceLCDBusyTiming` is set.

## Testing

```sh
swift test                                        # 81 tests, about 15 s
TI84_ROM_PATH=/path/ti84.rom swift test           # also boots your ROM
```

- `CPUTests`: instructions, flags, stack, calls and branches, prefixes (CB, ED,
  DD, FD, DDCB), block ops, I/O, IM 1/IM 2/NMI, EI delay, HALT, cycle counts,
  R register, undefined-opcode reporting, disassembler.
- `MemoryTests`: bus reads and writes, ROM validation and checksums, ROM
  immutability, bank switching (modes 0 and 1), RAM pages, ports 27h/28h,
  Flash protection, program and erase, privileged unlock (allowed and denied).
- `HardwareTests`: LCD commands and modes, dummy reads, row shift, frames, key
  matrix and ghosting, key presses reaching ROM code, ON interrupt, timer rates
  at 6 and 15 MHz, interrupt mask and acknowledge, crystal timers, MD5, RTC, link
  lines, deterministic execution, exact save-state resume, persistence,
  breakpoints, the threaded runner, and the LCD renderer.
- `ROMBootTests`: boots a synthetic ROM (hand-assembled Z80 in the test target)
  through the real reset path. With the real ROM (bundled or `TI84_ROM_PATH`)
  it boots TI-OS, checks the privileged Flash unlock, IM 1 and interrupts,
  presses ON, types `2+3*4 ENTER`, and checks the pixels of the "14" that
  TI-OS draws. The screen is printed as ASCII art.

The CPU can also be checked against the classic exercisers (not included):

```sh
swift build -c release
.build/release/ti84-cli zex zexall.com
```

## Command-line tool

```sh
swift run -c release ti84-cli info  --rom ti84.rom
swift run -c release ti84-cli boot  --rom ti84.rom --seconds 3 --keys on,clear,two,add,three,enter --ppm screen.ppm
swift run -c release ti84-cli boot  --keys on,clear,yEquals,wait1,xtThetaN,square,subtract,four,graph,wait3
swift run -c release ti84-cli bench --rom ti84.rom
```

`boot` prints the LCD as text plus a register dump. Key names are the `Key`
enum cases (`two`, `add`, `enter`, `second`, `alpha`, `yEquals`, …), and
`wait<seconds>` pauses between keys. After a reset the calculator is off,
so start with `on`. TI-OS drops keys tapped while it is still drawing a
screen (the Y= editor takes about half a second), just as the real calculator
does.

## Debugger

Turn on **Settings ▸ Developer debugger**. On iPhone it opens as a sheet; on a
wide iPad it appears as a side panel. It shows PC/SP/AF/BC/DE/HL/IX/IY (and the
shadow set), the flags, the current opcode and a disassembly, the stack, a
memory view, recent port values, the memory map, pending interrupts, and LCD
and keypad state. Controls are Run, Pause, Step and Reset. Tap a disassembly
line or type an address to set a breakpoint.
