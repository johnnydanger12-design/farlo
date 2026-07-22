class FaqItem {
  const FaqItem({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    required this.sortOrder,
    required this.categorySortOrder,
  });

  final String id;
  final String category;
  final String question;
  final String answer;
  final int sortOrder;
  final int categorySortOrder;

  factory FaqItem.fromMap(Map<String, dynamic> map) {
    return FaqItem(
      id: map['id'] as String,
      category: map['category'] as String,
      question: map['question'] as String,
      answer: map['answer'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
      categorySortOrder: map['category_sort_order'] as int? ?? 0,
    );
  }
}
