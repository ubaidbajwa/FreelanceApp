using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddSuggestionPerformanceIndexes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_Connections_ReceiverId_Status",
                table: "Connections",
                columns: new[] { "ReceiverId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_Connections_RequesterId_Status",
                table: "Connections",
                columns: new[] { "RequesterId", "Status" });

            // GIN index cannot be expressed with HasIndex() — must use raw SQL
            migrationBuilder.Sql(
                """CREATE INDEX "IX_Profiles_Skills_GIN" ON "Profiles" USING GIN ("Skills");""");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Connections_ReceiverId_Status",
                table: "Connections");

            migrationBuilder.DropIndex(
                name: "IX_Connections_RequesterId_Status",
                table: "Connections");

            migrationBuilder.Sql(
                """DROP INDEX IF EXISTS "IX_Profiles_Skills_GIN";""");
        }
    }
}
