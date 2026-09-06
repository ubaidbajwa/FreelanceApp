using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddMessageFileName : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "MediaFileName",
                table: "Messages",
                type: "character varying(255)",
                maxLength: 255,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "MediaFileName",
                table: "Messages");
        }
    }
}
