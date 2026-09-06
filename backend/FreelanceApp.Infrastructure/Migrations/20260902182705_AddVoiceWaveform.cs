using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddVoiceWaveform : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "MediaWaveform",
                table: "Messages",
                type: "character varying(512)",
                maxLength: 512,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "MediaWaveform",
                table: "Messages");
        }
    }
}
