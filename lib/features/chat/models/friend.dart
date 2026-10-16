class Friend {
  Friend({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.imageUrl,
    this.isFavorite = false,
    this.isHidden = false,
    this.isDeleted = false,
    this.aiRole,
    this.traits,
    this.assistantInstructions = const [],
  });

  final String id;
  final String name;
  final String description;
  final String type; // 'human' or 'ai'
  final String? imageUrl;
  bool isFavorite;
  bool isHidden;
  final bool isDeleted;
  final String? aiRole;
  final String? traits;
  final List<String> assistantInstructions;

  bool get isAi => type == 'ai';

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'type': type,
        'imageUrl': imageUrl,
        'isFavorite': isFavorite,
        'isHidden': isHidden,
        'isDeleted': isDeleted,
        'aiRole': aiRole,
        'traits': traits,
        'assistantInstructions': assistantInstructions,
      };

  factory Friend.fromMap(Map<String, dynamic> map, String docId) => Friend(
        id: docId,
        name: map['name'] as String? ?? '친구',
        description: map['description'] as String? ?? '',
        type: map['type'] as String? ?? 'human',
        imageUrl: map['imageUrl'] as String?,
        isFavorite: map['isFavorite'] as bool? ?? false,
        isHidden: map['isHidden'] as bool? ?? false,
        isDeleted: map['isDeleted'] as bool? ?? false,
        aiRole: map['aiRole'] as String?,
        traits: map['traits'] as String?,
        assistantInstructions: (map['assistantInstructions'] as List?)
                ?.whereType<String>()
                .toList() ??
            <String>[],
      );
}
