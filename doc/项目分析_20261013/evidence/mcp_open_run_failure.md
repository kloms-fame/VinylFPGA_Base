# SynthPilot TD saved-run reopen failure

Date: 2026-10-13 Asia/Shanghai
Tool: td_open_run(run=phy_1, run_type=phy, run_stage=route)
Context: copied project and complete GUI run in a local temporary audit snapshot; td_open_project succeeded.
Result: ERROR: TD operation outcome is unknown; the process was invalidated: TD process exited before response completion (returncode=None).
Action: no retry or save; original project/run untouched. Fresh td_build through opt_gate had already succeeded; only that fresh synthesis and original GUI report evidence are used.
Root cause: unconfirmed; do not infer RTL or route failure from this process exit.
