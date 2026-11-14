# LockIn backend integration

The Flutter app uses the deployed LockIn REST API as its only commitment data
source. It does not cache commitments or check-ins locally.

## Configuration

Run with the web app's Clerk publishable key and an API URL with no trailing
slash:

```sh
flutter run --dart-define-from-file=env/dev.json
```

```json
{
  "CLERK_PUBLISHABLE_KEY": "pk_test_...",
  "API_URL": "https://lockin-a0os.onrender.com/api/v1",
  "ENABLE_DEVICE_MODE": false
}
```

`API_BASE_URL` remains a temporary compatibility fallback, but new
configuration must use `API_URL`.

## Implementation

`ApiClient` in `lib/core/network/api_client.dart` obtains a fresh Clerk token
immediately before every request, sends it in `Authorization: Bearer ...`,
and uses 65-second connect/send/receive timeouts for Render cold starts. It
retries once on a timeout, a 5xx response, or a 401 response (which obtains a
fresh token). NestJS error messages, including validation message arrays, are
converted to `ApiException`. A repeated 401 is shown in the app without
deleting Clerk's local session: a valid Clerk session can be rejected when the
backend's Clerk instance or authorized-party configuration is incorrect.

`RemoteCommitmentRepository` is selected by
`commitmentRepositoryProvider`. It calls `GET /me` first to provision the
profile and fills a missing display name from Clerk. It then loads
`GET /commitments`; create, check-in, pause, resume, and restart actions call
the documented server endpoints. Calendar-date fields from server responses
are treated as date-only strings by retaining their first ten characters.

The old SharedPreferences commitment snapshots and creation drafts are deleted
once on startup by migration `lockin.remote-data-reset.v1`. Clerk's encrypted
session and user preferences are not removed.

## API rules reflected by the client

The app follows the same rules as the LockIn web app; they live in
`lib/features/commitments/domain/api_progress.dart`.

- **Check-ins and backfill.** One result per date. A kept day can be logged
  for today or backfilled for the previous two days (`apiBackfillDays`), inside
  the timeline, on a scheduled weekday, while the commitment is active. Today's
  check-in omits `date` (the server uses its own clock); backfills send it.
  Check-ins created on a later day than their date show as *logged late*.
- **Breaking a quit habit.** `BROKEN` is sent with the chosen reason and an
  optional note; the server stores them and ends the attempt (`breakReason`).
  `BUILD` commitments only send `KEPT`.
- **Periods.** Daily, Monday–Sunday weeks, calendar months, or windows from the
  start date. Edge periods are clipped but keep the full target, so the wizard
  runs `apiFeasibilityError` (a copy of the server's `validatePeriodFeasibility`)
  before locking.
- **Editing.** `PATCH /commitments/:id` changes the reward of an active
  commitment; `DELETE /commitments/:id` removes it; `PATCH /me` saves the
  display name shown in the app.
- **Restart.** The API has no restart endpoint or attempt links. Restarting a
  broken commitment creates a fresh server commitment with the same rules,
  starting today.

Device mode (`ENABLE_DEVICE_MODE=true`) uses the on-device
`LocalCommitmentRepository` instead of the API. It is a development/test mode
and still uses the legacy local lifecycle rules.
