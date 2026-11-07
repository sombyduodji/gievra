import 'exercises.dart';
import 'program.dart';
import 'l10n.dart' as l10n;

// Ohjelman pätevyystarkistus. Säännöt ja niiden perusta:
//  - Koko keho -päivä: alavartalon pääliike (kyykky tai lonkkasarana), työntö ja veto samassa treenissä;
//    ylävartalopäivä: sekä työntö että veto (NSCA:n ohjelmasuunnittelun liikemallit, toissijaiset lähteet:
//    nasm.org upper/lower splits, ecampusontario Human Movement).
//  - Viikossa vetoa vähintään yhtä paljon kuin työntöä (0,9–2,0 × työntösarjat) ja vaakavetoa mukana.
//    Valmennuskäytäntö: tutkimus ei todista tiettyä suhdetta, mutta olkapääriskit liittyvät etu-takapuolen
//    epätasapainoon (Kolber ym. 2010 -katsaus; palomies- ja poliisitutkimukset push/pull-suhteista).
//  - Viikossa kaikki päämallit: kyykky, lonkkasarana, vaakatyöntö, vaakaveto, pystyveto
//    (pystytyöntö saa puuttua vain, jos vammatila on poistanut sen).
//  - Lihaskasvussa jokaiselle päälihasryhmälle vähintään 4 murto-osasarjaa viikossa (Iversen ym. 2021)
//    ja 3+ päivän ohjelmissa vähintään 2 kertaa viikossa (Schoenfeld ym. 2016).
//  - Yhden treenin lihasryhmäkohtainen yläraja (Remmert ym. 2025: hyöty ei kasva ~11 sarjan jälkeen).
//  - Järjestys: moninivelliikkeet ennen eristäviä (ACSM 2009).

const pushSlots = {'VTY', 'VIN', 'PTY', 'RIE', 'KP', 'PEV'};
const pullSlots = {'VVE', 'PVE', 'TAK'};
const horizontalPull = {'VVE'};

/// Murto-osasarjat lihasryhmälle (suora 1, epäsuora 0,5), docs/tutkimus/ohjelmat.md kohta 2a.
const slotMuscles = <String, Map<String, double>>{
  'KYY': {'etureisi': 1, 'pakara': .5},
  'KK': {'etureisi': 1, 'pakara': .5},
  'KYV': {'etureisi': 1},
  'LON': {'takareisi': 1, 'pakara': 1},
  'KM': {'takareisi': 1, 'pakara': 1},
  'MAV': {'takareisi': 1, 'pakara': 1},
  'YKS': {'etureisi': 1, 'pakara': .5},
  'POJ': {'etureisi': 1},
  'POK': {'takareisi': 1},
  'PAK': {'pakara': 1, 'takareisi': .5},
  'POH': {'pohje': 1},
  'VTY': {'rinta': 1, 'ojentaja': .5, 'olkapää': .5},
  'KP': {'rinta': 1, 'ojentaja': .5, 'olkapää': .5},
  'PEV': {'rinta': 1, 'ojentaja': .5},
  'VIN': {'rinta': 1, 'olkapää': .5, 'ojentaja': .5},
  'PTY': {'olkapää': 1, 'ojentaja': .5},
  'VVE': {'selkä': 1, 'hauis': .5, 'takaolka': .5},
  'PVE': {'selkä': 1, 'hauis': .5},
  'RIE': {'rinta': 1},
  'OSI': {'olkapää': 1},
  'TAK': {'takaolka': 1},
  'HAU': {'hauis': 1},
  'OJE': {'ojentaja': 1},
  'KES': {'vatsa': 1},
};

/// Lihasryhmien nimet käännöksiä varten (näytetään t(nimi)-kutsulla).
// l10n: data
const muscleNames = [
  'etureisi',
  'hauis',
  'ojentaja',
  'olkapää',
  'pakara',
  'pohje',
  'rinta',
  'selkä',
  'takaolka',
  'takareisi',
  'vatsa',
];

const majorMuscles = ['rinta', 'selkä', 'etureisi', 'takareisi', 'pakara', 'olkapää'];

/// Viikon sarjat (voimanoston H/V-liikkeillä viikon 1 sarjat).
int setsOf(Program p, PlanItem i) => switch (i.kind) {
  'H' => plHeavy[0].$1,
  'V' => plVolume[0].$1,
  _ => i.sets,
};

class ProgramStats {
  final Map<String, double> weekly = {};
  final Map<String, int> frequency = {};
  double push = 0, pull = 0, hPull = 0;
}

ProgramStats statsOf(Program p) {
  final st = ProgramStats();
  for (final d in p.plan) {
    final hit = <String>{};
    for (final i in d.items) {
      final n = setsOf(p, i).toDouble();
      if (pushSlots.contains(i.slot)) st.push += n;
      if (pullSlots.contains(i.slot)) st.pull += n;
      if (horizontalPull.contains(i.slot)) st.hPull += n;
      for (final e in (slotMuscles[i.slot] ?? const <String, double>{}).entries) {
        st.weekly[e.key] = (st.weekly[e.key] ?? 0) + n * e.value;
        if (e.value >= 1) hit.add(e.key);
      }
    }
    for (final m in hit) {
      st.frequency[m] = (st.frequency[m] ?? 0) + 1;
    }
  }
  return st;
}

