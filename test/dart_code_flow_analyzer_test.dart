import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/services/dart_code_flow_analyzer.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';

void main() {
  const analyzer = DartCodeFlowAnalyzer();

  test('traces workspace method calls from the method under the cursor', () {
    const entries = <WorkspaceEntry>[
      WorkspaceEntry(
        id: 'main',
        path: 'lib/cart_page.dart',
        type: WorkspaceEntryType.file,
        content: '''
class CartPage {
  void build() {
    loadCart();
  }

  void loadCart() {
    repositoryFetch();
  }
}
''',
      ),
      WorkspaceEntry(
        id: 'repo',
        path: 'lib/cart_repository.dart',
        type: WorkspaceEntryType.file,
        content: '''
void repositoryFetch() {
  persistCart();
}

void persistCart() {}
''',
      ),
    ];

    final graph = analyzer.analyze(
      entries: entries,
      activeFilePath: 'lib/cart_page.dart',
      cursorLine: 2,
      cursorColumn: 6,
    );

    expect(graph.scannedFiles, 2);
    expect(graph.declarationCount, 4);
    expect(graph.root.displayName, 'CartPage.build');
    expect(graph.root.children, hasLength(1));
    expect(graph.root.children.single.displayName, 'CartPage.loadCart');
    expect(
      graph.root.children.single.children.single.displayName,
      'repositoryFetch',
    );
    expect(
      graph.root.children.single.children.single.children.single.displayName,
      'persistCart',
    );
    expect(graph.directCalleeCount, 1);
    expect(graph.directCallerCount, 0);
    expect(graph.callersRoot.displayName, 'CartPage.build');
  });

  test('traces callers backwards across workspace files', () {
    const entries = <WorkspaceEntry>[
      WorkspaceEntry(
        id: 'app',
        path: 'lib/app.dart',
        type: WorkspaceEntryType.file,
        content: '''
void main() {
  startCheckout();
}

void startCheckout() {
  submitOrder();
}
''',
      ),
      WorkspaceEntry(
        id: 'repo',
        path: 'lib/order_repository.dart',
        type: WorkspaceEntryType.file,
        content: '''
void submitOrder() {
  persistOrder();
}

void persistOrder() {}
''',
      ),
    ];

    final graph = analyzer.analyze(
      entries: entries,
      activeFilePath: 'lib/order_repository.dart',
      cursorLine: 1,
      cursorColumn: 5,
    );

    expect(graph.root.displayName, 'submitOrder');
    expect(graph.root.children.single.displayName, 'persistOrder');
    expect(graph.directCalleeCount, 1);
    expect(graph.callersRoot.displayName, 'submitOrder');
    expect(graph.directCallerCount, 1);
    expect(graph.callersRoot.children.single.displayName, 'startCheckout');
    expect(
      graph.callersRoot.children.single.children.single.displayName,
      'main',
    );
  });

  test('detects recursive calls without infinitely expanding the tree', () {
    const entries = <WorkspaceEntry>[
      WorkspaceEntry(
        id: 'main',
        path: 'lib/main.dart',
        type: WorkspaceEntryType.file,
        content: '''
void first() {
  second();
}

void second() {
  first();
}
''',
      ),
    ];

    final graph = analyzer.analyze(
      entries: entries,
      activeFilePath: 'lib/main.dart',
      cursorLine: 1,
      cursorColumn: 2,
    );

    final cycle = graph.root.children.single.children.single;
    expect(cycle.displayName, 'first');
    expect(cycle.isCycle, isTrue);
    expect(cycle.children, isEmpty);

    final callerCycle = graph.callersRoot.children.single.children.single;
    expect(callerCycle.displayName, 'first');
    expect(callerCycle.isCycle, isTrue);
    expect(callerCycle.children, isEmpty);
  });

  test('records concrete call-site locations for Monaco wire rendering', () {
    const entries = <WorkspaceEntry>[
      WorkspaceEntry(
        id: 'main',
        path: 'lib/main.dart',
        type: WorkspaceEntryType.file,
        content: '''
void buildCart() {
  loadCart();
  loadCart();
}

void loadCart() {}
''',
      ),
    ];

    final graph = analyzer.analyze(
      entries: entries,
      activeFilePath: 'lib/main.dart',
      cursorLine: 1,
      cursorColumn: 5,
    );

    expect(graph.edges, hasLength(2));

    final first = graph.edges.first;
    final second = graph.edges.last;

    expect(first.sourceName, 'buildCart');
    expect(first.source.filePath, 'lib/main.dart');
    expect(first.source.line, 2);
    expect(first.callSite.filePath, 'lib/main.dart');
    expect(first.callSite.line, 3);
    expect(first.callSite.column, 3);
    expect(first.callSite.length, 'loadCart'.length);
    expect(first.targetName, 'loadCart');
    expect(first.target.line, 7);

    expect(second.callSite.line, 4);
    expect(second.target.line, 7);
  });

  test('requires the cursor to identify a method or function', () {
    const entries = <WorkspaceEntry>[
      WorkspaceEntry(
        id: 'main',
        path: 'lib/main.dart',
        type: WorkspaceEntryType.file,
        content: '''
import 'package:flutter/material.dart';

void main() {}
''',
      ),
    ];

    expect(
      () => analyzer.analyze(
        entries: entries,
        activeFilePath: 'lib/main.dart',
        cursorLine: 1,
        cursorColumn: 0,
      ),
      throwsA(isA<CodeFlowAnalysisException>()),
    );
  });
}
