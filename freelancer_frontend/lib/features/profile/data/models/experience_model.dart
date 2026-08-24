// Experience ka data model — backend ke ExperienceResponseDto se match
class ExperienceModel {
  final String id;
  final String title;
  final String company;
  final DateTime startDate;
  final DateTime? endDate;     // null = current position
  final String? description;

  ExperienceModel({
    required this.id,
    required this.title,
    required this.company,
    required this.startDate,
    this.endDate,
    this.description,
  });

  factory ExperienceModel.fromJson(Map<String, dynamic> json) {
    return ExperienceModel(
      id: json['id'],
      title: json['title'],
      company: json['company'],
      // backend DateOnly bhejta hai — "2024-01-15" format, DateTime.parse chalega
      startDate: DateTime.parse(json['startDate']),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      description: json['description'],
    );
  }
}

// Add/update request — backend ka ExperienceRequestDto (dono ke liye same shape)
class AddExperienceRequest {
  final String title;
  final String company;
  final DateTime startDate;
  final DateTime? endDate;     // null = current position
  final String? description;

  AddExperienceRequest({
    required this.title,
    required this.company,
    required this.startDate,
    this.endDate,
    this.description,
  });

  // DateOnly sirf "yyyy-MM-dd" leta hai — time part hata do
  static String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'company': company,
      'startDate': _dateOnly(startDate),
      if (endDate != null) 'endDate': _dateOnly(endDate!),
      if (description != null) 'description': description,
    };
  }
}
