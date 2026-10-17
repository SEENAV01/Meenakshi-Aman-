// Runs the app's real GyanifyBackend against a Supabase project.
// Skipped unless these are set (use a local `supabase start` stack or a test
// project, not the live one, because it creates a throwaway student):
//   GYANIFY_IT_URL, GYANIFY_IT_KEY, GYANIFY_IT_TEACHER_EMAIL, GYANIFY_IT_TEACHER_PASSWORD
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/backend.dart';
import 'package:gyanify/src/links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final env = Platform.environment;
  final url = env['GYANIFY_IT_URL'];
  final key = env['GYANIFY_IT_KEY'];
  final teacherEmail = env['GYANIFY_IT_TEACHER_EMAIL'];
  final teacherPassword = env['GYANIFY_IT_TEACHER_PASSWORD'];
  final skip = [url, key, teacherEmail, teacherPassword].contains(null)
      ? 'GYANIFY_IT_* not set'
      : null;

  SupabaseClient newClient() => SupabaseClient(
    url!,
    key!,
    // The app itself uses PKCE via supabase_flutter's storage; a plain test
    // client has no storage, so it signs in with the implicit flow.
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
  );

  test(
    'teacher and student flows work end to end',
    () async {
      final teacherClient = newClient();
      final studentClient = newClient();
      final teacher = GyanifyBackend(teacherClient);
      final student = GyanifyBackend(studentClient);
      String? courseId;
      try {
        await teacherClient.auth.signInWithPassword(
          email: teacherEmail!,
          password: teacherPassword!,
        );
        expect(await teacher.currentRole(), 'teacher_admin');

        // Teacher builds a course.
        courseId = await teacher.createCourse('IT course', 'integration test');
        await teacher.createBatch(courseId, 'IT batch', '');
        final batch = (await teacher.loadTeacherCourses())
            .firstWhere((c) => c.id == courseId)
            .batches
            .single;
        final pdf = Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits);
        await teacher.uploadPdf(
          batchId: batch.id,
          title: 'Chapter 1 notes',
          description: '',
          fileName: 'chapter1.pdf',
          bytes: pdf,
        );
        await teacher.addVideo(
          batchId: batch.id,
          title: 'Lecture 1',
          description: '',
          youtubeUrl: canonicalYoutubeUrl(
            youtubeVideoId('https://youtu.be/dQw4w9WgXcQ?si=x')!,
          ),
        );
        final startsAt = DateTime.now().add(const Duration(hours: 2));
        await teacher.scheduleLiveClass(
          batchId: batch.id,
          title: 'Doubt class',
          description: '',
          startsAt: startsAt,
          meetingUrl: 'https://meet.google.com/abc-defg-hij',
        );

        // Student signs up (email confirmation off) and asks to join.
        final email =
            'it-${Random().nextInt(1 << 30)}@${env['GYANIFY_IT_DOMAIN'] ?? 'example.com'}';
        final signUp = await studentClient.auth.signUp(
          email: email,
          password: 'it-password-${Random().nextInt(1 << 30)}',
          data: {'display_name': 'IT Student'},
        );
        expect(signUp.session, isNotNull, reason: 'email confirmation is on');
        expect(await student.currentRole(), 'student');
        var catalog = await student.loadCatalog();
        expect(catalog.courses.any((c) => c.id == courseId), isTrue);
        await student.requestEnrollment(batch.id);
        expect(await student.loadMaterials(batch.id), isEmpty);
        expect(
          (await student.loadLiveClasses()).where((l) => l.batchId == batch.id),
          isEmpty,
        );
        expect(await student.loadApprovedBatches(), isEmpty);

        // Teacher sees name + email and approves.
        final request = (await teacher.loadEnrollmentRequests()).firstWhere(
          (r) => r.batchId == batch.id,
        );
        expect(request.studentName, 'IT Student');
        expect(request.studentEmail, email);
        expect(request.status, 'pending');
        await teacher.reviewEnrollment(request.id, 'approved');

        // Student now has everything.
        catalog = await student.loadCatalog();
        expect(catalog.enrollmentStatuses[batch.id], 'approved');
        expect((await student.loadApprovedBatches()).single.id, batch.id);
        final materials = await student.loadMaterials(batch.id);
        expect(materials.map((m) => m.kind).toSet(), {'pdf', 'youtube_video'});
        final pdfMaterial = materials.firstWhere((m) => m.isPdf);
        final video = materials.firstWhere((m) => m.isVideo);
        expect(youtubeVideoId(video.youtubeUrl!), 'dQw4w9WgXcQ');

        final http = HttpClient();
        Future<HttpClientResponse> get(String link) async =>
            (await http.getUrl(Uri.parse(link))).close();
        final view = await get(
          await student.createPdfLink(pdfMaterial.storagePath!),
        );
        expect(view.statusCode, 200);
        final bytes = await view.fold<List<int>>([], (a, b) => a..addAll(b));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        final download = await get(
          await student.createPdfDownloadLink(
            pdfMaterial.storagePath!,
            pdfMaterial.title,
          ),
        );
        await download.drain<void>();
        expect(download.statusCode, 200);
        expect(
          download.headers.value('content-disposition'),
          contains('Chapter 1 notes.pdf'),
        );
        http.close();

        final live = (await student.loadLiveClasses()).singleWhere(
          (l) => l.batchId == batch.id,
        );
        expect(live.meetingUrl, 'https://meet.google.com/abc-defg-hij');
        expect(live.startsAt.difference(startsAt).inSeconds.abs(), lessThan(2));
        expect(live.batchTitle, 'IT batch');

        // Teacher removes access, then deletes content.
        await teacher.reviewEnrollment(request.id, 'revoked');
        expect(await student.loadMaterials(batch.id), isEmpty);
        for (final m in await teacher.loadMaterials(batch.id)) {
          await teacher.deleteMaterial(m);
        }
        expect(await teacher.loadMaterials(batch.id), isEmpty);
        await teacher.deleteLiveClass(live.id);
        expect(
          (await teacher.loadLiveClasses()).where((l) => l.batchId == batch.id),
          isEmpty,
        );
      } finally {
        if (courseId != null) {
          await teacherClient.from('courses').delete().eq('id', courseId);
        }
        await teacherClient.dispose();
        await studentClient.dispose();
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
