import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class LearningBatch {
  const LearningBatch({
    required this.id,
    required this.courseId,
    required this.title,
    required this.courseTitle,
  });

  final String id;
  final String courseId;
  final String title;
  final String courseTitle;
}

class LearningCourse {
  const LearningCourse({
    required this.id,
    required this.title,
    required this.description,
    required this.batches,
  });

  final String id;
  final String title;
  final String description;
  final List<LearningBatch> batches;
}

class EnrollmentRequest {
  const EnrollmentRequest({
    required this.id,
    required this.batchId,
    required this.studentName,
    required this.studentEmail,
    required this.courseTitle,
    required this.batchTitle,
    required this.status,
  });

  final String id;
  final String batchId;
  final String studentName;
  final String studentEmail;
  final String courseTitle;
  final String batchTitle;
  final String status;
}

/// Thrown when the app needs a database change the owner has not run yet.
class SetupRequiredException implements Exception {
  const SetupRequiredException(this.migrationFile);

  final String migrationFile;

  @override
  String toString() =>
      'The database needs an update. In Supabase, open SQL Editor and run '
      'supabase/migrations/$migrationFile, then try again.';
}

const foldersMigration = '202610180001_material_folders.sql';

/// Maps "table/column does not exist" errors to [SetupRequiredException].
Future<T> requireMigration<T>(
  String migrationFile,
  Future<T> Function() run,
) async {
  try {
    return await run();
  } on PostgrestException catch (error) {
    // PGRST205 missing table, PGRST204 missing column (write),
    // 42703 missing column (read), 42P01 missing relation.
    if (const {'PGRST205', 'PGRST204', '42703', '42P01'}.contains(error.code)) {
      throw SetupRequiredException(migrationFile);
    }
    rethrow;
  }
}

/// A chapter inside a batch, e.g. "Chapter 1 – Greetings".
class MaterialFolder {
  const MaterialFolder({
    required this.id,
    required this.batchId,
    required this.title,
    required this.displayOrder,
  });

  final String id;
  final String batchId;
  final String title;
  final int displayOrder;
}

class LearningMaterial {
  const LearningMaterial({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    this.storagePath,
    this.youtubeUrl,
    this.folderId,
    this.displayOrder = 0,
  });

  final String id;
  final String kind;
  final String title;
  final String description;
  final String? storagePath;
  final String? youtubeUrl;

  /// null = not in a folder (added before folders existed).
  final String? folderId;
  final int displayOrder;

  bool get isPdf => kind == 'pdf';
  bool get isVideo => kind == 'youtube_video';
}

class LiveClass {
  const LiveClass({
    required this.id,
    required this.batchId,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.meetingUrl,
    required this.batchTitle,
    required this.courseTitle,
  });

  final String id;
  final String batchId;
  final String title;
  final String description;
  final DateTime startsAt;
  final String meetingUrl;
  final String batchTitle;
  final String courseTitle;
}

class Catalog {
  const Catalog({required this.courses, required this.enrollmentStatuses});

  final List<LearningCourse> courses;
  final Map<String, String> enrollmentStatuses;
}

class GyanifyBackend {
  GyanifyBackend(this.client);

  final SupabaseClient client;

