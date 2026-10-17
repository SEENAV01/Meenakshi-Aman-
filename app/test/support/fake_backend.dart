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

  // ---- folders and materials ----
  final folders = <MaterialFolder>[];
  final materials = <LearningMaterial>[];

  /// Simulates the owner not having run the folders SQL yet.
  bool missingFoldersMigration = false;

  void _check() {
    if (missingFoldersMigration) {
      throw const SetupRequiredException(foldersMigration);
    }
  }

  List<T> _sorted<T>(List<T> items, int Function(T) order) =>
      List.of(items)..sort((a, b) => order(a).compareTo(order(b)));

  @override
  Future<List<MaterialFolder>> loadFolders(String batchId) async {
    _check();
    return _sorted(
      folders.where((f) => f.batchId == batchId).toList(),
      (f) => f.displayOrder,
    );
  }

  @override
  Future<List<LearningMaterial>> loadMaterials(String batchId) async {
    _check();
    return _sorted(materials, (m) => m.displayOrder);
  }

  @override
  Future<void> createFolder({
    required String batchId,
    required String title,
    required int displayOrder,
  }) async {
    _check();
    folders.add(
      MaterialFolder(
        id: _id('f'),
        batchId: batchId,
        title: title,
        displayOrder: displayOrder,
      ),
    );
  }

  MaterialFolder _folderWith(MaterialFolder f, {String? title, int? order}) =>
      MaterialFolder(
        id: f.id,
        batchId: f.batchId,
        title: title ?? f.title,
        displayOrder: order ?? f.displayOrder,
      );

  LearningMaterial _materialWith(
    LearningMaterial m, {
    String? folderId,
    bool clearFolder = false,
    int? order,
  }) => LearningMaterial(
    id: m.id,
    kind: m.kind,
    title: m.title,
    description: m.description,
    storagePath: m.storagePath,
    youtubeUrl: m.youtubeUrl,
    folderId: clearFolder ? null : (folderId ?? m.folderId),
    displayOrder: order ?? m.displayOrder,
  );

  @override
  Future<void> renameFolder(String folderId, String title) async {
    final i = folders.indexWhere((f) => f.id == folderId);
    folders[i] = _folderWith(folders[i], title: title);
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    if (materials.any((m) => m.folderId == folderId)) {
      throw StateError('foreign key: folder still has materials');
    }
    folders.removeWhere((f) => f.id == folderId);
  }

  @override
  Future<void> reorderFolders(List<MaterialFolder> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      final j = folders.indexWhere((f) => f.id == ordered[i].id);
      folders[j] = _folderWith(folders[j], order: i);
    }
  }

  @override
  Future<void> reorderMaterials(List<LearningMaterial> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      final j = materials.indexWhere((m) => m.id == ordered[i].id);
      materials[j] = _materialWith(materials[j], order: i);
    }
  }

  @override
  Future<void> moveMaterial(
    LearningMaterial material, {
    required String? folderId,
    required int displayOrder,
  }) async {
    final j = materials.indexWhere((m) => m.id == material.id);
    materials[j] = _materialWith(
      materials[j],
      folderId: folderId,
      clearFolder: folderId == null,
      order: displayOrder,
    );
  }

  @override
  Future<void> addVideo({
    required String batchId,
    required String title,
    required String description,
    required String youtubeUrl,
    String? folderId,
    int displayOrder = 0,
  }) async {
    materials.add(
      LearningMaterial(
        id: _id('m'),
        kind: 'youtube_video',
        title: title,
        description: description,
        youtubeUrl: youtubeUrl,
        folderId: folderId,
        displayOrder: displayOrder,
      ),
    );
  }

  @override
  Future<void> deleteMaterial(LearningMaterial material) async {
    materials.removeWhere((m) => m.id == material.id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
