import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/exams/domain/exam_review.dart';
import 'package:learnoo/features/exams/models/quiz_models.dart';

QuizQuestion _question({
  required String id,
  String type = 'single_choice',
  String text = 'Question text',
  List<Map<String, dynamic>> answers = const [],
}) {
  return QuizQuestion.fromJson({
    'id': id,
    'attributes': {
      'text': text,
      'type': type,
      'score': 5,
      'answers': answers,
    },
  });
}

Map<String, dynamic> _answer(String id, String text, {bool correct = false}) {
  return {
    'id': id,
    'attributes': {'text': text, 'is_correct': correct},
  };
}

/// The review used to be drawn from `selectedAnswerId` / `selectedAnswerIds` —
/// the selections held in memory while the exam was being taken — and from
/// whatever `is_correct` the taking payload happened to carry. The website
/// resolves the chosen options out of the server's `answer_text`, matched on
/// each option's text, and takes the verdict from the row's `is_correct`.
void main() {
  group('selectedAnswersFromAnswerText', () {
    final answers = [
      QuizAnswer.fromJson(_answer('1', 'Cairo', correct: true)),
      QuizAnswer.fromJson(_answer('2', 'Alexandria')),
      QuizAnswer.fromJson(_answer('3', 'Giza')),
    ];

    test('matches a single option on its text', () {
      final selected = selectedAnswersFromAnswerText('Cairo', answers);
      expect(selected.map((a) => a.id), ['1']);
    });

    test('splits on commas and trims each part', () {
      final selected =
          selectedAnswersFromAnswerText(' Cairo ,  Giza ', answers);
      expect(selected.map((a) => a.id), ['1', '3']);
    });

    test("tolerates the option's own surrounding whitespace", () {
      final padded = [QuizAnswer.fromJson(_answer('9', '  Cairo  '))];
      expect(selectedAnswersFromAnswerText('Cairo', padded), hasLength(1));
    });

    test('an empty answer text selects nothing', () {
      expect(selectedAnswersFromAnswerText('', answers), isEmpty);
    });

    test('a short answer never resolves to options', () {
      expect(
        selectedAnswersFromAnswerText('Cairo', answers, isShortAnswer: true),
        isEmpty,
      );
    });

    test('no match when nothing lines up', () {
      expect(selectedAnswersFromAnswerText('Luxor', answers), isEmpty);
    });

    test(
        'an option whose own text contains a comma can never match — '
        "the website's split tears it in two, and the app mirrors that",
        () {
      final commaAnswers = [
        QuizAnswer.fromJson(_answer('1', 'Cairo, Egypt', correct: true)),
        QuizAnswer.fromJson(_answer('2', 'Tunis')),
      ];
      // Exactly what the backend recorded for the student's pick.
      expect(selectedAnswersFromAnswerText('Cairo, Egypt', commaAnswers),
          isEmpty);
    });

    test('two options with the same text are both marked as chosen', () {
      final duplicate = [
        QuizAnswer.fromJson(_answer('1', 'True', correct: true)),
        QuizAnswer.fromJson(_answer('2', 'True')),
      ];
      expect(selectedAnswersFromAnswerText('True', duplicate), hasLength(2));
    });
  });

  group('localQuestionCorrect', () {
    test('single choice: the one pick must be the correct option', () {
      final question = _question(
        id: '10',
        answers: [_answer('1', 'A', correct: true), _answer('2', 'B')],
      );
      expect(
        localQuestionCorrect(question, [question.answers.first]),
        isTrue,
      );
      expect(localQuestionCorrect(question, [question.answers.last]), isFalse);
      expect(localQuestionCorrect(question, const []), isFalse);
      expect(localQuestionCorrect(question, question.answers), isFalse,
          reason: 'more than one pick is never right for a single choice');
    });

    test('multiple choice: the chosen set must equal the correct set', () {
      final question = _question(
        id: '11',
        type: 'multiple_choice',
        answers: [
          _answer('1', 'A', correct: true),
          _answer('2', 'B', correct: true),
          _answer('3', 'C'),
        ],
      );
      expect(
        localQuestionCorrect(question, question.answers.take(2).toList()),
        isTrue,
      );
      expect(
        localQuestionCorrect(question, [question.answers.first]),
        isFalse,
        reason: 'a partial set is wrong',
      );
      expect(localQuestionCorrect(question, question.answers), isFalse);
    });

    test('a question with no options cannot be right', () {
      expect(localQuestionCorrect(_question(id: '12'), const []), isFalse);
    });

    test('short answer: text present means awaiting grading, blank is wrong',
        () {
      final question = _question(id: '13', type: 'short_answer');
      expect(localQuestionCorrect(question, const [], shortText: 'My essay'),
          isNull);
      expect(localQuestionCorrect(question, const [], shortText: '   '),
          isFalse);
    });
  });

  group('buildQuestionReview', () {
    test("the server's answer_text drives the selection, not the local pick",
        () {
      final question = _question(
        id: '20',
        answers: [_answer('1', 'Cairo', correct: true), _answer('2', 'Tunis')],
      )..selectedAnswerId = 2;

      final review = buildQuestionReview(
        question,
        QuizAnswerReview.fromJson({
          'attributes': {'quiz_question_id': 20, 'answer_text': 'Cairo'},
        }),
      );

      expect(review.selected.map((a) => a.id), ['1']);
      expect(review.usedLocalSelection, isFalse);
      expect(review.correct, isTrue);
    });

    test("the server's is_correct is never overridden locally", () {
      final question = _question(
        id: '21',
        answers: [_answer('1', 'Cairo', correct: true), _answer('2', 'Tunis')],
      );

      final review = buildQuestionReview(
        question,
        QuizAnswerReview.fromJson({
          'attributes': {
            'quiz_question_id': 21,
            'answer_text': 'Cairo',
            'is_correct': false,
          },
        }),
      );

      expect(review.selected.map((a) => a.id), ['1'],
          reason: 'the option is still shown as the one chosen');
      expect(review.correct, isFalse,
          reason: 'but the verdict belongs to the backend');
    });

    test('with no server row the in-memory selection is the fallback', () {
      final question = _question(
        id: '22',
        answers: [_answer('1', 'Cairo', correct: true), _answer('2', 'Tunis')],
      )..selectedAnswerId = 1;

      final review = buildQuestionReview(question, null);
      expect(review.usedLocalSelection, isTrue);
      expect(review.selected.map((a) => a.id), ['1']);
      expect(review.correct, isTrue);
    });

    test('multiple choice resolves every comma-separated pick', () {
      final question = _question(
        id: '23',
        type: 'multiple_choice',
        answers: [
          _answer('1', 'A', correct: true),
          _answer('2', 'B', correct: true),
          _answer('3', 'C'),
        ],
      );

      final review = buildQuestionReview(
        question,
        QuizAnswerReview.fromJson({
          'attributes': {'quiz_question_id': 23, 'answer_text': 'A, B'},
        }),
      );
      expect(review.selected.map((a) => a.id), ['1', '2']);
      expect(review.correct, isTrue);
    });

    test('a short answer keeps awaiting grading until the backend decides', () {
      final question = _question(id: '24', type: 'short_answer');

      final pending = buildQuestionReview(
        question,
        QuizAnswerReview.fromJson({
          'attributes': {
            'quiz_question_id': 24,
            'answer_text': 'Because of the tides.',
          },
        }),
      );
      expect(pending.shortText, 'Because of the tides.');
      expect(pending.isPending, isTrue);
      expect(pending.selected, isEmpty);

      final graded = buildQuestionReview(
        question,
        QuizAnswerReview.fromJson({
          'attributes': {
            'quiz_question_id': 24,
            'answer_text': 'Because of the tides.',
            'is_correct': true,
            'feedback': 'Good.',
          },
        }),
      );
      expect(graded.isPending, isFalse);
      expect(graded.correct, isTrue);
      expect(graded.server!.feedback, 'Good.');
    });

    test('a short answer falls back to what was typed on the device', () {
      final question = _question(id: '25', type: 'short_answer')
        ..textAnswer = 'Typed offline';
      final review = buildQuestionReview(question, null);
      expect(review.shortText, 'Typed offline');
      expect(review.isPending, isTrue);
    });

    test('an unanswered question is wrong, not pending', () {
      final question = _question(
        id: '26',
        answers: [_answer('1', 'Cairo', correct: true)],
      );
      final review = buildQuestionReview(
        question,
        QuizAnswerReview.fromJson({
          'attributes': {'quiz_question_id': 26, 'answer_text': ''},
        }),
      );
      expect(review.selected, isEmpty);
      expect(review.correct, isFalse);
    });

    test('the explanation shows for correct options and for the picks', () {
      final question = _question(
        id: '27',
        answers: [
          {
            'id': '1',
            'attributes': {
              'text': 'Cairo',
              'is_correct': true,
              'reason': 'It is the capital.',
            },
          },
          {
            'id': '2',
            'attributes': {
              'text': 'Tunis',
              'is_correct': false,
              'reason': 'Wrong country.',
            },
          },
          {
            'id': '3',
            'attributes': {
              'text': 'Giza',
              'is_correct': false,
              'reason': 'Close, but no.',
            },
          },
        ],
      );

      final review = buildQuestionReview(
        question,
        QuizAnswerReview.fromJson({
          'attributes': {'quiz_question_id': 27, 'answer_text': 'Tunis'},
        }),
      );

      expect(review.explanationAnswers.map((a) => a.id), ['1', '2'],
          reason: 'the correct option and the one the student chose, no others');
      expect(review.correctAnswers.map((a) => a.text), ['Cairo']);
    });
  });

  group('questionsFromResultPayload', () {
    test('reads data.quiz.attributes.questions with graded options', () {
      final questions = questionsFromResultPayload({
        'data': {
          'quiz': {
            'id': '5',
            'attributes': {
              'title': 'Unit 1',
              'questions': [
                {
                  'id': '31',
                  'attributes': {
                    'text': 'Capital of Egypt?',
                    'type': 'single_choice',
                    'answers': [
                      _answer('1', 'Cairo', correct: true),
                      _answer('2', 'Tunis'),
                    ],
                  },
                },
                {
                  'id': '32',
                  'attributes': {'text': '   ', 'type': 'single_choice'},
                },
              ],
            },
          },
        },
      });

      expect(questions, hasLength(1),
          reason: 'blank-text questions are dropped, as normalizeQuestions does');
      expect(questions.single.questionId, 31);
      expect(questions.single.correctAnswers.map((a) => a.text), ['Cairo']);
    });

    test('reads a top-level quiz too', () {
      final questions = questionsFromResultPayload({
        'quiz': {
          'questions': [
            {
              'id': '40',
              'attributes': {'text': 'Q', 'type': 'true_false'},
            },
          ],
        },
      });
      expect(questions.single.questionId, 40);
    });

    test('empty for a payload without a quiz', () {
      expect(questionsFromResultPayload({'data': {}}), isEmpty);
      expect(questionsFromResultPayload(null), isEmpty);
    });
  });

  group('questionsFromQuizAttributes', () {
    test('reads the quiz resource the website takes the exam from', () {
      final questions = questionsFromQuizAttributes({
        'title': 'Unit 1',
        'questions': [
          {
            'id': '50',
            'attributes': {
              'text': 'Capital of Egypt?',
              'type': 'single_choice',
              'answers': [
                _answer('1', 'Cairo', correct: true),
                _answer('2', 'Tunis'),
              ],
            },
          },
          {
            'id': '51',
            'attributes': {'text': '', 'type': 'single_choice'},
          },
        ],
      });

      expect(questions.map((q) => q.questionId), [50]);
      expect(questions.single.correctAnswers.map((a) => a.text), ['Cairo'],
          reason: "only the quiz resource carries the options' is_correct");
    });

    test('empty when the quiz carries no questions', () {
      expect(questionsFromQuizAttributes(null), isEmpty);
      expect(questionsFromQuizAttributes({'title': 'Unit 1'}), isEmpty);
      expect(questionsFromQuizAttributes({'questions': 'nope'}), isEmpty);
    });

    test('accepts a JSON:API `questions.data` wrapper', () {
      final questions = questionsFromQuizAttributes({
        'questions': {
          'data': [
            {
              'id': '60',
              'attributes': {'text': 'Q', 'type': 'true_false'},
            },
          ],
        },
      });
      expect(questions.single.questionId, 60);
    });
  });
}
