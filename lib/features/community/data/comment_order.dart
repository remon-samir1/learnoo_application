import 'models/post_model.dart';

/// The comments of [postId] in conversation order.
///
/// The feed lists posts newest first, but the comments under one post read
/// oldest first, so an answer always sits under the comment it answers — even
/// when the teacher answered with a new comment rather than a reply. Comments
/// saved in the same second keep the order they were saved in (by id). Rows
/// that belong to another post (the endpoint can echo the parent back) are
/// dropped, as on the web.
List<Post> commentsOldestFirst(Iterable<Post> rows, String postId) {
  final comments = rows.where((c) => c.attributes.parentId == postId).toList();
  comments.sort((a, b) {
    final byDate = a.attributes.createdAt.compareTo(b.attributes.createdAt);
    if (byDate != 0) return byDate;
    final ia = int.tryParse(a.id);
    final ib = int.tryParse(b.id);
    if (ia != null && ib != null) return ia.compareTo(ib);
    return a.id.compareTo(b.id);
  });
  return comments;
}
