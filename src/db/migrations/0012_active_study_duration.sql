-- Rebuild historical session duration from effective per-answer time.
-- Each answer is capped at 10 minutes to discard legacy idle/wall-clock outliers.
UPDATE study_sessions
SET duration_ms = COALESCE((
  SELECT SUM(
    CASE
      WHEN review_logs.duration_ms IS NULL OR review_logs.duration_ms <= 0 THEN 0
      WHEN review_logs.duration_ms > 600000 THEN 600000
      ELSE review_logs.duration_ms
    END
  )
  FROM review_logs
  WHERE review_logs.study_session_id = study_sessions.id
), 0)
WHERE completed_count > 0;
