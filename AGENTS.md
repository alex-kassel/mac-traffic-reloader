# AGENTS.MD — `mac-traffic-reloader` (Traffic Reloader)

Autonomous Drillisch Servicewelt data snack (+2 GB) auto-reloader for macOS.

---

## 1. Architectural Overview

1. **Drillisch Servicewelt HTTP Client (`ServiceweltClient.swift`)**:
   - Lightweight `URLSession` pipeline with automatic session cookie handling and CSRF tokens.
   - **Form Encoding Requirement**: When encoding parameters with array brackets (e.g. `UserLoginType[alias]`), `[` and `]` must be preserved as literal characters; never over-encode with `.alphanumerics`.
   - Directly checks quota and booking button state at `/mytariff/invoice/showGprsDataUsage` rather than relying on homepage `/start` DOM.

2. **2Captcha Client (`TwoCaptchaClient.swift`)**:
   - Downloads image captcha from Servicewelt, encodes to base64, submits to 2Captcha API, and polls for result.
   - Built-in balance check method for the Settings window.

3. **Autonomous Engine & State Machine (`ReloaderEngine.swift`)**:
   - States: `.success`, `.buttonInactive`, `.notNeeded`, `.failed`.
   - Prevent App Nap throttling using `ProcessInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical])`.
   - High-precision background scheduling with `DispatchSourceTimer` (GCD).

4. **Menu Bar Controller & Live Timers (`MenuBarController.swift`)**:
   - Clean, high-contrast 2-line header (`.labelColor`, 13pt / 12pt, zero emojis).
   - **Live Countdown in Open Menu**: When an `NSMenu` is open, macOS runs in `NSEventTrackingRunLoopMode`. The 1-second countdown timer is added to `RunLoop.main` in mode `.common` so the countdown ticks live while the menu is open.
   - One-click active/pause toggle (`● Active`).

5. **Dedicated Statistics Window (`StatisticsWindowController.swift`)**:
   - Native macOS modal window (`Cmd+S`) displaying full usage breakdown, active data snacks count, last response, next check countdown, and manual check button.

6. **Apple Keychain & Touch ID (`KeychainManager.swift`, `PreferencesWindowController.swift`)**:
   - Stores Servicewelt password in Apple Keychain with Touch ID quick-fill support.

7. **Expressive Logging (`Logger.swift`)**:
   - Writes to `~/.trafficreloader/trafficreloader.log` with 2 MB log rotation (`.log` -> `.log.1`).
   - Cycles segmented with empty newline `\n`.
   - Distinct, prominent banners for `*** [RELOAD SUCCESS: +2 GB DATA SNACK BOOKED!] ***`, idle checks, and errors.
   - Menu bar item **«Open Log File»**.

8. **Documentation & Release Policy**:
   - `README.md` is for humans/users; `AGENTS.md` is for agent development architecture. Avoid duplicate content.
   - Pushes to GitHub are allowed after cohesive milestones.
   - **Never create GitHub releases without asking the user first**.

---

## 2. Build & Test Commands

```bash
# Compile binary:
swift build --build-system native

# Build .app bundle:
bash scripts/build_app.sh

# Install into /Applications and launch:
bash scripts/install.sh

# Build DMG:
bash scripts/create_dmg.sh
```
