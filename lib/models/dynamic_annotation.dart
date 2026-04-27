enum DynamicAnnotationType {
  pianissimo,
  piano,
  mezzoPiano,
  mezzoForte,
  forte,
  fortissimo,
  crescendo,
  diminuendo,
}

extension DynamicAnnotationTypeLabel on DynamicAnnotationType {
  String get symbol => switch (this) {
    DynamicAnnotationType.pianissimo => 'pp',
    DynamicAnnotationType.piano => 'p',
    DynamicAnnotationType.mezzoPiano => 'mp',
    DynamicAnnotationType.mezzoForte => 'mf',
    DynamicAnnotationType.forte => 'f',
    DynamicAnnotationType.fortissimo => 'ff',
    DynamicAnnotationType.crescendo => '<',
    DynamicAnnotationType.diminuendo => '>',
  };
}

final class DynamicAnnotation {
  final int? id;
  final int sheetId;
  final int pageNumber;
  final DynamicAnnotationType type;
  final double x;
  final double y;
  final DateTime createdAt;

  const DynamicAnnotation({
    this.id,
    required this.sheetId,
    required this.pageNumber,
    required this.type,
    required this.x,
    required this.y,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'sheet_id': sheetId,
    'page_number': pageNumber,
    'type': type.name,
    'x': x,
    'y': y,
    'created_at': createdAt.toIso8601String(),
  };

  factory DynamicAnnotation.fromMap(Map<String, Object?> map) =>
      DynamicAnnotation(
        id: map['id'] as int?,
        sheetId: map['sheet_id'] as int,
        pageNumber: map['page_number'] as int,
        type: DynamicAnnotationType.values.byName(map['type'] as String),
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  DynamicAnnotation copyWith({
    int? id,
    int? sheetId,
    int? pageNumber,
    DynamicAnnotationType? type,
    double? x,
    double? y,
    DateTime? createdAt,
  }) => DynamicAnnotation(
    id: id ?? this.id,
    sheetId: sheetId ?? this.sheetId,
    pageNumber: pageNumber ?? this.pageNumber,
    type: type ?? this.type,
    x: x ?? this.x,
    y: y ?? this.y,
    createdAt: createdAt ?? this.createdAt,
  );
}
