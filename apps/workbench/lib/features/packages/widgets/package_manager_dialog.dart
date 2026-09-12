import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../runner/controllers/flutter_runner_controller.dart';
import '../models/package_models.dart';
import '../services/pub_dev_package_service.dart';
import '../services/pubspec_package_service.dart';

Future<void> showPackageManagerDialog(
  BuildContext context, {
  required FlutterRunnerController runner,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => PackageManagerDialog(runner: runner),
  );
}

class PackageManagerDialog extends StatefulWidget {
  const PackageManagerDialog({super.key, required this.runner});

  final FlutterRunnerController runner;

  @override
  State<PackageManagerDialog> createState() => _PackageManagerDialogState();
}

class _PackageManagerDialogState extends State<PackageManagerDialog> {
  final _searchController = TextEditingController();
  final _pubspec = const PubspecPackageService();
  final _pubDev = PubDevPackageService();

  List<PackageDependencyInfo> _dependencies = const <PackageDependencyInfo>[];
  List<String> _searchResults = const <String>[];
  final Map<String, PubDevPackageInfo> _packageInfo =
      <String, PubDevPackageInfo>{};

  Timer? _searchDebounce;
  bool _searching = false;
  bool _pubGetting = false;
  bool _checkingUpdates = false;
  bool _upgradingAll = false;
  String? _searchError;
  String? _updateError;
  String? _loadingPackage;
  String? _upgradingPackage;

  @override
  void initState() {
    super.initState();
    _refreshDependencies();
    widget.runner.addListener(_handleRunnerChanged);
    unawaited(_checkForUpdates());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _pubDev.close();
    widget.runner.removeListener(_handleRunnerChanged);
    super.dispose();
  }

  void _handleRunnerChanged() {
    if (mounted) setState(() {});
  }

