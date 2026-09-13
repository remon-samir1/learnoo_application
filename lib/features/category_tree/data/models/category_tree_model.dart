import 'package:equatable/equatable.dart';
import '../../../../core/utils/coerce.dart';

/// Stats attached to a category (counts of courses & students).
class CategoryStats extends Equatable {
  final int coursesCount;
  final int studentsCount;

  const CategoryStats({
    this.coursesCount = 0,
    this.studentsCount = 0,
  });

  factory CategoryStats.fromJson(dynamic json) {
    if (json is! Map) return const CategoryStats();
    return CategoryStats(
      coursesCount: coerceInt(json['courses']),
      studentsCount: coerceInt(json['students']),
    );
  }

  Map<String, dynamic> toJson() => {
        'courses': coursesCount,
        'students': studentsCount,
      };

  @override
  List<Object?> get props => [coursesCount, studentsCount];
}

/// Stats attached to a course (counts of notes, lectures, students).
class CourseStats extends Equatable {
  final int notesCount;
  final int lecturesCount;
  final int studentsCount;

  const CourseStats({
    this.notesCount = 0,
    this.lecturesCount = 0,
    this.studentsCount = 0,
  });

  factory CourseStats.fromJson(dynamic json) {
    if (json is! Map) return const CourseStats();
    return CourseStats(
      notesCount: coerceInt(json['notes']),
      lecturesCount: coerceInt(json['lectures']),
      studentsCount: coerceInt(json['students']),
    );
  }

  Map<String, dynamic> toJson() => {
        'notes': notesCount,
        'lectures': lecturesCount,
        'students': studentsCount,
      };

  @override
  List<Object?> get props => [notesCount, lecturesCount, studentsCount];
}

/// A course item nested inside a category.
class CourseItem extends Equatable {
  final String id;
  final String title;
  final String? subTitle;
  final String? thumbnail;
  final bool isLocked;
  final dynamic status;
  final String? price;
  final String? description;
  final CourseStats stats;

  const CourseItem({
    required this.id,
    required this.title,
    this.subTitle,
    this.thumbnail,
    this.isLocked = false,
    this.status = 1,
    this.price,
    this.description,
    this.stats = const CourseStats(),
  });

  /// Check whether the course is active:
  /// status == 1 || status == "active" || status == true || status == null
  bool get isActive {
    if (status == null) return true;
    if (status == 1 || status == '1') return true;
    if (status == true) return true;
    if (status is String && status.toString().trim().toLowerCase() == 'active') {
      return true;
    }
    return false;
  }

  factory CourseItem.fromJson(dynamic json) {
    if (json is! Map) {
      return const CourseItem(id: '', title: '');
    }

    final raw = json['data'] is Map ? json['data'] as Map : json;
    final id = coerceId(raw['id']) ?? '';
    final attrs = raw['attributes'] is Map
        ? Map<String, dynamic>.from(raw['attributes'])
        : Map<String, dynamic>.from(raw);

    final title = coerceString(attrs['title']) ??
        coerceString(attrs['name']) ??
        'Untitled Course';
    final subTitle = coerceString(attrs['sub_title']) ??
        coerceString(attrs['subtitle']) ??
        coerceString(attrs['description']);
    final thumbnail = coerceString(attrs['thumbnail']) ??
        coerceString(attrs['image']) ??
        coerceString(attrs['cover_image']);
    final isLocked = coerceFlag(attrs['is_locked']);
    final status = attrs['status'];
    final price = coerceString(attrs['price']);
    final description = coerceString(attrs['description']);
    final stats = CourseStats.fromJson(attrs['stats']);

    return CourseItem(
      id: id,
      title: title,
      subTitle: subTitle,
      thumbnail: thumbnail,
      isLocked: isLocked,
      status: status,
      price: price,
      description: description,
      stats: stats,
    );
  }

