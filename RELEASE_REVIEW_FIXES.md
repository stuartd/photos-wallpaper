# Photos Wallpaper 2.0 review fixes

Continued locally on 4 October 2026, on `codex/release-review-fixes`, from `main` at `4d4b31c`.
The source edits and regression tests were recovered from the cloud chat **Code Review Photos Wallpaper**, whose unpublished fixes commit was `272b48e` on `fix/2.0-release-review`. The local branch includes further corrections found by Xcode builds, tests, and source inspection.

| Finding | Implemented change |
| --- | --- |
| R1: stalled image requests | Cancellable requests, a 60-second deadline, cycle generations, and useful manual retry with failure notification. |
| R2: stale automatic results | Recheck active session, screen sleep, schedule, and current display identity before application; cancel superseded cycles. |
| R3: unnecessary log snapshots | Writes no longer reread log files or queue UI snapshots. Open windows refresh at most once per second, with reads off the main actor. |
| R4: cache leaks and unsafe deletion | Remove files from failed applications, protect actual current URLs and the latest file per display, and retain other files for seven days. Cleanup runs after each successful display update. |
| R5: permission retry debounce | Treat an authorization retry as continuation of the original cycle, bypassing the new-login debounce. |
| R6: timer/deadline mismatch | Successful manual changes restart both the real interval timer and the stored deadline. |
| R7: overlapping album creation | Queue shared album mutations, retain the created collection identifier, and expose menu busy state. A renamed saved album is not silently reused. |
| R8: US-only shortcut labels | Use the keyboard layout resolver for labels and native equivalents, and refresh on input-source changes. Physical key bindings remain stable. |
| R9: metadata overwriting current wallpaper | Record and persist structured asset/display identity at application time; delayed metadata only enriches history, using the application timestamp. |
| R10: blocking Photos AppleScript | Run AppleScript on a serialized background queue with a 20-second Apple-event timeout, awaiting the result from the UI. |
| R11: false album-add success | Require a change request and confirmed asset membership before reporting success. |
| R12: duplicate launch clearing logs | Acquire the instance lock before initializing shared logs; rejected launches do not initialize the resetting logger. |
| R13: reset missing hidden cache | Share a cache-file discovery helper that includes both legacy files and `.WallpaperCache`, preserving unrelated files. |

Additional corrections include Unicode log scroll offsets, menu tracking limited to the app's menus, registration errors in shortcut settings, direct image-to-JPEG conversion, CI commit metadata, and clearer privacy/release documentation. The Xcode project and deployment settings are unchanged.

## Verification

- `scripts/build_and_test.sh`: Debug build and 154 tests pass.
- `CONFIGURATION=Release scripts/build_and_test.sh`: Release build and 153 tests pass; one existing test is Debug-only.
- Release tests enable testable imports. Ad hoc test hosts disable hardened runtime only during the test phase; the ordinary Release build keeps its normal setting.
- Shell syntax checks and `git diff --check` pass.
- An isolated temporary fixture confirms reset cache discovery includes legacy/current generated files and excludes unrelated files. No app reset or Photos album deletion was performed.
- Cache integration tests use temporary files and a fake wallpaper manager; they do not alter the desktop or read Photos assets.

## Remaining release QA

Smoke-test the signed sandboxed app with multiple displays, iCloud-only images, Photos/Automation permission denial, sleep and session switching, non-US keyboard layouts, and a real duplicate process launch. Cache cleanup cannot enumerate inactive Space wallpaper references; its retention policy is documented in `photos-wallpaper/PRIVACY.md`.

The changes are local. The cloud GitHub push was rejected by automatic approval review for lack of explicit publishing authorization. No push, PR, or release was created during this continuation.
