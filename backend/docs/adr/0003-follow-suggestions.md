# ADR 0003 — Follow Suggestions: Three-Query Signal Union + In-Memory Weighted Scoring

**Date:** 2026-07-24  
**Status:** Accepted

---

## Decision

`GET /api/network/follow-suggestions` uses a signal-driven, bounded candidate pipeline:

### Candidate selection — three server-side queries, unioned in C#

- **Query A (social graph reach):** EF LINQ — finds users followed by anyone I have an `Accepted` connection with. Backed by `IX_Follows_FollowerId`. This raw signal will power the "followed by X" preview labels in slice N6b; we compute the count now.
- **Query B (skill overlap):** `FromSqlInterpolated` with `EXISTS (SELECT 1 FROM unnest("Skills") AS s WHERE lower(s) = ANY(@p0))`. Skills pre-lowercased in C#; comparison runs entirely server-side. Backed by GIN index `IX_Profiles_Skills_GIN`.
- **Query C (global popularity):** `GROUP BY FolloweeId ORDER BY COUNT(*) DESC LIMIT TopPopularCandidates` over the `Follows` table. Backed by `IX_Follows_FolloweeId`. **This is the cold-start path** — a brand-new user with no connections and no skills still receives results here.

Results are unioned and deduplicated by UserId in C#, then capped at `SuggestionSettings.MaxCandidates`. After capping, a fixed number of additional queries (not one per candidate) load user+profile details, per-candidate follower counts, and social-reach counts.

### Scoring (in-memory, behind `IFollowSuggestionScorer`)

```
score = (SocialReachCount × SocialReachWeight)
      + (SharedSkillsCount × SharedSkillWeight)
      + Math.Min(FollowersCount, MaxPopularityBonus)
```

Popularity is deliberately **capped** at `MaxPopularityBonus` so a single mega-followed account cannot dominate every user's feed — it acts as a tiebreaker, not the primary signal.

Sort order: Score DESC, FollowersCount DESC, UserId ASC (deterministic stable paging).

---

## Why zero-score candidates ARE kept here (unlike connect-suggestions)

Connect-suggestions drops zero-score candidates because a connection request requires the other party's approval — surfacing random people with no shared signal is noise.

Follow is a **low-commitment, unilateral** action. A cold-start feed of globally popular accounts is useful discovery content, not noise. Dropping zero-score candidates would break the cold-start guarantee entirely for new users.

---

## Why popularity is capped

Without a cap, a single account with millions of followers scores so high on popularity alone that it appears first for every single user, regardless of relevance. The cap converts `FollowersCount` from a dominant signal into a tiebreaker between candidates that are otherwise equally relevant to the caller.

---

## Why NOT exclude connections (unlike connect-suggestions)

Following someone and connecting with someone are independent social gestures. You may want to follow someone you are already connected with (to see their posts), and vice-versa. Connect-suggestions exclude connections because connecting again is meaningless; follow-suggestions must not, because the follow relationship has independent value.

---

## Known cost

**Query C** performs a global `GROUP BY` over the `Follows` table on every request. At current scale (thousands of users) this is fast. The index `IX_Follows_FolloweeId` makes it a full index scan with grouping, which EF Core translates to a single indexed GROUP BY.

**Revisit trigger:** p95 latency of `GET /api/network/follow-suggestions` exceeds 300 ms, OR the `Follows` table exceeds approximately 1 M rows.

**Migration path:** Cache the top-popular list with a short TTL using the existing `ISuggestionCache` seam (already wired; currently no-ops), or maintain a materialized view refreshed by a background job. See `docs/TODO.md`.

---

## DB round trips per request

8 total, fixed regardless of candidate set size or page size:

1. `GetMySkillsAsync` — my profile skills
2. `GetMyAcceptedConnectionIdsAsync` — my accepted connection IDs
3. Query A (inside `GetFollowSuggestionCandidateIdsAsync`)
4. Query B (inside `GetFollowSuggestionCandidateIdsAsync`)
5. Query C (inside `GetFollowSuggestionCandidateIdsAsync`)
6. `LoadFollowSuggestionDetailsAsync` — User + Profile LEFT JOIN for bounded set
7. `GetFollowerCountsForCandidatesAsync` — GROUP BY over candidate IDs
8. `GetSocialReachDataAsync` — LEFT JOINs Follows → Users → Profiles for bounded set, groups in C#

No query is issued inside a loop over candidates.

---

## Appendix: SuggestionKind discriminator (N6b)

**Decision:** `SuggestionDismissal` gains a `SuggestionKind Kind` column (`NOT NULL DEFAULT 0`).
The unique index is replaced: `(UserId, DismissedUserId)` → `(UserId, DismissedUserId, Kind)`.

**Why a discriminator instead of a separate table:**
- A second `FollowSuggestionDismissal` table would duplicate the idempotency + cascade-delete logic already written for `SuggestionDismissal`. The discriminator reuses that schema without duplication.
- Follow-dismiss and connect-dismiss are structurally identical (who dismissed whom + when). The *intent* differs; Kind captures that.

**Why Kind is REQUIRED on every dismiss/undismiss call-site (no default value, no overload without it):**
- A default or optional `kind` parameter would silently apply to whichever value the compiler chose. A wrong Kind causes a user to vanish from the wrong feed or remain in a feed they dismissed from — both silent, hard-to-reproduce bugs.
- Forcing callers to write `SuggestionKind.Connect` or `SuggestionKind.Follow` explicitly makes the wrong Kind a code-review catch, not a runtime incident.

**Independence invariant:**
- Connect-suggestions filter `Kind = Connect`; follow-suggestions filter `Kind = Follow`. The same `(UserId, DismissedUserId)` pair can exist in both — dismissing someone from "People you may know" does not remove them from "Popular on Skillora" and vice versa.

**Social proof preview (N6b):**
- `GetSocialReachCountsAsync` (round trip 8, previously `GROUP BY FolloweeId`) is replaced by `GetSocialReachDataAsync`, which LEFT JOINs Follows → Users → Profiles, fetches all matching rows, then groups in C# to build `{ Count, Preview }`. Still one round trip.
- Preview: at most 3 connections ordered by `FullName ASC, UserId ASC` for determinism. Empty list (not null) when no proof.
