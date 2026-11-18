# Gen5W pre-zygote activation and active portable update design

Date: 2026-11-17
Status: superseded by user constraint on 2026-11-17; see 2026-11-17-portable-persistent-live-update-design.md
Project: `kona-gen5w-research`, active checkout `gen5w-kr-stock-first`

## User outcome

Fix both reported problems before returning to dongle expansion:

1. A normal vehicle boot must not stop and restart Android/zygote to apply the portable overlays. The normal framework boot should remain uninterrupted.
2. A newer portable USB package must be installable over the currently armed portable package, with the currently owned overlays and services safely quiesced, and with a clear automatic reboot/update result.

This is not verified as fixed until repeated cold boots and an update are exercised on the vehicle. The unrelated Bluetooth audio, HUD, INFO and dongle work remain out of scope for this design.

## Evidence

- `tools/portable/boot.sh` waits for the first zygote, then calls `bounded transact`; `transact` stops zygote, applies the owned overlay/runtime, and starts zygote. Thus the current architecture deliberately interrupts the framework on every cold boot.
- `tools/portable/NEMESIS.data` registers `service.sh` as a normal NEMESIS background service. It is not an init pre-zygote hook.
- The extracted V039 `D:\kona_gen5w_decrypted\boot.img` is an Android boot image whose ramdisk contains `init.rc`. In that file, `on post-fs-data` precedes `on boot`'s `class_start main`; `init.tcc897x.rc` is imported by `init.rc` and also has a `post-fs-data` action. This supplies a potential ordering point before zygote, but does not prove the vehicle's currently installed boot partition is byte-identical or safely writable.
- V039 `factory.fstab` names `/dev/block/platform/bdm/by-name/boot` at `/boot`; host-side image extraction does not establish vehicle flashing safety, active boot source, alternate boot/recovery availability, or rollback behavior.
- `tools/portable/usb/NEMESIS.sh` detects the installed portable package, but refuses it when `boot.sh status` returns `enabled|1`. `tests/portable_usb.sh` explicitly encodes this refusal.
- The packaged portable metadata is 0.3.71. The separate dongle candidate 0.3.73 is not the portable update.
- `docs/portable-candidate.md` says the current candidate does not modify `/system` or boot images. This design is a proposal to change that boundary only if platform safety checks pass.

## Approaches

### A. Keep late NEMESIS activation and retain the framework restart

Lowest installation risk and consistent with current private bind overlays. It cannot satisfy the no-interruption requirement on every cold boot. Rejected for the requested outcome.

### B. Add a pre-zygote dispatcher to the boot ramdisk

A small init integration invokes a stable, bounded dispatcher after `/data` is mounted and before the main Android class starts. The dispatcher reads the currently installed portable package's enable/state marker and staged plan, applies only the already-owned overlays, validates the resulting view, and returns control to init. Normal NEMESIS late service becomes a status/health checker and must not run a second transaction. On any preflight/apply failure, it removes only partial owned mounts and lets init continue with the stock view. This is the only currently evidenced path that can avoid restarting an already-running zygote while preserving private overlay behavior.

This requires proving the exact current vehicle boot image, init command/service semantics, `/data` availability and SELinux permissions, boot partition write path, and a usable rollback route. The dispatcher must be packaged and updateable from `/data`; the ramdisk change should be a small, versioned trampoline so routine feature updates do not require reflashing boot.

### C. Patch the stock system artifacts persistently

Would also avoid ephemeral overlays but changes `/system` contents, complicates integrity/OTA/recovery, and contradicts the project's current no-system-write boundary. Rejected.

**Recommendation:** pursue B only after the preflight safety gates below pass. If boot partition rollback cannot be demonstrated, do not install a modified boot image; report that the no-restart requirement is blocked on a supported boot integration rather than shipping a risky partial change.

## Proposed boot behavior

1. Before reboot, USB install verifies the candidate ZIP, NEMESIS version, package identity, boot-image base hash, and free space. It snapshots the exact currently installed boot image and its metadata to an independently readable recovery location and verifies the snapshot byte-for-byte.
2. Build the boot image from the exact installed base, adding only the pre-zygote dispatcher/init integration. Preserve header fields, kernel, ramdisk entries, command line, and partition size constraints; reject unknown base images and unsupported image format.
3. Install the dispatcher payload and activation manifest under a fixed root-owned `/data` location. Keep normal service disabled until all files, hashes, permissions, SELinux labels, and boot image recovery material are verified.
4. Write the boot image only through a tested bounded writer with readback hash verification. Keep the original image and a USB-side copy. If boot partition identity, capacity, write/readback, and recovery entry point are not verified, refuse before writing.
5. At boot, the pre-zygote hook checks an atomic enable marker, boot ID, manifest/hash, source identity, and a strict deadline. It applies overlays while zygote is still stopped. On error it unmounts only mounts proven owned, writes a stock-fallback reason, and exits so normal Android startup proceeds. It must not invoke `stop-android` or `start-android`.
6. NEMESIS `boot.sh run` becomes an observer/health finalizer for this boot. It confirms init reported `prezygote-applied` or `stock-fallback`, verifies framework/app readiness, and retains current rescue and failure-budget protections. It must not issue a duplicate transaction.
7. A one-shot rescue mode disables the early hook and restores the exact prior boot image from independently verified recovery material. If Android/NEMESIS fails to start, recovery must be executable outside the regular Android UI through a documented, vehicle-supported path.

