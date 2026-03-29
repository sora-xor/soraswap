# Automation Interface

Contract: `contracts/automation/job_queue.ko`

Public entrypoints:
- `main() -> int`
- `enqueue(job, owner, payload_hash)`
- `assign_executor(job, executor)`
- `configure_job(job, next_slot, max_retries, retry_delay_slots)`
- `configure_cron(job, interval_slots)`
- `mark_running(job, current_slot)`
- `dispatch_job(job, executor, current_slot)`
- `mark_done(job)`
- `complete_run(job, executor, current_slot)`
- `retry(job)`
- `retry_at(job, current_slot)`
- `pause_job(job)`
- `resume_job(job, current_slot)`
- `cancel_job(job)`
- `mirror_job(job) -> (int, int, int, int, int, int, int, int, int, int, int)`

Notes:
- Jobs now model a minimal scheduler lifecycle instead of only queue-or-done: queued, running, paused, done, and canceled are all explicit status values.
- `assign_executor` plus `dispatch_job` add an executor-bound path for off-chain workers without removing the older unbound compatibility entrypoints.
- `configure_cron` plus `complete_run` model recurring jobs by re-queueing work at `current_slot + interval_slots` instead of forcing every successful run into a terminal done state.
- `retry()` remains as a compatibility entrypoint and reschedules from the stored `JobLastRunSlot`; `retry_at()` is the explicit slot-aware path used by smoke.
- `mirror_job` is a `view fn` consumed through `/v1/contracts/view`.
