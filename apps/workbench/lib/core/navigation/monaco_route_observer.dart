import 'package:flutter_monaco/flutter_monaco.dart';

/// Shared navigator observer used by Monaco editors on Flutter Web.
///
/// Monaco runs inside an iframe in the browser. Route overlays such as dialogs,
/// popup menus, and modal sheets must temporarily disable iframe interaction so
/// the Flutter overlay can receive pointer and keyboard events.
final MonacoRouteObserver monacoRouteObserver = MonacoRouteObserver();
