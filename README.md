# auv3-midi-template

A clean, **dependency-free** starting point for an **Audio Unit v3 (AUv3) MIDI
plugin** that runs on **iOS/iPadOS and macOS**. The included example is a working
**MIDI arpeggiator**: feed it a held chord and it generates an arpeggiated MIDI
stream synced to the host tempo.

It uses only Apple frameworks (AudioToolbox, CoreAudioKit, SwiftUI) — no JUCE, no
third-party runtime libraries. The realtime engine is plain C++; the UI is
SwiftUI; the two are bridged with a thin Objective-C++ `AUAudioUnit` subclass.

---

## Project layout

```
Shared/                         # Code shared by the iOS & macOS AU extensions
  Kernel/
    ArpParameters.h             # Parameter + enum definitions (single source of truth)
    ArpKernel.hpp               # Realtime-safe C++ arpeggiator engine
  AudioUnit/
    ArpAudioUnit.h / .mm        # AUAudioUnit subclass (Obj-C++) — owns the kernel
    ArpAudioUnitViewController.swift  # Principal class: AUViewController + factory
    ArpView.swift               # Cross-platform SwiftUI parameter UI
    Arp-Bridging-Header.h       # Exposes the Obj-C++ AU to Swift
iOS/
  App/                          # Minimal SwiftUI host app + Info.plist
  Extension/                    # AU extension Info.plist (AudioComponents)
macOS/
  App/                          # Minimal SwiftUI host app + Info.plist
  Extension/                    # AU extension Info.plist (AudioComponents)
project.yml                     # XcodeGen project definition (generates the .xcodeproj)
Makefile                        # Convenience: project / build / validate
```

Each platform has a **host app** with an **embedded AU app-extension**. The host
app exists mainly to register the extension with the system; the plugin itself
lives in the extension.

---

## Building

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (a build-time tool only — it adds
nothing to the shipped plugin). This keeps the repo free of an unreadable,
merge-hostile `.pbxproj`.

```bash
brew install xcodegen      # one-time
make open                  # generates ArpMIDI.xcodeproj and opens it in Xcode
```

or manually:

```bash
xcodegen generate
open ArpMIDI.xcodeproj
```

Then in Xcode pick a scheme:

- **Arp-iOS** → run on a device/simulator to install the iOS extension.
- **Arp-macOS** → run to register the macOS extension.

> Set your Apple Developer **Team** (Signing & Capabilities, or
> `DEVELOPMENT_TEAM` in `project.yml`) to run on a physical iOS device.

### Don't want XcodeGen?

Create a new Xcode **"Audio Unit Extension"** target (App + Extension) and drop
the files under `Shared/` into the extension target, the `*/App/` files into the
app target, and point each Info.plist build setting at the plists here. The
source files — not the project file — are the durable part of this template.

---

## Validating it works

On **macOS**, after building the macOS app once:

```bash
pluginkit -mAv | grep -i arp     # confirm the extension is registered
make validate                    # == auval -v aumi arp1 Hase
```

`auval` runs Apple's official Audio Unit test suite against the component.

On **iOS**, run the host app on a device, then open an AUv3 host (AUM, Cubasis,
Drambo, GarageBand…), add **Arp** as a **MIDI effect**, route a keyboard into it
and its MIDI output into an instrument. Hold a chord — you should hear it
arpeggiate, following the host tempo.

---

## How it works

- **Component type `aumi`** (`kAudioUnitType_MIDIProcessor`) is declared in each
  extension's `Info.plist` under `NSExtension → NSExtensionAttributes →
  AudioComponents`. This marks the plugin as a MIDI-only processor.
- **MIDI in** arrives in `internalRenderBlock` (`ArpAudioUnit.mm`) as an
  `AURenderEvent` linked list; events with `eventType == AURenderEventMIDI` are
  forwarded into the C++ kernel at their per-sample offset.
- **MIDI out** is emitted through the host's cached **`MIDIOutputEventBlock`**.
  The unit advertises **`MIDIOutputNames`** (`"Arp Out"`) so hosts expose its
  output port.
- **Tempo sync**: the render block reads the host `musicalContextBlock` (tempo,
  beat position) and `transportStateBlock`; the kernel locks its step grid to the
  host beat while playing and free-runs otherwise.
- **Realtime safety**: all note tracking and scheduling lives in
  `ArpKernel.hpp` — no allocation and no Objective-C messaging on the audio
  thread. The kernel is plain C++ and trivially unit-testable.

### Parameters

| Parameter | Address           | Values                                   |
|-----------|-------------------|------------------------------------------|
| Rate      | `ArpParamRate`    | 1/4, 1/8, 1/16, 1/8T, 1/16T              |
| Mode      | `ArpParamMode`    | Up, Down, Up/Down, Random, As Played     |
| Octaves   | `ArpParamOctaves` | 1–4                                      |
| Gate      | `ArpParamGate`    | 5%–100% of the step length               |
| Hold      | `ArpParamHold`    | Latch held notes on/off                  |

---

## Making it your own

1. **Identity** — change the 4-char codes and names in **both** extension
   `Info.plist` files (`iOS/Extension/Info.plist`, `macOS/Extension/Info.plist`):
   - `type` (`aumi` for MIDI processors — see note below),
   - `subtype` (`arp1` → your code),
   - `manufacturer` (`Hase` → your registered code; must contain an uppercase
     letter),
   - `name` (`"Hase: Arp"`).
   Also update bundle identifiers in `project.yml`.
2. **Behavior** — replace the logic in `ArpKernel.hpp`. The contract is small:
   `handleMIDIInput()` for incoming events, `process()` once per cycle, and the
   `SendFn` callback to emit MIDI. Swap the arpeggiator for a transposer,
   chord-mapper, humanizer, etc.
3. **Parameters** — edit `ArpParameters.h` and the `parameterTree` in
   `ArpAudioUnit.mm`; the SwiftUI `ArpView` binds to them automatically.

### Note on `aumi` vs `aufx`

`aumi` is the correct, modern type for a MIDI-only plugin and is what hosts use
to populate **MIDI effect** slots. A few older iOS hosts historically only
surfaced MIDI plugins presented as audio effects (`aufx`) with a MIDI output. If
a specific legacy host doesn't list the plugin, switching `type` to `aufx` (and
keeping the silent audio output bus already present in `ArpAudioUnit.mm`) makes
it appear in audio-effect slots while still emitting MIDI.

---

## License

See [LICENSE](LICENSE).
