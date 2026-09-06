# ADR 0005 — API Rate Limiting and Email Off the Request Cycle

**Date:** 2026-09-05
**Status:** Accepted

---

## Decision

Two long-deferred hardening items, shipped together:

1. **Rate limiting** via the built-in ASP.NET Core 8 limiter — settings-bound, partitioned by IP (pre-auth) or user id (authenticated), fixed-window, returning RFC 7807 with `Retry-After`. The SignalR hub is exempt.
2. **Auth emails sent off the request thread** via an in-process `Channel<T>` + `BackgroundService`, with an explicit short SMTP timeout. The handler enqueues and returns immediately.

Neither needed a migration.

---

## 1. Rate limiting

**Why now:** `TooManyRequestsException` (429) existed but nothing enforced a request ceiling, so `POST /api/auth/login` accepted unlimited attempts — brute force, credential stuffing, and OTP guessing were all unbounded. Rate limiting is the missing companion to the existing user-enumeration protection and adaptive hashing.

**Built-in, no package.** `Microsoft.AspNetCore.RateLimiting` is part of the shared framework. No third-party dependency.

**Partitioning — IP for anonymous, user id for authenticated.** Pre-auth endpoints (`login`, `register`, `forgot-password`, OTP verify/resend) partition by client IP. Authenticated endpoints (`media`, and the global ceiling) partition by the `sub` claim. IP alone is wrong for authenticated traffic: an office or university behind one NAT would throttle each other, and that is exactly Skillora's user base. This requires the limiter to run **after** `UseAuthentication()` so `HttpContext.User` is populated — the middleware order was changed accordingly (`UseRouting → UseCors → UseAuthentication → UseRateLimiter → UseAuthorization`). Pre-auth policies partition by IP and are unaffected by the move.

**Fixed window, not token bucket.** A token bucket refills continuously, letting an attacker sustain a steady trickle indefinitely. A fixed window is a hard ceiling per period — the correct shape for auth endpoints.

**Policies (defaults; tunable in config).**

| Policy | Limit | Partition |
|---|---|---|
| `login` | 5 / 15 min | IP |
| `register` | 3 / hour | IP |
| `forgot-password` | 3 / hour | IP |
| `otp` (verify / resend / reset) | 5 / 15 min | IP |
| `media` | 20 / hour | user |
| Global — authenticated | 300 / min | user |
| Global — anonymous | 60 / min | IP |

**Configurable, not hardcoded.** Limits live in `RateLimitSettings` (`Application/Common/Settings/`), bound from the `RateLimiting` config section — a hardcoded limit cannot be tuned in production without a redeploy. Defaults on the class keep the limiter safe if the section is absent.

**RFC 7807 + `Retry-After`.** `OnRejected` writes an `application/problem+json` body of the same shape `GlobalExceptionHandler` emits for every other error (status/title/detail/type/instance + `traceId`), and sets a `Retry-After` header from the limiter's `MetadataName.RetryAfter`. A bare 429 with no body would be the only non-conforming error in the app.

**SignalR hub exempt.** The global limiter returns `NoLimiter` for `/hubs/*`. A long-lived WebSocket is one connection, not repeated requests; throttling reconnects would break recovery on flaky networks exactly when it matters most.

**Testing choice.** Exercising the live middleware needs `WebApplicationFactory` (new to this test project) and wall-clock windows — disproportionate for a config-bound limiter. Instead `RateLimitSettingsTests` asserts what is deterministic and load-bearing: the section binds, values resolve as configured, overrides tune without a redeploy, and defaults are safe when the section is absent. Policy registration itself is exercised by app startup (an unknown policy name throws). This is a deliberate scope call, reported rather than silently skipped.

**Revisit trigger:** multi-instance deployment — an in-memory limiter counts per process, so N instances allow N× the limit. Migration: back the limiter with the existing Redis (a distributed limiter) so the ceiling is global.

---

## 2. Email off the request cycle

**Why:** `POST /api/auth/forgot-password` blocked on the SMTP send inside the request handler. When Mailtrap was slow or misconfigured the request hung with it (a ~20 s client receive-timeout). A handler must never block on an external service it does not control.

**Channel + BackgroundService, not `Task.Run`.** A singleton `EmailQueueService` wraps a bounded `Channel<EmailQueueItem>` (capacity 512, `DropOldest`); `EmailBackgroundService` drains it. The endpoint enqueues (a non-blocking `TryWrite`) and returns immediately. A bare `Task.Run` has no lifecycle, no graceful shutdown, and no logging discipline — in-flight emails vanish on stop and an unobserved exception can take the process down. A `BackgroundService` gives cancellation and shutdown for the same effort.

**Explicit short SMTP timeout.** Each send runs under a linked `CancellationTokenSource` (`stoppingToken` ⊕ a 10 s per-email deadline). MailKit's async methods honor the token (`SmtpClient.Timeout` covers only sync socket ops), so an unbounded call can't tie a worker up forever. A send failure is logged and the loop continues — one email's failure doesn't stall the queue.

**OTP shares the path.** Registration and resend-OTP emails go through `OtpService.GenerateAndSendAsync`, which enqueues on the same channel — the same fix covers them, so no auth email blocks a request.

**Not a database outbox.** An outbox is the right answer when an email must survive a process crash — a deliberate future step, deferred in `docs/TODO.md`. A password reset does not meet that bar: the user simply requests another. The bounded channel's `DropOldest` is acceptable for OTP/reset mail.

**User enumeration — timing was itself a leak.** `forgot-password` already returned an identical body for known and unknown emails, but the *known* path formerly did more synchronous work (OTP row + SMTP) while the unknown path returned early — an observable timing difference. Moving the send to the background removes the SMTP portion of that gap as a side effect. The endpoint sends only when the account exists, without the response revealing which branch ran (same status, same body, silent no-op for unknown).

**Reset-token hygiene (audited).** The reset "token" is the 6-digit `EmailOtp` code: single-use (`IsUsed` set on success; prior unused codes invalidated on regenerate), 10-minute expiry, 3-attempt cap, and a 60 s per-account resend cooldown plus the `forgot-password` IP limit. One weakness — the code is stored in plaintext. For a short-lived, attempt-capped 6-digit code this is materially lower risk than a plaintext long-lived URL token; hashing it is structural (touches `OtpService`, verification, and the OTP test suite) and is **deferred** to `docs/TODO.md` rather than bundled into this slice.

**Revisit trigger:** a lost email becomes a correctness problem rather than an inconvenience (payment receipts, legal notices) — introduce a DB outbox with a relay worker; the `IEmailQueue` seam is where it swaps in.

---

## Notes

- Both items were audited as partially pre-existing; this ADR records the completed decisions, not a from-scratch build.
- Deferred follow-ups (distributed limiter, DB outbox, OTP hashing) are tracked in `docs/TODO.md`.
