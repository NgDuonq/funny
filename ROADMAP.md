# Real Dynamic Notch — staged implementation

## 0.3: Dynamic Core + first system integrations

Implemented:
- Independent IslandCore state machine: idle / transient HUD / expanded / multiple activities.
- EventBus, EventScheduler, PriorityEngine, IslandCoordinator and persistent SettingsStore.
- Coalescing by event ID, deterministic priorities, expiring HUDs restore underlying activities.
- User-expanded content outranks transient events; those events may expire while expanded.
- Music bridge preserved; coordinator subscribes to music state instead of coupling geometry to PlayerModel.
- Core Audio default-output volume/mute property listeners. Hardware without a master scalar volume (e.g. some HDMI/USB outputs) does not provide this HUD; no fake value is substituted.
- IOKit power-source notifications for charger transitions / crossing 20% battery threshold.
- Timer presets, pause/resume/cancel, wall-clock deadline reconciled after sleep, completion HUD.
- Spring content transitions, animated top-anchored panel resizing, hover delay, click-to-pin, immediate quit.
- System listeners removed during sleep; scheduler expires stale events on wake.
- Unit tests for priority, event coalescing, expiry, restoration and concurrent music/timer activities.

Limitations: timer does not persist across app termination; 25-minute preset is not an automated Pomodoro cycle. Native macOS volume HUD is not suppressed. Panel animation and physical notch alignment still require real-device QA. Current display handling still chooses the notched display automatically; DisplayManager extraction and user display selection remain pending.

## Next gated milestones (not implemented / not advertised as working)

1. Hardware validation: MacBook volume/mute, headphones, power connect/disconnect, sleep/wake, fullscreen and rapid hover. Measure CPU/RAM/energy with Instruments.
2. Interactive: File Shelf with safe bookmarks, images/URLs, EventKit Calendar with explicit opt-in, stopwatch and Pomodoro cycles; selectable displays and per-display geometry.
3. System devices: output device connection names, Bluetooth/AirPods through supported APIs, Wi-Fi state; brightness only after stable public API feasibility is confirmed. No private API fallbacks.
4. Music Pro: LRCLIB automatic lyrics with opt-in networking, cache/offsets; real audio visualizer only after capture permission and valid audio stream. Never synthesize bars in normal mode.
5. Developer integrations: authenticated loopback API, bounded payloads and rate limits; terminal client; GitHub Actions opt-in with Keychain token; downloads/notifications only from explicit supported senders.
6. Production: accessibility and layout tests, signature/notarization using owner's signing identity, persistent settings and state migrations, release packaging and real-device test matrix.

Do not advance or call the app production-ready before the applicable milestone's tests pass. CI validates compilation and packaged startup; it does not validate live websites, device permissions or hardware behavior.
