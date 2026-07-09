// Backend ke UserRole enum se EXACT match (Freelancer=0, Client=1)
// Values match hona zaroori — API integration mein yehi numbers jayenge
enum UserRole {
  freelancer(0, 'Freelancer', 'Find work & grow your career'),
  client(1, 'Client', 'Hire verified talent worldwide');

  final int value;
  final String label;
  final String description;
  const UserRole(this.value, this.label, this.description);
}