The exact init syntax, ordering guarantee, SELinux domain, image repacker, partition writer and recovery UX are open engineering checks before implementation; do not infer them from the extracted image alone.

## Proposed active-update behavior

1. Complete all read-only admission first: validate ZIP checksum/version, require compatible NEMESIS, inspect package status and boot-image dispatcher status, verify no foreign/uncertain mounts, read AP state, check storage, and confirm the candidate is newer or explicitly marked as a repair build.
2. If current portable is armed, invoke its own bounded `disable`/recovery path. It must disable the early dispatcher first, wait for the boot transaction lock to clear, remove only owned mounts/runtime wrappers, and prove the current framework is in the stock view. Do not neutralize `package-preun.sh` while any early hook or owned mount remains active.
3. Stop only the portable's own NEMESIS-managed processes. Preserve the old package and boot image backup until the new NEMESIS package, postinstall, dispatcher payload, status and rollback materials all verify.
4. Run `nemesis install <stage> --update` under the tested umask. Any failure restores the old hook/package state or leaves an explicit rescue-required state; it never silently drops both old and new recovery paths.
5. On success, atomically publish the new dispatcher payload and manifest, arm for the next boot, display that a one-time reboot is required, and request reboot. The next boot should have no post-start framework restart.
6. If reboot request fails, leave the new install armed only if status and rollback checks pass; show actionable instructions and save a complete report.

The update will still perform one full reboot after installation. The requirement is that routine future boots do not produce a second framework restart/black-screen cycle.

## Failure handling and invariants

- Unknown image format/base, missing or unverifiable original boot image, uncertain active boot partition, insufficient recovery space, missing supported recovery path, or failed readback means refuse before boot-partition writes.
- Never use the firmware-extracted boot image as a flash payload unless its hash is proven identical to the currently installed image.
- Never continue with a partially applied overlay; revert only mounts marked and verified as owned.
- A failure to apply early overlays must let stock Android boot. A failure to restore the boot image must be reported as recovery-required, not success.
- Keep NEMESIS 1.16.7+ package install and HMG guard; do not directly `pm install` APKs.
- Do not change USB contents or vehicle state during design/review. Do not include dongle, audio, HUD, or INFO changes in this implementation.

## Verification

### Host-side tests

- Init-order fixture proves the pre-zygote event is before the `class_start main`/zygote start point for supported base images, and rejects unknown layouts.
- Early dispatcher tests cover disabled, valid plan, missing payload, corrupt manifest, stale boot ID, timeout, partial mount failure, cleanup, stock fallback, and no calls to stop/start Android.
- Existing boot lifecycle suite proves NEMESIS observer path never starts a second transaction after early success and keeps rescue/failure-budget behavior.
- USB updater tests cover armed update success, disable timeout, active lock, foreign/unknown mount, AP guard, corrupt ZIP, old package preservation, NEMESIS update failure, postinstall failure, dispatcher publish failure, boot image readback failure, reboot request failure, and successful automatic reboot request.
- Image builder audit compares all unchanged boot header/kernel fields and ramdisk entries, verifies deterministic output and exact restore image, and tests size/capacity rejection.
- Run the complete preserved regression suite and package audit before building any vehicle candidate.

### Vehicle checks before release

- Read and hash current boot partition; compare its format and init files against the supported base.
- Demonstrate a non-destructive recovery route and restore the original image before any modified-image trial.
- Install via USB, confirm the requested update/reboot notice and actual reboot.
- On repeated cold boots, collect init markers/timeline and verify zygote starts once, there is no `framework-stop`/`framework-start` transaction, and the display does not blank a second time.
- Exercise forced preflight and partial-apply failures; confirm stock UI boots and the rescue route restores the original image.
- Only after boot/update acceptance, separately resume the user's audio/HUD/INFO and dongle tests.

## Open questions / gates

1. Can the vehicle expose and safely restore the currently active boot image if the Android framework never starts? What is the exact supported recovery path?
2. Is the live boot image identical to the extracted V039 base, and can its bootloader/partition accept a modified image without signing or integrity rejection?
3. Which init command/service mechanism in this exact init binary gives a synchronous pre-zygote barrier, and under which SELinux domain can the dispatcher execute?
4. Can boot image backup and staged candidate fit in available `/data` and USB space with power-loss-safe publication?

No implementation should begin until this design is reviewed and the boot-partition/recovery gates are answered.

