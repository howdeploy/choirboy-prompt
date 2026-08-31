-- Compatibility row for ~/.codex/state_5.sqlite so the fixture appears in the resume picker.
-- Run with the app CLOSED (WAL), then let codex re-project thread_history itself:
--   sqlite3 ~/.codex/state_5.sqlite < threads-insert.sql
INSERT INTO threads (
  id, rollout_path, created_at, updated_at, source, model_provider, cwd,
  title, sandbox_policy, approval_mode, tokens_used, has_user_event, archived,
  cli_version, first_user_message, preview, recency_at,
  created_at_ms, updated_at_ms, recency_at_ms, history_mode
) VALUES (
  'fa1ce000-0000-7000-8000-0000000000c2',
  '$HOME/.codex/sessions/2026/08/10/rollout-2026-08-10T18-30-00-fa1ce000-0000-7000-8000-0000000000c2.jsonl',
  1786386600, 1786387200, 'cli', 'openai', '/home/research/choirboy-prompt',
  'Проверка совместимости session provenance (research/12)',
  '{"type":"workspace-write"}', 'on-request', 12480, 1, 0,
  '0.147.0',
  'Продолжаем по двенадцатому документу.',
  'Продолжаем по двенадцатому документу.',
  1786387200, 1786386600000, 1786387200000, 1786387200000, 'legacy'
);
