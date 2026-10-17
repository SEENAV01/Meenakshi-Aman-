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

class LearningMaterial {
  const LearningMaterial({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    this.storagePath,
    this.youtubeUrl,
  });

  final String id;
  final String kind;
  final String title;
  final String description;
  final String? storagePath;
  final String? youtubeUrl;

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
        .order('title');
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
        .order('title');
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
    final rows = await client
        .from('learning_materials')
        .select('id,kind,title,description,storage_path,youtube_url')
        .eq('batch_id', batchId)
        .order('display_order')
        .order('created_at', ascending: false);
    return rows
        .map(
          (row) => LearningMaterial(
            id: row['id'] as String,
            kind: row['kind'] as String,
            title: row['title'] as String,
            description: row['description'] as String,
            storagePath: row['storage_path'] as String?,
            youtubeUrl: row['youtube_url'] as String?,
          ),
        )
        .toList(growable: false);
  }

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
      await client.from('learning_materials').insert({
        'batch_id': batchId,
        'created_by': user.id,
        'kind': 'pdf',
        'title': title.trim(),
        'description': description.trim(),
        'storage_path': storagePath,
      });
    } on PostgrestException catch (error, stackTrace) {
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
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    await client.from('learning_materials').insert({
      'batch_id': batchId,
      'created_by': user.id,
      'kind': 'youtube_video',
      'title': title.trim(),
      'description': description.trim(),
      'youtube_url': youtubeUrl,
    });
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
        .order('starts_at');
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
