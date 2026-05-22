class SocialLink {
  final String id;
  final String type;
  final SocialLinkAttributes attributes;

  String get link => attributes.link;

  SocialLink({
    required this.id,
    required this.type,
    required this.attributes,
  });

  factory SocialLink.fromJson(Map<String, dynamic> json) {
    return SocialLink(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'social-links',
      attributes: SocialLinkAttributes.fromJson(json['attributes'] ?? {}),
      
    );
  }
}

class SocialLinkAttributes {
  final List<SocialLinkCourse> courses;
  final String icon;
  final String title;
  final String subtitle;
  final String? color;
  final String link;
  final bool status;
  final DateTime createdAt;
  final DateTime updatedAt;

  SocialLinkAttributes({
    required this.courses,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color,
    required this.link,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SocialLinkAttributes.fromJson(Map<String, dynamic> json) {
    final coursesList = json['courses'] as List<dynamic>?;
    return SocialLinkAttributes(
      courses: coursesList?.map((c) => SocialLinkCourse.fromJson(c)).toList() ?? [],
      icon: json['icon']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      color: json['color']?.toString(),
      link: json['link']?.toString() ?? '',
      status: json['status'] ?? false,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  bool hasCourse(String courseId) {
    return courses.any((c) => c.id == courseId);
  }
}

class SocialLinkCourse {
  final String id;
  final String type;
  final SocialLinkCourseAttributes attributes;

  SocialLinkCourse({
    required this.id,
    required this.type,
    required this.attributes,
  });

  factory SocialLinkCourse.fromJson(Map<String, dynamic> json) {
    return SocialLinkCourse(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'courses',
      attributes: SocialLinkCourseAttributes.fromJson(json['attributes'] ?? {}),
    );
  }
}

class SocialLinkCourseAttributes {
  final String title;
  final String subTitle;
  final String description;
  final String thumbnail;

  SocialLinkCourseAttributes({
    required this.title,
    required this.subTitle,
    required this.description,
    required this.thumbnail,
  });

  factory SocialLinkCourseAttributes.fromJson(Map<String, dynamic> json) {
    return SocialLinkCourseAttributes(
      title: json['title']?.toString() ?? '',
      subTitle: json['sub_title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
    );
  }
}
