# Automation State Layout

Per-job maps:
- `JobOwner`
- `JobExecutor`
- `JobPayloadHash`
- `JobStatus`
- `RetryCount`
- `JobNextSlot`
- `JobCronIntervalSlots`
- `JobMaxRetries`
- `JobRetryDelaySlots`
- `JobLastRunSlot`
- `JobRunCount`

View tuple fields returned by `mirror_job()`:
- `soraswap_automation_job_registered`
- `soraswap_automation_executor_bound`
- `soraswap_automation_job_payload_hash`
- `soraswap_automation_job_status`
- `soraswap_automation_retry_count`
- `soraswap_automation_next_slot`
- `soraswap_automation_cron_interval_slots`
- `soraswap_automation_max_retries`
- `soraswap_automation_retry_delay_slots`
- `soraswap_automation_last_run_slot`
- `soraswap_automation_run_count`

Notes:
- `JobExecutor` is optional; when absent, the legacy unbound scheduler entrypoints still work.
- `JobCronIntervalSlots` drives recurring reschedule behavior through `complete_run()`.
