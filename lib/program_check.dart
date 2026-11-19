import 'exercises.dart';
import 'models.dart' show fmtNum;
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
  'etuolkapää',
  'sivuolkapää',
  'takaolkapää',
  'leveä selkälihas',
  'yläselkä',
  'alaselkä',
  'kyynärvarret',
  'lähentäjät',
  'käsivarret',
  'jalat',
];

const majorMuscles = ['rinta', 'selkä', 'etureisi', 'takareisi', 'pakara', 'olkapää'];

/// Viikon sarjat (voimanoston H/V-liikkeillä viikon 1 sarjat).
int setsOf(Program p, PlanItem i) => switch (i.kind) {
  'H' => plHeavy[0].$1,
  'V' => plVolume[0].$1,
  _ => i.sets,
};

/// Olkapään ja selän osat (käyttäjä 16.11.: alarivit viikon kuormaan). Vain sarjamäärä, ei suositusta: liikemalli
/// kertoo pääpainon (punnerrus etuolkapäälle, vipunosto sivulle, soutu yläselälle, pystyveto leveälle selkälihakselle),
/// otteen ja kyynärpään asennon vaikutusta ei tiedetä.
const subMuscles = {
  'olkapää': ['etuolkapää', 'sivuolkapää', 'takaolkapää'],
  'selkä': ['leveä selkälihas', 'yläselkä', 'alaselkä'],
};
const slotSubMuscles = <String, Map<String, double>>{
  'VTY': {'etuolkapää': .5},
  'KP': {'etuolkapää': .5},
  'VIN': {'etuolkapää': .5},
  'PTY': {'etuolkapää': 1, 'sivuolkapää': .5},
  'OSI': {'sivuolkapää': 1},
  'TAK': {'takaolkapää': 1, 'yläselkä': .5},
  'VVE': {'yläselkä': 1, 'leveä selkälihas': .5, 'takaolkapää': .5},
  'PVE': {'leveä selkälihas': 1},
  'LON': {'alaselkä': .5},
  'KM': {'alaselkä': 1, 'yläselkä': .5},
  'MAV': {'alaselkä': 1, 'yläselkä': .5},
  'KAN': {'yläselkä': .5},
  // Lähentäjät saavat paljon kyykyistä ja askelkyykyistä (iso lähentäjä), puolikkaana.
  'KYY': {'lähentäjät': .5},
  'KK': {'lähentäjät': .5},
  'YKS': {'lähentäjät': .5},
};

/// Tietorivit (käyttäjä 16.11.): kyynärvarret käsivarsien ja lähentäjät jalkojen alla. Vain sarjamäärä.
const infoMuscles = {'kyynärvarret', 'lähentäjät'};

/// Liikekohtaiset lihakset paikan sijaan: lähennykset eivät ole keskivartaloa (Kööpenhaminan lähennys puoliksi),
/// kylkilankku on keskivartaloa eikä kantoa.
const exerciseMuscles = <String, Map<String, double>>{
  'Kööpenhaminan lähennys': {'lähentäjät': 1, 'vatsa': .5},
  'Lonkan lähennys': {'lähentäjät': 1},
  'Kylkilankku': {'vatsa': 1},
};

/// Liikekohtaiset lisät paikan lihasten päälle: kyynärvarret suorista ote- ja kantoliikkeistä ja puolet
/// vasarakäännöstä (olkavarsi-värttinäluulihas). Maastaveto, soutu ja leuanveto kuormittavat otetta myös, mutta
/// niitä ei lasketa (rivi olisi kaikilla iso eikä kertoisi mitään).
const exerciseExtraMuscles = <String, Map<String, double>>{
  'Ranteen koukistus': {'kyynärvarret': 1},
  'Ranteen ojennus': {'kyynärvarret': 1},
  'Vasarakääntö': {'kyynärvarret': .5},
  'Farmer walk': {'kyynärvarret': 1},
  'Farmer walk hex barilla': {'kyynärvarret': 1},
  'Matkalaukkukanto': {'kyynärvarret': 1},
  'Roikunta': {'kyynärvarret': 1},
  'Olankohautus': {'yläselkä': 1},
  'Lapaluuveto roikkuen': {'yläselkä': 1},
};

/// Lihasvalinta omalle liikkeelle (käyttäjä 16.11.: "jalat? mitkä osat, kädet? mitkä osat"): alue → osat.
/// 'vatsa' näytetään nimellä keskivartalo.
const muscleAreas = <String, List<String>>{
  'Jalat': ['etureisi', 'takareisi', 'pakara', 'pohje', 'lähentäjät'],
  'Kädet': ['hauis', 'ojentaja', 'kyynärvarret'],
  'Rinta': ['rinta'],
  'Selkä': ['leveä selkälihas', 'yläselkä', 'alaselkä'],
  'Olkapäät': ['etuolkapää', 'sivuolkapää', 'takaolkapää'],
  'Keskivartalo': ['vatsa'],
};

/// Osan pääpalkki (oman liikkeen osa laskee myös pääpalkkiin; takaolkapää kuten valmiissa liikkeissä).
const _partParent = {
  'etuolkapää': 'olkapää',
  'sivuolkapää': 'olkapää',
  'takaolkapää': 'takaolka',
  'leveä selkälihas': 'selkä',
  'yläselkä': 'selkä',
};

