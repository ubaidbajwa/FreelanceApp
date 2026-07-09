using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddIdentityVerification : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "IdentityVerifications",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    DocumentType = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    FrontImageUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    BackImageUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    SelfieImageUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    ExtractedFullName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ExtractedDocumentNumber = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    ExtractedDateOfBirth = table.Column<DateOnly>(type: "date", nullable: true),
                    FaceMatchScore = table.Column<double>(type: "double precision", nullable: true),
                    RejectionReason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    AttemptCount = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    VerifiedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_IdentityVerifications", x => x.Id);
                    table.ForeignKey(
                        name: "FK_IdentityVerifications_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_IdentityVerifications_UserId",
                table: "IdentityVerifications",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "IdentityVerifications");
        }
    }
}
