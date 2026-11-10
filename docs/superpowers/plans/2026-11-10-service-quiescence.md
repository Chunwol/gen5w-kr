# Service quiescence and recovery-first delivery

User approved inline execution through release and USB preparation on 2026-11-10; no further design approval gate. Actual vehicle execution remains outside this run.

1. RED/GREEN: supported version gate and strict allowlisted inventory parsing; preserve legacy recovery.
2. RED/GREEN: stop via public API, verify stop markers/status and owned process descendants; protect the installer, refuse unresolved processes rather than broad killing. Recheck before hooks, including newly installed services.
3. Verify failure reporting and recovery integration. Keep official platform update separate from package install. Document conservative limitations honestly.
4. Freeze source, run complete tests, clean build/artifact audit, independent review; version, push, CI/release, back up and refresh the actual USB with recovery first and inert platform-update staging.

## Execution ledger

- Starting source: ec9ef73; existing linked worktree, clean. USB/public release: 3be9fce. Vehicle still requires recovery.
- Confirmed fix already present: stock hotspot removal avoids unnecessary rw/ro remount. Actual patch remount failure remains unproven.
- Decision: never kill unknown/orphan processes or stop NEMESIS supervisor. If exact ownership cannot be proved, stop before further package writes; recovery on legacy platform remains explicitly warned.
- Implementation candidate: supported API + strict inventory, supervisor-before-inventory guard persisted across runners, counted boot-keyed descendant journal, APK prior-state capture, guarded consistent-generation resume, independent launcher/report writer protection.
- Focused verification includes PID/starttime, superclass epoch before inventory, parent/late/orphan session cases, persistent uncertainty before stop, Android prior state, current-boot startup intent after worker exit, root-to-nobody UID behavior, and numeric errno/persistence stages. See final logs for latest counts. Stock hotspot original/no-op regression was already verified in84fb078.
- Pre-review full suite: shell and all Python/JVM except one core_recovery host scheduling failure passed. Standalone retry passed; provider-entry latch added before the unchanged700ms blocked-client bound. This run is NOT final-source completion evidence.
- Review rulings: normal removal remains prior compatibility; unknown platform cannot use legacy rollback exemption. No direct descendant signals. Surviving old generations require rollback/cold reboot before new install.
- Candidate version:0.3.61-rc.1/code17. Final frozen full suite/build/audit/review/CI/release/USB checks still required before completion.
- Final independent code review approved with no Critical/Important findings after pre-stop uncertainty and interrupted-worker hold fixes. Documentation terminology aligned. Earlier concurrent manual /proc fixtures contaminated one full run: do not launch additional WSL fixtures alongside the final suite.
- Frozen-source verification: `.build/quiescence-final-source-full.log` exit0, ALL TESTS PASSED (private OEM fixture skipped); focused service quiescence38/0, root-to-nobody startup hold10/0, diagnostic persistence4/0, helper sync and diff whitespace checks passed. Release/build/USB gates follow the source commit; actual vehicle validation remains pending.
