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
        final pendingBefore = await teacher.countPendingRequests();
        await student.requestEnrollment(batch.id);
        // Badge count: one more pending request for this teacher.
        expect(await teacher.countPendingRequests(), pendingBefore + 1);
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
        expect(
          await teacher.countPendingRequests(),
          pendingBefore,
          reason: 'badge goes back down after approving',
        );

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

  test(
    'folders: create, order, add into, move, reorder; student reads in order',
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
        courseId = await teacher.createCourse('IT folders', '');
        await teacher.createBatch(courseId, 'IT folder batch', '');
        final batch = (await teacher.loadTeacherCourses())
            .firstWhere((c) => c.id == courseId)
            .batches
            .single;

        await teacher.createFolder(
          batchId: batch.id,
          title: 'Chapter 1 – Greetings',
          displayOrder: 0,
        );
        await teacher.createFolder(
          batchId: batch.id,
          title: 'Chapter 2',
          displayOrder: 1,
        );
        var folders = await teacher.loadFolders(batch.id);
        expect(folders.map((f) => f.title), [
          'Chapter 1 – Greetings',
          'Chapter 2',
        ]);
        await teacher.renameFolder(folders[1].id, 'Chapter 2 – Numbers');
        await teacher.reorderFolders([folders[1], folders[0]]);
        folders = await teacher.loadFolders(batch.id);
        expect(folders.map((f) => f.title), [
          'Chapter 2 – Numbers',
          'Chapter 1 – Greetings',
        ]);
        final ch1 = folders[1];
        final ch2 = folders[0];

        // Three items in Chapter 1, in order.
        await teacher.uploadPdf(
          batchId: batch.id,
          title: 'Notes A',
          description: '',
          fileName: 'a.pdf',
          bytes: Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits),
          folderId: ch1.id,
          displayOrder: 0,
        );
        for (final (i, title) in [(1, 'Video B'), (2, 'Video C')]) {
          await teacher.addVideo(
            batchId: batch.id,
            title: title,
            description: '',
            youtubeUrl: canonicalYoutubeUrl('dQw4w9WgXcQ'),
            folderId: ch1.id,
            displayOrder: i,
          );
        }
        List<String> titlesIn(List<LearningMaterial> all, String folderId) => [
          for (final m in all.where((m) => m.folderId == folderId)) m.title,
        ];
        var all = await teacher.loadMaterials(batch.id);
        expect(titlesIn(all, ch1.id), ['Notes A', 'Video B', 'Video C']);

        // Swap B and C, then move A to Chapter 2.
        final inCh1 = all.where((m) => m.folderId == ch1.id).toList();
        await teacher.reorderMaterials([inCh1[0], inCh1[2], inCh1[1]]);
        await teacher.moveMaterial(inCh1[0], folderId: ch2.id, displayOrder: 0);
        all = await teacher.loadMaterials(batch.id);
        expect(titlesIn(all, ch1.id), ['Video C', 'Video B']);
        expect(titlesIn(all, ch2.id), ['Notes A']);

        // A folder with items cannot be deleted; an emptied one can.
        await expectLater(teacher.deleteFolder(ch2.id), throwsA(anything));
        await teacher.moveMaterial(
          all.firstWhere((m) => m.title == 'Notes A'),
          folderId: ch1.id,
          displayOrder: 3, // end of Chapter 1 (C=1, B=2), like the app does
        );
        await teacher.deleteFolder(ch2.id);
        expect((await teacher.loadFolders(batch.id)).map((f) => f.id), [
          ch1.id,
        ]);

        // Student: nothing before approval, everything in order after.
        final email =
            'it-${Random().nextInt(1 << 30)}@${env['GYANIFY_IT_DOMAIN'] ?? 'example.com'}';
        await studentClient.auth.signUp(
          email: email,
          password: 'it-password-${Random().nextInt(1 << 30)}',
          data: {'display_name': 'IT Folder Student'},
        );
        await student.requestEnrollment(batch.id);
        expect(await student.loadFolders(batch.id), isEmpty);
        expect(await student.loadMaterials(batch.id), isEmpty);
        final request = (await teacher.loadEnrollmentRequests()).firstWhere(
          (r) => r.batchId == batch.id,
        );
        await teacher.reviewEnrollment(request.id, 'approved');
        expect((await student.loadFolders(batch.id)).map((f) => f.title), [
          'Chapter 1 – Greetings',
        ]);
        expect(titlesIn(await student.loadMaterials(batch.id), ch1.id), [
          'Video C',
          'Video B',
          'Notes A',
        ]);

        for (final m in await teacher.loadMaterials(batch.id)) {
          await teacher.deleteMaterial(m);
        }
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
