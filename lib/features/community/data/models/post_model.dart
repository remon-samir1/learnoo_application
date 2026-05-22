// Post Model matching API response structure

class Post {
  final String id;
  final String type;
  final PostAttributes attributes;

  Post({
    required this.id,
    required this.type,
    required this.attributes,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? 'posts',
      attributes: PostAttributes.fromJson(json['attributes'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'attributes': attributes.toJson(),
    };
  }
}

class PostAttributes {
  final PostUser? user;
  final PostCourse? course;
  final String status;
  final String postType;
  final String title;
  final String content;
  final List<String> tags;
  final int reactionsCount;
  final String? userReaction;
  final DateTime createdAt;
  final DateTime updatedAt;

  PostAttributes({
    this.user,
    this.course,
    required this.status,
    required this.postType,
    required this.title,
    required this.content,
    required this.tags,
    required this.reactionsCount,
    this.userReaction,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PostAttributes.fromJson(Map<String, dynamic> json) {
    final userData = json['user']?['data'];
    final courseData = json['course']?['data'];

    return PostAttributes(
      user: userData != null ? PostUser.fromJson(userData) : null,
      course: courseData != null ? PostCourse.fromJson(courseData) : null,
      status: json['status'] ?? 'draft',
      postType: json['type'] ?? 'post',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      reactionsCount: json['reactions_count'] ?? 0,
      userReaction: json['user_reaction'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'type': postType,
      'title': title,
      'content': content,
      'tags': tags,
      'reactions_count': reactionsCount,
      'user_reaction': userReaction,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class PostUser {
  final String id;
  final String type;
  final UserAttributes attributes;

  PostUser({
    required this.id,
    required this.type,
    required this.attributes,
  });

  factory PostUser.fromJson(Map<String, dynamic> json) {
    return PostUser(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? 'users',
      attributes: UserAttributes.fromJson(json['attributes'] ?? {}),
    );
  }
}

class UserAttributes {
  final String firstName;
  final String lastName;
  final int? phone;
  final String role;
  final String email;
  final String? emailVerifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserAttributes({
    required this.firstName,
    required this.lastName,
    this.phone,
    required this.role,
    required this.email,
    this.emailVerifiedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserAttributes.fromJson(Map<String, dynamic> json) {
    return UserAttributes(
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      phone: json['phone'],
      role: json['role'] ?? 'Student',
      email: json['email'] ?? '',
      emailVerifiedAt: json['email_verified_at'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  String get fullName => '$firstName $lastName';
}

class PostCourse {
  final String id;
  final String type;
  final CourseAttributes attributes;

  PostCourse({
    required this.id,
    required this.type,
    required this.attributes,
  });

  factory PostCourse.fromJson(Map<String, dynamic> json) {
    return PostCourse(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? 'courses',
      attributes: CourseAttributes.fromJson(json['attributes'] ?? {}),
    );
  }
}

class CourseAttributes {
  final String title;
  final String subTitle;
  final String description;
  final String thumbnail;
  final String objectives;
  final String price;
  final int maxViewsPerStudent;
  final String visibility;
  final int approval;
  final int status;
  final String reason;

  CourseAttributes({
    required this.title,
    required this.subTitle,
    required this.description,
    required this.thumbnail,
    required this.objectives,
    required this.price,
    required this.maxViewsPerStudent,
    required this.visibility,
    required this.approval,
    required this.status,
    required this.reason,
  });

  factory CourseAttributes.fromJson(Map<String, dynamic> json) {
    return CourseAttributes(
      title: json['title'] ?? '',
      subTitle: json['sub_title'] ?? '',
      description: json['description'] ?? '',
      thumbnail: json['thumbnail'] ?? '',
      objectives: json['objectives'] ?? '',
      price: json['price'] ?? '0',
      maxViewsPerStudent: json['max_views_per_student'] ?? 0,
      visibility: json['visibility'] ?? 'public',
      approval: json['approval'] ?? 0,
      status: json['status'] ?? 0,
      reason: json['reason'] ?? '',
    );
  }
}

// Reaction types
enum ReactionType {
  like,
  love,
  haha,
  wow,
  sad,
  angry;

  String get value {
    switch (this) {
      case ReactionType.like:
        return 'like';
      case ReactionType.love:
        return 'love';
      case ReactionType.haha:
        return 'haha';
      case ReactionType.wow:
        return 'wow';
      case ReactionType.sad:
        return 'sad';
      case ReactionType.angry:
        return 'angry';
    }
  }

  static ReactionType? fromString(String? value) {
    if (value == null) return null;
    switch (value) {
      case 'like':
        return ReactionType.like;
      case 'love':
        return ReactionType.love;
      case 'haha':
        return ReactionType.haha;
      case 'wow':
        return ReactionType.wow;
      case 'sad':
        return ReactionType.sad;
      case 'angry':
        return ReactionType.angry;
      default:
        return null;
    }
  }
}

// Request models
class CreatePostRequest {
  final int? courseId;
  final String postType;
  final String title;
  final String content;
  final List<String> tags;

  CreatePostRequest({
    this.courseId,
    required this.postType,
    required this.title,
    required this.content,
    required this.tags,
  });

  Map<String, dynamic> toJson() {
    return {
      if (courseId != null) 'course_id': courseId,
      'type': postType,
      'title': title,
      'content': content,
      'tags': tags,
    };
  }
}

class ReactionRequest {
  final String type;

  ReactionRequest({required this.type});

  Map<String, dynamic> toJson() {
    return {'type': type};
  }
}
