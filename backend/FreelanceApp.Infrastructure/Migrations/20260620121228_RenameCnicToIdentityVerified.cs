using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class RenameCnicToIdentityVerified : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "IsCnicVerified",
                table: "Users",
                newName: "IsIdentityVerified");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "IsIdentityVerified",
                table: "Users",
                newName: "IsCnicVerified");
        }
    }
}
