# Traffic Reloader — Autonomous Drillisch Servicewelt Data Snack Reloader for macOS

**Traffic Reloader** is a native, ultra-lightweight macOS menu bar utility that autonomously monitors your mobile data quota and activates free **+2 GB Highspeed Data Snacks** on **Drillisch Servicewelt** mobile plans (such as **SIM24**, **sim.de**, **handyvertrag.de**, **winsim.de**, and others).

Built 100% in pure **Swift** with **zero external dependencies** and **no headless browser overhead** (no Chrome, no Puppeteer, no Python). It runs quietly in the system menu bar, consuming only **~15 MB RAM** and an app bundle of just **~360 KB**.

---

## Supported Providers (Drillisch Online GmbH)

All mobile providers operated by **Drillisch Online GmbH (1&1 Group)** share the unified **Servicewelt** platform. Traffic Reloader natively supports:

* **SIM24** (`service.sim24.de`)
* **sim.de** (`service.sim.de`)
* **Handyvertrag.de** (`service.handyvertrag.de`)
* **WinSIM** (`service.winsim.de`)
* **PremiumSIM** (`service.premiumsim.de`)
* **smartmobil.de** (`service.smartmobil.de`)
* **yourfone** (`service.yourfone.de`)
* **BlackSIM** (`service.blacksim.de`)
* **CyberSIM** (`service.cyber-sim.de`)
* **maXXim** (`service.maxxim.de`)
* **Custom Domain** (any private or upcoming Servicewelt portal)

---

## Key Features

1. **One-Click Active / Pause Toggle in Menu Bar**:
   - Easily enable or pause automatic checks directly from the menu bar (`● Active`).
   - Perfect if you are running a server-side cron script or temporarily want to prevent local requests without quitting the app.
   - The menu bar icon changes dynamically:
     - `📶` (Active, monitoring in background)
     - `⏸` (Paused / Deactivated)
     - `↻` (Actively checking or booking +2 GB)
2. **Autonomous HTTP Lifecycle (Zero Browser Overhead)**:
   - Authenticates via lightweight HTTP POST with session cookie management and CSRF tokens.
   - Inspects `/start` for the *«Datenvolumen nachbuchen»* button. If sufficient quota is available, it sleeps until the next interval without making unnecessary booking calls.
   - If traffic is low, requests the booking modal and submits service activation.
3. **Automated Captcha Solving via 2Captcha**:
   - If Servicewelt presents an image captcha during booking, the image is automatically extracted, sent to the 2Captcha API, solved, and injected into the form.
4. **Native macOS Preferences Window**:
   - Configure username, password, 2Captcha key, provider, and check interval (5, 10, 15, 30, 60 minutes).
   - Built-in **"Check Balance"** button to view your remaining 2Captcha balance in real-time.
5. **System Notifications & Live Status**:
   - Menu bar displays your current data usage (e.g. `Quota: 333,21 GB von 334,00 GB (142 snacks)`).
   - Sends native macOS Notification Center alerts when +2 GB is successfully activated.
6. **Native Login Item**:
   - One-click *«Launch at Login»* via macOS 13+ `SMAppService` (clean system integration, no deprecated launch daemons).

---

## How It Works (HTTP Pipeline)

```
[ Scheduled Timer or 'Check & Reload Now' ]
                   │
                   ▼
       [ Active toggle enabled? ]
        ├── NO  ──► Skip check & wait
        └── YES ──► 1. GET / (Extract _SID & CSRF token)
                        │
                        ▼
                    2. POST /public/login_check (Form login)
                        │
                        ▼
                    3. GET /start
                        ├── No 'Datenvolumen nachbuchen' ──► Quota OK, sleep N min
                        └── Button present ───────────────► 4. GET /mytariff/invoice/showGprsDataUsage
                                                                │
                                                                ▼
                                                            5. Inspect "Buchen" Button
                                                                ├── Disabled ──► Wait until active
                                                                └── Active ────► POST /mytariff/invoice/getChangeServiceInfo
                                                                                    │
                                                                                    ▼
                                                                                6. Captcha Required?
                                                                                    ├── YES ──► Download image ──► Solve via 2Captcha
                                                                                    └── NO
                                                                                    │
                                                                                    ▼
                                                                                7. POST /mytariff/invoice/changeService (Activate)
                                                                                    │
                                                                                    ▼
                                                                                8. Fetch updated quota & notify user (+2 GB)
```

---

## Quick Start (Working Without Agents)

### 1. Installation

If you already have the pre-built `TrafficReloader.app`:
1. Move `TrafficReloader.app` to your `/Applications` folder.
2. Double-click to launch.
3. Look for the antenna icon (`📶`) in your top macOS menu bar.

### 2. Configuration via UI

1. Click the menu bar icon -> select **«Settings...»** (or press `Cmd+,`).
2. Choose your provider (e.g., **SIM24** or **sim.de**).
3. Enter your **Username / Phone number** and **Servicewelt Password**.
4. Enter your **2Captcha API Key** (click *«Check Balance»* to verify connectivity).
5. Select your desired **Check Interval** (default: 15 minutes).
6. Click **«Save Changes»**.

### 3. Quick Actions in Menu Bar

* **Active (Auto-Reload)**: Check or uncheck to instantly start or pause background monitoring.
* **Check & Reload Now**: Forces an immediate manual check without waiting for the timer.
* **Launch at Login**: Toggle automatic startup on macOS boot.
* **Open Log File**: Opens `~/.trafficreloader/trafficreloader.log` to inspect live network events.

---

## Building from Source

Requirements: macOS 13.0+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
cd mac-traffic-reloader

# 1. Compile debug executable:
swift build --build-system native

# 2. Assemble release .app bundle:
make app
# or: bash scripts/build_app.sh

# 3. Create distributable .dmg image:
make dmg
# or: bash scripts/create_dmg.sh

# 4. Install into /Applications and launch:
make install
# or: bash scripts/install.sh
```

---

## Configuration & Logs Storage

* **JSON Config**: `~/.trafficreloader/config.json`
  Stores credentials, active provider, check interval, and notification preferences.
* **Log File**: `~/.trafficreloader/trafficreloader.log`
  All network operations, quota updates, captcha transactions, and error reports are logged here with automatic log rotation at 2 MB.
* **Process Lock**: `~/.trafficreloader/trafficreloader.pid`
  Ensures only a single instance of the application runs at any time.

---

## Troubleshooting

| Issue | Resolution |
| :--- | :--- |
| **"Login failed"** | Verify your Servicewelt credentials in *Settings...*. Ensure you can log in manually at `service.sim24.de`. |
| **"Captcha was presented but 2Captcha API key is not configured"** | Enter your 2Captcha API key in *Settings...* and verify your balance via *Check Balance*. |
| **Paused monitoring** | Check the menu bar menu and ensure **«Active (Auto-Reload)»** has a checkmark. |
| **App rebuilds lose permissions** | Build scripts use `codesign --requirements '=designated => identifier "com.fcc.TrafficReloader"'` so macOS TCC remembers authorization across rebuilds. |

---

## License

MIT License. Designed and crafted for macOS by Alex Kassel.
