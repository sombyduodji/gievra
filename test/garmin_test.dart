import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/garmin_import.dart';
import 'package:treenipaivakirja/models.dart';

// Garmin Connectin suomenkielisen CSV-viennin sarakkeet; arvot keksittyjä.
const header =
    'Suorituksen tyyppi,Päiväys,Suosikki,Otsikko,Etäisyys,Kalorit,Aika,Keskisyke,Maksimisyke,Aerobinen TE,'
    'Keskimääräinen askeltiheys,Maksimi askeltiheys,Keskitahti,Paras tahti,Kokonaisnousu,Kokonaislasku,'
    'Askeleen keskipituus,Keskipystysuhde,Keskimääräinen pystysuuntainen liikehdintä,Maakosketuksen keskikesto,'
    'Keski-GAP,Normalized Power® (NP®),Training Stress Score®,Keskiteho,Maksimiteho,Askeleet,'
    'Body Battery -kulutus,Paineentasaus,Paras kierrosaika,Kierrosten määrä,Aika liikkeellä,Kulunut aika,'
    'Minimikorkeus,Maksimikorkeus';

const csv =
    '$header\n'
    'Juoksu,2025-05-10 07:30:00,false,"Esimerkki Juoksu","12.00","1,050","01:30:00","140","160","4.5","160","175",'
    '"7:30","5:30","100","100","0.90","9.0","8.0","300","7:30","250","0.0","250","400","15,000","\'-20","Ei",'
    '"00:00:10.0","12","01:29:00","01:30:00","10","50"\n'
    'Juoksumattojuoksu,2025-05-05 06:00:00,false,"Juoksumattojuoksu","5.00","400","00:40:00","130","150","3.0",'
    '"150","170","8:00","6:00","--","--","0.90","9.0","8.0","300","--","250","0.0","220","300","6,000","--","Ei",'
    '"00:05:00.0","5","00:39:00","00:40:00","--","--"\n'
    'Voimaharjoittelu,2025-05-06 18:00:00,false,"Voimaharjoittelu","0.00","300","00:45:00","110","140","2.1",'
    '"--","--","--","--","--","--","--","--","--","--","--","--","--","--","--","--","--","Ei","--","1",'
    '"00:45:00","00:45:00","--","--"\n'
    'Allasuinti,2025-05-07 07:00:00,false,"Uinti","1,500","400","00:35:10","120","150","2.0","--","--","--",'
    '"--","--","--","--","--","--","--","--","--","--","--","--","--","--","Ei","--","30","00:33:00","00:35:10",'
    '"--","--"\n';

void main() {
  test('Luvut ja ajat Garminin muodossa', () {
    expect(garminNum('12.34'), 12.34);
    expect(garminNum('1,050'), 1050);
    expect(garminNum('20,848'), 20848);
    expect(garminNum('12.34'), 12.34);
    expect(garminNum('--'), isNull);
    expect(garminDuration('01:02:03'), 3723);
    expect(garminDuration('00:00:08.5'), 9);
    expect(garminSport('Juoksumattojuoksu'), 'Juoksu');
    expect(garminSport('Trail Running'), 'Juoksu');
    expect(garminSport('Indoor Cycling'), 'Pyöräily');
    expect(garminSport('Strength Training'), isNull);
  });

  test('Juoksut, uinti ja ohitettu voimaharjoittelu', () {
    final (r, skipped) = readGarminCsv(csv, const []);
    expect(skipped, 1);
    expect(r.workouts.length, 3);
    final run = r.workouts.last;
    expect(run.activity, 'Juoksu');
    expect(run.date, DateTime(2025, 5, 10));
    expect(run.started, DateTime(2025, 5, 10, 7, 30));
    expect(run.distanceKm, 12);
    expect(run.seconds, 5400);
    expect(run.kcal, 1050);
    expect(run.hrAvg, 140);
    expect(run.hrMax, 160);
    expect(run.intensity, 'kova');
    expect(run.pace, '7:30 /km');
    expect(run.notes, contains('nousu 100 m'));
    expect(run.notes, contains('askeltiheys 160 /min'));
    final mill = r.workouts.firstWhere((w) => w.date == DateTime(2025, 5, 5));
    expect(mill.notes, contains('juoksumatto'));
    final swim = r.workouts.firstWhere((w) => w.activity == 'Uinti');
    expect(swim.distanceKm, 1.5); // metreistä kilometreiksi
    // Tiedostoon ja takaisin: kesto, syke ja matka säilyvät.
    final back = parseWorkout(workoutToMarkdown(run));
    expect(back.seconds, 5400);
    expect(back.hrAvg, 140);
    expect(back.activity, 'Juoksu');
  });

  test('Sama päivä: oma treeninumero; uusi tuonti ei tuo kaksoiskappaleita', () {
    final gym = Workout(date: DateTime(2025, 5, 10), title: 'Koko keho A');
    final (r, _) = readGarminCsv(csv, [gym]);
    final run = r.workouts.last;
    expect(run.session, 2); // sali on treeni 1
    // Toinen tuonti: sama juoksu jo päiväkirjassa -> sama numero, esikatselu laskee sen olemassa olevaksi.
    final (r2, _) = readGarminCsv(csv, [gym, run]);
    expect(r2.workouts.last.session, run.session);
  });

  test('Kävelyssä askeleet omaan kenttäänsä, juoksussa muistiinpanoihin', () {
    final walk =
        '$header\n'
        'Kävely,2025-05-11 18:00:00,false,"Iltakävely","4.00","250","00:50:00","100","120","1.5","110","120",'
        '"12:30","10:00","20","20","0.70","--","--","--","--","--","0.0","--","--","6,200","--","Ei","--","4",'
        '"00:49:00","00:50:00","--","--"\n';
    final (r, _) = readGarminCsv(walk, const []);
    final w = r.workouts.single;
    expect(w.activity, 'Kävely');
    expect(w.steps, 6200);
    expect(w.notes, isNot(contains('askeleet')));
    final md = workoutToMarkdown(w);
    expect(md, contains('steps: 6200'));
    expect(md, contains('6200 askelta'));
    expect(parseWorkout(md).steps, 6200);
    // Juoksussa askeleet jäävät muistiinpanoihin.
    final (run, _) = readGarminCsv(csv, const []);
    expect(run.workouts.last.steps, isNull);
    expect(run.workouts.last.notes, contains('askeleet 15000'));
  });
}
