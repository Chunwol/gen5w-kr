# V039 local hotspot switch trial

Optional, separately installed NEMESIS module for the exact Korean Kona V039
WifiSettings APK/ODEX identities. Does not change Bluelink provisioning, subscription
properties, credentials, boot configuration, or Android Wi-Fi framework files.

The three hotspot entry points (screen and two service requests) follow their
existing AP path even when CCS is inactive. Existing CarPlay/Android Auto AP ownership
checks remain in place. Internet service is not provisioned by this module.

Build: `python tools/local-hotspot/build.py --ndk <Android NDK path>`.
Result: `.build/local-hotspot/gen5w.kr.localhotspot-trial.zip`.
Install through NEMESIS, then restart the head unit manually. Removing the module
restores the verified original ODEX; the original backup stays on the head unit.
Unknown APK/ODEX, missing backups on a patched unit, symlinks and conflicting writes
are rejected. Interrupted temporary output is moved into the durable backup
directory, never discarded. A dead PID lock (or an empty legacy lock during removal)
is recovered; a live owner blocks concurrent operations. A failed installation
restores the verified original, including on final read-only remount failure.

Full builds include `gen5w.kr.localhotspot.zip` and its recovery checks in every
installer. Create an empty `GEN5W-LOCAL-HOTSPOT` at the USB root to opt in.
Full removal and bootguard recovery include this module even without that marker.
The backup directory also retains `hotspot-patch` and `recover.sh`, so after a
data reset the verified original can be restored using
`/system/bin/sh /system/etc/gen5w-kr-backup/local-hotspot/recover.sh remove`.

This is a vehicle-unverified trial. The switch can still be refused by another
runtime condition; DHCP, driver loading and ADB connectivity require a vehicle test.
Do not distribute OEM APK/ODEX or the private audit output.
