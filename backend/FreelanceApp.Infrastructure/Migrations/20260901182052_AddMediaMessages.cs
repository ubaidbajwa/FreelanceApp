using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddMediaMessages : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "MediaDurationMs",
                table: "Messages",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "MediaHeight",
                table: "Messages",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "MediaMimeType",
                table: "Messages",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "MediaPublicId",
                table: "Messages",
                type: "character varying(255)",
                maxLength: 255,
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "MediaSizeBytes",
                table: "Messages",
                type: "bigint",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "MediaThumbnailUrl",
                table: "Messages",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "MediaUrl",
                table: "Messages",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "MediaWidth",
                table: "Messages",
                type: "integer",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "MediaDurationMs",
                table: "Messages");

            migrationBuilder.DropColumn(
                name: "MediaHeight",
                table: "Messages");

            migrationBuilder.DropColumn(
                name: "MediaMimeType",
                table: "Messages");

            migrationBuilder.DropColumn(
                name: "MediaPublicId",
                table: "Messages");

            migrationBuilder.DropColumn(
                name: "MediaSizeBytes",
                table: "Messages");

            migrationBuilder.DropColumn(
                name: "MediaThumbnailUrl",
                table: "Messages");

            migrationBuilder.DropColumn(
                name: "MediaUrl",
                table: "Messages");

            migrationBuilder.DropColumn(
                name: "MediaWidth",
                table: "Messages");
        }
    }
}
