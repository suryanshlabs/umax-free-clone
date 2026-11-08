import '../../core/report.dart';
import 'profile_wiki_bodies_a.dart';
import 'profile_wiki_bodies_b.dart';
import 'profile_wiki_bodies_c.dart';

/// Offline encyclopedia of looksmaxing and glow-up topics.
///
/// Hardcoded text modules. No network, no asset reads at runtime.
class WikiItem {
  const WikiItem({required this.heading, required this.body, required this.evidence});
  final String heading;
  final String body;
  final EvidenceStrength evidence;
}

class WikiSection {
  const WikiSection({required this.title, required this.tag, required this.items});
  final String title;
  final String tag;
  final List<WikiItem> items;
}

class ProfileWiki {
  const ProfileWiki();

  static final List<WikiSection> sections = <WikiSection>[
    WikiSection(
      title: 'Forward Facial Growth',
      tag: 'POSTURE',
      items: <WikiItem>[
        WikiItem(heading: 'Tongue posture (mewing)', body: mewingBody(), evidence: EvidenceStrength.emerging),
        WikiItem(heading: 'Swallowing mechanics', body: swallowBody(), evidence: EvidenceStrength.moderate),
        WikiItem(heading: 'Nasal breathing benefits', body: nasalBody(), evidence: EvidenceStrength.moderate),
      ],
    ),
    WikiSection(
      title: 'Symmetry Optimization',
      tag: 'SYMMETRY',
      items: <WikiItem>[
        WikiItem(heading: 'Sleeping postures', body: sleepBody(), evidence: EvidenceStrength.moderate),
        WikiItem(heading: 'Chewing equalization', body: chewBody(), evidence: EvidenceStrength.moderate),
        WikiItem(heading: 'Muscle imbalances', body: muscleBody(), evidence: EvidenceStrength.emerging),
      ],
    ),
    WikiSection(
      title: 'Body Composition & Angularity',
      tag: 'BODY COMP',
      items: <WikiItem>[
        WikiItem(heading: 'Body fat percentages', body: fatBody(), evidence: EvidenceStrength.strong),
        WikiItem(heading: 'Tracking facial definition', body: trackBody(), evidence: EvidenceStrength.measurement),
        WikiItem(heading: 'Sodium & water retention', body: sodiumBody(), evidence: EvidenceStrength.moderate),
        WikiItem(heading: 'Dietary guidelines', body: dietBody(), evidence: EvidenceStrength.strong),
      ],
    ),
    WikiSection(
      title: 'Skin & Hair Archetypes',
      tag: 'GROOMING',
      items: <WikiItem>[
        WikiItem(heading: 'Skin routine by archetype', body: skinBody(), evidence: EvidenceStrength.strong),
        WikiItem(heading: 'Routine schedules', body: scheduleBody(), evidence: EvidenceStrength.moderate),
        WikiItem(heading: 'Hairstyles for facial proportions', body: hairBody(), evidence: EvidenceStrength.moderate),
      ],
    ),
  ];
}
