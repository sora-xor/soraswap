# Automation Interface

Contract: `contracts/automation/job_queue.ko`

Public entrypoints:
- `main() -> int`
- `enqueue(job, payload_hash)`
- `assign_executor(job, executor)`
- `configure_job(job, next_slot, max_retries, retry_delay_slots)`
- `configure_cron(job, interval_slots)`
- `mark_running(job, current_slot)`
- `dispatch_job(job, current_slot)`
- `mark_done(job)`
- `complete_run(job, current_slot)`
- `retry(job)`
- `retry_at(job, current_slot)`
- `pause_job(job)`
- `resume_job(job, current_slot)`
- `cancel_job(job)`
- `mirror_job(job) -> (int, int, int, int, int, int, int, int, int, int, int)`

Notes:
- Jobs now model a minimal scheduler lifecycle instead of only queue-or-done: queued, running, paused, done, and canceled are all explicit status values.
- Job ownership is bound to `authority()` at `enqueue`; caller identity is no longer passed through the public ABI.
- `assign_executor` plus `dispatch_job` add an executor-bound path for off-chain workers while still allowing the owner to run the job when no explicit executor is stored.
- `configure_cron` plus `complete_run` model recurring jobs by re-queueing work at `current_slot + interval_slots` instead of forcing every successful run into a terminal done state.
- `mark_running` and `dispatch_job` share the same runner checks and state transition semantics.
- `retry()` reschedules from the stored `JobLastRunSlot`; `retry_at()` is the explicit slot-aware path used by smoke.
- `mirror_job` is a `view fn` consumed through `/v1/contracts/view`.
