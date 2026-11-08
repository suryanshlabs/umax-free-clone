import 'package:flutter/material.dart';

import 'profile_wiki.dart';
import 'wiki_detail_screen.dart';

/// Pushes the detail page for [section].
void showWikiDetail(BuildContext context, WikiSection section) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => WikiDetailScreen(section: section),
    ),
  );
}
