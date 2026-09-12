import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import 'admin_api.dart';

enum _AdminSection {
  dashboard,
  lessons,
  users,
  projects,
}

class AdminApp extends StatefulComponent {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  static const _tokenStorageKey = 'flutter_workbench_admin_token';

  late final AdminApi _api;

  String _email = '';
  String _password = '';
  String? _token;
  String? _adminUsername;
  String? _error;
  String? _notice;
  bool _busy = false;
  _AdminSection _section = _AdminSection.dashboard;

  Map<String, dynamic> _overview = <String, dynamic>{};
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _projects = <Map<String, dynamic>>[];
  Map<String, dynamic>? _lessonCatalog;
  String _catalogDraft = '';
  int? _selectedLessonProjectIndex;
  int? _selectedLessonIndex;

  @override
  void initState() {
    super.initState();
    _api = AdminApi();
    final storedToken = web.window.sessionStorage.getItem(_tokenStorageKey);
    if (storedToken != null && storedToken.trim().isNotEmpty) {
      _token = storedToken.trim();
      Future<void>.microtask(_restoreSession);
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final token = _token;
    if (token == null) return;

    _setBusy(true);
    try {
      final me = await _api.verifyAdmin(token);
      _adminUsername = me['username']?.toString();
      await _refreshAll();
    } catch (error) {
      web.window.sessionStorage.removeItem(_tokenStorageKey);
      setState(() {
        _token = null;
        _adminUsername = null;
        _error = _message(error);
      });
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _login() async {
    if (_email.trim().isEmpty || _password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }

    _setBusy(true);
    _clearMessages();
    try {
      final session = await _api.login(
        email: _email,
        password: _password,
      );
      await _api.verifyAdmin(session.accessToken);
      web.window.sessionStorage.setItem(
        _tokenStorageKey,
        session.accessToken,
      );
      setState(() {
        _token = session.accessToken;
        _adminUsername = session.username;
        _password = '';
      });
      await _refreshAll();
    } catch (error) {
      setState(() => _error = _message(error));
    } finally {
      _setBusy(false);
    }
  }

  void _logout() {
    web.window.sessionStorage.removeItem(_tokenStorageKey);
    setState(() {
      _token = null;
      _adminUsername = null;
      _overview = <String, dynamic>{};
      _users = <Map<String, dynamic>>[];
      _projects = <Map<String, dynamic>>[];
      _lessonCatalog = null;
      _catalogDraft = '';
      _selectedLessonProjectIndex = null;
      _selectedLessonIndex = null;
      _section = _AdminSection.dashboard;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _refreshAll() async {
    final token = _token;
    if (token == null) return;

    _clearMessages();
    final overview = await _api.overview(token);
    final users = await _api.users(token);
    final projects = await _api.projects(token);

    Map<String, dynamic>? lessons;
    try {
      lessons = await _api.lessons(token);
    } on AdminApiException catch (error) {
      if (error.statusCode != 404) rethrow;
    }

    setState(() {
      _overview = overview;
      _users = users;
      _projects = projects;
      _lessonCatalog = lessons;
      _catalogDraft = lessons == null
          ? ''
          : const JsonEncoder.withIndent('  ').convert(lessons);
      _normalizeLessonSelection();
    });
  }

  Future<void> _refreshCurrent() async {
    _setBusy(true);
    try {
      await _refreshAll();
      setState(() => _notice = 'Data refreshed.');
    } catch (error) {
      setState(() => _error = _message(error));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final token = _token;
    final userId = user['userId']?.toString() ?? '';
    final username = user['username']?.toString() ?? userId;
    if (token == null || userId.isEmpty) return;

    final confirmed = web.window.confirm(
      'Delete user "$username" and all of their Workspace projects? This cannot be undone.',
    );
    if (!confirmed) return;

    _setBusy(true);
    try {
      await _api.deleteUser(token, userId);
      await _refreshAll();
      setState(() => _notice = 'User $username deleted.');
    } catch (error) {
      setState(() => _error = _message(error));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _deleteProject(Map<String, dynamic> row) async {
    final token = _token;
    final owner = _map(row['owner']);
    final project = _map(row['project']);
    final userId = owner['userId']?.toString() ?? '';
    final workspaceId = project['id']?.toString() ?? '';
    final projectName = project['name']?.toString() ?? workspaceId;
    if (token == null || userId.isEmpty || workspaceId.isEmpty) return;

    final confirmed = web.window.confirm(
      'Delete project "$projectName" from ${owner['username'] ?? userId}? This cannot be undone.',
    );
    if (!confirmed) return;

    _setBusy(true);
    try {
      await _api.deleteProject(
        token,
        userId: userId,
        workspaceId: workspaceId,
      );
      await _refreshAll();
      setState(() => _notice = 'Project $projectName deleted.');
    } catch (error) {
      setState(() => _error = _message(error));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _saveLessons() async {
    final token = _token;
    final catalog = _lessonCatalog;
    if (token == null || catalog == null) return;

    _setBusy(true);
    _clearMessages();
    try {
      final saved = await _api.saveLessons(token, catalog);
      setState(() {
        _lessonCatalog = saved;
        _catalogDraft = const JsonEncoder.withIndent('  ').convert(saved);
        _notice = 'Lesson catalog saved.';
      });
      _overview = await _api.overview(token);
    } catch (error) {
      setState(() => _error = _message(error));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _saveCatalogJson() async {
    final token = _token;
    if (token == null) return;

    _setBusy(true);
    _clearMessages();
    try {
      final decoded = jsonDecode(_catalogDraft);
      if (decoded is! Map) {
        throw const FormatException('Catalog JSON must be an object.');
      }
      final saved = await _api.saveLessons(
        token,
        Map<String, dynamic>.from(decoded),
      );
      setState(() {
        _lessonCatalog = saved;
        _catalogDraft = const JsonEncoder.withIndent('  ').convert(saved);
        _notice = 'Full lesson JSON saved.';
        _normalizeLessonSelection();
      });
      _overview = await _api.overview(token);
    } catch (error) {
      setState(() => _error = _message(error));
    } finally {
      _setBusy(false);
    }
  }

  void _normalizeLessonSelection() {
    final projects = _lessonProjects;
    if (projects.isEmpty) {
      _selectedLessonProjectIndex = null;
      _selectedLessonIndex = null;
      return;
    }

    var projectIndex = _selectedLessonProjectIndex ?? 0;
    if (projectIndex < 0 || projectIndex >= projects.length) projectIndex = 0;
    final lessons = _lessonsForProject(projects[projectIndex]);
    if (lessons.isEmpty) {
      _selectedLessonProjectIndex = projectIndex;
      _selectedLessonIndex = null;
      return;
    }

    var lessonIndex = _selectedLessonIndex ?? 0;
    if (lessonIndex < 0 || lessonIndex >= lessons.length) lessonIndex = 0;
    _selectedLessonProjectIndex = projectIndex;
    _selectedLessonIndex = lessonIndex;
  }

  void _selectLesson(int projectIndex, int lessonIndex) {
    setState(() {
      _selectedLessonProjectIndex = projectIndex;
      _selectedLessonIndex = lessonIndex;
      _error = null;
      _notice = null;
    });
  }

  void _updateSelectedLesson(String key, Object? value) {
    final lesson = _selectedLesson;
    if (lesson == null) return;
    lesson[key] = value;
  }

  void _setBusy(bool value) {
    setState(() => _busy = value);
  }

  void _clearMessages() {
    setState(() {
      _error = null;
      _notice = null;
    });
  }

  String _message(Object error) {
    if (error is AdminApiException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }

  List<Map<String, dynamic>> get _lessonProjects {
    final raw = _lessonCatalog?['projects'];
    if (raw is! Iterable) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map(_map).toList(growable: false);
  }

  List<Map<String, dynamic>> _lessonsForProject(Map<String, dynamic> project) {
    final raw = project['lessons'];
    if (raw is! Iterable) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map(_map).toList(growable: false);
  }

  Map<String, dynamic>? get _selectedLesson {
    final projectIndex = _selectedLessonProjectIndex;
    final lessonIndex = _selectedLessonIndex;
    final projects = _lessonProjects;
    if (projectIndex == null ||
        lessonIndex == null ||
        projectIndex < 0 ||
        projectIndex >= projects.length) {
      return null;
    }
    final lessons = _lessonsForProject(projects[projectIndex]);
    if (lessonIndex < 0 || lessonIndex >= lessons.length) return null;
    return lessons[lessonIndex];
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(value);
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'admin-root', [
      if (_token == null) _buildLogin() else _buildConsole(),
    ]);
  }

  Component _buildLogin() {
    return div(classes: 'login-page', [
      div(classes: 'login-orb login-orb-one', []),
      div(classes: 'login-orb login-orb-two', []),
      div(classes: 'login-card', [
        div(classes: 'brand-lockup', [
          div(classes: 'brand-mark', [text('FW')]),
          div([
            h1([text('Flutter Workbench')]),
            p(classes: 'muted', [text('Administration console')]),
          ]),
        ]),
        div(classes: 'login-copy', [
          h2([text('Welcome back')]),
          p([
            text(
              'Sign in with an existing Flutter Workbench account configured as an administrator.',
            ),
          ]),
        ]),
        label(classes: 'field-label', [text('Email')]),
        input<String>(
          attributes: const <String, String>{
            'type': 'email',
            'autocomplete': 'email',
            'placeholder': 'you@example.com',
          },
          events: events<String>(onInput: (value) => _email = value),
          [],
        ),
        const SizedBoxComponent(height: 0),
        label(classes: 'field-label password-label', [text('Password')]),
        input<String>(
          attributes: const <String, String>{
            'type': 'password',
            'autocomplete': 'current-password',
            'placeholder': '••••••••',
          },
          events: events<String>(onInput: (value) => _password = value),
          [],
        ),
        if (_error != null)
          div(classes: 'message error-message', [text(_error!)]),
        button(
          classes: 'primary-button login-button',
          disabled: _busy,
          onClick: _login,
          [text(_busy ? 'Signing in…' : 'Sign in')],
        ),
        p(classes: 'login-footnote', [
          text('Admin access is enforced by the Workspace backend.'),
        ]),
      ]),
    ]);
  }

  Component _buildConsole() {
    return div(classes: 'console-shell', [
      aside(classes: 'sidebar', [
        div(classes: 'sidebar-brand', [
          div(classes: 'brand-mark small', [text('FW')]),
          div([
            strong([text('Flutter Workbench')]),
            span([text('Admin')]),
          ]),
        ]),
        nav(classes: 'nav-list', [
          _navButton(_AdminSection.dashboard, 'Overview', '⌂'),
          _navButton(_AdminSection.lessons, 'Courses', '◫'),
          _navButton(_AdminSection.users, 'Users', '◎'),
          _navButton(_AdminSection.projects, 'Projects', '◇'),
        ]),
        div(classes: 'sidebar-footer', [
          div(classes: 'admin-chip', [
            div(classes: 'avatar-dot', [
              text(
                (_adminUsername?.isNotEmpty == true
                        ? _adminUsername![0]
                        : 'A')
                    .toUpperCase(),
              ),
            ]),
            div([
              strong([text(_adminUsername ?? 'Administrator')]),
              span([text('Administrator')]),
            ]),
          ]),
          button(classes: 'ghost-button full-button', onClick: _logout, [
            text('Sign out'),
          ]),
        ]),
      ]),
      div(classes: 'content-shell', [
        div(classes: 'topbar', [
          div([
            p(classes: 'eyebrow', [text('FLUTTER WORKBENCH')]),
            h1([text(_sectionTitle)]),
          ]),
          div(classes: 'topbar-actions', [
            if (_busy) span(classes: 'syncing', [text('Syncing…')]),
            button(
              classes: 'ghost-button',
              disabled: _busy,
              onClick: _refreshCurrent,
              [text('↻ Refresh')],
            ),
          ]),
        ]),
        if (_error != null)
          div(classes: 'message error-message banner', [text(_error!)]),
        if (_notice != null)
          div(classes: 'message success-message banner', [text(_notice!)]),
        div(classes: 'page-content', [
          switch (_section) {
            _AdminSection.dashboard => _buildDashboard(),
            _AdminSection.lessons => _buildLessons(),
            _AdminSection.users => _buildUsers(),
            _AdminSection.projects => _buildProjects(),
          },
        ]),
      ]),
    ]);
  }

  String get _sectionTitle => switch (_section) {
        _AdminSection.dashboard => 'Overview',
        _AdminSection.lessons => 'Courses',
        _AdminSection.users => 'User accounts',
        _AdminSection.projects => 'Workspace projects',
      };

  Component _navButton(_AdminSection section, String labelText, String iconText) {
    final selected = _section == section;
    return button(
      classes: 'nav-button${selected ? ' selected' : ''}',
      onClick: () => setState(() {
        _section = section;
        _error = null;
        _notice = null;
      }),
      [
        span(classes: 'nav-icon', [text(iconText)]),
        span([text(labelText)]),
      ],
    );
  }

  Component _buildDashboard() {
    return div([
      div(classes: 'hero-panel', [
        div([
          p(classes: 'eyebrow', [text('SYSTEM STATUS')]),
          h2([text('One place to manage your learning platform')]),
          p(classes: 'muted hero-copy', [
            text(
              'Courses, Workspace users and projects are now managed through the same authenticated backend.',
            ),
          ]),
        ]),
        div(classes: 'status-pill', [
          span(classes: 'status-dot', []),
          text('Workspace API connected'),
        ]),
      ]),
      div(classes: 'stat-grid', [
        _statCard('Users', '${_overview['users'] ?? _users.length}', 'Registered accounts'),
        _statCard('Projects', '${_overview['projects'] ?? _projects.length}', 'Cloud workspaces'),
        _statCard('Courses', '${_overview['lessons'] ?? 0}', 'Lesson entries'),
        _statCard(
          'Catalog',
          _overview['lessonCatalogInitialized'] == true ? 'Live' : 'Seed pending',
          _overview['lessonCatalogInitialized'] == true
              ? 'Remote source of truth'
              : 'Open Lesson Mode once as admin',
        ),
      ]),
      div(classes: 'two-column-grid', [
        div(classes: 'panel', [
          div(classes: 'panel-heading', [
            div([
              h3([text('Content pipeline')]),
              p(classes: 'muted', [
                text('How lessons move from authoring to students.'),
              ]),
            ]),
          ]),
          _timelineItem('1', 'Seed', 'Existing LessonCatalog migrates once.'),
          _timelineItem('2', 'Manage', 'Edit and publish from this Jaspr console.'),
          _timelineItem('3', 'Consume', 'Flutter Lesson Mode reads /content/lessons.'),
          _timelineItem('4', 'Fallback', 'Offline clients keep the built-in catalog.'),
        ]),
        div(classes: 'panel', [
          div(classes: 'panel-heading', [
            div([
              h3([text('Recent platform snapshot')]),
              p(classes: 'muted', [
                text('Quick operational totals from Workspace Storage.'),
              ]),
            ]),
          ]),
          _keyValue('Admin', _adminUsername ?? '—'),
          _keyValue('Users', '${_users.length}'),
          _keyValue('Projects', '${_projects.length}'),
          _keyValue(
            'Lesson groups',
            '${_overview['lessonProjects'] ?? _lessonProjects.length}',
          ),
          _keyValue(
            'Last lesson update',
            _overview['lessonCatalogUpdatedAt']?.toString() ?? 'Not initialized',
          ),
        ]),
      ]),
    ]);
  }

  Component _statCard(String title, String value, String caption) {
    return div(classes: 'stat-card', [
      p(classes: 'stat-title', [text(title)]),
      strong(classes: 'stat-value', [text(value)]),
      p(classes: 'muted stat-caption', [text(caption)]),
    ]);
  }

  Component _timelineItem(String number, String title, String copy) {
    return div(classes: 'timeline-item', [
      div(classes: 'timeline-index', [text(number)]),
      div([
        strong([text(title)]),
        p(classes: 'muted', [text(copy)]),
      ]),
    ]);
  }

  Component _keyValue(String labelText, String value) {
    return div(classes: 'key-value', [
      span(classes: 'muted', [text(labelText)]),
      strong([text(value)]),
    ]);
  }

  Component _buildLessons() {
    final catalog = _lessonCatalog;
    if (catalog == null) {
      return div(classes: 'empty-state panel', [
        div(classes: 'empty-icon', [text('◫')]),
        h2([text('Lesson catalog has not been migrated yet')]),
        p(classes: 'muted', [
          text(
            'After this backend is deployed with your admin username configured, sign into Flutter Workbench and open Lesson Mode once. The existing hardcoded LessonCatalog will be uploaded automatically and will then appear here.',
          ),
        ]),
        button(classes: 'ghost-button', onClick: _refreshCurrent, [
          text('Check again'),
        ]),
      ]);
    }

    final projects = _lessonProjects;
    final selected = _selectedLesson;

    return div([
      div(classes: 'section-toolbar', [
        div([
          h2([text('Course catalog')]),
          p(classes: 'muted', [
            text('${projects.length} groups · ${_overview['lessons'] ?? 0} lessons'),
          ]),
        ]),
        button(
          classes: 'primary-button',
          disabled: _busy,
          onClick: _saveLessons,
          [text('Save course changes')],
        ),
      ]),
      div(classes: 'lesson-workspace', [
        div(classes: 'lesson-tree panel', [
          for (var projectIndex = 0;
              projectIndex < projects.length;
              projectIndex++)
            _lessonProjectGroup(projectIndex, projects[projectIndex]),
        ]),
        div(classes: 'lesson-editor panel', [
          if (selected == null)
            div(classes: 'empty-editor', [
              h3([text('Select a lesson')]),
              p(classes: 'muted', [text('Choose a lesson from the left to edit it.')]),
            ])
          else
            _lessonForm(selected),
        ]),
      ]),
      div(classes: 'panel json-panel', [
        div(classes: 'panel-heading', [
          div([
            h3([text('Advanced catalog JSON')]),
            p(classes: 'muted', [
              text(
                'Edit steps, hints, starter code, answer assets and AST requirements without waiting for a dedicated form field.',
              ),
            ]),
          ]),
          button(
            classes: 'ghost-button',
            disabled: _busy,
            onClick: _saveCatalogJson,
            [text('Validate & save JSON')],
          ),
        ]),
        textarea(
          classes: 'json-editor',
          attributes: const <String, String>{
            'spellcheck': 'false',
            'aria-label': 'Lesson catalog JSON',
          },
          events: events<String>(onInput: (value) => _catalogDraft = value),
          [text(_catalogDraft)],
        ),
      ]),
    ]);
  }

  Component _lessonProjectGroup(
    int projectIndex,
    Map<String, dynamic> project,
  ) {
    final lessons = _lessonsForProject(project);
    return div(classes: 'lesson-group', [
      div(classes: 'lesson-group-title', [
        span(classes: 'lesson-group-dot', []),
        div([
          strong([text(project['title']?.toString() ?? 'Untitled group')]),
          span([text('${lessons.length} lessons')]),
        ]),
      ]),
      div(classes: 'lesson-list', [
        for (var lessonIndex = 0; lessonIndex < lessons.length; lessonIndex++)
          button(
            classes: 'lesson-row${_selectedLessonProjectIndex == projectIndex && _selectedLessonIndex == lessonIndex ? ' selected' : ''}',
            onClick: () => _selectLesson(projectIndex, lessonIndex),
            [
              span(classes: 'lesson-number', [text('${lessonIndex + 1}')]),
              span(classes: 'lesson-row-copy', [
                strong([text(lessons[lessonIndex]['title']?.toString() ?? 'Untitled')]),
                span([
                  text(
                    lessons[lessonIndex]['comingSoon'] == true
                        ? 'Coming soon'
                        : lessons[lessonIndex]['category']?.toString() ?? 'Lesson',
                  ),
                ]),
              ]),
            ],
          ),
      ]),
    ]);
  }

  Component _lessonForm(Map<String, dynamic> lesson) {
    final lessonId = lesson['id']?.toString() ?? 'lesson';
    return div(key: ValueKey<String>('lesson-editor-$lessonId'), [
      div(classes: 'editor-heading', [
        div([
          p(classes: 'eyebrow', [text(lessonId)]),
          h2([text(lesson['title']?.toString() ?? 'Untitled lesson')]),
        ]),
        span(
          classes: 'badge${lesson['comingSoon'] == true ? ' pending' : ''}',
          [text(lesson['comingSoon'] == true ? 'Coming soon' : 'Published')],
        ),
      ]),
      _formField(
        'Title',
        lesson['title']?.toString() ?? '',
        (value) => _updateSelectedLesson('title', value),
      ),
      _formArea(
        'Description',
        lesson['description']?.toString() ?? '',
        (value) => _updateSelectedLesson('description', value),
      ),
      div(classes: 'form-grid', [
        _formField(
          'Category',
          lesson['category']?.toString() ?? '',
          (value) => _updateSelectedLesson('category', value),
        ),
        _formField(
          'Difficulty',
          lesson['difficulty']?.toString() ?? '',
          (value) => _updateSelectedLesson('difficulty', value),
        ),
      ]),
      div(classes: 'form-grid', [
        _formField(
          'Estimated minutes',
          '${lesson['estimatedMinutes'] ?? 0}',
          (value) => _updateSelectedLesson(
            'estimatedMinutes',
            int.tryParse(value) ?? 0,
          ),
          type: 'number',
        ),
        _formField(
          'Tags (comma separated)',
          _stringList(lesson['tags']).join(', '),
          (value) => _updateSelectedLesson(
            'tags',
            value
                .split(',')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false),
          ),
        ),
      ]),
      label(classes: 'toggle-row', [
        input<bool>(
          attributes: <String, String>{
            'type': 'checkbox',
            if (lesson['comingSoon'] == true) 'checked': 'checked',
          },
          events: events<bool>(
            onChange: (value) => _updateSelectedLesson('comingSoon', value),
          ),
          [],
        ),
        span([
          strong([text('Coming soon')]),
          span(classes: 'muted', [
            text('Disable opening this lesson in the Flutter client.'),
          ]),
        ]),
      ]),
      div(classes: 'lesson-meta-strip', [
        _miniMeta('Steps', '${(lesson['steps'] as List?)?.length ?? 0}'),
        _miniMeta('Version', lesson['version']?.toString() ?? 'beginner'),
        _miniMeta('ID', lessonId),
      ]),
      p(classes: 'muted editor-note', [
        text(
          'For starter code, hints, answer assets and checking requirements, use the full JSON editor below. Those values are preserved exactly.',
        ),
      ]),
    ]);
  }

  Component _formField(
    String labelText,
    String value,
    void Function(String) onInput, {
    String type = 'text',
  }) {
    return label(classes: 'field-block', [
      span(classes: 'field-label', [text(labelText)]),
      input<String>(
        attributes: <String, String>{
          'type': type,
          'value': value,
        },
        events: events<String>(onInput: onInput),
        [],
      ),
    ]);
  }

  Component _formArea(
    String labelText,
    String value,
    void Function(String) onInput,
  ) {
    return label(classes: 'field-block', [
      span(classes: 'field-label', [text(labelText)]),
      textarea(
        events: events<String>(onInput: onInput),
        [text(value)],
      ),
    ]);
  }

  Component _miniMeta(String labelText, String value) {
    return div([
      span(classes: 'muted', [text(labelText)]),
      strong([text(value)]),
    ]);
  }

  Component _buildUsers() {
    return div([
      div(classes: 'section-toolbar', [
        div([
          h2([text('Registered accounts')]),
          p(classes: 'muted', [
            text('${_users.length} accounts in Workspace Storage'),
          ]),
        ]),
      ]),
      div(classes: 'panel table-panel', [
        div(classes: 'data-table', [
          div(classes: 'table-row table-head users-grid', [
            span([text('User')]),
            span([text('Email')]),
            span([text('Sessions')]),
            span([text('Created')]),
            span([text('')]),
          ]),
          for (final user in _users)
            div(classes: 'table-row users-grid', [
              div(classes: 'user-cell', [
                div(classes: 'avatar-dot', [
                  text(
                    (user['username']?.toString().isNotEmpty == true
                            ? user['username'].toString()[0]
                            : 'U')
                        .toUpperCase(),
                  ),
                ]),
                div([
                  strong([text(user['username']?.toString() ?? 'Unknown')]),
                  span(classes: 'muted mono-small', [
                    text(user['userId']?.toString() ?? ''),
                  ]),
                ]),
              ]),
              span([text(user['email']?.toString() ?? '—')]),
              span([text('${user['activeSessions'] ?? 0}')]),
              span([text(_shortDate(user['createdAt']))]),
              div(classes: 'row-actions', [
                if (user['username']?.toString() == _adminUsername)
                  span(classes: 'badge', [text('Current admin')])
                else
                  button(
                    classes: 'danger-button compact-button',
                    disabled: _busy,
                    onClick: () => _deleteUser(user),
                    [text('Delete')],
                  ),
              ]),
            ]),
        ]),
      ]),
    ]);
  }

  Component _buildProjects() {
    return div([
      div(classes: 'section-toolbar', [
        div([
          h2([text('Workspace projects')]),
          p(classes: 'muted', [
            text('${_projects.length} projects across all users'),
          ]),
        ]),
      ]),
      div(classes: 'project-grid', [
        for (final row in _projects) _projectCard(row),
      ]),
      if (_projects.isEmpty)
        div(classes: 'empty-state panel', [
          div(classes: 'empty-icon', [text('◇')]),
          h3([text('No projects yet')]),
          p(classes: 'muted', [
            text('Projects created in Flutter Workbench will appear here.'),
          ]),
        ]),
    ]);
  }

  Component _projectCard(Map<String, dynamic> row) {
    final owner = _map(row['owner']);
    final project = _map(row['project']);
    final name = project['name']?.toString() ?? 'Untitled project';
    final slug = project['slug']?.toString() ?? project['id']?.toString() ?? '';
    final ownerName = owner['username']?.toString() ?? 'unknown';
    final kind = project['kind']?.toString() ?? 'workspace';
    final platforms = _stringList(project['flutterPlatforms']);

    return div(classes: 'project-card', [
      div(classes: 'project-card-top', [
        div(classes: 'project-mark', [text('</>')]),
        span(classes: 'badge', [text(kind)]),
      ]),
      h3([text(name)]),
      p(classes: 'project-path', [text('$ownerName/$slug')]),
      p(classes: 'muted', [
        text(platforms.isEmpty ? 'Workspace project' : platforms.join(' · ')),
      ]),
      div(classes: 'project-owner', [
        span([text(owner['email']?.toString() ?? ownerName)]),
        button(
          classes: 'danger-button compact-button',
          disabled: _busy,
          onClick: () => _deleteProject(row),
          [text('Delete')],
        ),
      ]),
    ]);
  }

  List<String> _stringList(Object? source) {
    if (source is! Iterable) return const <String>[];
    return source.map((item) => item.toString()).toList(growable: false);
  }

  String _shortDate(Object? source) {
    final value = source?.toString() ?? '';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return '—';
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }
}

/// Zero-layout compatibility component used only to keep spacing code simple in
/// the login form while Jaspr renders native HTML/CSS.
class SizedBoxComponent extends StatelessComponent {
  const SizedBoxComponent({required this.height, super.key});

  final double height;

  @override
  Component build(BuildContext context) {
    return div(
      attributes: <String, String>{'style': 'height:${height}px'},
      [],
    );
  }
}
