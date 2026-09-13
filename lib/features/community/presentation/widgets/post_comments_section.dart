import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/post_model.dart';
import '../../data/repositories/community_repository.dart';

/// Comment thread under one community post.
///
/// Port of the web's `StudentCommunityPostComments`: a collapsed count that
/// expands into the thread, a composer, a like button per comment and a delete
/// button on the student's own comments. The repository already spoke to
/// `GET /v1/post?parent_id=` — only this UI was missing, so app students could
/// see a post but never its replies.
class PostCommentsSection extends StatefulWidget {
  const PostCommentsSection({
    super.key,
    required this.post,
    required this.currentUserId,
    this.readOnly = false,
    this.onChanged,
  });

  final Post post;

  /// Id of the signed-in student, used to decide which comments they may
  /// delete. `null` while the profile is still loading.
  final String? currentUserId;

  final bool readOnly;

  /// Called after a comment is added or removed, so the host can refresh the
  /// post's own counters.
  final Future<void> Function()? onChanged;

  @override
  State<PostCommentsSection> createState() => _PostCommentsSectionState();
}

class _PostCommentsSectionState extends State<PostCommentsSection> {
  final _repository = CommunityRepository();
  final _composerController = TextEditingController();

  bool _expanded = false;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _error;
  List<Post> _comments = const [];

  /// Local count so the header updates immediately after a post or delete,
  /// without waiting for the parent feed to refetch.
  late int _count = widget.post.attributes.commentsCount;

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final next = !_expanded;
    setState(() => _expanded = next);
    if (next && _comments.isEmpty) await _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _repository.getComments(widget.post.id);

    if (!mounted) return;

    if (result['success'] != true) {
      setState(() {
        _isLoading = false;
        _error = result['message']?.toString();
      });
      return;
    }

    // The endpoint can echo the parent back, so rows are re-checked against
    // `parent_id` the same way the web filters them.
    final comments = ((result['data'] as List?) ?? const [])
        .whereType<Post>()
        .where((c) => c.attributes.parentId == widget.post.id)
        .toList()
      ..sort((a, b) =>
          a.attributes.createdAt.compareTo(b.attributes.createdAt));

    setState(() {
      _isLoading = false;
      _comments = comments;
      _count = comments.length;
    });
  }

  Future<void> _submit() async {
    final content = _composerController.text.trim();
    if (content.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    final result = await _repository.addComment(
      postId: widget.post.id,
      content: content,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] != true) {
      _showMessage(result['message']?.toString() ?? 'community.comment_failed'.tr());
      return;
    }

    _composerController.clear();
    await _load();
    await widget.onChanged?.call();
  }

  Future<void> _delete(Post comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('community.delete_comment_title'.tr()),
        content: Text('community.delete_comment_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('profile.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'community.delete'.tr(),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await _repository.deleteComment(comment.id);
    if (!mounted) return;

    if (result['success'] != true) {
      _showMessage(result['message']?.toString() ?? 'community.delete_failed'.tr());
      return;
    }

    await _load();
    await widget.onChanged?.call();
  }

  Future<void> _react(Post comment) async {
    final result = await _repository.reactToPost(comment.id, 'like');
    if (!mounted) return;
    if (result['success'] != true) {
      _showMessage(result['message']?.toString() ?? 'community.reaction_failed'.tr());
      return;
    }
    await _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  bool _canDelete(Post comment) {
    final userId = widget.currentUserId;
    if (userId == null) return false;
    return comment.attributes.user?.id == userId;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            child: Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                Text(
                  _expanded
                      ? 'community.hide_comments'.tr(args: ['$_count'])
                      : 'community.show_comments'.tr(args: ['$_count']),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_error != null)
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              )
            else if (_comments.isEmpty)
              Text(
                'community.no_comments_yet'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF64748B),
                ),
              )
            else
              ..._comments.map(_buildComment),
            if (!widget.readOnly) ...[
              const SizedBox(height: 12),
              _buildComposer(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildComment(Post comment) {
    final author = comment.attributes.user?.attributes;
    final name = author == null || author.fullName.trim().isEmpty
        ? 'community.unknown_user'.tr()
        : author.fullName.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (_canDelete(comment))
                InkWell(
                  onTap: () => _delete(comment),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            comment.attributes.content,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: widget.readOnly ? null : () => _react(comment),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.thumb_up_outlined,
                  size: 14,
                  color: comment.attributes.userReaction == null
                      ? const Color(0xFF94A3B8)
                      : AppColors.primaryBlue,
                ),
                const SizedBox(width: 4),
                Text(
                  '${comment.attributes.reactionsCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _composerController,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'community.write_comment'.tr(),
              hintStyle: const TextStyle(fontSize: 13),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primaryBlue, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, color: AppColors.primaryBlue),
        ),
      ],
    );
  }
}
