# CloudTune Release Checklist

## Pre-Release

1. Ensure `main/master` is green in CI (`go test ./...` and `flutter test`).
2. Confirm production `.env.prod` values are up to date (DB/JWT/monitoring keys).
3. Confirm storage and upload limits are intentionally set:
   - `CLOUD_STORAGE_QUOTA_BYTES`
   - `CLOUD_MAX_UPLOAD_SIZE_BYTES`
   - `CLOUD_MAX_PARALLEL_UPLOADS`
4. Confirm monitoring bot alert thresholds are set and recipients are valid.
5. Confirm deploy account is non-root (or explicitly approved via `ALLOW_DEPLOY_AS_ROOT=true`).

## Deploy

1. Run `backend/scripts/deploy-from-github.sh` with target branch.
2. Verify output includes successful backend rollout and landing sync.
3. Verify post-deploy smoke tests completed (`POST_DEPLOY_TESTS_PASSED`).

## Smoke Validation (Post Deploy)

1. `GET /health` returns `200`.
2. Auth flow works (`/auth/register`, `/auth/login`).
3. Upload flow works (`/api/songs/upload`) and song appears in `/api/songs/library`.
4. Pagination/search smoke checks pass for:
   - `/api/songs/library?limit=...&offset=...&search=...`
   - `/api/playlists?limit=...&offset=...&search=...`
   - `/api/playlists/:id/songs?limit=...&offset=...&search=...`
5. Monitoring snapshot is available and includes upload error counters.

## Rollback Criteria

Rollback is required when any of the following is true:

1. Smoke tests fail.
2. Upload `5xx` spikes above configured alert threshold.
3. Upload `4xx` spike is caused by server regression (not client misuse).
4. Backend health or critical endpoints remain degraded after deploy.

## Rollback Procedure

1. Use the previous commit (`PREVIOUS_COMMIT`) from deploy logs.
2. Re-run deploy script rollback path (automatic when `ROLLBACK_ON_TEST_FAILURE=true`).
3. Confirm health and smoke tests on rolled-back version.
4. Announce rollback in release channel and open a postmortem task.
