import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import 'admin_api.dart';
import 'catalog_localization.dart';

enum _AdminSection { dashboard, lessons, users, projects }

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
  int? _selectedProjectIndex;
  int? _selectedLessonIndex;
  String _courseEditLanguage = 'en';

  int? _creatingCourseGroupIndex;
  String _newCourseId = '';
  String _newCourseTitle = '';
  String _newCourseDescription = '';
  String _newCourseCategory = '';
  String _newCourseDifficulty = 'Beginner';
  String _newCourseMinutes = '60';
  String _newCourseTags = '';
  bool _newCourseComingSoon = false;

  @override
  void initState() {
    super.initState();
    _api = AdminApi();
    final stored = web.window.sessionStorage.getItem(_tokenStorageKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _token = stored.trim();
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
      final session = await _api.login(email: _email, password: _password);
      await _api.verifyAdmin(session.accessToken);
      web.window.sessionStorage.setItem(_tokenStorageKey, session.accessToken);
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
      _selectedProjectIndex = null;
      _selectedLessonIndex = null;
      _creatingCourseGroupIndex = null;
      _courseEditLanguage = 'en';
      _section = _AdminSection.dashboard;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _refreshAll() async {
    final token = _token;
    if (token == null) return;
    final overview = await _api.overview(token);
    final users = await _api.users(token);
    final projects = await _api.projects(token);
    Map<String, dynamic>? lessons;
    try {
      lessons = await _api.lessons(
        token,
        languageCode: _courseEditLanguage,
      );
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
    _clearMessages();
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
    final id = user['userId']?.toString() ?? '';
    final name = user['username']?.toString() ?? id;
    if (token == null || id.isEmpty) return;
    if (!web.window.confirm(
      'Delete user "$name" and all of their Workspace projects? This cannot be undone.',
    )) return;

    _setBusy(true);
    try {
      await _api.deleteUser(token, id);
      await _refreshAll();
      setState(() => _notice = 'User $name deleted.');
    } catch (error) {
      setState(() => _error = _message(error));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _deleteProject(Map<String, dynamic> row) async {
    final token = _token;
    final owner = _mapRef(row['owner']);
    final project = _mapRef(row['project']);
    final userId = owner['userId']?.toString() ?? '';
    final workspaceId = project['id']?.toString() ?? '';
    final name = project['name']?.toString() ?? workspaceId;
    if (token == null || userId.isEmpty || workspaceId.isEmpty) return;
    if (!web.window.confirm(
      'Delete project "$name" from ${owner['username'] ?? userId}? This cannot be undone.',
    )) return;

    _setBusy(true);
    try {
      await _api.deleteProject(
        token,
        userId: userId,
        workspaceId: workspaceId,
      );
      await _refreshAll();
      setState(() => _notice = 'Project $name deleted.');
    } catch (error) {
      setState(() => _error = _message(error));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _saveLessons({String successMessage = 'Lesson catalog saved.'}) async {
    final token = _token;
    final catalog = _lessonCatalog;
    if (token == null || catalog == null) return;
    _setBusy(true);
    _clearMessages();
    try {
      final saved = await _api.saveLessons(
        token,
        catalog,
        languageCode: _courseEditLanguage,
      );
      final overview = await _api.overview(token);
      setState(() {
        _lessonCatalog = saved;
        _overview = overview;
        _catalogDraft = const JsonEncoder.withIndent('  ').convert(saved);
        _notice = successMessage;
        _normalizeLessonSelection();
      });
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
        languageCode: _courseEditLanguage,
      );
      final overview = await _api.overview(token);
      setState(() {
        _lessonCatalog = saved;
        _overview = overview;
        _catalogDraft = const JsonEncoder.withIndent('  ').convert(saved);
        _notice = 'Full lesson JSON saved.';
        _normalizeLessonSelection();
      });
    } catch (error) {
      setState(() => _error = _message(error));
    } finally {
      _setBusy(false);
    }
  }

  void _switchCourseLanguage(String languageCode) {
    if (languageCode == _courseEditLanguage) return;
    final catalog = _lessonCatalog;
    if (catalog == null) {
      setState(() => _courseEditLanguage = languageCode);
      return;
    }

    CatalogLocalization.capture(catalog, _courseEditLanguage);
    CatalogLocalization.materialize(catalog, languageCode);
    setState(() {
      _courseEditLanguage = languageCode;
      _catalogDraft = const JsonEncoder.withIndent('  ').convert(catalog);
      _error = null;
      _notice = null;
    });
  }

  void _normalizeLessonSelection() {
    final groups = _lessonGroups;
    if (groups.isEmpty) {
      _selectedProjectIndex = null;
      _selectedLessonIndex = null;
      return;
    }
    var groupIndex = _selectedProjectIndex ?? 0;
    if (groupIndex < 0 || groupIndex >= groups.length) groupIndex = 0;
    final lessons = _lessonList(groups[groupIndex]);
    _selectedProjectIndex = groupIndex;
    if (lessons.isEmpty) {
      _selectedLessonIndex = null;
      return;
    }
    var lessonIndex = _selectedLessonIndex ?? 0;
    if (lessonIndex < 0 || lessonIndex >= lessons.length) lessonIndex = 0;
    _selectedLessonIndex = lessonIndex;
  }

  List<Map<String, dynamic>> get _lessonGroups {
    final raw = _lessonCatalog?['projects'];
    if (raw is! Iterable) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map(_mapRef).toList(growable: false);
  }

  List<Map<String, dynamic>> _lessonList(Map<String, dynamic> group) {
    final raw = group['lessons'];
    if (raw is! Iterable) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map(_mapRef).toList(growable: false);
  }

  Map<String, dynamic>? get _selectedLesson {
    final groupIndex = _selectedProjectIndex;
    final lessonIndex = _selectedLessonIndex;
    final groups = _lessonGroups;
    if (groupIndex == null || lessonIndex == null) return null;
    if (groupIndex < 0 || groupIndex >= groups.length) return null;
    final lessons = _lessonList(groups[groupIndex]);
    if (lessonIndex < 0 || lessonIndex >= lessons.length) return null;
    return lessons[lessonIndex];
  }

  void _openCreateCourse(int groupIndex) {
    final groups = _lessonGroups;
    if (groupIndex < 0 || groupIndex >= groups.length) return;
    setState(() {
      _creatingCourseGroupIndex = groupIndex;
      _selectedProjectIndex = groupIndex;
      _newCourseId = '';
      _newCourseTitle = '';
      _newCourseDescription = '';
      _newCourseCategory = '';
      _newCourseDifficulty = _courseEditLanguage == 'zh' ? '初级' : 'Beginner';
      _newCourseMinutes = '60';
      _newCourseTags = '';
      _newCourseComingSoon = false;
      _error = null;
      _notice = null;
    });
  }

  void _cancelCreateCourse() {
    setState(() => _creatingCourseGroupIndex = null);
  }

  Future<void> _createCourse() async {
    final catalog = _lessonCatalog;
    final groupIndex = _creatingCourseGroupIndex;
    final groups = _lessonGroups;
    if (catalog == null || groupIndex == null) return;
    if (groupIndex < 0 || groupIndex >= groups.length) return;

    final title = _newCourseTitle.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Course title is required.');
      return;
    }

    var id = _newCourseId.trim().isEmpty
        ? _slugify(title)
        : _slugify(_newCourseId);
    if (id.isEmpty) {
      id = 'course-${DateTime.now().millisecondsSinceEpoch}';
    }

    final duplicate = groups
        .expand(_lessonList)
        .any((lesson) => lesson['id']?.toString() == id);
    if (duplicate) {
      setState(() => _error = 'A course with ID "$id" already exists.');
      return;
    }

    final category = _newCourseCategory.trim().isEmpty
        ? (_courseEditLanguage == 'zh' ? '通用' : 'General')
        : _newCourseCategory.trim();
    final difficulty = _newCourseDifficulty.trim().isEmpty
        ? (_courseEditLanguage == 'zh' ? '初级' : 'Beginner')
        : _newCourseDifficulty.trim();
    final minutes = int.tryParse(_newCourseMinutes.trim()) ?? 60;
    final tags = _newCourseTags
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final description = _newCourseDescription.trim();
    final presentation = <String, dynamic>{
      'title': title,
      'description': description,
      'difficulty': difficulty,
      'category': category,
      'tags': tags,
      'prerequisites': <String>[],
    };

    final course = <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'difficulty': difficulty,
      'category': category,
      'tags': tags,
      'estimatedMinutes': minutes < 1 ? 1 : minutes,
      'prerequisites': <String>[],
      'comingSoon': _newCourseComingSoon,
      'version': 'beginner',
      'steps': <Object?>[],
      'translations': <String, dynamic>{
        'en': Map<String, dynamic>.from(presentation),
        'zh': Map<String, dynamic>.from(presentation),
      },
    };

    final group = groups[groupIndex];
    final rawLessons = group['lessons'];
    late final List<dynamic> lessons;
    if (rawLessons is List) {
      lessons = rawLessons;
    } else {
      lessons = <dynamic>[];
      group['lessons'] = lessons;
    }
    lessons.add(course);

    setState(() {
      _selectedProjectIndex = groupIndex;
      _selectedLessonIndex = lessons.length - 1;
      _creatingCourseGroupIndex = null;
      _catalogDraft = const JsonEncoder.withIndent('  ').convert(catalog);
    });

    await _saveLessons(successMessage: 'Course "$title" created.');
  }

  String _slugify(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug;
  }

  Map<String, dynamic> _mapRef(Object? source) {
    if (source is Map<String, dynamic>) return source;
    if (source is Map) return Map<String, dynamic>.from(source);
    return <String, dynamic>{};
  }

  List<String> _stringList(Object? source) {
    if (source is! Iterable) return const <String>[];
    return source.map((item) => item.toString()).toList(growable: false);
  }

  void _updateLesson(String key, Object? value) {
    final lesson = _selectedLesson;
    if (lesson != null) lesson[key] = value;
  }

  void _setBusy(bool value) => setState(() => _busy = value);

  void _clearMessages() {
    setState(() {
      _error = null;
      _notice = null;
    });
  }

  String _message(Object error) => error is AdminApiException
      ? error.message
      : error.toString().replaceFirst('Exception: ', '');

  @override
  Component build(BuildContext context) {
    return div(classes: 'admin-root', [
      _token == null ? _loginPage() : _console(),
    ]);
  }

  Component _loginPage() {
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
          p([text('Use an existing Flutter Workbench administrator account.')]),
        ]),
        label(classes: 'field-label', [text('Email')]),
        input<String>(
          attributes: const {
            'type': 'email',
            'autocomplete': 'email',
            'placeholder': 'you@example.com',
          },
          events: events<String>(onInput: (value) => _email = value),
        ),
        label(classes: 'field-label password-label', [text('Password')]),
        input<String>(
          attributes: const {
            'type': 'password',
            'autocomplete': 'current-password',
            'placeholder': '••••••••',
          },
          events: events<String>(onInput: (value) => _password = value),
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
          text('Admin permission is enforced by Workspace Storage.'),
        ]),
      ]),
    ]);
  }

  Component _console() {
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
          _nav(_AdminSection.dashboard, 'Overview', '⌂'),
          _nav(_AdminSection.lessons, 'Courses', '◫'),
          _nav(_AdminSection.users, 'Users', '◎'),
          _nav(_AdminSection.projects, 'Projects', '◇'),
        ]),
        div(classes: 'sidebar-footer', [
          div(classes: 'admin-chip', [
            div(classes: 'avatar-dot', [text(_initial(_adminUsername))]),
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
            _AdminSection.dashboard => _dashboard(),
            _AdminSection.lessons => _lessonsPage(),
            _AdminSection.users => _usersPage(),
            _AdminSection.projects => _projectsPage(),
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

  Component _nav(_AdminSection section, String labelText, String iconText) {
    return button(
      classes: 'nav-button${_section == section ? ' selected' : ''}',
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

  Component _dashboard() {
    return div([
      div(classes: 'hero-panel', [
        div([
          p(classes: 'eyebrow', [text('SYSTEM STATUS')]),
          h2([text('Manage the whole learning platform')]),
          p(classes: 'muted hero-copy', [
            text('Courses, users and Workspace projects share one authenticated backend.'),
          ]),
        ]),
        div(classes: 'status-pill', [
          span(classes: 'status-dot', []),
          text('Workspace API connected'),
        ]),
      ]),
      div(classes: 'stat-grid', [
        _stat('Users', '${_overview['users'] ?? _users.length}', 'Registered accounts'),
        _stat('Projects', '${_overview['projects'] ?? _projects.length}', 'Cloud workspaces'),
        _stat('Courses', '${_overview['lessons'] ?? 0}', 'Lesson entries'),
        _stat(
          'Catalog',
          _overview['lessonCatalogInitialized'] == true ? 'Live' : 'Seed pending',
          _overview['lessonCatalogInitialized'] == true
              ? 'Remote source of truth'
              : 'Open Lesson Mode once as admin',
        ),
      ]),
      div(classes: 'two-column-grid', [
        div(classes: 'panel', [
          h3([text('Content pipeline')]),
          _timeline('1', 'Seed', 'Existing LessonCatalog uploads once.'),
          _timeline('2', 'Manage', 'Edit lessons from this Jaspr console.'),
          _timeline('3', 'Consume', 'Flutter reads /content/lessons.'),
          _timeline('4', 'Fallback', 'Offline clients retain the built-in seed.'),
        ]),
        div(classes: 'panel', [
          h3([text('Platform snapshot')]),
          _keyValue('Admin', _adminUsername ?? '—'),
          _keyValue('Users', '${_users.length}'),
          _keyValue('Projects', '${_projects.length}'),
          _keyValue('Lesson groups', '${_overview['lessonProjects'] ?? _lessonGroups.length}'),
          _keyValue(
            'Last lesson update',
            _overview['lessonCatalogUpdatedAt']?.toString() ?? 'Not initialized',
          ),
        ]),
      ]),
    ]);
  }

  Component _stat(String title, String value, String caption) {
    return div(classes: 'stat-card', [
      p(classes: 'stat-title', [text(title)]),
      strong(classes: 'stat-value', [text(value)]),
      p(classes: 'muted stat-caption', [text(caption)]),
    ]);
  }

  Component _timeline(String number, String title, String copy) {
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

  Component _lessonsPage() {
    if (_lessonCatalog == null) {
      return div(classes: 'empty-state panel', [
        div(classes: 'empty-icon', [text('◫')]),
        h2([text('Lesson catalog has not been migrated yet')]),
        p(classes: 'muted', [
          text(
            'After the updated backend is deployed, sign into Flutter Workbench with an admin account and open Lesson Mode once. The existing hardcoded catalog will be uploaded automatically.',
          ),
        ]),
        button(classes: 'ghost-button', onClick: _refreshCurrent, [text('Check again')]),
      ]);
    }

    final groups = _lessonGroups;
    final lesson = _selectedLesson;
    final creatingGroupIndex = _creatingCourseGroupIndex;
    final creatingGroup = creatingGroupIndex != null &&
            creatingGroupIndex >= 0 &&
            creatingGroupIndex < groups.length
        ? groups[creatingGroupIndex]
        : null;

    return div([
      div(classes: 'section-toolbar', [
        div([
          h2([text('Course catalog')]),
          p(classes: 'muted', [
            text('${groups.length} groups · ${_overview['lessons'] ?? 0} lessons'),
          ]),
        ]),
        div(classes: 'topbar-actions', [
          button(
            classes: _courseEditLanguage == 'en'
                ? 'primary-button compact-button'
                : 'ghost-button compact-button',
            disabled: _busy,
            onClick: () => _switchCourseLanguage('en'),
            [text('English')],
          ),
          button(
            classes: _courseEditLanguage == 'zh'
                ? 'primary-button compact-button'
                : 'ghost-button compact-button',
            disabled: _busy,
            onClick: () => _switchCourseLanguage('zh'),
            [text('中文')],
          ),
          if (groups.isNotEmpty)
            button(
              classes: 'ghost-button',
              disabled: _busy,
              onClick: () => _openCreateCourse(_selectedProjectIndex ?? 0),
              [text('＋ Add course')],
            ),
          button(
            classes: 'primary-button',
            disabled: _busy,
            onClick: () => _saveLessons(),
            [text('Save course changes')],
          ),
        ]),
      ]),
      div(classes: 'lesson-workspace', [
        div(classes: 'lesson-tree panel', [
          for (var groupIndex = 0; groupIndex < groups.length; groupIndex++)
            _lessonGroup(groupIndex, groups[groupIndex]),
        ]),
        div(classes: 'lesson-editor panel', [
          creatingGroup != null
              ? _newCourseForm(creatingGroup)
              : lesson == null
                  ? div(classes: 'empty-editor', [
                      h3([text('Select a lesson')]),
                      p(classes: 'muted', [text('Choose a lesson from the left.')]),
                    ])
                  : _lessonForm(lesson),
        ]),
      ]),
      div(classes: 'panel json-panel', [
        div(classes: 'panel-heading', [
          div([
            h3([text('Advanced catalog JSON')]),
            p(classes: 'muted', [
              text('Translations for English and Chinese are stored together with steps, starter code, answer assets and AST requirements.'),
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
          attributes: const {'spellcheck': 'false', 'aria-label': 'Lesson catalog JSON'},
          events: events<String>(onInput: (value) => _catalogDraft = value),
          [text(_catalogDraft)],
        ),
      ]),
    ]);
  }

  Component _lessonGroup(int groupIndex, Map<String, dynamic> group) {
    final lessons = _lessonList(group);
    return div(classes: 'lesson-group', [
      div(classes: 'lesson-group-title', [
        span(classes: 'lesson-group-dot', []),
        div([
          strong([text(group['title']?.toString() ?? 'Untitled group')]),
          span([text('${lessons.length} lessons')]),
        ]),
        button(
          classes: 'ghost-button compact-button',
          disabled: _busy,
          onClick: () => _openCreateCourse(groupIndex),
          [text('＋')],
        ),
      ]),
      div(classes: 'lesson-list', [
        for (var lessonIndex = 0; lessonIndex < lessons.length; lessonIndex++)
          button(
            classes: 'lesson-row${_selectedProjectIndex == groupIndex && _selectedLessonIndex == lessonIndex ? ' selected' : ''}',
            onClick: () => setState(() {
              _creatingCourseGroupIndex = null;
              _selectedProjectIndex = groupIndex;
              _selectedLessonIndex = lessonIndex;
            }),
            [
              span(classes: 'lesson-number', [text('${lessonIndex + 1}')]),
              span(classes: 'lesson-row-copy', [
                strong([text(lessons[lessonIndex]['title']?.toString() ?? 'Untitled')]),
                span([
                  text(
                    lessons[lessonIndex]['comingSoon'] == true
                        ? (_courseEditLanguage == 'zh' ? '即将推出' : 'Coming soon')
                        : lessons[lessonIndex]['category']?.toString() ?? 'Lesson',
                  ),
                ]),
              ]),
            ],
          ),
      ]),
    ]);
  }

  Component _newCourseForm(Map<String, dynamic> group) {
    return div(key: const Key('new-course-editor'), [
      div(classes: 'editor-heading', [
        div([
          p(classes: 'eyebrow', [
            text(_courseEditLanguage == 'zh' ? '新课程 · 中文' : 'NEW COURSE · ENGLISH'),
          ]),
          h2([text(_courseEditLanguage == 'zh' ? '添加课程' : 'Add course')]),
          p(classes: 'muted', [
            text('Add a course to ${group['title']?.toString() ?? 'this group'}.'),
          ]),
        ]),
        span(classes: 'badge', [text('Draft')]),
      ]),
      _field(
        _courseEditLanguage == 'zh' ? '课程标题' : 'Course title',
        _newCourseTitle,
        (value) => _newCourseTitle = value,
      ),
      _field(
        'Course ID',
        _newCourseId,
        (value) => _newCourseId = value,
      ),
      p(classes: 'muted editor-note', [
        text('Leave the ID empty to generate it automatically.'),
      ]),
      _area(
        _courseEditLanguage == 'zh' ? '课程简介' : 'Description',
        _newCourseDescription,
        (value) => _newCourseDescription = value,
      ),
      div(classes: 'form-grid', [
        _field(
          _courseEditLanguage == 'zh' ? '分类' : 'Category',
          _newCourseCategory,
          (value) => _newCourseCategory = value,
        ),
        _field(
          _courseEditLanguage == 'zh' ? '难度' : 'Difficulty',
          _newCourseDifficulty,
          (value) => _newCourseDifficulty = value,
        ),
      ]),
      div(classes: 'form-grid', [
        _field(
          'Estimated minutes',
          _newCourseMinutes,
          (value) => _newCourseMinutes = value,
          type: 'number',
        ),
        _field(
          _courseEditLanguage == 'zh' ? '标签（逗号分隔）' : 'Tags (comma separated)',
          _newCourseTags,
          (value) => _newCourseTags = value,
        ),
      ]),
      label(classes: 'toggle-row', [
        input<bool>(
          attributes: {
            'type': 'checkbox',
            if (_newCourseComingSoon) 'checked': 'checked',
          },
          events: events<bool>(onChange: (value) {
            setState(() => _newCourseComingSoon = value);
          }),
        ),
        span([
          strong([text(_courseEditLanguage == 'zh' ? '即将推出' : 'Coming soon')]),
          span(classes: 'muted', [text('Create the course but keep it unavailable to students.')]),
        ]),
      ]),
      div(classes: 'topbar-actions', [
        button(
          classes: 'ghost-button',
          disabled: _busy,
          onClick: _cancelCreateCourse,
          [text('Cancel')],
        ),
        button(
          classes: 'primary-button',
          disabled: _busy,
          onClick: _createCourse,
          [text(_busy ? 'Creating…' : 'Create course')],
        ),
      ]),
      p(classes: 'muted editor-note', [
        text('The initial text is copied to both languages. After creation, switch English / 中文 above and edit each translation separately.'),
      ]),
    ]);
  }

  Component _lessonForm(Map<String, dynamic> lesson) {
    final id = lesson['id']?.toString() ?? 'lesson';
    final languageLabel = _courseEditLanguage == 'zh' ? '中文' : 'English';
    return div(key: Key('lesson-editor-$id-$_courseEditLanguage'), [
      div(classes: 'editor-heading', [
        div([
          p(classes: 'eyebrow', [text('$id · $languageLabel')]),
          h2([text(lesson['title']?.toString() ?? 'Untitled lesson')]),
        ]),
        span(
          classes: 'badge${lesson['comingSoon'] == true ? ' pending' : ''}',
          [
            text(
              lesson['comingSoon'] == true
                  ? (_courseEditLanguage == 'zh' ? '即将推出' : 'Coming soon')
                  : (_courseEditLanguage == 'zh' ? '已发布' : 'Published'),
            ),
          ],
        ),
      ]),
      _field(
        _courseEditLanguage == 'zh' ? '标题' : 'Title',
        lesson['title']?.toString() ?? '',
        (value) => _updateLesson('title', value),
      ),
      _area(
        _courseEditLanguage == 'zh' ? '简介' : 'Description',
        lesson['description']?.toString() ?? '',
        (value) => _updateLesson('description', value),
      ),
      div(classes: 'form-grid', [
        _field(
          _courseEditLanguage == 'zh' ? '分类' : 'Category',
          lesson['category']?.toString() ?? '',
          (value) => _updateLesson('category', value),
        ),
        _field(
          _courseEditLanguage == 'zh' ? '难度' : 'Difficulty',
          lesson['difficulty']?.toString() ?? '',
          (value) => _updateLesson('difficulty', value),
        ),
      ]),
      div(classes: 'form-grid', [
        _field(
          'Estimated minutes',
          '${lesson['estimatedMinutes'] ?? 0}',
          (value) => _updateLesson('estimatedMinutes', int.tryParse(value) ?? 0),
          type: 'number',
        ),
        _field(
          _courseEditLanguage == 'zh' ? '标签（逗号分隔）' : 'Tags (comma separated)',
          _stringList(lesson['tags']).join(', '),
          (value) => _updateLesson(
            'tags',
            value.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList(),
          ),
        ),
      ]),
      label(classes: 'toggle-row', [
        input<bool>(
          attributes: {
            'type': 'checkbox',
            if (lesson['comingSoon'] == true) 'checked': 'checked',
          },
          events: events<bool>(onChange: (value) => _updateLesson('comingSoon', value)),
        ),
        span([
          strong([text(_courseEditLanguage == 'zh' ? '即将推出' : 'Coming soon')]),
          span(classes: 'muted', [text('Prevent students from opening this lesson.')]),
        ]),
      ]),
      div(classes: 'lesson-meta-strip', [
        _miniMeta('Steps', '${(lesson['steps'] as List?)?.length ?? 0}'),
        _miniMeta('Version', lesson['version']?.toString() ?? 'beginner'),
        _miniMeta('ID', id),
      ]),
      p(classes: 'muted editor-note', [
        text('Switch English / 中文 to edit the same course in both languages. Steps, code and checker requirements remain shared.'),
      ]),
    ]);
  }

  Component _field(
    String labelText,
    String value,
    void Function(String) onInput, {
    String type = 'text',
  }) {
    return label(classes: 'field-block', [
      span(classes: 'field-label', [text(labelText)]),
      input<String>(
        attributes: {'type': type, 'value': value},
        events: events<String>(onInput: onInput),
      ),
    ]);
  }

  Component _area(String labelText, String value, void Function(String) onInput) {
    return label(classes: 'field-block', [
      span(classes: 'field-label', [text(labelText)]),
      textarea(events: events<String>(onInput: onInput), [text(value)]),
    ]);
  }

  Component _miniMeta(String labelText, String value) {
    return div([
      span(classes: 'muted', [text(labelText)]),
      strong([text(value)]),
    ]);
  }

  Component _usersPage() {
    return div([
      div(classes: 'section-toolbar', [
        div([
          h2([text('Registered accounts')]),
          p(classes: 'muted', [text('${_users.length} accounts in Workspace Storage')]),
        ]),
      ]),
      div(classes: 'panel table-panel', [
        div(classes: 'data-table', [
          div(classes: 'table-row table-head users-grid', [
            span([text('User')]),
            span([text('Email')]),
            span([text('Sessions')]),
            span([text('Created')]),
            span([]),
          ]),
          for (final user in _users)
            div(classes: 'table-row users-grid', [
              div(classes: 'user-cell', [
                div(classes: 'avatar-dot', [text(_initial(user['username']?.toString()))]),
                div([
                  strong([text(user['username']?.toString() ?? 'Unknown')]),
                  span(classes: 'muted mono-small', [text(user['userId']?.toString() ?? '')]),
                ]),
              ]),
              span([text(user['email']?.toString() ?? '—')]),
              span([text('${user['activeSessions'] ?? 0}')]),
              span([text(_shortDate(user['createdAt']))]),
              div(classes: 'row-actions', [
                user['username']?.toString() == _adminUsername
                    ? span(classes: 'badge', [text('Current admin')])
                    : button(
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

  Component _projectsPage() {
    return div([
      div(classes: 'section-toolbar', [
        div([
          h2([text('Workspace projects')]),
          p(classes: 'muted', [text('${_projects.length} projects across all users')]),
        ]),
      ]),
      div(classes: 'project-grid', [
        for (final row in _projects) _projectCard(row),
      ]),
      if (_projects.isEmpty)
        div(classes: 'empty-state panel', [
          div(classes: 'empty-icon', [text('◇')]),
          h3([text('No projects yet')]),
          p(classes: 'muted', [text('Projects created in Flutter Workbench will appear here.')]),
        ]),
    ]);
  }

  Component _projectCard(Map<String, dynamic> row) {
    final owner = _mapRef(row['owner']);
    final project = _mapRef(row['project']);
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

  String _initial(String? value) {
    if (value == null || value.isEmpty) return 'A';
    return value.substring(0, 1).toUpperCase();
  }

  String _shortDate(Object? source) {
    final parsed = DateTime.tryParse(source?.toString() ?? '')?.toLocal();
    if (parsed == null) return '—';
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }
}
