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
