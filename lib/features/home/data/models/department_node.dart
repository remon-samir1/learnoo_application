/// Department model with support for recursive children
class DepartmentNode {
  final String id;
  final String name;
  final String? image;
  final int? order;
  final String? parentId;
  final String? parentType;
  final Map<String, dynamic> stats;
  final List<dynamic> courses;
  final List<DepartmentNode> children;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DepartmentNode({
    required this.id,
    required this.name,
    this.image,
    this.order,
    this.parentId,
    this.parentType,
    this.stats = const {},
    this.courses = const [],
    this.children = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory DepartmentNode.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] ?? {};

    // Parse parent info
    String? parentId;
    String? parentType;
    final parent = attributes['parent'] as Map<String, dynamic>?;
    if (parent != null) {
      final parentData = parent['data'] as Map<String, dynamic>?;
      if (parentData != null) {
        parentId = parentData['id']?.toString();
        parentType = parentData['type']?.toString();
      }
    }

    // Fallback to parent_id
    if (parentId == null) {
      parentId = attributes['parent_id']?.toString();
    }

    return DepartmentNode(
      id: json['id']?.toString() ?? '',
      name: attributes['name']?.toString() ?? '',
      image: attributes['image']?.toString(),
      order: attributes['order'] as int?,
      parentId: parentId,
      parentType: parentType,
      stats: attributes['stats'] as Map<String, dynamic>? ?? {},
      courses: attributes['courses'] as List<dynamic>? ?? [],
      children: const [], // Populated by tree builder
      createdAt: _parseDateTime(attributes['created_at']),
      updatedAt: _parseDateTime(attributes['updated_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  DepartmentNode copyWith({
    String? id,
    String? name,
    String? image,
    int? order,
    String? parentId,
    String? parentType,
    Map<String, dynamic>? stats,
    List<dynamic>? courses,
    List<DepartmentNode>? children,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DepartmentNode(
      id: id ?? this.id,
      name: name ?? this.name,
      image: image ?? this.image,
      order: order ?? this.order,
      parentId: parentId ?? this.parentId,
      parentType: parentType ?? this.parentType,
      stats: stats ?? this.stats,
      courses: courses ?? this.courses,
      children: children ?? this.children,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': 'department',
      'attributes': {
        'name': name,
        'image': image,
        'order': order,
        'parent_id': parentId,
        'stats': stats,
        'courses': courses,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'parent': parentId != null
            ? {
                'data': {'id': parentId, 'type': parentType ?? 'faculty'}
              }
            : null,
      },
      'children': children.map((c) => c.toJson()).toList(),
    };
  }
}
