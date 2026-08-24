# ADR 0001 — Suggestion Ranking: Signal-Driven Candidates + In-Memory Weighted Scoring

**Date:** 2026-07-23  
**Status:** Accepted

---

## Decision

Candidate selection is driven by **signal** (friend-of-friend via connection graph, or skill overlap), not recency. Two server-side queries are issued:

- **Query A (FOF):** EF LINQ correlated subqueries — finds users who share at least one `Accepted` connection with the caller. Backed by composite indexes `IX_Connections_RequesterId_Status` and `IX_Connections_ReceiverId_Status`.
- **Query B (Skill):** `FromSqlInterpolated` with `EXISTS (SELECT 1 FROM unnest("Skills") AS s WHERE lower(s) = ANY(@p0))`. Skills are lowercased in C# before the call; the `= ANY` comparison is case-insensitive at the DB level. Backed by GIN index `IX_Profiles_Skills_GIN`.

Results are unioned and deduplicated in C#, capped at `SuggestionSettings.MaxCandidates` (default 500), then scored entirely in memory:

```
score = mutualConnections × MutualConnectionWeight + sharedSkills × SharedSkillWeight
```

Zero-score candidates are excluded. Remaining candidates are sorted by score descending, then `CreatedAt` descending as a tie-breaker.

Scoring is behind `ISuggestionScorer`; the current implementation is `WeightedSuggestionScorer`. Caching is behind `ISuggestionCache`; the default is `NoOpSuggestionCache` (disabled). Both are seams for future replacement.

---

## Why NOT precomputed scores or a background job yet

1. **Weights are untuned.** At current scale, we do not have enough user interaction data to know whether 10:5 (mutual:skill) is the right ratio. Precomputing with the wrong weights means stale wrong scores.
2. **Invalidation is a separate module.** Every connection accept/reject, skill edit, and dismissal must invalidate the precomputed row. That event bus does not exist yet.
3. **Scale does not require it.** In-memory scoring over ≤500 candidates takes < 5 ms on commodity hardware. The cost of early optimization outweighs the benefit.

---

## Trigger conditions for revisiting

Revisit this decision when **any** of the following is true:

- `MaxCandidates` cap warning fires regularly in production logs (means real candidates are being dropped)
- p95 latency of `GET /api/network/suggestions` exceeds 300 ms
- Total registered users exceed approximately 100 k
- A/B test shows meaningful CTR lift from an ML-ranked scorer

---

## Migration path (when triggered)

1. Implement a new `ISuggestionScorer` backed by a precomputed scores table.
2. Add a background job that populates the table on a schedule and in response to relevant domain events (connection state change, profile skill update, dismissal).
3. Set `SuggestionSettings.CacheSeconds > 0` to activate `RedisSuggestionCache` (already wired; currently no-ops by default).
4. `ISuggestionCache` TTL becomes the last line of defence against stale scores between job runs.
5. `GetCandidatesAsync` can be replaced with a single indexed lookup on the precomputed table — no FOF/skill queries needed.
