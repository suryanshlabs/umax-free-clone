import 'package:flutter/material.dart';

import '../theme.dart';
import 'profile_wiki.dart';
import 'wiki_routes.dart';

/// Offline encyclopedia browser: the four hardcoded ProfileWiki sections.
/// No network, no assets — text ships inside the app.
class EncyclopaediaScreen extends StatelessWidget {
  const EncyclopaediaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile Encyclopedia')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: <Widget>[
          const Text(
            'Hardcoded, offline reference. Tap a section to read it in full.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          for (final WikiSection section in ProfileWiki.sections)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.outline),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(section.title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text('${section.tag} · ${section.items.length} topics',
                    style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                onTap: () => showWikiDetail(context, section),
              ),
            ),
        ],
      ),
    );
  }
}
