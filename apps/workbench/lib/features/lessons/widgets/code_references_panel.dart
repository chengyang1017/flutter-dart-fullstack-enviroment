import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../models/code_reference.dart';

class CodeReferencesPanel extends StatelessWidget {
  const CodeReferencesPanel({
    super.key,
    required this.symbol,
    required this.references,
    required this.onOpenReference,
  });

  final String symbol;
  final List<CodeReference> references;
  final ValueChanged<CodeReference> onOpenReference;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (references.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.tr(
              '没有找到 $symbol 的引用。',
              'No references found for $symbol.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(
            l10n.tr(
              '$symbol · ${references.length} 个结果',
              '$symbol · ${references.length} results',
            ),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: references.length,
            separatorBuilder: (context, index) {
              return const Divider(height: 1);
            },
            itemBuilder: (context, index) {
              final reference = references[index];

              return ListTile(
                dense: true,
                leading: Icon(
                  reference.isDefinition
                      ? Icons.account_tree_outlined
                      : Icons.call_made_outlined,
                ),
                title: Text(
                  '${reference.fileName}:'
                  '${reference.line}:'
                  '${reference.column}',
                ),
                subtitle: Text(
                  reference.lineText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontFamilyFallback: [
                      'Cascadia Mono',
                      'Cascadia Code',
                      'Courier New',
                    ],
                  ),
                ),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    if (reference.isStandardAnswer)
                      Chip(
                        label: Text(l10n.tr('标准答案', 'Reference answer')),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (reference.isDefinition)
                      Chip(
                        label: Text(l10n.tr('定义', 'Definition')),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                onTap: () {
                  onOpenReference(reference);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
