import '../../../../core/network/api_constants.dart';
import 'social_link_model.dart';

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
    final rawAttrs = json['attributes'];
    final attrs = rawAttrs is Map
        ? Map<String, dynamic>.from(rawAttrs)
        : (json.containsKey('title') || json.containsKey('content') ? json : <String, dynamic>{});
    return Post(
      id: json['id']?.toString() ?? attrs['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'posts',
      attributes: PostAttributes.fromJson(attrs),
    );
  }

  Post copyWith({
    String? id,
    String? type,
    PostAttributes? attributes,
  }) {
    return Post(
      id: id ?? this.id,
      type: type ?? this.type,
      attributes: attributes ?? this.attributes,
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

  /// Replies on this post. The API counts them for us; the app used to have to
  /// fetch the whole thread to know whether a post had any.
  final int commentsCount;

  /// Set on a reply, pointing at the thread it belongs to. `null` on a
  /// top-level post — which is how the web tells the two apart.
  final String? parentId;

  /// Course this post is attached to, `null` for a general post.
  final String? courseId;

  final String? userReaction;
  final List<SocialLink> socialLinks;
  final List<String> images; // post image attachments
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
    this.commentsCount = 0,
    this.parentId,
    this.courseId,
    this.userReaction,
    this.socialLinks = const [],
    this.images = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory PostAttributes.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final rawUserData = rawUser is Map
        ? (rawUser['data'] is Map ? rawUser['data'] : rawUser)
        : null;
    final userData = rawUserData is Map
        ? Map<String, dynamic>.from(rawUserData)
        : null;

    final rawCourse = json['course'];
    final rawCourseData = rawCourse is Map
        ? (rawCourse['data'] is Map ? rawCourse['data'] : rawCourse)
        : null;
    final courseData = rawCourseData is Map
        ? Map<String, dynamic>.from(rawCourseData)
        : null;

    // Parse tags safely whether list or string
    List<String> parsedTags = [];
    final rawTags = json['tags'];
    if (rawTags is List) {
      parsedTags = rawTags.map((e) => e.toString()).toList();
    } else if (rawTags is String && rawTags.isNotEmpty) {
      parsedTags = rawTags.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    // Parse social links if present on post or post's course
    final rawSocialLinks = json['social-links'] ??
        json['social_links'] ??
        courseData?['attributes']?['social-links'] ??
        courseData?['attributes']?['social_links'];
    List<SocialLink> socialLinksList = [];
    if (rawSocialLinks is List) {
      for (final item in rawSocialLinks) {
        if (item is Map) {
          try {
            socialLinksList.add(SocialLink.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
    }

    final postCourse = courseData != null ? PostCourse.fromJson(courseData) : null;
    if (socialLinksList.isEmpty && postCourse != null && postCourse.attributes.socialLinks.isNotEmpty) {
      socialLinksList = postCourse.attributes.socialLinks;
    }

    final imagesList = parsePostImages(json);

    return PostAttributes(
      user: userData != null ? PostUser.fromJson(userData) : null,
      course: postCourse,
      status: json['status']?.toString() ?? 'draft',
      postType: json['type']?.toString() ?? 'post',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      tags: parsedTags,
      reactionsCount: json['reactions_count'] is num
          ? (json['reactions_count'] as num).toInt()
          : (json['reactions'] is List
              ? (json['reactions'] as List).length
              : (int.tryParse('${json['reactions_count'] ?? 0}') ?? 0)),
      commentsCount: json['comments_count'] is num
          ? (json['comments_count'] as num).toInt()
          : (json['comments'] is List
              ? (json['comments'] as List).length
              : (int.tryParse('${json['comments_count'] ?? 0}') ?? 0)),
      parentId: _optionalId(json['parent_id']),
      courseId: _optionalId(json['course_id']) ??
          _optionalId(courseData?['id']),
      userReaction: json['user_reaction']?.toString() ?? json['userReaction']?.toString(),
      socialLinks: socialLinksList,
      images: imagesList,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  PostAttributes copyWith({
    PostUser? user,
    PostCourse? course,
    String? status,
    String? postType,
    String? title,
    String? content,
    List<String>? tags,
    int? reactionsCount,
    int? commentsCount,
    String? parentId,
    String? courseId,
    String? userReaction,
    List<SocialLink>? socialLinks,
    List<String>? images,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostAttributes(
      user: user ?? this.user,
      course: course ?? this.course,
      status: status ?? this.status,
      postType: postType ?? this.postType,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      reactionsCount: reactionsCount ?? this.reactionsCount,
      commentsCount: commentsCount ?? this.commentsCount,
      parentId: parentId ?? this.parentId,
      courseId: courseId ?? this.courseId,
      userReaction: userReaction ?? this.userReaction,
      socialLinks: socialLinks ?? this.socialLinks,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
      'comments_count': commentsCount,
      'parent_id': parentId,
      'course_id': courseId,
      'user_reaction': userReaction,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Collects every displayable image URL on a post's attributes.
///
/// Mirrors the website's `pickPostImageUrl` (src/lib/community-post-media.ts):
/// the dashboard uploads the file as `image`, and the API may echo it back as
/// `image`, `image_url`, `thumbnail`, an `attachment` (string, `{url|path}` or
/// list) or `attachments`. Values can be absolute URLs or paths relative to the
/// API origin, so each one goes through [resolveCommunityMediaUrl].
List<String> parsePostImages(Map<String, dynamic> json) {
  final result = <String>[];

  void addValue(dynamic value) {
    if (value == null) return;
    if (value is String) {
      final url = resolveCommunityMediaUrl(value);
      if (url != null && !_isNonImageFile(url) && !result.contains(url)) {
        result.add(url);
      }
    } else if (value is Map) {
      addValue(value['url'] ??
          value['original_url'] ??
          value['path'] ??
          value['src'] ??
          value['href']);
    } else if (value is List) {
      for (final item in value) {
        addValue(item);
      }
    }
  }

  const keys = [
    'image',
    'image_url',
    'imageUrl',
    'images',
    'thumbnail',
    'thumbnail_url',
    'cover_image',
    'coverImage',
    'media_url',
    'mediaUrl',
    'photo',
    'attachment',
    'attachments',
    'media',
  ];
  for (final key in keys) {
    addValue(json[key]);
  }
  return result;
}

/// Turns an API media value into a loadable URL, or `null` when empty.
String? resolveCommunityMediaUrl(String? raw) {
  final value = raw?.trim().replaceAll('\\', '/');
  if (value == null || value.isEmpty || value == 'null') return null;
  if (value.startsWith('data:')) return value;
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('//')) return 'https:$value';
  final base = ApiConstants.baseUrl.endsWith('/')
      ? ApiConstants.baseUrl.substring(0, ApiConstants.baseUrl.length - 1)
      : ApiConstants.baseUrl;
  return '$base${value.startsWith('/') ? value : '/$value'}';
}

bool _isNonImageFile(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  const nonImage = [
    '.pdf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx', '.zip',
    '.rar', '.mp3', '.wav', '.m4a', '.aac', '.ogg', '.mp4', '.mov', '.webm',
  ];
  return nonImage.any(path.endsWith);
}

/// Normalises an id to a string, treating `null` and `0` as absent — the API
/// uses both for "no parent" and "no course".
String? _optionalId(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text == '0') return null;
  return text;
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
    final rawAttrs = json['attributes'];
    final attrs = rawAttrs is Map
        ? Map<String, dynamic>.from(rawAttrs)
        : <String, dynamic>{};
    return PostUser(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'users',
      attributes: UserAttributes.fromJson(attrs),
    );
  }
}

class UserAttributes {
  final String firstName;
  final String lastName;
  final dynamic phone;
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
      firstName: json['first_name']?.toString() ??
          json['firstName']?.toString() ??
          json['name']?.toString() ??
          '',
      lastName: json['last_name']?.toString() ??
          json['lastName']?.toString() ??
          '',
      phone: json['phone'],
      role: json['role']?.toString() ?? 'Student',
      email: json['email']?.toString() ?? '',
      emailVerifiedAt: json['email_verified_at']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  String get fullName {
    final combined = '$firstName $lastName'.trim();
    return combined.isNotEmpty ? combined : 'User';
  }
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

  PostCourse copyWith({
    String? id,
    String? type,
    CourseAttributes? attributes,
  }) {
    return PostCourse(
      id: id ?? this.id,
      type: type ?? this.type,
      attributes: attributes ?? this.attributes,
    );
  }

  factory PostCourse.fromJson(Map<String, dynamic> json) {
    final rawAttrs = json['attributes'];
    final attrs = rawAttrs is Map
        ? Map<String, dynamic>.from(rawAttrs)
        : json;
    final courseId = json['id']?.toString() ?? attrs['id']?.toString() ?? '';
    final courseType = json['type']?.toString() ?? 'courses';
    final courseAttrs = CourseAttributes.fromJson(attrs);

    // If course has nested posts, attach course info and course social links to each post
    final populatedPosts = courseAttrs.posts.map((p) {
      final needsCourse = p.attributes.course == null;
      final needsCourseId = p.attributes.courseId == null || p.attributes.courseId!.isEmpty;
      final needsSocialLinks = p.attributes.socialLinks.isEmpty && courseAttrs.socialLinks.isNotEmpty;

      if (needsCourse || needsCourseId || needsSocialLinks) {
        return p.copyWith(
          attributes: p.attributes.copyWith(
            course: needsCourse
                ? PostCourse(
                    id: courseId,
                    type: courseType,
                    attributes: courseAttrs.copyWith(posts: const []),
                  )
                : null,
            courseId: needsCourseId ? courseId : null,
            socialLinks: needsSocialLinks ? courseAttrs.socialLinks : null,
          ),
        );
      }
      return p;
    }).toList();

    return PostCourse(
      id: courseId,
      type: courseType,
      attributes: courseAttrs.copyWith(posts: populatedPosts),
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
  final List<SocialLink> socialLinks;
  final List<Post> posts;

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
    this.socialLinks = const [],
    this.posts = const [],
  });

  CourseAttributes copyWith({
    String? title,
    String? subTitle,
    String? description,
    String? thumbnail,
    String? objectives,
    String? price,
    int? maxViewsPerStudent,
    String? visibility,
    int? approval,
    int? status,
    String? reason,
    List<SocialLink>? socialLinks,
    List<Post>? posts,
  }) {
    return CourseAttributes(
      title: title ?? this.title,
      subTitle: subTitle ?? this.subTitle,
      description: description ?? this.description,
      thumbnail: thumbnail ?? this.thumbnail,
      objectives: objectives ?? this.objectives,
      price: price ?? this.price,
      maxViewsPerStudent: maxViewsPerStudent ?? this.maxViewsPerStudent,
      visibility: visibility ?? this.visibility,
      approval: approval ?? this.approval,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      socialLinks: socialLinks ?? this.socialLinks,
      posts: posts ?? this.posts,
    );
  }

  factory CourseAttributes.fromJson(Map<String, dynamic> json) {
    final rawSocialLinks = json['social-links'] ?? json['social_links'] ?? json['socialLinks'];
    List<SocialLink> socialLinksList = [];
    if (rawSocialLinks is List) {
      for (final item in rawSocialLinks) {
        if (item is Map) {
          try {
            socialLinksList.add(SocialLink.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
    }

    // Community posts from course attributes
    final rawPosts = json['posts'];
    List<Post> postsList = [];
    if (rawPosts is List) {
      for (final item in rawPosts) {
        if (item is Map) {
          try {
            postsList.add(Post.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
    }

    return CourseAttributes(
      title: json['title']?.toString() ?? '',
      subTitle: json['sub_title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      objectives: json['objectives']?.toString() ?? '',
      price: json['price']?.toString() ?? '0',
      maxViewsPerStudent: json['max_views_per_student'] is num
          ? (json['max_views_per_student'] as num).toInt()
          : int.tryParse('${json['max_views_per_student'] ?? 0}') ?? 0,
      visibility: json['visibility']?.toString() ?? 'public',
      approval: json['approval'] is num
          ? (json['approval'] as num).toInt()
          : int.tryParse('${json['approval'] ?? 0}') ?? 0,
      status: json['status'] is num
          ? (json['status'] as num).toInt()
          : int.tryParse('${json['status'] ?? 0}') ?? 0,
      reason: json['reason']?.toString() ?? '',
      socialLinks: socialLinksList,
      posts: postsList,
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
