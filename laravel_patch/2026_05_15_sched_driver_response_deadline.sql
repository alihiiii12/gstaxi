-- حجز مسبق: مهلة رد السائق بعد جاهزية الراكب (15 دقيقة)
ALTER TABLE `requests`
  ADD COLUMN IF NOT EXISTS `sched_driver_response_deadline_at` DATETIME NULL
  AFTER `sched_driver_deferred_at`;
