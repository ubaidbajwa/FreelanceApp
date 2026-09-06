using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddMessagePlays : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "MessagePlays",
                columns: table => new
                {
                    MessageId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    PlayedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MessagePlays", x => new { x.MessageId, x.UserId });
                    table.ForeignKey(
                        name: "FK_MessagePlays_Messages_MessageId",
                        column: x => x.MessageId,
                        principalTable: "Messages",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_MessagePlays_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_MessagePlays_MessageId",
                table: "MessagePlays",
                column: "MessageId");

            migrationBuilder.CreateIndex(
                name: "IX_MessagePlays_UserId",
                table: "MessagePlays",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "MessagePlays");
        }
    }
}
