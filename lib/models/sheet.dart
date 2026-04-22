final class Sheet {
  final int? id;
  final String name;
  final String path;
  final String? composer;
  final String? arranger;
  final String? genre;
  final String? period;
  final String? key;
  final String? difficulty;
  final String? notes;
  final DateTime lastOpened;
  final DateTime createdAt;

  const Sheet({
    this.id,
    required this.name,
    required this.path,
    this.composer,
    this.arranger,
    this.genre,
    this.period,
    this.key,
    this.difficulty,
    this.notes,
    required this.lastOpened,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'path': path,
    'composer': composer,
    'arranger': arranger,
    'genre': genre,
    'period': period,
    'key': key,
    'difficulty': difficulty,
    'notes': notes,
    'last_opened': lastOpened.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory Sheet.fromMap(Map<String, dynamic> map) => Sheet(
    id: map['id'] as int?,
    name: map['name'] as String,
    path: map['path'] as String,
    composer: map['composer'] as String?,
    arranger: map['arranger'] as String?,
    genre: map['genre'] as String?,
    period: map['period'] as String?,
    key: map['key'] as String?,
    difficulty: map['difficulty'] as String?,
    notes: map['notes'] as String?,
    lastOpened: DateTime.parse(map['last_opened'] as String),
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  Sheet copyWith({
    int? id,
    String? name,
    String? path,
    String? composer,
    String? arranger,
    String? genre,
    String? period,
    String? key,
    String? difficulty,
    String? notes,
    DateTime? lastOpened,
    DateTime? createdAt,
  }) =>
      Sheet(
        id: id ?? this.id,
        name: name ?? this.name,
        path: path ?? this.path,
        composer: composer ?? this.composer,
        arranger: arranger ?? this.arranger,
        genre: genre ?? this.genre,
        period: period ?? this.period,
        key: key ?? this.key,
        difficulty: difficulty ?? this.difficulty,
        notes: notes ?? this.notes,
        lastOpened: lastOpened ?? this.lastOpened,
        createdAt: createdAt ?? this.createdAt,
      );

  String get subtitle {
    final parts = <String>[
      if (composer != null && composer!.isNotEmpty) composer!,
      if (period != null && period!.isNotEmpty) period!,
      if (key != null && key!.isNotEmpty) key!,
    ];
    return parts.join(' · ');
  }
}
