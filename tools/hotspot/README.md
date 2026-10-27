# CarPlay AP profile selection

The authored replacement for `NetworkManagementService.startAccessPoint` selects Connectivity credentials in command-local registers for mode 2. It never writes ordinary SSID/key fields or the configuration store. It uses existing method/type pools and a fixed code slot; no original method instructions are distributed. Signature, field layout and command interface facts are used for interoperability.

Both supported services ODEX hashes are paired with exact framework ODEX hashes. Permission enforcement, firmware reload, null configuration, ordinary/factory profiles, channel selection and native exception conversion remain. Credentials use SensitiveArg to suppress connector diagnostics. The Java controller requires WPA2 (OEM auth type 4) and an empty factory auth override.

`python -I tools/hotspot/build.py --ndk <path>` generates API19 ARM helpers. `python -I tests/hotspot_profile.py` checks authored command behavior, and `bash tests/hotspot_profile.sh` checks owned backups, restoration and reboot readiness. Optional private input verification regenerates recipes outside published artifacts. No firmware inputs are included here.

A root service publishes readiness only when the exact patched disk image and owned original are valid and a kernel boot boundary has passed since application. Installing bytes alone does not prove that system_server loaded them. Vehicle behavior has not been validated.
