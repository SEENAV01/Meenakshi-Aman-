import 'package:gyanify/src/backend.dart';

/// In-memory stand-in for [GyanifyBackend] used by widget tests.
/// Members a test does not need fall through to [noSuchMethod].
class FakeBackend implements GyanifyBackend {
  final courses = <LearningCourse>[];
  int _ids = 0;

  String _id(String prefix) => '$prefix${++_ids}';

  @override
  Future<List<LearningCourse>> loadTeacherCourses() async => List.of(courses);

  @override
  Future<String> createCourse(String title, String description) async {
    final id = _id('c');
    courses.add(
      LearningCourse(
        id: id,
        title: title,
        description: description,
        batches: const [],
      ),
    );
    return id;
  }

  @override
  Future<void> createBatch(
    String courseId,
    String title,
    String description,
  ) async {
    final i = courses.indexWhere((c) => c.id == courseId);
    final c = courses[i];
    courses[i] = LearningCourse(
      id: c.id,
      title: c.title,
      description: c.description,
      batches: [
        ...c.batches,
        LearningBatch(
          id: _id('b'),
          courseId: c.id,
          title: title,
          courseTitle: c.title,
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
