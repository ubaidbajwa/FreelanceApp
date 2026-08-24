using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddSuggestionKindDiscriminator : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_SuggestionDismissals_UserId_DismissedUserId",
                table: "SuggestionDismissals");

            migrationBuilder.AddColumn<int>(
                name: "Kind",
                table: "SuggestionDismissals",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateIndex(
                name: "IX_SuggestionDismissals_UserId_DismissedUserId_Kind",
                table: "SuggestionDismissals",
                columns: new[] { "UserId", "DismissedUserId", "Kind" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_SuggestionDismissals_UserId_DismissedUserId_Kind",
                table: "SuggestionDismissals");

            migrationBuilder.DropColumn(
                name: "Kind",
                table: "SuggestionDismissals");

            migrationBuilder.CreateIndex(
                name: "IX_SuggestionDismissals_UserId_DismissedUserId",
                table: "SuggestionDismissals",
                columns: new[] { "UserId", "DismissedUserId" },
                unique: true);
        }
    }
}
