import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'backend.dart';
import 'dialogs.dart';
import 'links.dart';
import 'youtube.dart';

part 'batch_pages.dart';

/// The name people see. Internal IDs (package name, gyanify:// scheme,
/// database) keep the old "gyanify" name on purpose.
const appName = 'Meenakshi Amman Hindi Classes';

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
      title: appName,
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
              Text(appName, style: TextStyle(fontSize: 28)),
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
        onComplete: () => setState(() {
          _isPasswordRecovery = false;
        }),
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
              setState(() {
                _roleFuture = _backend.currentRole();
              });
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
        return MainShell(
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
        // With email confirmation off, sign-up signs the student in directly.
        if (response.session == null) {
          setState(() {
            _message =
                'Account created. If you received a verification email, '
                'open it first, then sign in.';
          });
        }
      } else {
        await _client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      setState(() {
        _message = error.message;
      });
    } catch (error) {
      setState(() {
        _message = _errorText(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _sendRecovery() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _message = 'Enter your email address first.';
      });
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
      setState(() {
        _message =
            'If this account exists, a password recovery link has been sent.';
      });
    } on AuthException catch (error) {
      setState(() {
        _message = error.message;
      });
    } catch (error) {
      setState(() {
        _message = _errorText(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
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
                      appName,
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
      setState(() {
        _message = 'Use at least 8 characters.';
      });
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
      setState(() {
        _message = error.message;
      });
    } catch (error) {
      setState(() {
        _message = _errorText(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
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

class MainShell extends StatefulWidget {
  const MainShell({
    required this.backend,
    required this.role,
    required this.displayName,
    super.key,
  });

  final GyanifyBackend backend;
  final String role;
  final String displayName;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  int _pendingRequests = 0;

  /// One per tab; firing it makes that tab reload its data.
  final _signals = List.generate(4, (_) => ReloadSignal());
  late final AppLifecycleListener _lifecycle;

  bool get _isTeacher => widget.role == 'teacher_admin';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _reloadCurrent);
    _loadPendingCount();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    for (final signal in _signals) {
      signal.dispose();
    }
    super.dispose();
  }

  /// Back from the background, Refresh button: reload what is on screen.
  void _reloadCurrent() {
    _signals[_selectedIndex].fire();
    _loadPendingCount();
  }

  void _select(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _reloadCurrent();
  }

  Future<void> _loadPendingCount() async {
    if (!_isTeacher) return;
    try {
      _setPending(await widget.backend.countPendingRequests());
    } catch (_) {
      // The badge is a hint; the Requests tab shows real errors.
    }
  }

  void _setPending(int count) {
    if (mounted && count != _pendingRequests) {
      setState(() {
        _pendingRequests = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTeacher = _isTeacher;
    final pages = isTeacher
        ? [
            TeacherCoursesPage(
              backend: widget.backend,
              reloadSignal: _signals[0],
            ),
            _TeacherRequestsPage(
              backend: widget.backend,
              reloadSignal: _signals[1],
              onPendingCount: _setPending,
            ),
            _LiveClassesPage(
              backend: widget.backend,
              isTeacher: true,
              reloadSignal: _signals[2],
            ),
            _ProfilePage(displayName: widget.displayName),
          ]
        : [
            _CatalogPage(backend: widget.backend, reloadSignal: _signals[0]),
            _StudentLearningPage(
              backend: widget.backend,
              reloadSignal: _signals[1],
            ),
            _LiveClassesPage(
              backend: widget.backend,
              isTeacher: false,
              reloadSignal: _signals[2],
            ),
            _ProfilePage(displayName: widget.displayName),
          ];
    final destinations = isTeacher
        ? [
            const NavigationDestination(
              icon: Icon(Icons.school_outlined),
              label: 'Courses',
            ),
            NavigationDestination(
              icon: Badge.count(
                count: _pendingRequests,
                isLabelVisible: _pendingRequests > 0,
                child: const Icon(Icons.how_to_reg_outlined),
              ),
              label: 'Requests',
              tooltip: _pendingRequests > 0
                  ? 'Requests ($_pendingRequests pending)'
                  : 'Requests',
            ),
            const NavigationDestination(
              icon: Icon(Icons.video_camera_front_outlined),
              label: 'Live Classes',
            ),
            const NavigationDestination(
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
      appBar: AppBar(
        title: AppHeaderTitle(isTeacher: isTeacher),
        actions: [
          if (_selectedIndex != 3)
            IconButton(
              tooltip: 'Refresh',
              onPressed: _reloadCurrent,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        destinations: destinations,
      ),
    );
  }
}

/// Two-line app bar title: the full app name, and who is signed in.
class AppHeaderTitle extends StatelessWidget {
  const AppHeaderTitle({required this.isTeacher, super.key});

  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Never cut the name: on a narrow phone or with a large font setting
        // it shrinks a little instead.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(appName, maxLines: 1, style: theme.textTheme.titleMedium),
        ),
        Text(
          isTeacher ? 'Teacher' : 'Student',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _LiveClassesPage extends StatefulWidget {
  const _LiveClassesPage({
    required this.backend,
    required this.isTeacher,
    this.reloadSignal,
  });

  final GyanifyBackend backend;
  final ReloadSignal? reloadSignal;
  final bool isTeacher;

  @override
  State<_LiveClassesPage> createState() => _LiveClassesPageState();
}

class _LiveClassesPageState extends State<_LiveClassesPage>
    with _ReloadsOnSignal<_LiveClassesPage> {
  @override
  ReloadSignal? get reloadSignal => widget.reloadSignal;

  late Future<List<LiveClass>> _classes = widget.backend.loadLiveClasses();

  @override
  Future<void> _refresh() async {
    setState(() {
      _classes = widget.backend.loadLiveClasses();
    });
    await _settle(_classes);
  }

  Future<void> _schedule() async {
    try {
      final courses = await widget.backend.loadTeacherCourses();
      final batches = [for (final c in courses) ...c.batches];
      if (!mounted) return;
      if (batches.isEmpty) {
        _showMessage(context, 'Create a course and a batch first.');
        return;
      }
      final input = await showDialog<LiveClassInput>(
        context: context,
        builder: (_) => ScheduleClassDialog(batches: batches),
      );
      if (input == null) return;
      await widget.backend.scheduleLiveClass(
        batchId: input.batchId,
        title: input.title,
        description: input.description,
        startsAt: input.startsAt,
        meetingUrl: input.meetingUrl,
      );
      await _refresh();
      if (mounted) _showMessage(context, 'Live class scheduled.');
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  Future<void> _delete(LiveClass liveClass) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this class?',
      detail: '"${liveClass.title}" will disappear for students.',
    );
    if (!confirmed) return;
    try {
      await widget.backend.deleteLiveClass(liveClass.id);
      await _refresh();
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: widget.isTeacher
        ? FloatingActionButton.extended(
            onPressed: _schedule,
            icon: const Icon(Icons.add),
            label: const Text('Schedule class'),
          )
        : null,
    body: FutureBuilder<List<LiveClass>>(
      future: _classes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _RefreshableList(
            onRefresh: _refresh,
            children: [
              _LoadError(
                message:
                    'Could not load live classes: ${_errorText(snapshot.error!)}',
                onRetry: _refresh,
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final classes = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                'Live classes',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                widget.isTeacher
                    ? 'Paste a Google Meet or Zoom link. Students of that '
                          'batch will see a Join button.'
                    : 'Classes for your approved batches appear here.',
              ),
              const SizedBox(height: 12),
              if (classes.isEmpty)
                const _EmptyState(
                  icon: Icons.video_camera_front_outlined,
                  title: 'No upcoming classes',
                  detail: 'Pull down to refresh.',
                )
              else
                for (final liveClass in classes)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            liveClass.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${liveClass.courseTitle} · ${liveClass.batchTitle}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(context, liveClass.startsAt),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (liveClass.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(liveClass.description),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (widget.isTeacher)
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () => _delete(liveClass),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: () => _openExternal(
                                  context,
                                  liveClass.meetingUrl,
                                ),
                                icon: const Icon(Icons.videocam_outlined),
                                label: const Text('Join'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    ),
  );
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Welcome${displayName.isEmpty ? '' : ', $displayName'}',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text('Your account role is managed securely by $appName.'),
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
  const _CatalogPage({required this.backend, this.reloadSignal});

  final GyanifyBackend backend;
  final ReloadSignal? reloadSignal;

  @override
  State<_CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<_CatalogPage>
    with _ReloadsOnSignal<_CatalogPage> {
  @override
  ReloadSignal? get reloadSignal => widget.reloadSignal;

  late Future<Catalog> _catalog = widget.backend.loadCatalog();

  @override
  Future<void> _refresh() async {
    setState(() {
      _catalog = widget.backend.loadCatalog();
    });
    await _settle(_catalog);
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
        return _RefreshableList(
          onRefresh: _refresh,
          children: [
            _LoadError(
              message: 'Could not load courses: ${_errorText(snapshot.error!)}',
              onRetry: _refresh,
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final catalog = snapshot.data!;
      if (catalog.courses.isEmpty) {
        return _RefreshableList(
          onRefresh: _refresh,
          children: [
            const _EmptyState(
              icon: Icons.school_outlined,
              title: 'No courses yet',
              detail: 'Available courses will appear here.',
            ),
          ],
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                                builder: (_) => BatchPage(
                                  backend: widget.backend,
                                  batch: batch,
                                  isTeacher: false,
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
  const _StudentLearningPage({required this.backend, this.reloadSignal});

  final GyanifyBackend backend;
  final ReloadSignal? reloadSignal;

  @override
  State<_StudentLearningPage> createState() => _StudentLearningPageState();
}

class _StudentLearningPageState extends State<_StudentLearningPage>
    with _ReloadsOnSignal<_StudentLearningPage> {
  @override
  ReloadSignal? get reloadSignal => widget.reloadSignal;

  late Future<List<LearningBatch>> _batches = widget.backend
      .loadApprovedBatches();

  @override
  Future<void> _refresh() async {
    setState(() {
      _batches = widget.backend.loadApprovedBatches();
    });
    await _settle(_batches);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LearningBatch>>(
    future: _batches,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _RefreshableList(
          onRefresh: _refresh,
          children: [
            _LoadError(
              message:
                  'Could not load your batches: '
                  '${_errorText(snapshot.error!)}',
              onRetry: _refresh,
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final batches = snapshot.data!;
      if (batches.isEmpty) {
        return _RefreshableList(
          onRefresh: _refresh,
          children: [
            const _EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'Nothing to learn yet',
              detail: 'Request to join a batch. Approved batches appear here.',
            ),
          ],
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                      builder: (_) => BatchPage(
                        backend: widget.backend,
                        batch: batch,
                        isTeacher: false,
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

class TeacherCoursesPage extends StatefulWidget {
  const TeacherCoursesPage({
    required this.backend,
    this.reloadSignal,
    super.key,
  });

  final GyanifyBackend backend;
  final ReloadSignal? reloadSignal;

  @override
  State<TeacherCoursesPage> createState() => _TeacherCoursesPageState();
}

class _TeacherCoursesPageState extends State<TeacherCoursesPage>
    with _ReloadsOnSignal<TeacherCoursesPage> {
  @override
  ReloadSignal? get reloadSignal => widget.reloadSignal;

  late Future<List<LearningCourse>> _courses = widget.backend
      .loadTeacherCourses();

  @override
  Future<void> _refresh() async {
    setState(() {
      _courses = widget.backend.loadTeacherCourses();
    });
    await _settle(_courses);
  }

  Future<void> _createCourse() async {
    final values = await showTextForm(
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
    final values = await showTextForm(
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
        return _RefreshableList(
          onRefresh: _refresh,
          children: [
            _LoadError(
              message: 'Could not load courses: ${_errorText(snapshot.error!)}',
              onRetry: _refresh,
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final courses = snapshot.data!;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                                builder: (_) => BatchPage(
                                  backend: widget.backend,
                                  batch: batch,
                                  isTeacher: true,
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
  const _TeacherRequestsPage({
    required this.backend,
    this.reloadSignal,
    this.onPendingCount,
  });

  final GyanifyBackend backend;
  final ReloadSignal? reloadSignal;

  /// Tells MainShell how many requests are pending (for the badge).
  final ValueChanged<int>? onPendingCount;

  @override
  State<_TeacherRequestsPage> createState() => _TeacherRequestsPageState();
}

class _TeacherRequestsPageState extends State<_TeacherRequestsPage>
    with _ReloadsOnSignal<_TeacherRequestsPage> {
  @override
  ReloadSignal? get reloadSignal => widget.reloadSignal;

  late Future<List<EnrollmentRequest>> _requests = _load();

  Future<List<EnrollmentRequest>> _load() async {
    final requests = await widget.backend.loadEnrollmentRequests();
    widget.onPendingCount?.call(
      requests.where((r) => r.status == 'pending').length,
    );
    return requests;
  }

  @override
  Future<void> _refresh() async {
    setState(() {
      _requests = _load();
    });
    await _settle(_requests);
  }

  Future<void> _review(EnrollmentRequest request, String status) async {
    try {
      await widget.backend.reviewEnrollment(request.id, status);
      await _refresh();
      if (mounted) {
        _showMessage(context, switch (status) {
          'approved' => 'Student approved.',
          'revoked' => 'Access removed.',
          _ => 'Request rejected.',
        });
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
        return _RefreshableList(
          onRefresh: _refresh,
          children: [
            _LoadError(
              message:
                  'Could not load enrollment requests: ${_errorText(snapshot.error!)}',
              onRetry: _refresh,
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final requests = snapshot.data!;
      if (requests.isEmpty) {
        return _RefreshableList(
          onRefresh: _refresh,
          children: [
            const _EmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'No enrollment requests',
              detail: 'New student requests for your batches will appear here.',
            ),
          ],
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                      if (request.studentEmail.isNotEmpty)
                        Text(request.studentEmail),
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
                        Row(
                          children: [
                            Text(switch (request.status) {
                              'approved' => 'Approved',
                              'rejected' => 'Rejected',
                              'revoked' => 'Access removed',
                              _ => request.status,
                            }),
                            const Spacer(),
                            if (request.status == 'approved')
                              TextButton(
                                onPressed: () => _review(request, 'revoked'),
                                child: const Text('Remove access'),
                              )
                            else
                              TextButton(
                                onPressed: () => _review(request, 'approved'),
                                child: const Text('Approve'),
                              ),
                          ],
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

class _VideoPage extends StatefulWidget {
  const _VideoPage({required this.title, required this.videoId});

  final String title;
  final String videoId;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final YoutubePlayerController _controller =
      YoutubePlayerController.fromVideoId(
        videoId: widget.videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          strictRelatedVideos: true,
        ),
      );

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        YoutubePlayer(controller: _controller),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text(
                'Video not playing? Open it in the YouTube app instead.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    _openExternal(context, canonicalYoutubeUrl(widget.videoId)),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in YouTube'),
              ),
            ],
          ),
        ),
      ],
    ),
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

/// Opens Meet, Zoom, YouTube or a download link outside the app.
Future<void> _openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    _showMessage(context, 'Could not open the link.');
  }
}

String _formatDateTime(BuildContext context, DateTime value) {
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatFullDate(value)} · '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
}

/// Pull-to-refresh list that also works when it only holds an empty or
/// error message (AlwaysScrollableScrollPhysics).
class _RefreshableList extends StatelessWidget {
  const _RefreshableList({required this.onRefresh, required this.children});

  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: children,
    ),
  );
}

/// Waits for a load without throwing: its FutureBuilder shows the error.
Future<void> _settle(Future<Object?> load) =>
    load.then<void>((_) {}, onError: (Object _) {});

/// MainShell fires this to make a tab reload (tab switch, app resume,
/// Refresh button).
class ReloadSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Reloads a tab whenever its [ReloadSignal] fires.
mixin _ReloadsOnSignal<T extends StatefulWidget> on State<T> {
  ReloadSignal? get reloadSignal;
  Future<void> _refresh();

  void _onSignal() {
    if (mounted) _refresh();
  }

  @override
  void initState() {
    super.initState();
    reloadSignal?.addListener(_onSignal);
  }

  @override
  void dispose() {
    reloadSignal?.removeListener(_onSignal);
    super.dispose();
  }
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
