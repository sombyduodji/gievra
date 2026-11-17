import 'health.dart';
import 'heart_rate.dart' show hrProfile, repairWalkKcal;
import 'hr_calc.dart' show HrSeries;
import 'l10n.dart';
import 'models.dart';
import 'session_compare.dart' show fmtDuration;
import 'share_text.dart' show thousands;
import 'sports.dart';

/// Health Connect -päivitys tallennettuun treeniin tieto kerrallaan (ulkoasun kohennus 16.11., `hc-paivitys`):
/// jokainen tieto omana rivinään, uusi arvo ja nykyinen. Valmiiksi valittu vain se, mikä puuttuu tai on selvästi
/// parempi (sama lähde päivittynyt, enemmän askeleita); kesto ja käsin tai sykevyöllä kirjatut eivät ole valmiiksi
/// valittuja. Vain valitut päivitetään.
enum HcField { hr, kcal, steps, distance, duration }

class HcChange {
  final HcField field;
  final String label; // käännetty nimi: Syke, Kalorit …
  final String now; // nykyinen arvo tekstinä
  final String value; // uusi arvo tekstinä
  final String? note; // miksi (ei) valmiiksi valittu
  final bool preselect;
  const HcChange(this.field, this.label, this.now, this.value, {this.note, required this.preselect});
}

String _hrText(int? avg, int? max) => [
  if (avg != null) t('ka. {0}', [avg]),
  if (max != null) t('maks. {0}', [max]),
].join(' · ');

String _src(String? s) => switch (s) {
  'sykevyö' => t('sykevyö'),
  'käsin' => t('käsin'),
  'kello' => t('kello'),
  'syke' => t('sykkeestä'),
  _ => '',
};

/// Askelmäärä, jonka Health Connect antaa tälle treenille (suurempi vaihtoehto, kuten treenin jälkeisessä haussa).
int? hcSteps(HealthCandidate c) {
  final opts = stepOptions(c);
  if (opts.isEmpty) return (c.steps ?? 0) > 0 ? c.steps : null;
  return opts.map((o) => o.$2).reduce((a, b) => a > b ? a : b);
}

/// Erot treenin ja Health Connectin ehdokkaan välillä. Tyhjä = ei mitään uutta.
List<HcChange> hcChanges(Workout w, HealthCandidate c) {
  final out = <HcChange>[];
  final protectedHr = w.hrSource == 'sykevyö' || w.hrSource == 'käsin';
  if ((c.hrAvg != null || c.hrMax != null) && (c.hrAvg != w.hrAvg || c.hrMax != w.hrMax)) {
    final none = w.hrAvg == null && w.hrMax == null;
    out.add(
      HcChange(
        HcField.hr,
        t('Syke'),
        none ? t('ei sykettä') : '${_hrText(w.hrAvg, w.hrMax)} (${_src(w.hrSource)})',
        _hrText(c.hrAvg, c.hrMax),
        note: protectedHr ? t('nykyinen on kirjattu käsin tai sykevyöllä') : null,
        preselect: none || w.hrSource == 'kello',
      ),
    );
  }
  final protectedKcal = w.kcalSource == 'syke' || w.kcalSource == 'käsin';
  if (c.kcal != null && c.kcal != w.kcal) {
    out.add(
      HcChange(
        HcField.kcal,
        t('Kalorit'),
        w.kcal == null ? t('ei') : '${w.kcal} kcal (${_src(w.kcalSource)})',
        '${c.kcal} kcal',
        note: protectedKcal ? t('nykyinen on laskettu sykkeestä tai kirjattu käsin') : null,
        preselect: w.kcal == null || w.kcalSource == 'kello',
      ),
    );
  }
  final steps = hcSteps(c);
  if ((sportOf(w.activity)?.steps ?? false) && steps != null && steps != w.steps) {
    final more = w.steps != null && steps > w.steps!;
    out.add(
      HcChange(
        HcField.steps,
        t('Askeleet'),
        w.steps == null ? t('ei') : thousands(w.steps!),
        thousands(steps),
        note: more ? t('kello synkronoi myöhemmin: enemmän askeleita') : null,
        preselect: w.steps == null || more,
      ),
    );
  }
  final km = (c.meters ?? 0) > 0 ? (c.meters! / 10).round() / 100 : null;
  if (km != null && w.activity != null && (sportOf(w.activity)?.distance ?? false) && w.distanceKm == null) {
    out.add(HcChange(HcField.distance, t('Matka'), t('ei'), '${fmtNum(km)} km', preselect: true));
  }
  final own = w.seconds ?? (w.minutes == null ? null : w.minutes! * 60);
  final hcSec = c.session ? c.duration.inSeconds : null;
  if (hcSec != null && hcSec > 0 && (own == null || (hcSec - own).abs() >= 60)) {
    out.add(
      HcChange(
        HcField.duration,
        t('Kesto'),
        own == null ? t('ei') : fmtDuration((own / 60).round()),
        fmtDuration((hcSec / 60).round()),
        note: own == null ? null : t('oletuksena pois: oma ajanotto on tarkempi'),
        preselect: own == null,
      ),
    );
  }
  return out;
}

