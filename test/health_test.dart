import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/models.dart';

// Keksityt treenit ja kellon harjoitukset (ei oikeita tietoja).
void main() {
  final day = DateTime(2026, 11, 8);
  Workout run0() => Workout(date: day, title: 'Juoksu', activity: 'Juoksu', seconds: 1800, distanceKm: 6.2);
  Workout run({DateTime? start, int secs = 1800}) =>
      Workout(date: day, title: 'Juoksu', activity: 'Juoksu', started: start, seconds: secs);
  HealthCandidate c(DateTime s, int mins, {bool session = true, int? hr = 140, String app = 'Kello'}) =>
      HealthCandidate(
        session: session,
        start: s,
        end: s.add(Duration(minutes: mins)),
        hrAvg: hr,
        hrMax: 170,
        app: app,
      );

  test('Lähin päällekkäinen harjoitus ensin; kaukana oleva jää pois', () {
    final w = run(start: DateTime(2026, 11, 8, 12, 0));
    final best = c(DateTime(2026, 11, 8, 11, 58), 33, app: 'Paras');
    final near = c(DateTime(2026, 11, 8, 12, 40), 20, app: 'Lähellä');
    final far = c(DateTime(2026, 11, 8, 18, 0), 30, app: 'Kaukana');
    final hrOnly = c(DateTime(2026, 11, 8, 12, 0), 30, session: false, app: '');
    final r = rankCandidates(w, [far, near, hrOnly, best]);
    expect(r.first.app, 'Paras');
    expect(r.map((x) => x.app), isNot(contains('Kaukana')));
    // Treenin koko ajan kattava sykedata ennen 40 min myöhemmin alkanutta harjoitusta, mutta parhaan jälkeen.
    expect(r.map((x) => x.app), ['Paras', '', 'Lähellä']);
  });

  test('Ilman alkuaikaa: saman päivän harjoitukset, lähin kesto ensin', () {
    final w = run(secs: 1800);
    final r = rankCandidates(w, [
      c(DateTime(2026, 11, 8, 7, 0), 90, app: 'Pitkä'),
      c(DateTime(2026, 11, 8, 17, 0), 31, app: 'Sama kesto'),
      c(DateTime(2026, 11, 9, 7, 0), 30, app: 'Huomenna'),
    ]);
    expect(r.map((x) => x.app), ['Sama kesto', 'Pitkä']);
  });

  test('Kellon tiedot tallentuvat .md-tiedostoon ja luetaan takaisin (liikunta ja salitreeni)', () {
    final run = run0()..steps = 5600;
    applyCandidate(run, HealthCandidate(session: true, start: day, end: day, hrAvg: 144, hrMax: 157, kcal: 420));
    final md = workoutToMarkdown(run);
    expect(md, allOf(contains('hr_avg: 144'), contains('hr_max: 157'), contains('kcal: 420'), contains('steps: 5600')));
    final back = parseWorkout(md);
    expect((back.hrAvg, back.hrMax, back.kcal, back.steps), (144, 157, 420, 5600));
    final gym = Workout(
      date: day,
      title: 'Koko keho A',
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(80, 5)]),
      ],
    );
    applyCandidate(gym, HealthCandidate(session: true, start: day, end: day, hrAvg: 120, hrMax: 165, kcal: 380));
    final g = parseWorkout(workoutToMarkdown(gym));
    expect((g.hrAvg, g.hrMax, g.kcal, g.steps), (120, 165, 380, null));
  });

  test('Ehdokas ilman sykettä tai kaloreita ohitetaan; lisäys täyttää vain löytyneet', () {
    final w = run(start: DateTime(2026, 11, 8, 12, 0))..kcal = 300;
    expect(rankCandidates(w, [c(DateTime(2026, 11, 8, 12, 0), 30, hr: null).copyWithoutMax()]), isEmpty);
    applyCandidate(w, HealthCandidate(session: true, start: day, end: day, hrAvg: 151, hrMax: 178));
    expect((w.hrAvg, w.hrMax, w.kcal), (151, 178, 300));
    // Askeleet vain kävely- ja juoksulajeihin.
    final steps = HealthCandidate(session: true, start: day, end: day, hrAvg: 140, steps: 5600);
    applyCandidate(w, steps, steps: true);
    expect(w.steps, 5600);
    final gym = Workout(date: day, title: 'Sali');
    applyCandidate(gym, steps);
    expect(gym.steps, isNull);
  });
}

extension on HealthCandidate {
  HealthCandidate copyWithoutMax() =>
      HealthCandidate(session: session, start: start, end: end, title: title, type: type, app: app, hrAvg: hrAvg);
}
