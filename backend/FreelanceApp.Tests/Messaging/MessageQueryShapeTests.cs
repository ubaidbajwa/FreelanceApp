using System.Text.RegularExpressions;
using FreelanceApp.Infrastructure.Persistence;
using FreelanceApp.Infrastructure.Repositories;
using Microsoft.EntityFrameworkCore;
using Xunit.Abstractions;

namespace FreelanceApp.Tests.Messaging;

// Documents the SQL shape of the message page. Uses the Npgsql provider so ToQueryString() emits
// real Postgres SQL — no database connection is opened by ToQueryString(). Guards the two N+1
// invariants: replyTo is a correlated subquery inside the single page SELECT (not a per-row round
// trip), and the page SELECT does NOT fan out a reactions collection (those are one separate
// GROUP BY, see ConversationRepository.AttachReactionsAsync).
public class MessageQueryShapeTests
{
    private readonly ITestOutputHelper _output;
    public MessageQueryShapeTests(ITestOutputHelper output) => _output = output;

    private static AppDbContext NpgsqlContext() =>
        new(new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql("Host=localhost;Database=shape;Username=x;Password=x")
            .Options);

    [Fact]
    public void GetMessagesPage_IsASingleSelect_WithReplyToSubquery_AndNoReactionCollection()
    {
        using var db = NpgsqlContext();
        var repo = new ConversationRepository(db);

        var sql = repo.MessagePageQuery(Guid.NewGuid(), Guid.NewGuid(), before: DateTime.UtcNow, limit: 31)
            .ToQueryString();

        _output.WriteLine(sql);

        // One statement (no ';'-separated batch) — the whole page is a single round-trip.
        Assert.DoesNotContain(";", sql);
        // Delete-for-me exclusion is resolved in-SQL (NOT EXISTS over MessageDeletions).
        Assert.Contains("MessageDeletions", sql);
        // Reply snippet is truncated IN SQL, not after transfer.
        Assert.Contains("substring", sql, StringComparison.OrdinalIgnoreCase);
        // Reactions are a SEPARATE aggregate query — they must NOT be joined into the page SELECT
        // (a per-row collection here would Cartesian-explode the page).
        Assert.DoesNotContain("MessageReactions", sql);

        // ── Full-table-scan guard ──────────────────────────────────────────────
        // The replyTo resolution must NOT be a windowed subquery. A FirstOrDefault()/Take(1) over a
        // correlated Where makes EF emit `ROW_NUMBER() OVER(...)` inside a subquery that reads every
        // row of "Messages" before the outer join filters it — cost then scales with the whole table,
        // not the page. Assert that shape is gone.
        Assert.DoesNotContain("ROW_NUMBER", sql, StringComparison.OrdinalIgnoreCase);
        // Match `OVER (` or `OVER(` regardless of the provider's spacing.
        Assert.DoesNotMatch(new Regex(@"OVER\s*\(", RegexOptions.IgnoreCase), sql);

        // Positive shape: replyTo is resolved by an INDEXED join on the primary key — the outer
        // ReplyToMessageId equated to a joined Messages alias's "Id" (a unique-index seek), in either
        // operand order. This is what replaces the window function.
        Assert.Matches(
            new Regex("\"ReplyToMessageId\"\\s*=\\s*\\w+\\.\"Id\"|\\w+\\.\"Id\"\\s*=\\s*\\w+\\.\"ReplyToMessageId\""),
            sql);

        // No unfiltered self-scan of "Messages" as a derived table: every occurrence of the table in
        // a FROM/JOIN must carry a predicate (a WHERE on the base query, or an ON for the reply join),
        // never a bare `FROM "Messages" AS <alias>` feeding a window function.
        foreach (Match m in Regex.Matches(sql, "FROM \"Messages\" AS (\\w+)"))
        {
            var alias = m.Groups[1].Value;
            // The base page scan is filtered by the conversation predicate; the reply lookup is an ON join.
            var referencedByPredicate =
                Regex.IsMatch(sql, $"WHERE.*\\b{alias}\\.\"ConversationId\"", RegexOptions.Singleline) ||
                Regex.IsMatch(sql, $"ON .*\\b{alias}\\.\"Id\"") ||
                Regex.IsMatch(sql, $"= {alias}\\.\"Id\"");
            Assert.True(referencedByPredicate,
                $"\"Messages\" AS {alias} appears without a filtering predicate — possible full-table scan.");
        }
    }
}