  void _refreshDependencies() {
    try {
      _dependencies = _pubspec.read(widget.runner.workspace);
    } catch (error) {
      _dependencies = const <PackageDependencyInfo>[];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.tr(
                '读取 pubspec.yaml 失败：$error',
                'Failed to read pubspec.yaml: $error',
              ),
            ),
          ),
        );
      });
    }
  }

  Iterable<PackageDependencyInfo> get _hostedDependencies =>
      _dependencies.where(
        (dependency) => dependency.source == PackageDependencySource.hosted,
      );

  int get _updateCount => _hostedDependencies.where(_hasUpdate).length;

  bool _hasUpdate(PackageDependencyInfo dependency) {
    final latest = _packageInfo[dependency.name]?.latestVersion;
    if (latest == null) return false;
    final current = dependency.resolvedVersion ??
        _simpleDeclaredVersion(dependency.constraint);
    return current != null && current != latest;
  }

  String? _simpleDeclaredVersion(String constraint) {
    var value = constraint.trim();
    if (value.startsWith('^') || value.startsWith('~')) {
      value = value.substring(1);
    }
    return RegExp(
      r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$',
    ).hasMatch(value)
        ? value
        : null;
  }

  bool _useCompatibleRange(String constraint) {
    if (constraint.startsWith('^')) return true;
    return _simpleDeclaredVersion(constraint) == null;
  }

  Future<void> _checkForUpdates({bool force = false}) async {
    if (_checkingUpdates) return;
    final hosted = _hostedDependencies.toList(growable: false);
    if (hosted.isEmpty) return;

    setState(() {
      _checkingUpdates = true;
      _updateError = null;
    });

    final fetched = <String, PubDevPackageInfo>{};
    final failed = <String>[];
    for (final dependency in hosted) {
      if (!force && _packageInfo.containsKey(dependency.name)) continue;
      try {
        fetched[dependency.name] =
            await _pubDev.packageInfo(dependency.name);
      } catch (_) {
        failed.add(dependency.name);
      }
    }

    if (!mounted) return;
    final l10n = context.l10n;
    setState(() {
      _packageInfo.addAll(fetched);
      _checkingUpdates = false;
      _updateError = failed.isEmpty
          ? null
          : l10n.tr(
              '以下 package 暂时无法读取最新版本：${failed.join(', ')}',
              'Latest versions are temporarily unavailable for: ${failed.join(', ')}',
            );
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const <String>[];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 280),
      () => unawaited(_search(query)),
    );
  }

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await _pubDev.search(query);
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searchResults = const <String>[];
        _searchError = '$error';
        _searching = false;
      });
    }
  }

  PackageDependencyInfo? _installed(String name) {
    for (final dependency in _dependencies) {
      if (dependency.name == name) return dependency;
    }
    return null;
  }

  Future<PubDevPackageInfo> _loadPackageInfo(String packageName) async {
    final cached = _packageInfo[packageName];
    if (cached != null) return cached;
    final info = await _pubDev.packageInfo(packageName);
    if (mounted) setState(() => _packageInfo[packageName] = info);
    return info;
  }

  Future<void> _choosePackage(String packageName) async {
    if (_loadingPackage != null) return;
    setState(() => _loadingPackage = packageName);
    try {
      final info = await _loadPackageInfo(packageName);
      if (!mounted) return;

      final selection = await _showVersionDialog(
        info,
        existing: _installed(packageName),
      );
      if (selection == null || !mounted) return;

      _pubspec.upsertHostedDependency(
        widget.runner.workspace,
        packageName: packageName,
        version: selection.version,
        group: selection.group,
        compatibleRange: selection.compatibleRange,
      );
      setState(_refreshDependencies);
      if (selection.runPubGet) await _runPubGet();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr(
              '读取 $packageName 失败：$error',
              'Failed to load $packageName: $error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingPackage = null);
    }
  }

  Future<void> _upgradePackage(PackageDependencyInfo dependency) async {
    if (_upgradingPackage != null || _upgradingAll) return;
    setState(() => _upgradingPackage = dependency.name);

    try {
      final info = await _loadPackageInfo(dependency.name);
      _pubspec.upsertHostedDependency(
        widget.runner.workspace,
        packageName: dependency.name,
        version: info.latestVersion,
        group: dependency.group,
        compatibleRange: _useCompatibleRange(dependency.constraint),
      );
      if (!mounted) return;
      setState(_refreshDependencies);

      if (widget.runner.canPubGet) {
        await _runPubGet();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.tr(
                '${dependency.name} 已写入 ${info.latestVersion}，请稍后执行 Pub Get。',
                '${dependency.name} was updated to ${info.latestVersion}. Run Pub Get later.',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr(
              '升级 ${dependency.name} 失败：$error',
              'Failed to upgrade ${dependency.name}: $error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _upgradingPackage = null);
    }
  }

  Future<void> _upgradeAll() async {
    if (_upgradingAll || _upgradingPackage != null || _checkingUpdates) return;
    if (_packageInfo.isEmpty) {
      await _checkForUpdates();
      if (!mounted) return;
    }

    final candidates =
        _hostedDependencies.where(_hasUpdate).toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr(
              '当前没有可升级的 hosted package。',
              'There are no hosted packages to upgrade.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _upgradingAll = true);
    try {
      for (final dependency in candidates) {
        final info = _packageInfo[dependency.name];
        if (info == null) continue;
        _pubspec.upsertHostedDependency(
          widget.runner.workspace,
          packageName: dependency.name,
          version: info.latestVersion,
          group: dependency.group,
          compatibleRange: _useCompatibleRange(dependency.constraint),
        );
      }

      if (!mounted) return;
      setState(_refreshDependencies);
      if (widget.runner.canPubGet) {
        await _runPubGet();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.tr(
                '已把 ${candidates.length} 个 package 写入最新版本，请稍后执行 Pub Get。',
                '${candidates.length} packages were updated to their latest versions. Run Pub Get later.',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr(
              '全部升级失败：$error',
              'Upgrade all failed: $error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _upgradingAll = false);
    }
  }

  Future<_PackageSelection?> _showVersionDialog(
    PubDevPackageInfo info, {
    PackageDependencyInfo? existing,
  }) {
    final existingVersion =
        existing == null ? null : _simpleDeclaredVersion(existing.constraint);
    var selectedVersion =
        existingVersion != null && info.versions.contains(existingVersion)
            ? existingVersion
            : info.latestVersion;
    var group = existing?.group ?? PackageDependencyGroup.dependencies;
    var compatibleRange =
        existing == null || _useCompatibleRange(existing.constraint);
    final l10n = context.l10n;

    return showDialog<_PackageSelection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final versions = <String>{
            info.latestVersion,
            ...info.versions.take(80),
          }.toList(growable: false);

          return AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text(info.name)),
                _LatestBadge(version: info.latestVersion),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (info.description.trim().isNotEmpty) ...[
                      Text(info.description),
                      const SizedBox(height: 18),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: selectedVersion,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.tr('选择版本', 'Choose version'),
                        border: const OutlineInputBorder(),
                      ),
                      items: versions
                          .map(
                            (version) => DropdownMenuItem<String>(
                              value: version,
                              child: Text(
                                version == info.latestVersion
                                    ? '$version  · latest'
                                    : version,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedVersion = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<PackageDependencyGroup>(
                      segments: const [
                        ButtonSegment(
                          value: PackageDependencyGroup.dependencies,
                          icon: Icon(Icons.extension_outlined),
                          label: Text('dependencies'),
                        ),
                        ButtonSegment(
                          value: PackageDependencyGroup.devDependencies,
                          icon: Icon(Icons.build_outlined),
                          label: Text('dev_dependencies'),
                        ),
                      ],
                      selected: <PackageDependencyGroup>{group},
                      onSelectionChanged: (values) {
                        setDialogState(() => group = values.first);
                      },
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: compatibleRange,
                      title: Text(
                        l10n.tr(
                          '使用兼容范围  ^$selectedVersion',
                          'Use compatible range  ^$selectedVersion',
                        ),
                      ),
                      subtitle: Text(
                        l10n.tr(
                          '关闭后写入精确版本；默认使用 Dart/Flutter 常见的 ^ 约束。',
                          'Turn this off to write an exact version. The common Dart/Flutter ^ constraint is used by default.',
                        ),
                      ),
                      onChanged: (value) {
                        setDialogState(() => compatibleRange = value ?? true);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.tr('取消', 'Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _PackageSelection(
                    version: selectedVersion,
                    group: group,
                    compatibleRange: compatibleRange,
                    runPubGet: false,
                  ),
                ),
                child: Text(l10n.tr('仅写入 pubspec', 'Write pubspec only')),
              ),
              FilledButton.icon(
                onPressed: widget.runner.canPubGet
                    ? () => Navigator.pop(
                          dialogContext,
                          _PackageSelection(
                            version: selectedVersion,
                            group: group,
                            compatibleRange: compatibleRange,
                            runPubGet: true,
                          ),
                        )
                    : null,
                icon: const Icon(Icons.download_rounded),
                label: Text(l10n.tr('添加并 Pub Get', 'Add and Pub Get')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runPubGet() async {
    if (_pubGetting || !widget.runner.canPubGet) return;
    setState(() => _pubGetting = true);

    try {
      final result = await widget.runner.pubGet();
      if (!mounted) return;
      setState(_refreshDependencies);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.hasPackageConfig
                ? context.l10n.tr(
                    'Pub Get 完成：依赖已解析，package_config.json 已生成。',
                    'Pub Get complete: dependencies resolved and package_config.json generated.',
                  )
                : context.l10n.tr('Pub Get 完成。', 'Pub Get complete.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr(
              'Pub Get 失败：$error',
              'Pub Get failed: $error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _pubGetting = false);
    }
  }

  void _removeDependency(PackageDependencyInfo dependency) {
    _pubspec.removeDependency(
      widget.runner.workspace,
      packageName: dependency.name,
      group: dependency.group,
    );
    setState(() {
      _packageInfo.remove(dependency.name);
      _refreshDependencies();
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = (media.width - 32).clamp(280.0, 1020.0).toDouble();
    final height = (media.height - 32).clamp(400.0, 780.0).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            _buildPubGetStatus(),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 760) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 6, child: _buildInstalledList()),
                        const VerticalDivider(width: 1),
                        Expanded(flex: 5, child: _buildSearchPanel()),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(flex: 6, child: _buildInstalledList()),
                      const Divider(height: 1),
                      Expanded(flex: 5, child: _buildSearchPanel()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.extension_rounded),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flutter Packages',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Declared · Resolved · Latest · pub.dev · Pub Get',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.tr('关闭', 'Close'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildPubGetStatus() {
    final l10n = context.l10n;
    final lockExists = widget.runner.workspace.entryAt('pubspec.lock') != null;
    final verified = widget.runner.isPubGetVerifiedForCurrentPubspec;

    final String title;
    final String subtitle;
    final IconData icon;

    if (widget.runner.isMock) {
      title = 'Mock Runner';
      subtitle = l10n.tr(
        '可以测试界面和状态流，但不会真实下载 package。',
        'You can test the UI and state flow, but packages are not actually downloaded.',
      );
      icon = Icons.science_outlined;
    } else if (verified && lockExists) {
      title = l10n.tr('Pub Get 已完成', 'Pub Get complete');
      subtitle = l10n.tr(
        '当前 pubspec 已成功解析，pubspec.lock 已同步，可查看实际版本。',
        'The current pubspec was resolved successfully and pubspec.lock is synchronized, so resolved versions are available.',
      );
      icon = Icons.check_circle_outline_rounded;
    } else if (verified) {
      title = l10n.tr('Runner 已执行 Pub Get', 'Runner executed Pub Get');
      subtitle = l10n.tr(
        'Run 时已解析当前 pubspec；再点一次 Pub Get 可把 lock 版本同步回 Workspace。',
        'The current pubspec was resolved during Run. Run Pub Get once more to sync lock versions back to the Workspace.',
      );
      icon = Icons.check_circle_outline_rounded;
    } else if (lockExists) {
      title = l10n.tr('需要重新 Pub Get', 'Pub Get required');
      subtitle = l10n.tr(
        '存在 pubspec.lock，但当前 pubspec 尚未在本次 Runner 会话验证。',
        'pubspec.lock exists, but the current pubspec has not been verified in this Runner session.',
      );
      icon = Icons.info_outline_rounded;
    } else {
      title = l10n.tr('尚未确认 Pub Get', 'Pub Get not verified');
      subtitle = l10n.tr(
        '没有可确认的依赖解析结果。添加或改版本后执行 Pub Get。',
        'No dependency resolution result is available yet. Run Pub Get after adding or changing a version.',
      );
      icon = Icons.download_for_offline_outlined;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: widget.runner.canPubGet && !_pubGetting
                ? () => unawaited(_runPubGet())
                : null,
            icon: _pubGetting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(_pubGetting ? 'Pub Get...' : 'Pub Get'),
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledList() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.tr('当前依赖', 'Current dependencies'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_updateCount > 0) ...[
                FilledButton.tonalIcon(
                  onPressed: !_upgradingAll &&
                          _upgradingPackage == null &&
                          !_pubGetting
                      ? () => unawaited(_upgradeAll())
                      : null,
                  icon: _upgradingAll
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upgrade_rounded, size: 17),
                  label: Text(
                    l10n.tr(
                      '全部升级 $_updateCount',
                      'Upgrade all $_updateCount',
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: l10n.tr(
                  '重新检查最新版本',
                  'Check latest versions again',
                ),
                visualDensity: VisualDensity.compact,
                onPressed: _checkingUpdates
                    ? null
                    : () => unawaited(_checkForUpdates(force: true)),
                icon: _checkingUpdates
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          ),
        ),
        if (_updateError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _updateError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _dependencies.isEmpty
              ? Center(
                  child: Text(
                    l10n.tr(
                      'pubspec.yaml 中没有可显示的依赖。',
                      'There are no dependencies to display in pubspec.yaml.',
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  itemCount: _dependencies.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final dependency = _dependencies[index];
                    final latest = _packageInfo[dependency.name]?.latestVersion;
                    final updateAvailable = _hasUpdate(dependency);
                    final upgrading = _upgradingPackage == dependency.name;
                    return _DependencyTile(
                      dependency: dependency,
                      latestVersion: latest,
                      checkingLatest: _checkingUpdates && latest == null,
                      updateAvailable: updateAvailable,
                      upgrading: upgrading,
                      onUpgrade: updateAvailable
                          ? () => unawaited(_upgradePackage(dependency))
                          : null,
                      onManage:
                          dependency.source == PackageDependencySource.hosted
                              ? () => unawaited(_choosePackage(dependency.name))
                              : null,
                      onRemove:
                          dependency.source == PackageDependencySource.hosted
                              ? () => _removeDependency(dependency)
                              : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchPanel() {
    final l10n = context.l10n;
    final query = _searchController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              labelText: l10n.tr('搜索 pub.dev', 'Search pub.dev'),
              hintText: 'provider, dio, go_router...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.tr(
                '搜索失败：$_searchError',
                'Search failed: $_searchError',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: query.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.tr(
                        '输入 package 名称，在 pub.dev 中查找依赖。选择后默认最新版本，也可以切换历史版本。',
                        'Enter a package name to search pub.dev. The latest version is selected by default, and older versions remain available.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _searchResults.isEmpty && !_searching
                  ? Center(
                      child: Text(
                        l10n.tr(
                          '没有匹配的 package。',
                          'No matching packages.',
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final name = _searchResults[index];
                        final installed = _installed(name) != null;
                        final loading = _loadingPackage == name;
                        final latest = _packageInfo[name]?.latestVersion;
                        return ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(name),
                          subtitle: Text(
                            latest == null
                                ? (installed
                                    ? l10n.tr(
                                        '当前项目已声明',
                                        'Already declared in this project',
                                      )
                                    : 'pub.dev package')
                                : 'latest $latest',
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: _loadingPackage == null
                                ? () => unawaited(_choosePackage(name))
                                : null,
                            child: loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    installed
                                        ? l10n.tr('管理', 'Manage')
                                        : l10n.tr('选择', 'Select'),
                                  ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

enum _DependencyAction { manage, remove }

class _DependencyTile extends StatelessWidget {
  const _DependencyTile({
    required this.dependency,
    required this.latestVersion,
    required this.checkingLatest,
    required this.updateAvailable,
    required this.upgrading,
    required this.onUpgrade,
    required this.onManage,
    required this.onRemove,
  });

  final PackageDependencyInfo dependency;
  final String? latestVersion;
  final bool checkingLatest;
  final bool updateAvailable;
  final bool upgrading;
  final VoidCallback? onUpgrade;
  final VoidCallback? onManage;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final group = dependency.group == PackageDependencyGroup.dependencies
        ? 'dependencies'
        : 'dev_dependencies';

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      leading: Icon(
        dependency.source == PackageDependencySource.hosted
            ? Icons.extension_outlined
            : Icons.link_rounded,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              dependency.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (updateAvailable) ...[
            const SizedBox(width: 6),
            const _UpdateBadge(),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _InfoChip(label: 'Declared ${dependency.constraint}'),
            _InfoChip(
              label: dependency.resolvedVersion == null
                  ? l10n.tr('Resolved 未解析/未同步', 'Resolved — not resolved/synced')
                  : 'Resolved ${dependency.resolvedVersion}',
            ),
            _InfoChip(
              label: checkingLatest
                  ? l10n.tr('Latest 检查中...', 'Latest — checking...')
                  : latestVersion == null
                      ? 'Latest —'
                      : 'Latest $latestVersion',
            ),
            _InfoChip(label: dependency.source.label),
            _InfoChip(label: group),
          ],
        ),
      ),
      trailing: onManage == null
          ? const Icon(Icons.lock_outline_rounded, size: 17)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onUpgrade != null)
                  IconButton.filledTonal(
                    tooltip: latestVersion == null
                        ? l10n.tr('升级', 'Upgrade')
                        : l10n.tr(
                            '升级到 $latestVersion',
                            'Upgrade to $latestVersion',
                          ),
                    visualDensity: VisualDensity.compact,
                    onPressed: upgrading ? null : onUpgrade,
                    icon: upgrading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upgrade_rounded, size: 18),
                  ),
                PopupMenuButton<_DependencyAction>(
                  tooltip: l10n.tr('依赖操作', 'Dependency actions'),
                  onSelected: (action) {
                    switch (action) {
                      case _DependencyAction.manage:
                        onManage?.call();
                        break;
                      case _DependencyAction.remove:
                        onRemove?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _DependencyAction.manage,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.tune_rounded),
                        title: Text(l10n.tr('选择版本', 'Choose version')),
                      ),
                    ),
                    PopupMenuItem(
                      value: _DependencyAction.remove,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_outline_rounded),
                        title: Text(l10n.tr('移除依赖', 'Remove dependency')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        context.l10n.tr('可升级', 'Update available'),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _LatestBadge extends StatelessWidget {
  const _LatestBadge({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'latest $version',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _PackageSelection {
  const _PackageSelection({
    required this.version,
    required this.group,
    required this.compatibleRange,
    required this.runPubGet,
  });

  final String version;
  final PackageDependencyGroup group;
  final bool compatibleRange;
  final bool runPubGet;
}