/// Palauttaa havaitut ongelmat (tyhjä = pätevä).
List<String> validateProgram(Program p, {List<String> injuries = const []}) {
  final issues = <String>[];
  final st = statsOf(p);
  final slotsUsed = {for (final d in p.plan) ...d.items.map((i) => i.slot)};
  bool has(Iterable<String> any) => any.any(slotsUsed.contains);

  // 1. Päivien rakenne
  for (final d in p.plan) {
    final s = d.items.map((i) => i.slot).toSet();
    final push = s.any(pushSlots.contains), pull = s.any(pullSlots.contains);
    final lower = s.any({'KYY', 'KK', 'KYV', 'LON', 'KM', 'MAV', 'YKS'}.contains);
    final n = d.name.toLowerCase();
    if (n.startsWith('koko keho') || n.startsWith('voima')) {
      if (!lower) issues.add(l10n.t('{0}: ei alavartalon pääliikettä', [l10n.trName(d.name)]));
      if (!push || !pull) {
        issues.add(l10n.t('{0}: koko kehon treenissä pitää olla sekä työntö että veto', [l10n.trName(d.name)]));
      }
    } else if (n.startsWith('ylävartalo') || n.startsWith('penkki')) {
      if (!push || !pull) {
        issues.add(l10n.t('{0}: ylävartalopäivässä pitää olla sekä työntö että veto', [l10n.trName(d.name)]));
      }
    }
    // Järjestys: moninivelliikkeet ensin
    var seenIso = false;
    for (final i in d.items) {
      if (!i.compound && i.kind == null) seenIso = true;
      if (i.compound && seenIso) {
        issues.add(
          l10n.t('{0}: moninivelliike {1} eristävän jälkeen', [l10n.trName(d.name), exerciseLabel(i.exercise)]),
        );
      }
    }
    // Treenikohtainen yläraja
    final exp = p.goal == 'vapaa' ? 'keski' : p.experience; // "fiiliksellä" käyttää keskitason arvoja
    final cap = switch (exp) {
      'aloittelija' => 6.0,
      'kokenut' => 10.0,
      _ => 8.0,
    };
    final perDay = <String, double>{};
    for (final i in d.items) {
      for (final e in (slotMuscles[i.slot] ?? const <String, double>{}).entries) {
        perDay[e.key] = (perDay[e.key] ?? 0) + setsOf(p, i) * e.value;
      }
    }
    for (final e in perDay.entries) {
      if (majorMuscles.contains(e.key) && e.value > cap + .01 && !p.powerlifting) {
        issues.add(
          l10n.t('{0}: {1} {2} sarjaa yhdessä treenissä (yläraja {3})', [
            l10n.trName(d.name),
            l10n.t(e.key),
            e.value,
            cap,
          ]),
        );
      }
    }
  }

  // 2. Viikon työntö/veto-tasapaino
  if (st.push > 0 && (st.pull < st.push * .9 || st.pull > st.push * 2)) {
    issues.add(l10n.t('työntö {0} / veto {1} sarjaa viikossa: vetoa pitää olla 0,9–2 × työntö', [st.push, st.pull]));
  }
  if (st.hPull == 0) issues.add(l10n.t('ei vaakavetoa (soutua) viikossa'));

  // 3. Päämallit viikossa
  if (!has({'KYY', 'KK', 'KYV', 'YKS'})) issues.add(l10n.t('ei kyykkymallia'));
  if (!has({'LON', 'KM', 'MAV'})) issues.add(l10n.t('ei lonkkasaranaa'));
  if (!has({'VTY', 'KP', 'PEV', 'VIN'})) issues.add(l10n.t('ei vaakatyöntöä'));
  if (!has({'PVE'})) issues.add(l10n.t('ei pystyvetoa'));
  if (!has({'PTY'}) && injuries.isEmpty && !(p.powerlifting && p.experience != 'aloittelija' && p.plan.length < 4)) {
    issues.add(l10n.t('ei pystytyöntöä'));
  }

  // 4. Lihaskasvun volyymi ja tiheys
  if (!p.powerlifting) {
    for (final m in majorMuscles) {
      final v = st.weekly[m] ?? 0;
      if (v < 4) issues.add(l10n.t('{0}: {1} sarjaa viikossa (vähintään 4)', [l10n.t(m), v]));
      if (p.plan.length >= 3 &&
          p.goal != 'kunto' &&
          p.goal != 'vapaa' &&
          (st.frequency[m] ?? 0) < 2 &&
          m != 'olkapää' &&
          m != 'pakara') {
        issues.add(l10n.t('{0}: {1} kertaa viikossa (vähintään 2)', [l10n.t(m), st.frequency[m] ?? 0]));
      }
    }
  }
  return issues;
}
