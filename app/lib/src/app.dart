import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend.dart';

const _authRedirectUrl = String.fromEnvironment(
  'SUPABASE_AUTH_REDIRECT_URL',
  defaultValue: 'gyanify://login-callback/',
);

class GyanifyApp extends StatelessWidget {
  const GyanifyApp({required this.isBackendConfigured, super.key});

  final bool isBackendConfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GYANIFY',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B5B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F7F4),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: isBackendConfigured ? const _SessionGate() : const _BackendNotice(),
    );
  }
}

class _BackendNotice extends StatelessWidget {
  const _BackendNotice();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.school_outlined, size: 40),
              SizedBox(height: 20),
              Text('GYANIFY', style: TextStyle(fontSize: 28)),
              SizedBox(height: 12),
              Text(
                'Backend configuration is missing. Sign-in and teaching '
                'content are unavailable in this build.',
              ),
              SizedBox(height: 12),
              Text(
                'Build with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY '
                'from the owner-managed Supabase project.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  final _client = Supabase.instance.client;
  late final GyanifyBackend _backend = GyanifyBackend(_client);
  StreamSubscription<AuthState>? _subscription;
  Future<String>? _roleFuture;
  String? _roleUserId;
  bool _isPasswordRecovery = false;

  @override
  void initState() {
    super.initState();
    _setRoleFuture();
    _subscription = _client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPasswordRecovery = state.event == AuthChangeEvent.passwordRecovery;
        _setRoleFuture();
      });
    });
  }

  void _setRoleFuture() {
    final userId = _client.auth.currentUser?.id;
    if (userId != _roleUserId) {
      _roleUserId = userId;
      _roleFuture = userId == null ? null : _backend.currentRole();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPasswordRecovery && _client.auth.currentSession != null) {
      return _PasswordUpdatePage(
        onComplete: () => setState(() => _isPasswordRecovery = false),
      );
    }

    final session = _client.auth.currentSession;
    if (session == null) return const _AuthPage();
    if (_roleFuture == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return FutureBuilder<String>(
      key: ValueKey(session.user.id),
      future: _roleFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LoadError(
            message:
                'Could not load your account role: ${_errorText(snapshot.error!)}',
            onRetry: () {
              setState(() => _roleFuture = _backend.currentRole());
            },
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final role = snapshot.data!;
        if (role != 'student' && role != 'teacher_admin') {
          return const _LoadError(message: 'This account has an unknown role.');
        }
        return _MainShell(
          backend: _backend,
          role: role,
          displayName:
              session.user.userMetadata?['display_name'] as String? ?? '',
        );
      },
    );
  }
}

class _AuthPage extends StatefulWidget {
  const _AuthPage();

  @override
  State<_AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<_AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  String? _message;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_registering) {
        final response = await _client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          emailRedirectTo: _authRedirectUrl,
          data: {'display_name': _name.text.trim()},
        );
        if (response.session == null) {
          setState(() {
            _message =
                'Account created. Verify your email using the link we sent '
                'before signing in.';
          });
        }
      } else {
        await _client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      setState(() => _message = error.message);
    } catch (error) {
      setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendRecovery() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _message = 'Enter your email address first.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: _authRedirectUrl,
      );
      setState(
        () => _message =
            'If this account exists, a password recovery link has been sent.',
      );
    } on AuthException catch (error) {
      setState(() => _message = error.message);
    } catch (error) {
      setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.school_outlined,
                      size: 46,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'GYANIFY',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _registering
                          ? 'Create a student account'
                          : 'Sign in to continue',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (_registering) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) =>
                          value == null || !value.contains('@')
                          ? 'Enter a valid email address'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: [
                        _registering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (value) => value == null || value.length < 8
                          ? 'Use at least 8 characters'
                          : null,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_registering ? 'Create account' : 'Sign in'),
                    ),
                    if (!_registering)
                      TextButton(
                        onPressed: _busy ? null : _sendRecovery,
                        child: const Text('Forgot password?'),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _registering = !_registering;
                              _message = null;
                            }),
                      child: Text(
                        _registering
                            ? 'Already registered? Sign in'
                            : 'New student? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordUpdatePage extends StatefulWidget {
  const _PasswordUpdatePage({required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_PasswordUpdatePage> createState() => _PasswordUpdatePageState();
}

class _PasswordUpdatePageState extends State<_PasswordUpdatePage> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _message = 'Use at least 8 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      widget.onComplete();
    } on AuthException catch (error) {
      setState(() => _message = error.message);
    } catch (error) {
      setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set a new password')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving…' : 'Save password'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MainShell extends StatefulWidget {
  const _MainShell({
    required this.backend,
    required this.role,
    required this.displayName,
  });

  final GyanifyBackend backend;
  final String role;
  final String displayName;

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isTeacher = widget.role == 'teacher_admin';
    final pages = isTeacher
        ? [
            _TeacherCoursesPage(backend: widget.backend),
            _TeacherRequestsPage(backend: widget.backend),
            const _LiveClassesPage(),
            _ProfilePage(displayName: widget.displayName),
          ]
        : [
            _CatalogPage(backend: widget.backend),
            _StudentLearningPage(backend: widget.backend),
            const _LiveClassesPage(),
            _ProfilePage(displayName: widget.displayName),
          ];
    final destinations = isTeacher
        ? const [
            NavigationDestination(
              icon: Icon(Icons.school_outlined),
              label: 'Courses',
            ),
            NavigationDestination(
              icon: Icon(Icons.how_to_reg_outlined),
              label: 'Requests',
            ),
            NavigationDestination(
              icon: Icon(Icons.video_camera_front_outlined),
              label: 'Live Classes',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ]
        : const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              label: 'Courses',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: 'My learning',
            ),
            NavigationDestination(
              icon: Icon(Icons.video_camera_front_outlined),
              label: 'Live Classes',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ];
    return Scaffold(
      appBar: AppBar(title: Text(isTeacher ? 'GYANIFY · Teacher' : 'GYANIFY')),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: destinations,
      ),
    );
  }
}

