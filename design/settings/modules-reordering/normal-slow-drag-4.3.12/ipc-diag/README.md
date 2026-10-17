# Actual guest Foundation / VirtioFS IPC diagnosis

The diagnostic ran in the existing owned VM with no App, GUI or input. The guest Foundation reader polled three fixed filenames for eight seconds using Data(contentsOf:), recording epoch, elapsed time, content, inode and modification time for every read.

- Host atomic replace: host values and inodes advanced twice to host-2; the guest read host-0 throughout all eight seconds.
- Guest atomic replace on the same shared filesystem: guest observed guest-0, guest-1 and guest-2.
- Guest local atomic control: guest observed local-0, guest-1 and guest-2.
- No guest write errors. Host entry and guest entry both actually exited 0.

`guest-raw.jsonl` is the unmodified stdout; `report.json` contains host replacements and source hash. `reader.swift`, `guest-run.sh`, `host-run-executed.py`, and `run.sh` preserve the actual diagnostic inputs. `host-run.py` contains subsequent signal/registration hardening for future use and was not re-executed; this distinction is recorded in report.json.

`cleanup-report.json` is a separate read-only check, actual exit 0: guest temporary compile root absent, no process references its executable path or reader source; host test marker directories absent and no owned Tart IPC process remains. The guest root absence also proves its owned compile binary/subdirectory were removed. Original transient PIDs were not individually recorded, so this evidence reports exact owned-path process absence rather than inventing PID-by-PID history.

This supports guest-side publication for fixture commands. It is an IPC diagnosis, not a native drag acceptance result. The v6 first successful drop and next reset timeout are preserved separately by root.
