using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FreelanceApp.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddJobPreferencesToProfile : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // defaultValueSql: existing rows ke liye empty array — warna NOT NULL
            // add karna null-values error deta hai (23502) jab table mein rows hon
            migrationBuilder.AddColumn<List<string>>(
                name: "DesiredJobLocations",
                table: "Profiles",
                type: "text[]",
                nullable: false,
                defaultValueSql: "'{}'");

            migrationBuilder.AddColumn<List<string>>(
                name: "DesiredJobTitles",
                table: "Profiles",
                type: "text[]",
                nullable: false,
                defaultValueSql: "'{}'");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DesiredJobLocations",
                table: "Profiles");

            migrationBuilder.DropColumn(
                name: "DesiredJobTitles",
                table: "Profiles");
        }
    }
}
