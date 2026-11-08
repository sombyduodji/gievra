// Urheilulajit ja liikunta (näkyvät, kun ☰ → Asetukset → Urheilu ja liikunta on päällä).
// Kestävyyslajeissa kirjataan myös matka, jolloin vauhti lasketaan.

class Sport {
  final String name, icon, group;
  final bool distance;
  final bool steps; // askeleet kirjataan (kävely- ja juoksulajit)
  const Sport(this.name, this.icon, this.group, {this.distance = false, this.steps = false});
}

// l10n: data
const sportGroups = ['Kestävyys', 'Pallo- ja mailapelit', 'Muut lajit'];

// Lajien nimet pysyvät suomeksi myös saamenkielisessä käyttöliittymässä (natiivitarkistus myöhemmin).
// l10n: data
const sports = <Sport>[
  Sport('Juoksu', '🏃', 'Kestävyys', distance: true, steps: true),
  Sport('Hölkkä', '🏃', 'Kestävyys', distance: true, steps: true),
  Sport('Kävely', '🚶', 'Kestävyys', distance: true, steps: true),
  Sport('Sauvakävely', '🥢', 'Kestävyys', distance: true, steps: true),
  Sport('Pyöräily', '🚴', 'Kestävyys', distance: true),
  Sport('Uinti', '🏊', 'Kestävyys', distance: true),
  Sport('Hiihto', '⛷️', 'Kestävyys', distance: true),
  Sport('Soutu', '🚣', 'Kestävyys', distance: true),
  Sport('Melonta', '🛶', 'Kestävyys', distance: true),
  Sport('Luistelu', '⛸️', 'Kestävyys', distance: true),
  Sport('Retkeily', '🥾', 'Kestävyys', distance: true, steps: true),
  Sport('Lumikenkäily', '🌨️', 'Kestävyys', distance: true),
  Sport('Salibandy', '🏑', 'Pallo- ja mailapelit'),
  Sport('Jalkapallo', '⚽', 'Pallo- ja mailapelit'),
  Sport('Futsal', '⚽', 'Pallo- ja mailapelit'),
  Sport('Koripallo', '🏀', 'Pallo- ja mailapelit'),
  Sport('Lentopallo', '🏐', 'Pallo- ja mailapelit'),
  Sport('Jääkiekko', '🏒', 'Pallo- ja mailapelit'),
  Sport('Jääpallo', '🏑', 'Pallo- ja mailapelit'),
  Sport('Pesäpallo', '⚾', 'Pallo- ja mailapelit'),
  Sport('Squash', '🎾', 'Pallo- ja mailapelit'),
  Sport('Sulkapallo', '🏸', 'Pallo- ja mailapelit'),
  Sport('Tennis', '🎾', 'Pallo- ja mailapelit'),
  Sport('Padel', '🎾', 'Pallo- ja mailapelit'),
  Sport('Pöytätennis', '🏓', 'Pallo- ja mailapelit'),
  Sport('Golf', '⛳', 'Pallo- ja mailapelit'),
  Sport('Ryhmäliikunta', '🤸', 'Muut lajit'),
  Sport('Jooga', '🧘', 'Muut lajit'),
  Sport('Pilates', '🧘', 'Muut lajit'),
  Sport('Tanssi', '💃', 'Muut lajit'),
  Sport('Kiipeily', '🧗', 'Muut lajit'),
  Sport('Kamppailulajit', '🥋', 'Muut lajit'),
  Sport('Nyrkkeily', '🥊', 'Muut lajit'),
  Sport('CrossFit', '🏋️', 'Muut lajit'),
  Sport('Laskettelu', '🎿', 'Muut lajit'),
  Sport('Liikkuvuus ja venyttely', '🙆', 'Muut lajit'),
  Sport('Muu liikunta', '✨', 'Muut lajit'),
];

Sport? sportOf(String? name) => sports.where((s) => s.name == name).firstOrNull;

// l10n: data
const intensities = [('kevyt', 'Kevyt', '😌'), ('reipas', 'Reipas', '😤'), ('kova', 'Kova', '🥵')];

/// Juoksulajit: näissä on lenkin tyyppi ja oma kehitysnäkymä (☰ → Edistyminen ja tilastot → Juoksu).
const runningSports = {'Juoksu', 'Hölkkä'};
bool isRun(String? activity) => runningSports.contains(activity);

/// Lenkin tyyppi: avain tiedostoon, nimi, emoji, oletusrasitus ja lyhyt kuvaus.
/// Tyypit tavallisen juoksuharjoittelun mukaan (kevyt peruskestävyys, palauttava, pitkä, vauhtikestävyys,
/// intervallit, kisavauhti ja kilpailu tai testi).
// l10n: data
const runTypes = <(String, String, String, String, String)>[
  ('kevyt', 'Kevyt lenkki', '😌', 'kevyt', 'Rauhallinen peruskestävyys, puhe kulkee'),
  ('palauttava', 'Palauttava', '🧘', 'kevyt', 'Hyvin kevyt, kovan päivän jälkeen'),
  ('pitka', 'Pitkä lenkki', '🛣️', 'reipas', 'Viikon pisin, tasainen vauhti'),
  ('vauhti', 'Vauhtikestävyys', '⚡', 'kova', 'Tempo: reipas, mutta hallittu'),
  ('intervallit', 'Intervallit', '🔁', 'kova', 'Kovat vedot ja palautukset'),
  ('kisavauhti', 'Kisavauhti', '🎯', 'kova', 'Harjoitus tavoitekisan vauhdilla'),
  ('kilpailu', 'Kilpailu tai testi', '🏁', 'kova', 'Kisa tai aikatesti'),
];

(String, String, String, String, String)? runTypeOf(String? key) => runTypes.where((r) => r.$1 == key).firstOrNull;

/// Lajit käyttömäärän mukaan (eniten käytetty ensin); tasapelissä alkuperäinen järjestys.
List<Sport> sportsByUse(Iterable<String?> history, {Iterable<Sport> among = sports}) {
  final n = <String, int>{};
  for (final a in history) {
    if (a != null) n[a] = (n[a] ?? 0) + 1;
  }
  final list = among.toList();
  final order = {for (final (i, s) in list.indexed) s.name: i};
  return list..sort((a, b) {
    final c = (n[b.name] ?? 0).compareTo(n[a.name] ?? 0);
    return c != 0 ? c : order[a.name]!.compareTo(order[b.name]!);
  });
}
