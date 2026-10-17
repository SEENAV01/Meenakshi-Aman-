#!/usr/bin/env node
// Gyanify security test. Runs against a real Supabase project using only the
// publishable key, exactly like the app does. No service_role key is used.
//
// Required environment variables:
//   SUPABASE_URL               https://<project>.supabase.co
//   SUPABASE_PUBLISHABLE_KEY   sb_publishable_...
//   SECTEST_TEACHER_EMAIL      a teacher_admin account used only for this test
//   SECTEST_TEACHER_PASSWORD
// Optional:
//   SECTEST_STUDENT_EMAIL_DOMAIN  domain for throwaway student accounts (default example.com)
//
// Needs email confirmation OFF (sign-up must return a session).
// Everything the test creates lives under a course titled "[SECTEST] ..." and is
// deleted at the end. Throwaway student auth accounts stay behind (a student
// cannot delete itself); they are named "[SECTEST] ...".

import { randomBytes } from 'node:crypto';

const env = (name, fallback) => {
  const value = process.env[name] ?? fallback;
  if (!value) {
    console.error(`Missing environment variable ${name}`);
    process.exit(2);
  }
  return value;
};

const BASE = env('SUPABASE_URL').replace(/\/+$/, '');
const KEY = env('SUPABASE_PUBLISHABLE_KEY');
const TEACHER_EMAIL = env('SECTEST_TEACHER_EMAIL');
const TEACHER_PASSWORD = env('SECTEST_TEACHER_PASSWORD');
const STUDENT_DOMAIN = env('SECTEST_STUDENT_EMAIL_DOMAIN', 'example.com');
const BUCKET = 'learning-materials';
const PREFIX = '[SECTEST]';
const PDF_BYTES = Buffer.from(
  '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n' +
    '2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n',
);

let passed = 0;
const failures = [];

function check(name, ok, detail = '') {
  if (ok) {
    passed += 1;
    console.log(`  PASS  ${name}`);
  } else {
    failures.push(name);
    console.log(`  FAIL  ${name}${detail ? `  ->  ${detail}` : ''}`);
  }
}

