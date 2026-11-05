import 'dart:async';
import 'dart:io';

import 'package:cantivra/data/app_repository.dart';
import 'package:cantivra/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'FTS searches 10,000 records accurately while caller stays responsive',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cantivra-search-benchmark-',
      );
      final repository = await AppRepository.open(
        '${temporary.path}/benchmark.sqlite',
      );
      var heartbeats = 0;
      final heartbeat = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => heartbeats++,
      );
      try {
        final createdAt = DateTime.utc(2026, 11, 4);
        // Each row has enough source text to exercise a realistic lyric index.
        await Future.wait(
          List.generate(
            10000,
            (index) => repository.saveContent(
              ContentItem(
                id: 'benchmark-$index',
                title: 'Benchmark hymn $index',
                kind: index.isEven ? ContentKind.hymn : ContentKind.prayer,
                sourceText:
                    'Verse 1\nWe gather in hope and walk together in peace.\n'
                    'We share the gifts of this day with our community.\n\n'
                    'Refrain\nMay love guide every step we take.\n'
                    'May grace surround us as we serve.\n\n'
                    'Verse 2\nWe bring our joys and sorrows into this place.\n'
                    'In gratitude we lift our voices and sing.\n\n'
                    'Collection reference: Hymnal $index.\n'
                    'Search identifier: token${index}end',
                tags: ['benchmark', 'community'],
                modifiedAt: createdAt,
              ),
            ),
          ),
        );
        expect(
          heartbeats,
          greaterThan(0),
          reason: 'The caller isolate must process events while SQLite writes.',
        );
        expect(await repository.searchContent(''), hasLength(10005));
        final searchHeartbeatsBefore = heartbeats;
        final timings = <int>[];
        for (var run = 0; run < 120; run++) {
          // Four-digit references keep the title and multiword searches
          // naturally bounded without relying on a result-limit API. Prefix
          // searches deliberately match 111 rows of varying token lengths.
          final index = 1000 + (run * 73) % 9000;
          final prefix = (index ~/ 100).toString();
          final query = switch (run % 4) {
            0 => 'token${index}end',
            1 => 'token$prefix',
            2 => 'Benchmark hymn $index',
            // Quotes currently retain the repository's AND/prefix semantics;
            // this does not claim adjacent-phrase matching.
            _ => '"Hymnal $index"',
          };
          final stopwatch = Stopwatch()..start();
          final results = await repository.searchContent(query);
          stopwatch.stop();
          if (run % 4 == 1) {
            final expectedIds = {
              for (var candidate = 0; candidate < 10000; candidate++)
                if (candidate.toString().startsWith(prefix))
                  'benchmark-$candidate',
            };
            expect(results, hasLength(111));
            expect(results.map((item) => item.id).toSet(), expectedIds);
          } else {
            expect(results.single.id, 'benchmark-$index');
          }
          if (run >= 20) timings.add(stopwatch.elapsedMicroseconds);
        }

        // Exercise a real broad lyric query separately. All generated rows
        // match, as does the sample whose words are nonadjacent. This records
        // the current unbounded-return and AND/prefix behavior honestly.
        final broadStopwatch = Stopwatch()..start();
        final broadResults = await repository.searchContent(
          '"we gather in hope"',
        );
        broadStopwatch.stop();
        expect(broadResults, hasLength(10001));
        expect(broadResults.map((item) => item.id).toSet(), {
          for (var index = 0; index < 10000; index++) 'benchmark-$index',
          'sample-gathering',
        });
        expect(
          heartbeats,
          greaterThan(searchHeartbeatsBefore),
          reason:
              'Search work must allow the caller isolate to process events.',
        );
        timings.sort();
        final median = timings[timings.length ~/ 2] / 1000;
        final p95 = timings[(timings.length * .95).ceil() - 1] / 1000;
        final maximum = timings.last / 1000;
        // This is a recorded local measurement, not a cross-platform speed gate.
        // Native hardware, debug mode and the test runner affect timings.
        // ignore: avoid_print
        print(
          'FTS benchmark (10,005 rows, 20 warmups, 100 measured samples; '
          'exact identifier, prefix, title, multiword AND/prefix): '
          'p50=${median.toStringAsFixed(2)} ms, p95=${p95.toStringAsFixed(2)} ms; '
          'max=${maximum.toStringAsFixed(2)} ms; '
          'broad unbounded query (10,001 results)='
          '${(broadStopwatch.elapsedMicroseconds / 1000).toStringAsFixed(2)} ms; '
          'search caller heartbeats=${heartbeats - searchHeartbeatsBefore}; '
          'mode=Flutter test, os=${Platform.operatingSystem}',
        );
        expect(await repository.integrityCheck(), 'ok');
      } finally {
        heartbeat.cancel();
        await repository.close();
        await temporary.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
