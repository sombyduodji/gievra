import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/stats.dart';

Workout g(DateTime d, int feel, {String title = 'Koko keho A', String ex = 'Takakyykky', double kg = 100}) => Workout(
  date: d,
  title: title,
  feeling: feel,
  minutes: 60,
  exercises: [
    ExerciseEntry(ex, [SetEntry(kg, 5), SetEntry(kg, 5)]),
  ],
);

void main() {
  final today = DateTime(2026, 11, 7); // lauantai
  test('Viikko- ja kuukausikooste', () {
    final ws = [
      g(DateTime(2026, 11, 2), 4),
      g(DateTime(2026, 11, 4), 5),
      Workout(date: DateTime(2026, 11, 5), title: 'Juoksu', activity: 'Juoksu', minutes: 40, distanceKm: 7, feeling: 3),
      g(DateTime(2026, 10, 28), 3),
    ];
    final w = recap(ws, DateTime(2026, 11, 2), DateTime(2026, 11, 9));
    expect((w.gym, w.activities, w.sets, w.minutes, w.km), (2, 1, 4, 160, 7.0));
    expect(w.feeling, 4.0);
    final m = recap(ws, monthStart(today), nextMonth(today));
    expect(m.sessions, 3);
  });

  test('Fiiliksen lasku, raskas viikonpäivä ja raskas treeni tuottavat ehdotukset', () {
    final ws = <Workout>[];
    // 7 viikkoa sitten – 3 viikkoa sitten hyvä fiilis, sen jälkeen huono; maanantait aina raskaita.
    for (var i = 49; i >= 1; i--) {
      final d = addDays(today, -i);
      if (d.weekday == DateTime.monday) {
        ws.add(g(d, 2, title: 'Koko keho B', ex: 'Maastaveto'));
      } else if (d.weekday == DateTime.wednesday || d.weekday == DateTime.friday) {
        ws.add(g(d, i > 21 ? 5 : 3));
      }
    }
    final tips = feelingSuggestions(ws, today);
    expect(tips.join('\n'), contains('laskenut'));
    expect(tips.join('\n'), contains('Maanantain'));
    expect(tips.join('\n'), contains('Koko keho B'));
    final fs = feelingStats(ws, today);
    expect(fs.byWeekday.firstWhere((x) => x.label == 'ma').avg, 2);
    expect(fs.weekly.length, 12);
    expect(fs.weekly.where((w) => w.$3 > 0), isNotEmpty);
  });

  test('Voimakehitys kuukausittain', () {
    final ws = [for (var m = 6; m <= 11; m++) g(DateTime(2026, m, 10), 4, kg: 80.0 + m * 5)];
    final t = liftTrends(ws, today);
    expect(t.single.exercise, 'Takakyykky');
    expect(t.single.monthly.length, 6);
    expect(t.single.change, greaterThan(0));
    // Yksi kevyt kuukausi lopussa ei romahduta käyrää.
    final light = [
      ...ws,
      Workout(
        date: DateTime(2026, 11, 20),
        exercises: [
          ExerciseEntry('Takakyykky', [SetEntry(40, 5)]),
        ],
      ),
    ];
    expect(liftTrends(light, DateTime(2026, 11, 25)).single.monthly.last.$2, greaterThan(130));
  });

  test('Ei historiaa: ei ehdotuksia eikä virheitä', () {
    expect(feelingSuggestions([], today), isEmpty);
    expect(feelingStats([], today).count, 0);
    expect(liftTrends([], today), isEmpty);
  });

  test('iso pudotus näytetään kevyenä jaksona, pieni lasku prosentteina', () {
    final m = DateTime(2026, 5);
    final drop = LiftTrend('Maastaveto', [(m, 180), (DateTime(2026, 9), 180), (DateTime(2026, 10), 60)]);
    expect(drop.light, isTrue);
    final small = LiftTrend('Takakyykky', [(m, 160), (DateTime(2026, 10), 136)]);
    expect(small.light, isFalse);
    expect((small.change! * 100).round(), -15);
  });
}