async function call(method, path, { token, body, headers = {}, raw = false } = {}) {
  const h = { apikey: KEY, ...headers };
  if (token) h.Authorization = `Bearer ${token}`;
  let payload;
  if (body instanceof Buffer) {
    payload = body;
  } else if (body !== undefined) {
    h['Content-Type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  const res = await fetch(`${BASE}${path}`, { method, headers: h, body: payload });
  const buf = Buffer.from(await res.arrayBuffer());
  if (raw) return { status: res.status, buf };
  let json = null;
  try {
    json = buf.length ? JSON.parse(buf.toString('utf8')) : null;
  } catch {
    json = buf.toString('utf8');
  }
  return { status: res.status, json, buf };
}

const ok2xx = (r) => r.status >= 200 && r.status < 300;
const rest = (method, table, opts = {}) =>
  call(method, `/rest/v1/${table}`, {
    ...opts,
    headers: { Prefer: 'return=representation', ...(opts.headers ?? {}) },
  });

function must(r, what) {
  if (!ok2xx(r)) {
    throw new Error(`${what} failed: HTTP ${r.status} ${JSON.stringify(r.json)}`);
  }
  return r.json;
}

async function signIn(email, password) {
  const r = await call('POST', '/auth/v1/token?grant_type=password', {
    body: { email, password },
  });
  const json = must(r, `sign in ${email}`);
  return { token: json.access_token, id: json.user.id };
}

async function signUpStudent(label, metadata = {}) {
  const email = `sectest-${label}-${randomBytes(6).toString('hex')}@${STUDENT_DOMAIN}`;
  const password = randomBytes(18).toString('base64url');
  const r = await call('POST', '/auth/v1/signup', {
    body: { email, password, data: { display_name: `${PREFIX} ${label}`, ...metadata } },
  });
  const json = must(r, `sign up ${label}`);
  const token = json.access_token ?? json.session?.access_token;
  if (!token) {
    throw new Error(
      'Sign-up returned no session. Turn OFF "Confirm email" in Supabase ' +
        '(Authentication > Sign In / Providers > Email) and run again.',
    );
  }
  return { token, id: json.user?.id ?? json.id, email };
}

async function role(user) {
  const r = await rest('GET', `profiles?select=role&id=eq.${user.id}`, { token: user.token });
  return Array.isArray(r.json) && r.json[0] ? r.json[0].role : `unreadable (${r.status})`;
}

async function enrollmentStatus(teacher, id) {
  const r = await rest('GET', `enrollments?select=status&id=eq.${id}`, { token: teacher.token });
  return must(r, 'teacher reads enrollment')[0]?.status ?? 'missing';
}

async function cleanup(teacher) {
  const r = await rest(
    'GET',
    `courses?select=id,batches(id)&teacher_id=eq.${teacher.id}&title=like.${encodeURIComponent(PREFIX)}*`,
    { token: teacher.token },
  );
  for (const course of r.json ?? []) {
    for (const batch of course.batches ?? []) {
      const list = await call('POST', `/storage/v1/object/list/${BUCKET}`, {
        token: teacher.token,
        body: { prefix: batch.id, limit: 1000 },
      });
      const names = (Array.isArray(list.json) ? list.json : []).map((o) => `${batch.id}/${o.name}`);
      if (names.length) {
        await call('DELETE', `/storage/v1/object/${BUCKET}`, {
          token: teacher.token,
          body: { prefixes: names },
        });
      }
    }
    await rest('DELETE', `courses?id=eq.${course.id}`, { token: teacher.token });
  }
}

async function main() {
  console.log(`Gyanify security test against ${new URL(BASE).host}`);
  const teacher = await signIn(TEACHER_EMAIL, TEACHER_PASSWORD);
  if ((await role(teacher)) !== 'teacher_admin') {
    throw new Error('SECTEST_TEACHER_EMAIL is not a teacher_admin. Run the promote SQL first.');
  }
  await cleanup(teacher);

  // ---------- Setup: course, batch, PDF, video, live class ----------
  const course = must(
    await rest('POST', 'courses', {
      token: teacher.token,
      body: { teacher_id: teacher.id, title: `${PREFIX} delete me`, description: 'automated test' },
    }),
    'teacher creates course',
  )[0];
  const batch = must(
    await rest('POST', 'batches', {
      token: teacher.token,
      body: { course_id: course.id, title: `${PREFIX} batch` },
    }),
    'teacher creates batch',
  )[0];
  const pdfPath = `${batch.id}/sectest-${Date.now()}.pdf`;

  try {
    must(
      await call('POST', `/storage/v1/object/${BUCKET}/${pdfPath}`, {
        token: teacher.token,
        body: PDF_BYTES,
        headers: { 'Content-Type': 'application/pdf', 'x-upsert': 'false' },
      }),
      'teacher uploads PDF',
    );
    must(
      await rest('POST', 'learning_materials', {
        token: teacher.token,
        body: {
          batch_id: batch.id,
          created_by: teacher.id,
          kind: 'pdf',
          title: `${PREFIX} pdf`,
          storage_path: pdfPath,
        },
      }),
      'teacher adds PDF row',
    );
    must(
      await rest('POST', 'learning_materials', {
        token: teacher.token,
        body: {
          batch_id: batch.id,
          created_by: teacher.id,
          kind: 'youtube_video',
          title: `${PREFIX} video`,
          youtube_url: 'https://youtu.be/dQw4w9WgXcQ',
        },
      }),
      'teacher adds video row',
    );
    must(
      await rest('POST', 'live_sessions', {
        token: teacher.token,
        body: {
          batch_id: batch.id,
          created_by: teacher.id,
          title: `${PREFIX} live`,
          starts_at: new Date(Date.now() + 3600e3).toISOString(),
          meeting_url: 'https://meet.google.com/abc-defg-hij',
        },
      }),
      'teacher schedules live class',
    );

    // ---------- Students ----------
    // The rejected student also tries to pick the teacher role at sign-up.
    const rejected = await signUpStudent('rejected', { role: 'teacher_admin' });
    const approved = await signUpStudent('approved');

    const rejReq = must(
      await rest('POST', 'enrollments', {
        token: rejected.token,
        body: { batch_id: batch.id, student_id: rejected.id, status: 'pending' },
      }),
      'rejected student requests',
    )[0];
    const appReq = must(
      await rest('POST', 'enrollments', {
        token: approved.token,
        body: { batch_id: batch.id, student_id: approved.id, status: 'pending' },
      }),
      'approved student requests',
    )[0];

    console.log('\n1. Students cannot approve requests');
    await rest('PATCH', `enrollments?id=eq.${appReq.id}`, {
      token: rejected.token,
      body: { status: 'approved', reviewed_at: new Date().toISOString() },
    });
    check('another student cannot approve a classmate', (await enrollmentStatus(teacher, appReq.id)) === 'pending');
    await rest('PATCH', `enrollments?id=eq.${appReq.id}`, {
      token: approved.token,
      body: { status: 'approved', reviewed_at: new Date().toISOString() },
    });
    check('student cannot approve own request', (await enrollmentStatus(teacher, appReq.id)) === 'pending');
    const peek = await rest('GET', `enrollments?select=id&id=eq.${appReq.id}`, { token: rejected.token });
    check('student cannot see a classmate\'s request', Array.isArray(peek.json) && peek.json.length === 0, `HTTP ${peek.status} ${JSON.stringify(peek.json)}`);
    const otherBatch = must(
      await rest('POST', 'batches', { token: teacher.token, body: { course_id: course.id, title: `${PREFIX} batch 2` } }),
      'teacher creates batch 2',
    )[0];
    const selfApprove = await rest('POST', 'enrollments', {
      token: rejected.token,
      body: { batch_id: otherBatch.id, student_id: rejected.id, status: 'approved', reviewed_at: new Date().toISOString() },
    });
    check('student cannot insert an already-approved request', !ok2xx(selfApprove), `HTTP ${selfApprove.status}`);

    // Teacher decides.
    must(await rest('PATCH', `enrollments?id=eq.${rejReq.id}`, {
      token: teacher.token,
      body: { status: 'rejected', reviewed_at: new Date().toISOString() },
    }), 'teacher rejects');
    must(await rest('PATCH', `enrollments?id=eq.${appReq.id}`, {
      token: teacher.token,
      body: { status: 'approved', reviewed_at: new Date().toISOString() },
    }), 'teacher approves');

    console.log('\n2. Rejected student cannot reach batch files');
    const mats = await rest('GET', `learning_materials?select=id,storage_path&batch_id=eq.${batch.id}`, { token: rejected.token });
    check('cannot list learning_materials rows', Array.isArray(mats.json) && mats.json.length === 0, `HTTP ${mats.status} ${JSON.stringify(mats.json)}`);
    const lives = await rest('GET', `live_sessions?select=id,meeting_url&batch_id=eq.${batch.id}`, { token: rejected.token });
    check('cannot see live class links', Array.isArray(lives.json) && lives.json.length === 0, `HTTP ${lives.status}`);
    const list = await call('POST', `/storage/v1/object/list/${BUCKET}`, { token: rejected.token, body: { prefix: batch.id, limit: 100 } });
    check('cannot list storage folder', !ok2xx(list) || (Array.isArray(list.json) && list.json.length === 0), `HTTP ${list.status} ${JSON.stringify(list.json)}`);
    for (const [label, path] of [
      ['direct path download', `/storage/v1/object/${BUCKET}/${pdfPath}`],
      ['authenticated path download', `/storage/v1/object/authenticated/${BUCKET}/${pdfPath}`],
      ['public URL download', `/storage/v1/object/public/${BUCKET}/${pdfPath}`],
    ]) {
      const r = await call('GET', path, { token: rejected.token, raw: true });
      check(`cannot download by ${label}`, !ok2xx(r) && !r.buf.subarray(0, 5).equals(Buffer.from('%PDF-')), `HTTP ${r.status}`);
    }
    const sign = await call('POST', `/storage/v1/object/sign/${BUCKET}/${pdfPath}`, { token: rejected.token, body: { expiresIn: 60 } });
    check('cannot create a signed download link', !ok2xx(sign) || !sign.json?.signedURL, `HTTP ${sign.status}`);
    await rest('PATCH', `enrollments?id=eq.${rejReq.id}`, {
      token: rejected.token,
      body: { status: 'approved', reviewed_at: new Date().toISOString() },
    });
    check('cannot flip own rejection to approved', (await enrollmentStatus(teacher, rejReq.id)) === 'rejected');
    await rest('DELETE', `enrollments?id=eq.${rejReq.id}`, { token: rejected.token });
    check('cannot delete the rejection to re-apply', (await enrollmentStatus(teacher, rejReq.id)) === 'rejected');

    console.log('\n3. No student can become teacher_admin');
    check('sign-up metadata role is ignored', (await role(rejected)) === 'student', await role(rejected));
    for (const s of [rejected, approved]) {
      await rest('PATCH', `profiles?id=eq.${s.id}`, { token: s.token, body: { role: 'teacher_admin' } });
      check(`PATCH own profile role (${s === rejected ? 'rejected' : 'approved'})`, (await role(s)) === 'student', await role(s));
    }
    await rest('PATCH', `profiles?id=eq.${rejected.id}`, { token: rejected.token, body: { email: 'teacher@evil.test' } });
    const prof = await rest('GET', `profiles?select=email&id=eq.${rejected.id}`, { token: teacher.token });
    check('cannot change own stored email', prof.json?.[0]?.email === rejected.email, JSON.stringify(prof.json));
    const ins = await rest('POST', 'profiles', {
      token: rejected.token,
      body: { id: rejected.id, role: 'teacher_admin', display_name: 'x' },
      headers: { Prefer: 'return=representation,resolution=merge-duplicates' },
    });
    check('cannot upsert own profile as teacher', (await role(rejected)) === 'student', `HTTP ${ins.status}`);
    const teacherProfile = await rest('PATCH', `profiles?id=eq.${teacher.id}`, { token: rejected.token, body: { display_name: 'hacked' } });
    check('cannot edit the teacher profile', Array.isArray(teacherProfile.json) ? teacherProfile.json.length === 0 : !ok2xx(teacherProfile), `HTTP ${teacherProfile.status}`);

    console.log('\n4. Students cannot create or change teaching content');
    for (const [label, s] of [['rejected', rejected], ['approved', approved]]) {
      const c1 = await rest('POST', 'courses', { token: s.token, body: { teacher_id: s.id, title: `${PREFIX} student course` } });
      check(`${label}: cannot create a course as self`, !ok2xx(c1), `HTTP ${c1.status}`);
      const c2 = await rest('POST', 'courses', { token: s.token, body: { teacher_id: teacher.id, title: `${PREFIX} student course` } });
      check(`${label}: cannot create a course as teacher`, !ok2xx(c2), `HTTP ${c2.status}`);
      const b = await rest('POST', 'batches', { token: s.token, body: { course_id: course.id, title: `${PREFIX} student batch` } });
      check(`${label}: cannot create a batch`, !ok2xx(b), `HTTP ${b.status}`);
      const m = await rest('POST', 'learning_materials', {
        token: s.token,
        body: { batch_id: batch.id, created_by: s.id, kind: 'youtube_video', title: 'x', youtube_url: 'https://youtu.be/dQw4w9WgXcQ' },
      });
      check(`${label}: cannot add material`, !ok2xx(m), `HTTP ${m.status}`);
      const l = await rest('POST', 'live_sessions', {
        token: s.token,
        body: { batch_id: batch.id, created_by: s.id, title: 'x', starts_at: new Date().toISOString(), meeting_url: 'https://meet.google.com/abc-defg-hij' },
      });
      check(`${label}: cannot schedule a live class`, !ok2xx(l), `HTTP ${l.status}`);
      const up = await call('POST', `/storage/v1/object/${BUCKET}/${batch.id}/student-${label}.pdf`, {
        token: s.token,
        body: PDF_BYTES,
        headers: { 'Content-Type': 'application/pdf' },
      });
      check(`${label}: cannot upload into the batch folder`, !ok2xx(up), `HTTP ${up.status}`);
      await rest('PATCH', `courses?id=eq.${course.id}`, { token: s.token, body: { title: `${PREFIX} hacked` } });
      await rest('DELETE', `learning_materials?batch_id=eq.${batch.id}`, { token: s.token });
      await call('DELETE', `/storage/v1/object/${BUCKET}`, { token: s.token, body: { prefixes: [pdfPath] } });
    }
    const after = must(await rest('GET', `courses?select=title&id=eq.${course.id}`, { token: teacher.token }), 'reread course');
    check('course title unchanged by students', after[0]?.title === `${PREFIX} delete me`, JSON.stringify(after));
    const matsAfter = must(await rest('GET', `learning_materials?select=id&batch_id=eq.${batch.id}`, { token: teacher.token }), 'reread materials');
    check('materials not deleted by students', matsAfter.length === 2, `${matsAfter.length} rows`);
    const fileAfter = await call('GET', `/storage/v1/object/authenticated/${BUCKET}/${pdfPath}`, { token: teacher.token, raw: true });
    check('PDF not deleted by students', ok2xx(fileAfter), `HTTP ${fileAfter.status}`);

    console.log('\n5. Signed-out visitor sees nothing');
    const anonCourses = await rest('GET', 'courses?select=id');
    check('anon cannot list courses', !ok2xx(anonCourses) || (Array.isArray(anonCourses.json) && anonCourses.json.length === 0), `HTTP ${anonCourses.status}`);
    const anonFile = await call('GET', `/storage/v1/object/public/${BUCKET}/${pdfPath}`, { raw: true });
    check('anon cannot download the PDF', !ok2xx(anonFile), `HTTP ${anonFile.status}`);

    console.log('\n6. Positive control: approved student DOES get access (proves the test is real)');
    const goodMats = await rest('GET', `learning_materials?select=kind&batch_id=eq.${batch.id}`, { token: approved.token });
    check('approved student lists 2 materials', Array.isArray(goodMats.json) && goodMats.json.length === 2, JSON.stringify(goodMats.json));
    const goodLive = await rest('GET', `live_sessions?select=meeting_url&batch_id=eq.${batch.id}`, { token: approved.token });
    check('approved student sees the live class link', goodLive.json?.[0]?.meeting_url === 'https://meet.google.com/abc-defg-hij', JSON.stringify(goodLive.json));
    const goodSign = await call('POST', `/storage/v1/object/sign/${BUCKET}/${pdfPath}`, { token: approved.token, body: { expiresIn: 60 } });
    let downloaded = false;
    if (ok2xx(goodSign) && goodSign.json?.signedURL) {
      const file = await call('GET', `/storage/v1${goodSign.json.signedURL}`, { raw: true });
      downloaded = ok2xx(file) && file.buf.subarray(0, 5).equals(Buffer.from('%PDF-'));
    }
    check('approved student downloads the PDF via signed link', downloaded, `sign HTTP ${goodSign.status}`);

    console.log('\n7. Teacher removes access -> student loses it');
    must(await rest('PATCH', `enrollments?id=eq.${appReq.id}`, {
      token: teacher.token,
      body: { status: 'revoked', reviewed_at: new Date().toISOString() },
    }), 'teacher revokes');
    const revMats = await rest('GET', `learning_materials?select=id&batch_id=eq.${batch.id}`, { token: approved.token });
    check('revoked student cannot list materials', Array.isArray(revMats.json) && revMats.json.length === 0, JSON.stringify(revMats.json));
    const revFile = await call('GET', `/storage/v1/object/authenticated/${BUCKET}/${pdfPath}`, { token: approved.token, raw: true });
    check('revoked student cannot download', !ok2xx(revFile), `HTTP ${revFile.status}`);

    console.log('\n8. Database rejects bad links');
    const badVideo = await rest('POST', 'learning_materials', {
      token: teacher.token,
      body: { batch_id: batch.id, created_by: teacher.id, kind: 'youtube_video', title: 'x', youtube_url: 'https://evil.example/video' },
    });
    check('non-YouTube video link is refused', !ok2xx(badVideo), `HTTP ${badVideo.status}`);
    const badMeet = await rest('POST', 'live_sessions', {
      token: teacher.token,
      body: { batch_id: batch.id, created_by: teacher.id, title: 'x', starts_at: new Date().toISOString(), meeting_url: 'https://meet.jit.si/room' },
    });
    check('Jitsi / non Meet-Zoom link is refused', !ok2xx(badMeet), `HTTP ${badMeet.status}`);
  } finally {
    await cleanup(teacher);
  }

  console.log(`\n${passed} passed, ${failures.length} failed`);
  if (failures.length) {
    console.log('FAILED CHECKS:\n - ' + failures.join('\n - '));
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(`\nERROR: ${error.message}`);
  process.exit(1);
});