/// Päivittää valitut tiedot ehdokkaasta. Käsin tai sykevyöllä kirjattu korvataan vain, kun se on valittu.
void applyHcChanges(Workout w, HealthCandidate c, Set<HcField> pick) {
  if (pick.isEmpty) return;
  if (pick.contains(HcField.hr)) {
    final series = hrSeriesFromHealth(c.hrSamples);
    w.hrSeries = series;
    w.hrAvg = c.hrAvg ?? w.hrAvg;
    w.hrMax = c.hrMax ?? w.hrMax;
    w.hrSource = 'kello';
  }
  if (pick.contains(HcField.kcal) && c.kcal != null) {
    w.kcal = c.kcal;
    w.kcalSource = 'kello';
  }
  if (pick.contains(HcField.steps)) w.steps = hcSteps(c) ?? w.steps;
  if (pick.contains(HcField.distance) && (c.meters ?? 0) > 0) w.distanceKm = (c.meters! / 10).round() / 100;
  if (pick.contains(HcField.duration) && c.session) {
    w.seconds = c.duration.inSeconds;
    w.minutes = (w.seconds! / 60).round();
    w.watchTime = true;
    w.manualTime = false;
  }
  // Matka tuli kellosta (esim. kävelymatto): kävelyn sykkeestä lasketut kalorit vauhdista (käyttäjä 17.11.).
  if (!pick.contains(HcField.kcal)) repairWalkKcal(w, hrProfile());
  w.healthSource = c.app;
}

/// Kumoa: treenin kellotiedot ennen päivitystä.
class HcSnapshot {
  final int? hrAvg, hrMax, kcal, steps, seconds, minutes;
  final HrSeries? hrSeries;
  final String? hrSource, kcalSource, healthSource;
  final double? distanceKm;
  final bool watchTime, manualTime;
  HcSnapshot(Workout w)
    : hrAvg = w.hrAvg,
      hrMax = w.hrMax,
      kcal = w.kcal,
      steps = w.steps,
      seconds = w.seconds,
      minutes = w.minutes,
      hrSeries = w.hrSeries,
      hrSource = w.hrSource,
      kcalSource = w.kcalSource,
      healthSource = w.healthSource,
      distanceKm = w.distanceKm,
      watchTime = w.watchTime,
      manualTime = w.manualTime;

  void restore(Workout w) {
    w
      ..hrAvg = hrAvg
      ..hrMax = hrMax
      ..kcal = kcal
      ..steps = steps
      ..seconds = seconds
      ..minutes = minutes
      ..hrSeries = hrSeries
      ..hrSource = hrSource
      ..kcalSource = kcalSource
      ..healthSource = healthSource
      ..distanceKm = distanceKm
      ..watchTime = watchTime
      ..manualTime = manualTime;
  }
}
