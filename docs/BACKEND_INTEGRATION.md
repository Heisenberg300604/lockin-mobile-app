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
converted to `ApiException`; a second 401 signs the Clerk session out so the
router returns the person to sign-in.

`RemoteCommitmentRepository` is selected by
`commitmentRepositoryProvider`. It calls `GET /me` first to provision the
profile and fills a missing display name from Clerk. It then loads
`GET /commitments`; create, check-in, pause, resume, and restart actions call
the documented server endpoints. Calendar-date fields from server responses
are treated as date-only strings by retaining their first ten characters.

The old SharedPreferences commitment snapshots and creation drafts are deleted
once on startup by migration `lockin.remote-data-reset.v1`. Clerk's encrypted
session and user preferences are not removed.

## API constraints reflected by the client

The currently deployed API supports one check-in for the commitment's current
time-zone date only. The app does not claim it saved a legacy catch-up or
count-based check-in. `QUIT` commitments may send `BROKEN`; `BUILD`
commitments only send `KEPT`.

The API has no restart endpoint or persisted attempt links. Restarting a
broken commitment creates a fresh server commitment with the same rules.

`api_progress.dart` implements the API's date-only daily, weekly, monthly,
and fixed-window progress calculation. The card UI uses its current period
counts.