  CourseItem copyWith({
    String? id,
    String? title,
    String? subTitle,
    String? thumbnail,
    bool? isLocked,
    dynamic status,
    String? price,
    String? description,
    CourseStats? stats,
  }) {
    return CourseItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subTitle: subTitle ?? this.subTitle,
      thumbnail: thumbnail ?? this.thumbnail,
      isLocked: isLocked ?? this.isLocked,
      status: status ?? this.status,
      price: price ?? this.price,
      description: description ?? this.description,
      stats: stats ?? this.stats,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        subTitle,
        thumbnail,
        isLocked,
        status,
        price,
        description,
        stats,
      ];
}

/// Category node in the educational hierarchy.
class Category extends Equatable {
  final String id;
  final String name;
  final String? image;
  final String? parentId;
  final int? order;
  final CategoryStats stats;
  final List<Category> childrens;
  final List<CourseItem> courses;

  const Category({
    required this.id,
    required this.name,
    this.image,
    this.parentId,
    this.order,
    this.stats = const CategoryStats(),
    this.childrens = const [],
    this.courses = const [],
  });

  factory Category.fromJson(dynamic json) {
    if (json is! Map) {
      return const Category(id: '', name: '');
    }

    final id = coerceId(json['id']) ?? '';
    final attrs = json['attributes'] is Map
        ? Map<String, dynamic>.from(json['attributes'])
        : Map<String, dynamic>.from(json);

    final name = coerceString(attrs['name']) ??
        coerceString(attrs['title']) ??
        'Untitled Category';
    final image = coerceString(attrs['image']) ??
        coerceString(attrs['thumbnail']) ??
        coerceString(attrs['icon']);

    // Extract parent_id: direct attribute, or nested parent.data.id
    String? parentId = coerceId(attrs['parent_id']);
    if (parentId == null) {
      final parent = attrs['parent'];
      if (parent is Map && parent['data'] is Map) {
        parentId = coerceId(parent['data']['id']);
      }
    }
    if (parentId == null && json['parent_id'] != null) {
      parentId = coerceId(json['parent_id']);
    }

    final order = coerceInt(attrs['order']);
    final stats = CategoryStats.fromJson(attrs['stats']);

    // Parse childrens (supports 'childrens' and 'children', plus data envelope)
    final rawChildren = attrs['childrens'] ?? attrs['children'] ?? json['childrens'] ?? json['children'];
    final List<Category> parsedChildren = [];
    final childrenList = rawChildren is List
        ? rawChildren
        : (rawChildren is Map && rawChildren['data'] is List
            ? rawChildren['data'] as List
            : null);
    if (childrenList != null) {
      for (final child in childrenList) {
        if (child is Map) {
          parsedChildren.add(Category.fromJson(child));
        }
      }
    }

    // Parse courses (supports direct list, or JSON:API data envelope)
    final rawCourses = attrs['courses'] ?? json['courses'];
    final List<CourseItem> parsedCourses = [];
    final coursesList = rawCourses is List
        ? rawCourses
        : (rawCourses is Map && rawCourses['data'] is List
            ? rawCourses['data'] as List
            : null);
    if (coursesList != null) {
      for (final course in coursesList) {
        if (course is Map) {
          parsedCourses.add(CourseItem.fromJson(course));
        }
      }
    }

    return Category(
      id: id,
      name: name,
      image: image,
      parentId: parentId,
      order: order,
      stats: stats,
      childrens: parsedChildren,
      courses: parsedCourses,
    );
  }

  Category copyWith({
    String? id,
    String? name,
    String? image,
    String? parentId,
    int? order,
    CategoryStats? stats,
    List<Category>? childrens,
    List<CourseItem>? courses,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      image: image ?? this.image,
      parentId: parentId ?? this.parentId,
      order: order ?? this.order,
      stats: stats ?? this.stats,
      childrens: childrens ?? this.childrens,
      courses: courses ?? this.courses,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        image,
        parentId,
        order,
        stats,
        childrens,
        courses,
      ];
}
