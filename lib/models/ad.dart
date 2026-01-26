class Ad {
  final String id;
  final String type; // 'image' or 'video'
  final String url;
  final int duration; // seconds
  final List<String> assignedTablets;

  Ad({
    required this.id,
    required this.type,
    required this.url,
    required this.duration,
    required this.assignedTablets,
  });

  factory Ad.fromMap(String id, Map<String, dynamic> map) {
    return Ad(
      id: id,
      type: map['type'] ?? 'image',
      url: map['url'] ?? '',
      duration: (map['duration'] ?? 10) as int,
      assignedTablets: List<String>.from(map['assignedTablets'] ?? []),
    );
  }
}
