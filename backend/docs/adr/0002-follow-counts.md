# ADR 0002 — Follow Counts: Live COUNT(*) vs Denormalized Counters

**Date:** 2026-07-23  
**Status:** Accepted

---

## Decision

Follower and following counts for `GET /api/network/overview` are computed with a **live `COUNT(*)`** query at request time, not stored as denormalized counter columns on the `User` table.

The query uses a single `GroupBy(_ => 0)` aggregation (same pattern as `ConnectionRepository.GetCountsAsync`) backed by `IX_Follows_FollowerId` and `IX_Follows_FolloweeId`. A null-fallback handles the zero-row case so no special `INSERT 0` row is required.

---

## Why NOT denormalized counters yet

1. **Correctness by construction.** A denormalized counter requires the follow/unfollow write and the counter update to be in the same transaction. Any missed update leaves the counter permanently wrong. Live COUNT is always correct.
2. **No invalidation logic needed.** No background reconciliation job, no event bus, no "fix stuck counters" runbook entry.
3. **Index-backed and fast at current scale.** An index scan on a narrow table returns in < 1 ms for typical follow counts. The query is not on the hot path (it's triggered by opening the network tab, not every feed scroll).

---

## Trigger conditions for revisiting

Revisit this decision when **any** of the following is true:

- [ ] Any single user exceeds approximately 100 k followers (the index scan cost grows linearly with follower count)
- [ ] p95 latency of `GET /api/network/overview` exceeds 200 ms
- [ ] A follower-count sort or feed-ranking feature requires sub-millisecond count access

---

## Migration path if triggered

1. Add `FollowingCount int NOT NULL DEFAULT 0` and `FollowersCount int NOT NULL DEFAULT 0` columns to `Users` (additive migration).
2. Backfill with `UPDATE Users SET FollowersCount = (SELECT COUNT(*) FROM Follows WHERE FolloweeId = Users.Id)` etc.
3. Update `FollowRepository.FollowAsync` and `UnfollowAsync` to `UPDATE Users SET ... = ... + 1 / -1 WHERE Id = ...` in the same `SaveChangesAsync` call.
4. Add a periodic reconciliation job (e.g. nightly) to detect and fix any drift.
5. Switch `GetFollowCountsAsync` to read from the denormalized columns instead of aggregating.