class _LiveClassesPage extends StatelessWidget {
  const _LiveClassesPage();

  @override
  Widget build(BuildContext context) => const _EmptyState(
    icon: Icons.video_camera_front_outlined,
    title: 'Live classes',
    detail:
        'Scheduling and joining a Jitsi class are not connected yet. '
        'The Jitsi plugin remains in this development build.',
  );
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Welcome${displayName.isEmpty ? '' : ', $displayName'}',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text('Your account role is managed securely by GYANIFY.'),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () async {
          try {
            await Supabase.instance.client.auth.signOut();
          } catch (error) {
            if (context.mounted) _showMessage(context, _errorText(error));
          }
        },
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ],
  );
}

class _CatalogPage extends StatefulWidget {
  const _CatalogPage({required this.backend});

  final GyanifyBackend backend;

  @override
  State<_CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<_CatalogPage> {
  late Future<Catalog> _catalog = widget.backend.loadCatalog();

  Future<void> _refresh() async {
    setState(() => _catalog = widget.backend.loadCatalog());
    await _catalog;
  }

  Future<void> _request(LearningBatch batch) async {
    try {
      await widget.backend.requestEnrollment(batch.id);
      await _refresh();
      if (mounted) _showMessage(context, 'Enrollment request sent.');
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Catalog>(
    future: _catalog,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _LoadError(
          message: 'Could not load courses: ${_errorText(snapshot.error!)}',
          onRetry: _refresh,
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final catalog = snapshot.data!;
      if (catalog.courses.isEmpty) {
        return const _EmptyState(
          icon: Icons.school_outlined,
          title: 'No courses yet',
          detail: 'Available courses will appear here.',
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Explore courses',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            for (final course in catalog.courses)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (course.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(course.description),
                      ],
                      const Divider(height: 24),
                      if (course.batches.isEmpty)
                        const Text('No batches available yet.')
                      else
                        for (final batch in course.batches)
                          _BatchCatalogTile(
                            batch: batch,
                            status: catalog.enrollmentStatuses[batch.id],
                            onRequest: () => _request(batch),
                            onOpen: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _MaterialsPage(
                                  backend: widget.backend,
                                  batch: batch,
                                  canUpload: false,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _BatchCatalogTile extends StatelessWidget {
  const _BatchCatalogTile({
    required this.batch,
    required this.status,
    required this.onRequest,
    required this.onOpen,
  });

  final LearningBatch batch;
  final String? status;
  final VoidCallback onRequest;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (status) {
      'pending' => 'Request pending',
      'approved' => 'Enrolled',
      'rejected' => 'Request declined',
      'revoked' => 'Access revoked',
      _ => null,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(batch.title),
      subtitle: statusLabel == null ? null : Text(statusLabel),
      trailing: status == 'approved'
          ? TextButton(onPressed: onOpen, child: const Text('Open'))
          : status == null
          ? FilledButton.tonal(
              onPressed: onRequest,
              child: const Text('Request to join'),
            )
          : null,
    );
  }
}

class _StudentLearningPage extends StatefulWidget {
  const _StudentLearningPage({required this.backend});

  final GyanifyBackend backend;

  @override
  State<_StudentLearningPage> createState() => _StudentLearningPageState();
}

class _StudentLearningPageState extends State<_StudentLearningPage> {
  late Future<List<LearningBatch>> _batches = widget.backend
      .loadApprovedBatches();

  Future<void> _refresh() async {
    setState(() => _batches = widget.backend.loadApprovedBatches());
    await _batches;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LearningBatch>>(
    future: _batches,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _LoadError(
          message:
              'Could not load your batches: '
              '${_errorText(snapshot.error!)}',
          onRetry: _refresh,
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final batches = snapshot.data!;
      if (batches.isEmpty) {
        return const _EmptyState(
          icon: Icons.menu_book_outlined,
          title: 'Nothing to learn yet',
          detail: 'Request to join a batch. Approved batches appear here.',
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'My learning',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            for (final batch in batches)
              Card(
                child: ListTile(
                  title: Text(batch.courseTitle),
                  subtitle: Text(batch.title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _MaterialsPage(
                        backend: widget.backend,
                        batch: batch,
                        canUpload: false,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _TeacherCoursesPage extends StatefulWidget {
  const _TeacherCoursesPage({required this.backend});

  final GyanifyBackend backend;

  @override
  State<_TeacherCoursesPage> createState() => _TeacherCoursesPageState();
}

class _TeacherCoursesPageState extends State<_TeacherCoursesPage> {
  late Future<List<LearningCourse>> _courses = widget.backend
      .loadTeacherCourses();

  Future<void> _refresh() async {
    setState(() => _courses = widget.backend.loadTeacherCourses());
    await _courses;
  }

  Future<void> _createCourse() async {
    final values = await _showTextForm(
      context,
      title: 'Create course',
      nameLabel: 'Course title',
    );
    if (values == null) return;
    try {
      await widget.backend.createCourse(values.$1, values.$2);
      await _refresh();
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  Future<void> _createBatch(LearningCourse course) async {
    final values = await _showTextForm(
      context,
      title: 'Add a batch to ${course.title}',
      nameLabel: 'Batch title',
    );
    if (values == null) return;
    try {
      await widget.backend.createBatch(course.id, values.$1, values.$2);
      await _refresh();
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LearningCourse>>(
    future: _courses,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _LoadError(
          message: 'Could not load courses: ${_errorText(snapshot.error!)}',
          onRetry: _refresh,
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final courses = snapshot.data!;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your courses',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _createCourse,
                  icon: const Icon(Icons.add),
                  label: const Text('Course'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (courses.isEmpty)
              const _EmptyState(
                icon: Icons.school_outlined,
                title: 'Create your first course',
                detail: 'Then add batches and share the course with students.',
              )
            else
              for (final course in courses)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (course.description.isNotEmpty)
                          Text(course.description),
                        const Divider(height: 24),
                        for (final batch in course.batches)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(batch.title),
                            subtitle: const Text('Manage learning materials'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _MaterialsPage(
                                  backend: widget.backend,
                                  batch: batch,
                                  canUpload: true,
                                ),
                              ),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _createBatch(course),
                            icon: const Icon(Icons.add),
                            label: const Text('Add batch'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );
}

class _TeacherRequestsPage extends StatefulWidget {
  const _TeacherRequestsPage({required this.backend});

  final GyanifyBackend backend;

  @override
  State<_TeacherRequestsPage> createState() => _TeacherRequestsPageState();
}

class _TeacherRequestsPageState extends State<_TeacherRequestsPage> {
  late Future<List<EnrollmentRequest>> _requests = widget.backend
      .loadEnrollmentRequests();

  Future<void> _refresh() async {
    setState(() => _requests = widget.backend.loadEnrollmentRequests());
    await _requests;
  }

  Future<void> _review(EnrollmentRequest request, String status) async {
    try {
      await widget.backend.reviewEnrollment(request.id, status);
      await _refresh();
      if (mounted) {
        _showMessage(
          context,
          'Request ${status == 'approved' ? 'approved' : 'rejected'}.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<EnrollmentRequest>>(
    future: _requests,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _LoadError(
          message:
              'Could not load enrollment requests: ${_errorText(snapshot.error!)}',
          onRetry: _refresh,
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final requests = snapshot.data!;
      if (requests.isEmpty) {
        return const _EmptyState(
          icon: Icons.how_to_reg_outlined,
          title: 'No enrollment requests',
          detail: 'New student requests for your batches will appear here.',
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Enrollment requests',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            for (final request in requests)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.studentName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('${request.courseTitle} · ${request.batchTitle}'),
                      const SizedBox(height: 8),
                      if (request.status == 'pending')
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => _review(request, 'rejected'),
                              child: const Text('Reject'),
                            ),
                            const Spacer(),
                            FilledButton(
                              onPressed: () => _review(request, 'approved'),
                              child: const Text('Approve'),
                            ),
                          ],
                        )
                      else
                        Text('Status: ${request.status}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _MaterialsPage extends StatefulWidget {
  const _MaterialsPage({
    required this.backend,
    required this.batch,
    required this.canUpload,
  });

  final GyanifyBackend backend;
  final LearningBatch batch;
  final bool canUpload;

  @override
  State<_MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends State<_MaterialsPage> {
  late Future<List<LearningMaterial>> _materials = widget.backend.loadMaterials(
    widget.batch.id,
  );

  Future<void> _refresh() async {
    setState(() => _materials = widget.backend.loadMaterials(widget.batch.id));
    await _materials;
  }

  Future<void> _uploadPdf() async {
    final input = await _showTextForm(
      context,
      title: 'Upload a PDF',
      nameLabel: 'Material title',
    );
    if (input == null) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (result.isEmpty) return;
      final file = result.single;
      final fileLength = await file.length();
      if (fileLength == null) {
        throw StateError('The selected PDF size could not be read.');
      }
      if (fileLength > 20 * 1024 * 1024) {
        throw StateError('PDF must be 20 MB or smaller.');
      }
      if (!file.name.toLowerCase().endsWith('.pdf')) {
        throw StateError('Choose a PDF file.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw StateError(
          'The selected file does not contain a valid PDF header.',
        );
      }
      await widget.backend.uploadPdf(
        batchId: widget.batch.id,
        title: input.$1,
        description: input.$2,
        fileName: file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_'),
        bytes: bytes,
      );
      await _refresh();
      if (mounted) _showMessage(context, 'PDF uploaded.');
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  Future<void> _openPdf(LearningMaterial material) async {
    try {
      final url = await widget.backend.createPdfLink(material.storagePath);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PdfPage(title: material.title, url: url),
        ),
      );
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LearningMaterial>>(
    future: _materials,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.batch.title)),
          body: _LoadError(
            message:
                'Could not load protected materials: '
                '${_errorText(snapshot.error!)}',
            onRetry: _refresh,
          ),
        );
      }
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.batch.title)),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      final materials = snapshot.data!;
      return Scaffold(
        appBar: AppBar(title: Text(widget.batch.title)),
        floatingActionButton: widget.canUpload
            ? FloatingActionButton.extended(
                onPressed: _uploadPdf,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload PDF'),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: materials.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 100),
                    _EmptyState(
                      icon: Icons.picture_as_pdf_outlined,
                      title: 'No learning materials yet',
                      detail: 'Your teacher will add content here.',
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      widget.batch.courseTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final material in materials)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.picture_as_pdf),
                          title: Text(material.title),
                          subtitle: material.description.isEmpty
                              ? null
                              : Text(material.description),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => _openPdf(material),
                        ),
                      ),
                  ],
                ),
        ),
      );
    },
  );
}

class _PdfPage extends StatelessWidget {
  const _PdfPage({required this.title, required this.url});

  final String title;
  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: PdfViewer.uri(Uri.parse(url)),
  );
}

Future<(String, String)?> _showTextForm(
  BuildContext context, {
  required String title,
  required String nameLabel,
}) {
  final name = TextEditingController();
  final description = TextEditingController();
  return showDialog<(String, String)>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            maxLength: 200,
            decoration: InputDecoration(labelText: nameLabel),
          ),
          TextField(
            controller: description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty) return;
            Navigator.pop(dialogContext, (
              name.text.trim(),
              description.text.trim(),
            ));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(() {
    name.dispose();
    description.dispose();
  });
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(detail, textAlign: TextAlign.center),
      ],
    ),
  );
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _errorText(Object error) {
  if (error is PostgrestException) {
    return error.message;
  }
  if (error is StorageException) {
    return error.message;
  }
  if (error is AuthException) {
    return error.message;
  }
  return error.toString();
}