  Future<String> currentRole() async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    final row = await client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .single();
    return row['role'] as String;
  }

  Future<Catalog> loadCatalog() async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    final rows = await client
        .from('courses')
        .select('id,title,description,batches(id,title,course_id)')
        .order('title', ascending: true);
    final courses = rows
        .map((row) {
          final courseId = row['id'] as String;
          final courseTitle = row['title'] as String;
          final batches = (row['batches'] as List<dynamic>)
              .map(
                (item) => LearningBatch(
                  id: item['id'] as String,
                  courseId: item['course_id'] as String,
                  title: item['title'] as String,
                  courseTitle: courseTitle,
                ),
              )
              .toList(growable: false);
          return LearningCourse(
            id: courseId,
            title: courseTitle,
            description: row['description'] as String,
            batches: batches,
          );
        })
        .toList(growable: false);

    final enrollments = await client
        .from('enrollments')
        .select('batch_id,status')
        .eq('student_id', user.id);
    final statuses = <String, String>{
      for (final row in enrollments)
        row['batch_id'] as String: row['status'] as String,
    };
    return Catalog(courses: courses, enrollmentStatuses: statuses);
  }

  Future<List<LearningCourse>> loadTeacherCourses() async {
    final rows = await client
        .from('courses')
        .select('id,title,description,batches(id,title,course_id)')
        .order('title', ascending: true);
    return rows
        .map((row) {
          final courseTitle = row['title'] as String;
          final batches = (row['batches'] as List<dynamic>)
              .map(
                (item) => LearningBatch(
                  id: item['id'] as String,
                  courseId: item['course_id'] as String,
                  title: item['title'] as String,
                  courseTitle: courseTitle,
                ),
              )
              .toList(growable: false);
          return LearningCourse(
            id: row['id'] as String,
            title: courseTitle,
            description: row['description'] as String,
            batches: batches,
          );
        })
        .toList(growable: false);
  }

  Future<List<EnrollmentRequest>> loadEnrollmentRequests() async {
    final rows = await client
        .from('enrollments')
        .select(
          'id,batch_id,status,profiles(display_name,email),batches(title,courses(title))',
        )
        .order('requested_at', ascending: false);
    return rows
        .map((row) {
          final profile = row['profiles'] as Map<String, dynamic>;
          final batch = row['batches'] as Map<String, dynamic>;
          final course = batch['courses'] as Map<String, dynamic>;
          return EnrollmentRequest(
            id: row['id'] as String,
            batchId: row['batch_id'] as String,
            studentName: (profile['display_name'] as String).trim().isEmpty
                ? 'Student'
                : profile['display_name'] as String,
            studentEmail: profile['email'] as String? ?? '',
            courseTitle: course['title'] as String,
            batchTitle: batch['title'] as String,
            status: row['status'] as String,
          );
        })
        .toList(growable: false);
  }

  /// Pending requests for the teacher's own batches (row level security).
  Future<int> countPendingRequests() async {
    final rows = await client
        .from('enrollments')
        .select('id')
        .eq('status', 'pending');
    return rows.length;
  }

  Future<List<LearningBatch>> loadApprovedBatches() async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    final rows = await client
        .from('enrollments')
        .select('batch_id,batches(id,title,course_id,courses(title))')
        .eq('student_id', user.id)
        .eq('status', 'approved');
    return rows
        .map((row) {
          final batch = row['batches'] as Map<String, dynamic>;
          final course = batch['courses'] as Map<String, dynamic>;
          return LearningBatch(
            id: batch['id'] as String,
            courseId: batch['course_id'] as String,
            title: batch['title'] as String,
            courseTitle: course['title'] as String,
          );
        })
        .toList(growable: false);
  }

  Future<List<LearningMaterial>> loadMaterials(String batchId) async {
    final rows = await requireMigration(
      foldersMigration,
      () => client
          .from('learning_materials')
          .select(
            'id,kind,title,description,storage_path,youtube_url,'
            'folder_id,display_order',
          )
          .eq('batch_id', batchId)
          .order('display_order', ascending: true)
          .order('created_at', ascending: true),
    );
    return rows
        .map(
          (row) => LearningMaterial(
            id: row['id'] as String,
            kind: row['kind'] as String,
            title: row['title'] as String,
            description: row['description'] as String,
            storagePath: row['storage_path'] as String?,
            youtubeUrl: row['youtube_url'] as String?,
            folderId: row['folder_id'] as String?,
            displayOrder: row['display_order'] as int,
          ),
        )
        .toList(growable: false);
  }

  Future<List<MaterialFolder>> loadFolders(String batchId) async {
    final rows = await requireMigration(
      foldersMigration,
      () => client
          .from('material_folders')
          .select('id,batch_id,title,display_order')
          .eq('batch_id', batchId)
          .order('display_order', ascending: true)
          .order('created_at', ascending: true),
    );
    return rows
        .map(
          (row) => MaterialFolder(
            id: row['id'] as String,
            batchId: row['batch_id'] as String,
            title: row['title'] as String,
            displayOrder: row['display_order'] as int,
          ),
        )
        .toList(growable: false);
  }

  Future<void> createFolder({
    required String batchId,
    required String title,
    required int displayOrder,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    await requireMigration(
      foldersMigration,
      () => client.from('material_folders').insert({
        'batch_id': batchId,
        'created_by': user.id,
        'title': title.trim(),
        'display_order': displayOrder,
      }),
    );
  }

  Future<void> renameFolder(String folderId, String title) => requireMigration(
    foldersMigration,
    () => client
        .from('material_folders')
        .update({'title': title.trim()})
        .eq('id', folderId),
  );

  /// Fails (foreign key) while the folder still has materials.
  Future<void> deleteFolder(String folderId) => requireMigration(
    foldersMigration,
    () => client.from('material_folders').delete().eq('id', folderId),
  );

  /// Saves [ordered] as the new order (0, 1, 2, ...).
  Future<void> reorderFolders(List<MaterialFolder> ordered) => requireMigration(
    foldersMigration,
    () => Future.wait([
      for (var i = 0; i < ordered.length; i++)
        if (ordered[i].displayOrder != i)
          client
              .from('material_folders')
              .update({'display_order': i})
              .eq('id', ordered[i].id),
    ]),
  );

  /// Saves [ordered] (the items of one folder) as the new order.
  Future<void> reorderMaterials(List<LearningMaterial> ordered) =>
      requireMigration(
        foldersMigration,
        () => Future.wait([
          for (var i = 0; i < ordered.length; i++)
            if (ordered[i].displayOrder != i)
              client
                  .from('learning_materials')
                  .update({'display_order': i})
                  .eq('id', ordered[i].id),
        ]),
      );

  /// Puts [material] at the end of [folderId] (null = no folder).
  Future<void> moveMaterial(
    LearningMaterial material, {
    required String? folderId,
    required int displayOrder,
  }) => requireMigration(
    foldersMigration,
    () => client
        .from('learning_materials')
        .update({'folder_id': folderId, 'display_order': displayOrder})
        .eq('id', material.id),
  );

  Future<String> createCourse(String title, String description) async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    final row = await client
        .from('courses')
        .insert({
          'teacher_id': user.id,
          'title': title.trim(),
          'description': description.trim(),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> createBatch(
    String courseId,
    String title,
    String description,
  ) async {
    await client.from('batches').insert({
      'course_id': courseId,
      'title': title.trim(),
      'description': description.trim(),
    });
  }

  Future<void> requestEnrollment(String batchId) async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    try {
      await client.from('enrollments').insert({
        'batch_id': batchId,
        'student_id': user.id,
        'status': 'pending',
      });
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw StateError('You have already requested or joined this batch.');
      }
      rethrow;
    }
  }

  Future<void> reviewEnrollment(String id, String status) async {
    await client
        .from('enrollments')
        .update({
          'status': status,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> uploadPdf({
    required String batchId,
    required String title,
    required String description,
    required String fileName,
    required Uint8List bytes,
    String? folderId,
    int displayOrder = 0,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    final storagePath =
        '$batchId/${DateTime.now().microsecondsSinceEpoch}-$fileName';
    await client.storage
        .from('learning-materials')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: false,
          ),
        );
    try {
      await requireMigration(
        foldersMigration,
        () => client.from('learning_materials').insert({
          'batch_id': batchId,
          'created_by': user.id,
          'kind': 'pdf',
          'title': title.trim(),
          'description': description.trim(),
          'storage_path': storagePath,
          'folder_id': folderId,
          'display_order': displayOrder,
        }),
      );
    } on Exception catch (error, stackTrace) {
      // No row means nobody can ever open the file, so don't keep it.
      await client.storage.from('learning-materials').remove([storagePath]);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Saves a YouTube link. The video itself stays on YouTube.
  Future<void> addVideo({
    required String batchId,
    required String title,
    required String description,
    required String youtubeUrl,
    String? folderId,
    int displayOrder = 0,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    await requireMigration(
      foldersMigration,
      () => client.from('learning_materials').insert({
        'batch_id': batchId,
        'created_by': user.id,
        'kind': 'youtube_video',
        'title': title.trim(),
        'description': description.trim(),
        'youtube_url': youtubeUrl,
        'folder_id': folderId,
        'display_order': displayOrder,
      }),
    );
  }

  Future<void> deleteMaterial(LearningMaterial material) async {
    await client.from('learning_materials').delete().eq('id', material.id);
    final path = material.storagePath;
    if (path != null) {
      await client.storage.from('learning-materials').remove([path]);
    }
  }

  Future<String> createPdfLink(String storagePath) {
    return client.storage
        .from('learning-materials')
        .createSignedUrl(storagePath, 300);
  }

  /// A short-lived link that makes the browser save the PDF to Downloads.
  Future<String> createPdfDownloadLink(String storagePath, String title) {
    final safeName = title.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '_').trim();
    return client.storage
        .from('learning-materials')
        .createSignedUrl(
          storagePath,
          300,
          download: DownloadBehavior.named(
            '${safeName.isEmpty ? 'notes' : safeName}.pdf',
          ),
        );
  }

  /// Upcoming and recent live classes. Row level security returns only the
  /// teacher's own batches, or a student's approved batches.
  Future<List<LiveClass>> loadLiveClasses() async {
    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 4))
        .toIso8601String();
    final rows = await client
        .from('live_sessions')
        .select(
          'id,batch_id,title,description,starts_at,meeting_url,'
          'batches(title,courses(title))',
        )
        .not('meeting_url', 'is', null)
        .neq('status', 'cancelled')
        .gte('starts_at', since)
        .order('starts_at', ascending: true);
    return rows
        .map((row) {
          final batch = row['batches'] as Map<String, dynamic>;
          final course = batch['courses'] as Map<String, dynamic>;
          return LiveClass(
            id: row['id'] as String,
            batchId: row['batch_id'] as String,
            title: row['title'] as String,
            description: row['description'] as String,
            startsAt: DateTime.parse(row['starts_at'] as String).toLocal(),
            meetingUrl: row['meeting_url'] as String,
            batchTitle: batch['title'] as String,
            courseTitle: course['title'] as String,
          );
        })
        .toList(growable: false);
  }

  Future<void> scheduleLiveClass({
    required String batchId,
    required String title,
    required String description,
    required DateTime startsAt,
    required String meetingUrl,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    await client.from('live_sessions').insert({
      'batch_id': batchId,
      'created_by': user.id,
      'title': title.trim(),
      'description': description.trim(),
      'starts_at': startsAt.toUtc().toIso8601String(),
      'meeting_url': meetingUrl.trim(),
    });
  }

  Future<void> deleteLiveClass(String id) async {
    await client.from('live_sessions').delete().eq('id', id);
  }
}
