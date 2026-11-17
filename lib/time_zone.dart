import 'dart:async';

import 'package:flutter/foundation.dart';

/// Aikavyöhykkeen vaihto kesken käytön (matka, käsin vaihdettu vyöhyke).
///
/// Päivämäärät ovat paikallisen keskiyön DateTime-arvoja, ja `==` vertaa hetkiä: vyöhykkeen vaihduttua
/// `dateOnly(DateTime.now())` on eri hetki kuin ennen luettu saman päivän `w.date`, jolloin "tänään" ei enää täsmää
/// (päivätesti 14.11.: ajastin katosi, kesto jäi tallentumatta, Jatka-lista näytti treenit väärin). Muutoksen
/// jälkeen tallennetut treenit luetaan uudelleen tiedostonimistä ja avoinna olevat näkymät rakentavat päivänsä
/// uudelleen samoista kalenteripäivistä (ks. [rebaseDay]). Kesä- ja talviaika eivät muuta keskiöiden hetkiä.
class TimeZoneWatch extends ChangeNotifier {
  TimeZoneWatch({String Function()? key}) : _keyOf = key ?? _current {
    _key = _keyOf();
  }

  final String Function() _keyOf;
  late String _key;
  Timer? _timer;

  static String _current() {
    final n = DateTime.now();
    return '${n.timeZoneName}|${n.timeZoneOffset.inMinutes}';
  }

  /// Tarkistaa 15 s välein (ja sovellukseen palatessa [check]).
  void start() => _timer ??= Timer.periodic(const Duration(seconds: 15), (_) {
    check();
    dayWatch.check();
  });

  /// true, jos vyöhyke vaihtui edellisen tarkistuksen jälkeen (kuuntelijat saavat ilmoituksen).
  bool check() {
    final k = _keyOf();
    if (k == _key) return false;
    _key = k;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final tzWatch = TimeZoneWatch();

/// Päivän ja tervehdyksen vuorokaudenajan vaihtuminen sovelluksen ollessa auki (testikierros 17.11.: yöllä avattu
/// ja aamulla esiin otettu sovellus tervehti yhä "Buorre idja"; etusivun "tänään" ja viikko jäivät edelliseen
/// päivään, kunnes jokin muu päivitti näkymän). Tarkistetaan samalla ajastimella kuin vyöhyke ja sovellukseen
/// palatessa; kuuntelija (main) pyytää näkymiä rakentumaan uudelleen.
class DayWatch extends ChangeNotifier {
  DayWatch({DateTime Function()? now}) : _now = now ?? DateTime.now {
    _key = _keyOf();
  }

  final DateTime Function() _now;
  late String _key;

  /// Tervehdyksen jakso (ks. seGreeting): yö, aamu, päivä, ilta.
  static int slot(int hour) => hour < 5 || hour >= 23 ? 0 : (hour < 10 ? 1 : (hour < 17 ? 2 : 3));

  String _keyOf() {
    final n = _now();
    return '${n.year}-${n.month}-${n.day}|${slot(n.hour)}';
  }

  /// true, jos päivä tai vuorokaudenaika vaihtui edellisen tarkistuksen jälkeen.
  bool check() {
    final k = _keyOf();
    if (k == _key) return false;
    _key = k;
    notifyListeners();
    return true;
  }
}

final dayWatch = DayWatch();

/// Sama kalenteripäivä nykyisen vyöhykkeen keskiyönä. DateTime muistaa kerran lasketut päivä- ja kuukausikenttänsä,
/// joten jo näytetyn päivän kentät pysyvät alkuperäisinä.
DateTime rebaseDay(DateTime d) => DateTime(d.year, d.month, d.day);
