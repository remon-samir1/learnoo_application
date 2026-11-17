import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/services/share_link_service.dart';
import '../../../core/services/student_scope.dart';
import '../../course_content/presentation/screens/live_session_detail_screen.dart';
import '../../exams/data/exam_repository.dart';
import '../../exams/domain/usecases/exam_access_usecase.dart';
import '../../exams/models/quiz_models.dart';

/// Opens a shared exam / live session link above the student's home screen,
/// the same way a tap on that exam or session inside the app does: a live
/// session opens its page (join, not started yet, or the activate step); an
/// exam goes through [ExamAccessUseCase] (exam notice, activation code, or
/// "activate the course first").
Future<void> openShareLink(BuildContext context, ShareLinkTarget target) async {
  switch (target) {
    case LiveSessionLinkTarget(:final id):
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LiveSessionDetailScreen(roomId: id)),
      );
    case ExamLinkTarget(:final id):
      final result = await ExamRepository().getQuizById(int.parse(id));
      final quiz = result['data'];
      if (result['success'] != true || quiz is! Quiz) {
        if (context.mounted) {
          _message(
            context,
            result['message']?.toString() ?? 'exams.exam_not_found'.tr(),
          );
        }
        return;
      }
      final StudentScope scope;
      try {
        scope = await StudentScopeService().load();
      } catch (_) {
        if (context.mounted) _message(context, 'exams.load_exam_failed'.tr());
        return;
      }
      if (!context.mounted) return;
      await ExamAccessUseCase().handleExamAccess(
        context: context,
        quiz: quiz,
        enrolledCourseIds: scope.enrolledCourseIds,
      );
  }
}

void _message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
