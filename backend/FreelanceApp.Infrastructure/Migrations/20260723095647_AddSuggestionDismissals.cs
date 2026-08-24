using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddSuggestionDismissals : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<List<string>>(
                name: "HiringInterests",
                table: "Profiles",
                type: "text[]",
                nullable: false,
                defaultValueSql: "'{}'",
                oldClrType: typeof(List<string>),
                oldType: "text[]");

            migrationBuilder.CreateTable(
                name: "SuggestionDismissals",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    DismissedUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SuggestionDismissals", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SuggestionDismissals_Users_DismissedUserId",
                        column: x => x.DismissedUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_SuggestionDismissals_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SuggestionDismissals_DismissedUserId",
                table: "SuggestionDismissals",
                column: "DismissedUserId");

            migrationBuilder.CreateIndex(
                name: "IX_SuggestionDismissals_UserId",
                table: "SuggestionDismissals",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_SuggestionDismissals_UserId_DismissedUserId",
                table: "SuggestionDismissals",
                columns: new[] { "UserId", "DismissedUserId" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SuggestionDismissals");

            migrationBuilder.AlterColumn<List<string>>(
                name: "HiringInterests",
                table: "Profiles",
                type: "text[]",
                nullable: false,
                oldClrType: typeof(List<string>),
                oldType: "text[]",
                oldDefaultValueSql: "'{}'");
        }
    }
}
