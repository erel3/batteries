# Research — where battery data comes from

Measured on the owner's Mac, macOS 27.2.1 (26B131), 2026-11-20.

## Owner's devices (paired)

| Device | Notes |
|---|---|
| Mac internal battery | AlDente manages charging (limit 80%) |
| Andrey's AirPods Pro | left / right / case |
| Keychron K8 HE (keyboard), Keychron M3 mini 4K (mouse) | BLE |
| Sony WF-1000XM4 | vendor 0x054C product 0x0DE1 |
| DualSense Wireless Controller | vendor 0x054C product 0x0CE6 |
| Andrey's iPhone | not a Bluetooth accessory to the Mac |
| "mika" | owner's Sony Xperia (Android), unpaired 2026-11-20, may come back |

## Source 1 — IOPowerSources (public, covers almost everything)

`pmset -g accps` prints it; the API is `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` / `IOPSGetPowerSourceDescription`, and `IOPSNotificationCreateRunLoopSource` notifies on every change (no polling):

```
-InternalBattery-0 (id=24248419)        80%; AC attached; not charging present: true
-Keychron K8 HE (id=41292680)           61%;
-Andrey's AirPods Pro Case (id=46994344) 99%; discharging present: true
-Andrey's AirPods Pro (id=46994345)      80%; charging; 0:00 remaining present: true
-Keychron M3 mini 4K (id=41292702)       44%;
```

- The Keychrons' battery is NOT in `ioreg` (`BatteryPercent` absent) nor in `system_profiler`; it is only here (System Settings → Bluetooth shows the same 61% / 44%).
- AirPods appear as two sources (buds combined + case). Per-bud left/right: `system_profiler SPBluetoothDataType -json` (`device_batteryLevelLeft/Right/Case`), which also keeps the last values while the AirPods are disconnected. IOBluetooth private selectors `batteryPercentLeft/Right/Case/Single` give the same live.
- Unverified: whether Sony WF-1000XM4 and DualSense appear here when connected (both were disconnected during research). Check first thing with them connected.

## Source 2 — iPhone (and Apple Watch through it)

macOS does not publish an iPhone's battery anywhere. AirBuddy reads it through `AirIMD.framework` + `AirIMDService.xpc` (bundles `imdserver`): a copy of libimobiledevice. It pairs with the phone once (owner taps Trust), then talks lockdown over Wi-Fi (same protocol as Finder sync); `companion_proxy` (`com.apple.companion_proxy`) gives the Watch's battery via the phone. Battery domain in lockdown: `com.apple.mobile.battery` (`BatteryCurrentCapacity`, `BatteryIsCharging`).

**Security cost**: the pairing record (host certificate + private key + escrow bag) is a full-access key to the phone over the LAN, far beyond battery: device info, backups (mobilebackup2), media (AFC), app list. macOS keeps its own in root-only `/var/db/lockdown/`; our app would need its own copy. Decide in the design where it lives (Keychain, not a plain file) and what the app may ask lockdown for (battery domain only). The owner revokes all trusts on the phone: Settings → General → Transfer or Reset iPhone → Reset → Reset Location & Privacy.

**VERIFIED 2026-11-20 over Wi-Fi, no installs, stdlib only**: usbmuxd `ListDevices` (ConnectionType `Network`, after Finder's "Show this iPhone when on Wi-Fi") → `ReadPairRecord` (macOS's own Finder trust) → `Connect` port 62078 → lockdown `QueryType` → `StartSession` (`EnableSessionSSL: true`) → TLS with `HostCertificate`/`HostPrivateKey` (`CERT_NONE`, `ALL:@SECLEVEL=0`) → `GetValue` domain `com.apple.mobile.battery` = `{BatteryCurrentCapacity: 54, BatteryIsCharging: false, ExternalConnected: false, FullyCharged: false, …}` → `StopSession`. Python's `ssl` loads a key only from a file, so the probe wrote it 0600 to the scratchpad and deleted it at once; Swift (Network.framework / Security) can take it in memory, so the app never writes it.

**Pre-existing exposure, not ours**: `/var/run/usbmuxd` is `srw-rw-rw-` and `ReadPairRecord` hands the FULL pair record (`HostPrivateKey`, `RootPrivateKey`, `EscrowBag`) to any process of the logged-in user, no root, no prompt. Our app adds no new key and no new trust; it must only ever request the battery domain.

**Owner, 2026-11-20: the iPhone already trusts this Mac (Finder trust done), same Apple account.** Proposed route, to verify first: reuse that trust instead of pairing again. Apple's own usbmuxd (`/var/run/usbmuxd`) hands the existing pair record to a local client (`ReadPairRecord`, how libimobiledevice works on macOS without sudo), so the app never stores a key of its own. Network discovery needs Finder → the iPhone → "Show this iPhone when on Wi-Fi". The same Apple account does not replace this trust: lockdown pairing is per host, separate from iCloud.

Not yet checked: whether Homebrew `libimobiledevice` / `pymobiledevice3` is installed or acceptable as a dependency vs. implementing the lockdown subset ourselves; whether Finder's "Show this iPhone when on Wi-Fi" is enough for network discovery without our own pairing.

## How AirBuddy 3.1 does the rest (for reference, from its bundle)

- `AirCore.BluetoothHIDClient` — reads the standard GATT Battery Service (0x180F / 0x2A19) from already-connected BLE HID devices via CoreBluetooth.
- `ACProximityPairingParser` — parses AirPods' BLE proximity-pairing advertisements (Apple manufacturer data 0x004C, type 0x07): lid open, battery, in-ear.
- `BluetoothClassicService.xpc` — IOBluetooth `batteryPercent*` private selectors; `SonyBatteryState` (Sony's own headphone protocol).
- Links CoreBluetooth, IOBluetooth, IOBluetoothUI; weak-links MediaRemote, IconServices, VisionKitCore (private).
- Ships Sparkle (silent self-update, `SUAutomaticallyUpdate = 1`) and Paddle (licensing).
