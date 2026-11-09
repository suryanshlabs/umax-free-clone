import 'dart:convert';

import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/core/user_profile.dart';
import 'package:facial_analysis/data/scan_history.dart';
import 'package:facial_analysis/ui/profile_input_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scan-history file exactly as version 2 wrote it: a profile with age,
/// height, weight and BMI, and a scan with a per-metric BMI copy.
const String _legacyFile =
    '{"version":2,'
    '"profile":{"gender":"male","age":30,"heightCm":175.0,"weightKg":80.0,'
    '"heightKnown":true,"weightKnown":true},'
    '"scans":[{"id":"old","at":"2026-09-01T10:00:00.000","score":70,'
    '"grade":"Balanced","potential":78.5,'
    '"profile":{"gender":"male","age":30,"heightCm":175.0,"weightKg":80.0},'
    '"metrics":['
    '{"id":"eyeSymmetry","title":"Eye symmetry","raw":"1.2%","score":71},'
    '{"id":"jawline","title":"Jawline angularity","raw":"96°","score":64,'
    '"bmi":24.5,"age":30,"gender":"male"},'
    '{"id":"facialThirds","title":"Facial thirds","raw":"1:1:1","score":80}'
    '],"warnings":["Head turned"],"image":null}]}';

Map<String, Object?> _json(String contents) =>
    jsonDecode(contents) as Map<String, Object?>;

void main() {
  group('face onboarding', () {
    testWidgets('asks only for optional gender', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProfileInputSheet())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gender (optional)'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(
        find.text('Another identity / prefer to self-describe'),
        findsOneWidget,
      );
      expect(find.text('Prefer not to say'), findsOneWidget);

      // No body-composition inputs anywhere in the face flow.
      expect(find.textContaining('AGE'), findsNothing);
      expect(find.textContaining('HEIGHT'), findsNothing);
      expect(find.textContaining('WEIGHT'), findsNothing);
      expect(find.textContaining('BMI'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('nothing is preselected, and skipping returns nothing', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      UserProfile? result;
      bool opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    opened = true;
                    result = await showProfileInputSheet(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);

      // No default: nothing shows as selected, so Continue with no answer is
      // the same as skipping rather than a silent "other".
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('a chosen gender is returned as a gender-only profile', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      UserProfile? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showProfileInputSheet(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Female'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.gender, Gender.female);
      expect(result!.toJson().keys, <String>['gender']);
    });
  });

  group('scan-history compatibility', () {
    test('an older file keeps every scan and loses only body fields', () async {
      final MemoryScanHistoryStorage storage = MemoryScanHistoryStorage(
        _legacyFile,
      );
      final ScanHistory history = ScanHistory(storage: storage);
      await history.load();

      expect(history.isLoaded, isTrue);
      expect(history.scans, hasLength(1));
      final SavedScan scan = history.scans.single;
      expect(scan.id, 'old');
      expect(scan.overallScore, 70);
      // The retired rating and projection are ignored, not displayed: the band
      // is derived from the score with the current wording.
      expect(scan.bandLabel, 'Mixed');
      expect(scan.warnings, <String>['Head turned']);
      expect(scan.metric(MetricId.jawline)?.score, 64);
      expect(scan.metric(MetricId.jawline)?.rawValue, '96°');

      // The optional gender survives; the body-composition fields do not.
      expect(history.profile?.gender, Gender.male);

      // Force a rewrite, the way any save would.
      await history.setProfile(history.profile);
      final Map<String, Object?> written = _json(storage.contents!);
      expect(written['version'], 3);

      final Map<String, Object?> profile =
          written['profile']! as Map<String, Object?>;
      expect(profile.keys.toList(), <String>['gender']);
      expect(profile['gender'], 'male');

      final Map<String, Object?> storedScan =
          (written['scans']! as List<Object?>).single! as Map<String, Object?>;
      expect(storedScan.containsKey('profile'), isFalse);
      expect(storedScan['score'], 70);
      expect(storedScan['metrics'], hasLength(3));

      for (final Object? entry in storedScan['metrics']! as List<Object?>) {
        final Map<String, Object?> metric = entry! as Map<String, Object?>;
        expect(metric.containsKey('bmi'), isFalse);
        expect(metric.containsKey('age'), isFalse);
        expect(metric.containsKey('gender'), isFalse);
      }
    });

    test('new scans are written without body measurements', () {
      final SavedScan scan = SavedScan(
        id: 'new',
        createdAt: DateTime(2026, 11, 9, 10, 30),
        overallScore: 66,
        metrics: const <SavedMetric>[
          SavedMetric(
            id: MetricId.eyeSymmetry,
            title: 'Eye symmetry',
            rawValue: '1.8%',
            score: 70,
          ),
        ],
      );

      final Map<String, Object?> json = scan.toJson();
      expect(json.keys, isNot(contains('profile')));
      expect(json.keys, isNot(contains('bmi')));
      expect(json.keys, isNot(contains('heightCm')));
      expect(json.keys, isNot(contains('weightKg')));
      expect(json.keys, isNot(contains('age')));

      final Map<String, Object?> roundTripped = SavedScan.fromJson(
        jsonDecode(jsonEncode(json)),
      )!.toJson();
      expect(roundTripped.keys, json.keys);
    });

    test(
      'a corrupt or unrelated profile block is ignored, not fatal',
      () async {
        final ScanHistory history = ScanHistory(
          storage: MemoryScanHistoryStorage(
            '{"version":2,"profile":{"gender":"unknown-value"},"scans":[]}',
          ),
        );
        await history.load();
        expect(history.isLoaded, isTrue);
        expect(history.profile, isNull);
        expect(history.scans, isEmpty);
      },
    );
  });

  group('profile model', () {
    test('gender options are the four required choices', () {
      expect(Gender.values.map((Gender g) => g.label).toList(), <String>[
        'Male',
        'Female',
        'Another identity / prefer to self-describe',
        'Prefer not to say',
      ]);
    });

    test('an old profile reads back as gender only', () {
      final UserProfile? profile = UserProfile.fromJson(<String, Object?>{
        'gender': 'female',
        'age': 41,
        'heightCm': 165.0,
        'weightKg': 61.0,
        'heightKnown': true,
        'weightKnown': true,
      });
      expect(profile?.gender, Gender.female);
      expect(profile?.toJson().keys, <String>['gender']);
    });

    test('a missing or unrecognised gender is not turned into a default', () {
      expect(UserProfile.fromJson(null), isNull);
      expect(UserProfile.fromJson(<String, Object?>{}), isNull);
      expect(
        UserProfile.fromJson(<String, Object?>{'gender': 'other'}),
        isNull,
      );
      expect(const UserProfile().gender, isNull);
      expect(const UserProfile().isEmpty, isTrue);
    });
  });
}
