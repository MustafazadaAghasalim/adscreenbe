class Ad {
  final String id;
  final String name;
  final int duration;
  final String imageUrl;
  final String type; // 'image' or 'video'
  String? localPath; // For offline playback

  Ad({
    required this.id,
    required this.name,
    required this.duration,
    required this.imageUrl,
    required this.type,
    this.localPath,
  });

  factory Ad.fromJson(Map<String, dynamic> json) {
    return Ad(
      id: json['id'] as String? ?? 'unknown_id', // Firestore doc ID usually injected
      name: json['name'] as String? ?? 'Unknown Ad',
      duration: json['duration'] as int? ?? 15,
      imageUrl: (json['url'] ?? json['imageUrl'] ?? '') as String, // Support both
      type: json['type'] as String? ?? 'image',
      localPath: json['localPath'] as String?,
    );
  }
}
