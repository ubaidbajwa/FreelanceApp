using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddPinDurationAndSystemMessages : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ── Additive columns on Messages ─────────────────────────────────────────────────────────
            // All columns are nullable so existing rows require no back-fill.
            // Existing pinned rows will have PinExpiresAt = NULL, which the active-pin filter treats
            // as "never expires" — silently expiring them would be destructive in effect even though
            // the DDL is additive.

            migrationBuilder.AddColumn<DateTime>(
                name: "PinExpiresAt",
                table: "Messages",
                type: "timestamp with time zone",
                nullable: true);

            // 0 = MessagePinned, 1 = MessageUnpinned. Stored as int (same convention as MessageType).
            migrationBuilder.AddColumn<int>(
                name: "SystemEventType",
                table: "Messages",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "SystemTargetMessageId",
                table: "Messages",
                type: "uuid",
                nullable: true);

            // ── Index for active-pin queries ─────────────────────────────────────────────────────────
            // Supports GetPinnedAsync, CountPinnedAsync, GetOldestActivePinAsync.
            // The original IX_Messages_ConversationId_PinnedAt is retained.
            migrationBuilder.CreateIndex(
                name: "IX_Messages_ConversationId_PinnedAt_PinExpiresAt",
                table: "Messages",
                columns: new[] { "ConversationId", "PinnedAt", "PinExpiresAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Messages_ConversationId_PinnedAt_PinExpiresAt",
                table: "Messages");

            migrationBuilder.DropColumn(name: "PinExpiresAt",         table: "Messages");
            migrationBuilder.DropColumn(name: "SystemEventType",      table: "Messages");
            migrationBuilder.DropColumn(name: "SystemTargetMessageId", table: "Messages");
        }
    }
}
