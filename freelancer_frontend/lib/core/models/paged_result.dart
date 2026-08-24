// Backend ka reusable pagination envelope — generic taake saare list endpoints
// isi ko use karein. itemFromJson mapper se koi bhi T parse ho jata hai.
class PagedResult<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int totalCount;
  final int totalPages;
  final bool hasNextPage;

  const PagedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.totalPages,
    required this.hasNextPage,
  });

  factory PagedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) =>
      PagedResult(
        items: (json['items'] as List)
            .map((e) => itemFromJson(e as Map<String, dynamic>))
            .toList(),
        page: json['page'] as int,
        pageSize: json['pageSize'] as int,
        totalCount: json['totalCount'] as int,
        totalPages: json['totalPages'] as int,
        hasNextPage: json['hasNextPage'] as bool,
      );
}
