import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/services/dart_code_flow_analyzer.dart';
import 'package:flutter_ui_playground/features/playground/widgets/function_call_graph_view.dart';

void main() {
  const caller = CodeFlowNode(
    name: 'build',
    displayName: 'FeedScreen.build',
    location: CodeFlowLocation(
      filePath: 'lib/feed_screen.dart',
      line: 10,
      column: 3,
      length: 5,
    ),
    children: <CodeFlowNode>[
      CodeFlowNode(
        name: 'loadPosts',
        displayName: 'loadPosts',
        location: CodeFlowLocation(
          filePath: 'lib/feed_screen.dart',
          line: 24,
          column: 3,
          length: 9,
        ),
      ),
    ],
  );

  const incomingRoot = CodeFlowNode(
    name: 'loadPosts',
    displayName: 'loadPosts',
    location: CodeFlowLocation(
      filePath: 'lib/feed_screen.dart',
      line: 24,
      column: 3,
      length: 9,
    ),
    children: <CodeFlowNode>[
      CodeFlowNode(
        name: 'build',
        displayName: 'FeedScreen.build',
        location: CodeFlowLocation(
          filePath: 'lib/feed_screen.dart',
          line: 10,
          column: 3,
          length: 5,
        ),
      ),
    ],
  );

  testWidgets('call graph explains caller and callee endpoint semantics', (
    tester,
  ) async {
    CodeFlowNode? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: FunctionCallGraphView(
              root: caller,
              direction: FunctionCallGraphDirection.outgoing,
              onNodeTap: (node) => tapped = node,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('function-call-edge-legend')),
      findsOneWidget,
    );
    expect(find.text('调用者：圆点发出调用'), findsOneWidget);
    expect(find.text('被调用者：箭头指向这里'), findsOneWidget);
    expect(find.text('调用 → 被调用'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('function-call-edge-layer')),
      findsOneWidget,
    );
    expect(find.text('FeedScreen.build'), findsOneWidget);
    expect(find.text('loadPosts'), findsOneWidget);

    await tester.tap(find.text('loadPosts'));
    await tester.pump();
    expect(tapped?.displayName, 'loadPosts');
  });

  testWidgets('incoming graph keeps the real call direction semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: FunctionCallGraphView(
              root: incomingRoot,
              direction: FunctionCallGraphDirection.incoming,
              onNodeTap: (_) {},
            ),
          ),
        ),
      ),
    );

    // The root is the callee in incoming mode and its child is the caller.
    // The painter therefore draws the same caller-dot -> callee-arrow meaning
    // from right to left instead of redefining the endpoints.
    expect(find.text('调用者：圆点发出调用'), findsOneWidget);
    expect(find.text('被调用者：箭头指向这里'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('function-call-edge-layer')),
      findsOneWidget,
    );
    expect(find.text('loadPosts'), findsOneWidget);
    expect(find.text('FeedScreen.build'), findsOneWidget);
  });
}