/// Oman liikkeen valituista lihaksista kuorma: jokainen valittu 1 sarja sarjaa kohden, osat myös pääpalkkiin.
Map<String, double> _customLoad(List<String> parts) => {
  for (final x in parts) ...{x: 1.0, ?_partParent[x]: 1.0},
};

/// Onko lihas pääpalkki (ei osa eikä tietorivi).
bool isMainMuscle(String m) => !infoMuscles.contains(m) && !subMuscles.values.any((l) => l.contains(m));

/// Liikkeen kuormittamat lihakset, osat ja tietorivit: paikan mukaan, liikekohtaisin poikkeuksin.
Map<String, double> loadOf(String exercise, String slot) {
  final custom = customExerciseMuscles[exercise];
  if (custom != null && custom.isNotEmpty) return _customLoad(custom);
  final out = <String, double>{...?(exerciseMuscles[exercise] ?? slotMuscles[slot]), ...?slotSubMuscles[slot]};
  if (exerciseMuscles.containsKey(exercise)) {
    out.removeWhere((k, _) => !exerciseMuscles[exercise]!.containsKey(k) && isMainMuscle(k));
  }
  for (final e in (exerciseExtraMuscles[exercise] ?? const <String, double>{}).entries) {
    out[e.key] = (out[e.key] ?? 0) + e.value;
  }
  return out;
}

class ProgramStats {
  final Map<String, double> weekly = {};

  /// Olkapään ja selän osat ([subMuscles]).
  final Map<String, double> sub = {};
  final Map<String, int> frequency = {};
  double push = 0, pull = 0, hPull = 0;
}

ProgramStats statsOf(Program p) {
  final st = ProgramStats();
  for (final d in p.plan) {
    final hit = <String>{};
    for (final i in d.items) {
      // Vaihtoehdot (käyttäjä 16.11.: "tämä tai tuo" myös viikon kuormaan): sarjat jaetaan tasan vaihtoehtojen
      // kesken, eli oletetaan vuorottelu. Saman liikemallin vaihtoehto käyttää liikkeen paikkaa (sama kuorma).
      final choices = [
        (i.exercise, i.slot),
        for (final a in i.alts) (a, family(slotOf(a)) == family(i.slot) || slotOf(a).isEmpty ? i.slot : slotOf(a)),
      ];
      final n = setsOf(p, i) / choices.length;
      final share = <String, double>{};
      for (final (ex, s) in choices) {
        if (pushSlots.contains(s)) st.push += n;
        if (pullSlots.contains(s)) st.pull += n;
        if (horizontalPull.contains(s)) st.hPull += n;
        for (final e in loadOf(ex, s).entries) {
          if (!isMainMuscle(e.key)) {
            st.sub[e.key] = (st.sub[e.key] ?? 0) + n * e.value;
            continue;
          }
          st.weekly[e.key] = (st.weekly[e.key] ?? 0) + n * e.value;
          if (e.value >= 1) share[e.key] = (share[e.key] ?? 0) + 1 / choices.length;
        }
      }
      // Päivän lihakset (tiheys): vähintään puolet vaihtoehdoista kuormittaa raskaasti.
      for (final m in share.entries) {
        if (m.value >= .5 - 1e-9) hit.add(m.key);
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
      if (!lower) issues.add(l10n.t('{0}: ei alavartalon pääliikettä', [d.uiName]));
      if (!push || !pull) {
        issues.add(l10n.t('{0}: koko kehon treenissä pitää olla sekä työntö että veto', [d.uiName]));
      }
    } else if (n.startsWith('ylävartalo') || n.startsWith('penkki')) {
      if (!push || !pull) {
        issues.add(l10n.t('{0}: ylävartalopäivässä pitää olla sekä työntö että veto', [d.uiName]));
      }
    }
    // Järjestys: moninivelliikkeet ensin
    var seenIso = false;
    for (final i in d.items) {
      if (!i.compound && i.kind == null) seenIso = true;
      if (i.compound && seenIso) {
        issues.add(l10n.t('{0}: moninivelliike {1} eristävän jälkeen', [d.uiName, exerciseLabel(i.exercise)]));
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
            d.uiName,
            l10n.t(e.key),
            fmtNum(e.value),
            fmtNum(cap.toDouble()),
          ]),
        );
      }
    }
  }

  // Kahvakuulaohjelmat ovat valmiita pohjia (yötesti 19.11.): kahvakuulalla ei voi tehdä esim. pystyvetoa, joten
  // yleiset malli- ja määrärajat eivät koske niitä (ohjelma ei huomauta itsestään).
  if (p.kbFocus != null) return issues;

  // 2. Viikon työntö/veto-tasapaino
  if (st.push > 0 && (st.pull < st.push * .9 || st.pull > st.push * 2)) {
    issues.add(
      l10n.t('työntö {0} / veto {1} sarjaa viikossa: vetoa pitää olla 0,9–2 × työntö', [
        fmtNum(st.push),
        fmtNum(st.pull),
      ]),
    );
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
      if (v < 4) issues.add(l10n.t('{0}: {1} sarjaa viikossa (vähintään 4)', [l10n.t(m), fmtNum(v)]));
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
