import 'package:flutter/material.dart';

import '../theme.dart';
import 'profile_wiki.dart';

/// Detail page for one encyclopedia section: every item, in full.
class WikiDetailScreen extends StatelessWidget {
  const WikiDetailScreen({super.key, required this.section});

  final WikiSection section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(section.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: <Widget>[
          Text(section.tag,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.textTertiary)),
          const SizedBox(height: 16),
          for (final WikiItem item in section.items) ...<Widget>[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.outline),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(item.heading,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Text(item.evidence.name.toUpperCase(),
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.accentSoft)),
                const SizedBox(height: 10),
                Text(item.body,
                    style: const TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSecondary)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
