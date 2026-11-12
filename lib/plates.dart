import 'exercises.dart';

// Levylaskuri: tangon kokonaispainosta levyt kummallekin puolelle omista levyistä.

/// Levyt, joista käyttäjä voi valita omansa (kg, suurimmasta pienimpään).
const plateCatalog = <double>[50, 25, 20, 15, 10, 5, 2.5, 2, 1.25, 1, 0.5, 0.25];

/// Oletuksena kuntosalin tavalliset levyt ja 20 kg:n tanko.
const defaultPlates = <double>[25, 20, 15, 10, 5, 2.5, 1.25];
const defaultBarKg = 20.0;

/// Tankoliike (levylaskuri näytetään): tanko välineenä eikä paino käsipainoa tai kuulaa kohti.
bool isBarbell(String exercise) => exerciseEquipment[exercise]?.contains(Equip.tanko) ?? false;

/// Levyt yhdelle puolelle (suurimmasta pienimpään) ja jäännös kg puolta kohden, jota omilla levyillä ei saa.
/// Levyjä oletetaan olevan pareittain riittävästi. Pienin jäännös, sitten vähiten levyjä (ei ahne: 15+10 → 20
/// onnistuu kahdella kympillä).
(List<double>, double) platesPerSide(double total, double bar, Iterable<double> own) {
  const unit = 0.05; // kg: kaikki levyt ovat tämän monikertoja
  final side = (total - bar) / 2;
  if (side <= 0) return (const [], 0);
  final target = (side / unit).round();
  final coins = [
    for (final p in {...own}.where((p) => p > 0).toList()..sort((a, b) => b.compareTo(a))) (p, (p / unit).round()),
  ];
  // Vähiten levyjä kullekin summalle 0..target; -1 = ei mahdollinen.
  final best = List<int>.filled(target + 1, -1);
  final last = List<int>.filled(target + 1, -1);
  best[0] = 0;
  for (var s = 1; s <= target; s++) {
    for (var c = 0; c < coins.length; c++) {
      final v = coins[c].$2;
      if (v <= s && best[s - v] >= 0 && (best[s] < 0 || best[s - v] + 1 < best[s])) {
        best[s] = best[s - v] + 1;
        last[s] = c;
      }
    }
  }
  var reach = target;
  while (reach > 0 && best[reach] < 0) {
    reach--;
  }
  final out = <double>[];
  for (var s = reach; s > 0; s -= coins[last[s]].$2) {
    out.add(coins[last[s]].$1);
  }
  out.sort((a, b) => b.compareTo(a));
  return (out, (target - reach) * unit);
}

/// Lähin omilla levyillä tehtävä kokonaispaino (alaspäin).
double loadableTotal(double total, double bar, Iterable<double> own) {
  final (_, rest) = platesPerSide(total, bar, own);
  return total - 2 * rest;
}
