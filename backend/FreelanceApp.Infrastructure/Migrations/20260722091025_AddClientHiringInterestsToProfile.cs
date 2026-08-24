using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddClientHiringInterestsToProfile : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // defaultValueSql: existing rows ke liye empty array — warna NOT NULL add karna
            // null-values error deta hai (23502) jab table mein rows hon
            migrationBuilder.AddColumn<List<string>>(
                name: "HiringInterests",
                table: "Profiles",
                type: "text[]",
                nullable: false,
                defaultValueSql: "'{}'");

            migrationBuilder.AddColumn<int>(
                name: "HiringType",
                table: "Profiles",
                type: "integer",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "HiringInterests",
                table: "Profiles");

            migrationBuilder.DropColumn(
                name: "HiringType",
                table: "Profiles");
        }
    }
}
