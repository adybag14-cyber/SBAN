# SBAN v22 Status

This commit captures the v22 implementation work in progress.

Completed measured artifacts:

- `unified_prefix_v22_release.json`
- `unified_drift_v22_release.json`
- `unified_probe_v22_release.json`
- `longrun_v22_250k.json`
- `longrun_v22_1m.json`
- `longrun_v22_10m.json`

Measured results currently on disk:

- prefix: `99.6350%`
- drift: `99.5400%`
- probe: `99.9000%`
- 250k: `99.4076%`
- 1M: `99.4344%`
- 10M: `77.9175%`

Still ongoing:

- `longrun_v22_100m.json`

Current interpretation:

- The original engine-health suite remains at the v21 packaged baseline.
- The v22 dialogue, memory, paraphrase, and safety/runtime changes are implemented and locally validated.
- The near-100M hardening run is still executing in the background on a memory-bounded long-horizon profile and is not yet part of a completed packaged v22 release.

Operational note:

- `scripts/watch_v22_100m_completion.ps1` monitors the background run, writes `longrun_v22_100m_watch_status.txt` when the result lands, and raises a Windows notification on completion.
- Full v22 deliverable generation stays pending until the near-100M artifact and the remaining release outputs finish.
