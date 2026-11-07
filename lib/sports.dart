// Urheilulajit ja liikunta (näkyvät, kun ☰ → Asetukset → Urheilu ja liikunta on päällä).
// Kestävyyslajeissa kirjataan myös matka, jolloin vauhti lasketaan.

class Sport {
  final String name, icon, group;
  final bool distance;
  const Sport(this.name, this.icon, this.group, {this.distance = false});
}

// l10n: data
const sportGroups = ['Kestävyys', 'Pallo- ja mailapelit', 'Muut lajit'];

// Lajien nimet pysyvät suomeksi myös saamenkielisessä käyttöliittymässä (natiivitarkistus myöhemmin).
const sports = <Sport>[
  Sport('Juoksu', '🏃', 'Kestävyys', distance: true),
  Sport('Hölkkä', '🏃', 'Kestävyys', distance: true),
  Sport('Kävely', '🚶', 'Kestävyys', distance: true),
  Sport('Sauvakävely', '🥢', 'Kestävyys', distance: true),
  Sport('Pyöräily', '🚴', 'Kestävyys', distance: true),
  Sport('Uinti', '🏊', 'Kestävyys', distance: true),
  Sport('Hiihto', '⛷️', 'Kestävyys', distance: true),
  Sport('Soutu', '🚣', 'Kestävyys', distance: true),
  Sport('Melonta', '🛶', 'Kestävyys', distance: true),
  Sport('Luistelu', '⛸️', 'Kestävyys', distance: true),
  Sport('Retkeily', '🥾', 'Kestävyys', distance: true),
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
