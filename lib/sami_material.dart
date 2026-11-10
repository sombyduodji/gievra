import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'ui/widgets.dart' show seMonths, seWeekdays;

/// Flutterin omat tekstit pohjoissaameksi (kalenteri, kellonaika, kopioi/liitä, painikkeiden vihjeet).
/// Flutter ei tunne saamea: pohjana suomi, ja näkyvät tekstit, kuukaudet ja viikonpäivät korvataan saamella.
/// Sovelluksen omat tekstit tulevat .po-tiedostoista; tämä koskee vain Flutterin valmiita osia.
/// Sanat tarkistettu Voikolla (pohjoissaame); Peruuta, Poista, Sulje ja Jaa samoin kuin sovelluksessa muualla.
class SamiMaterialLocalizations extends MaterialLocalizationFi {
  SamiMaterialLocalizations()
    : super(
        localeName: 'fi',
        fullYearFormat: intl.DateFormat.y('fi'),
        compactDateFormat: intl.DateFormat.yMd('fi'),
        shortDateFormat: intl.DateFormat.yMMMd('fi'),
        mediumDateFormat: intl.DateFormat.MMMEd('fi'),
        longDateFormat: intl.DateFormat.yMMMMEEEEd('fi'),
        yearMonthFormat: intl.DateFormat.yMMMM('fi'),
        shortMonthDayFormat: intl.DateFormat.MMMd('fi'),
        decimalFormat: intl.NumberFormat.decimalPattern('fi'),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', 'fi'),
      );

  // Kuukaudet ja viikonpäivät samat kuin sovelluksessa muualla (itäiset muodot: vuossárga, maŋŋebárga).
  static const months = seMonths;
  static const weekdays = seWeekdays;

  String _wd(DateTime d) => weekdays[d.weekday - 1];

  @override
  String formatMonthYear(DateTime date) => '${months[date.month - 1]} ${date.year}';

  @override
  String formatMediumDate(DateTime date) => '${_wd(date)} ${date.day}.${date.month}.';

  @override
  String formatFullDate(DateTime date) => '${_wd(date)} ${date.day}. ${months[date.month - 1]} ${date.year}';

  @override
  String formatShortDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

  @override
  String formatShortMonthDay(DateTime date) => '${date.day}.${date.month}.';

  /// Sunnuntaista alkaen, kuten Flutter odottaa (firstDayOfWeekIndex tulee suomesta: maanantai).
  @override
  List<String> get narrowWeekdays => const ['S', 'V', 'M', 'G', 'D', 'B', 'L'];

  @override
  String get backButtonTooltip => 'Maŋos';
  @override
  String get closeButtonTooltip => 'Gidde';
  @override
  String get closeButtonLabel => 'Gidde';
  @override
  String get moreButtonTooltip => 'Eanet';
  @override
  String get openAppDrawerTooltip => 'Raba fálaldaga';
  @override
  String get showMenuTooltip => 'Čájet fálaldaga';
  @override
  String get deleteButtonTooltip => 'Sihko';
  @override
  String get cancelButtonLabel => 'Gaskkalduhte';
  @override
  String get okButtonLabel => 'OK';
  @override
  String get copyButtonLabel => 'Máŋge';
  @override
  String get cutButtonLabel => 'Čuohpa';
  @override
  String get pasteButtonLabel => 'Bija';
  @override
  String get selectAllButtonLabel => 'Vállje buot';
  @override
  String get shareButtonLabel => 'Juogat';
  @override
  String get searchFieldLabel => 'Oza';
  @override
  String get datePickerHelpText => 'Vállje beaivvi';
  @override
  String get dateRangePickerHelpText => 'Vállje beaivvi';
  @override
  String get timePickerDialHelpText => 'Vállje áiggi';
  @override
  String get timePickerInputHelpText => 'Vállje áiggi';
  @override
  String get nextMonthTooltip => 'Boahtte mánnu';
  @override
  String get previousMonthTooltip => 'Ovddit mánnu';
  @override
  String get selectYearSemanticsLabel => 'Vállje jagi';
}

class _SamiMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _SamiMaterialDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'se';
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      // Suomen päivämäärätiedot ladataan kuten Flutterin omassa suomessa. Synkroninen (ei tyhjää ensimmäistä ruutua).
      GlobalMaterialLocalizations.delegate.load(const Locale('fi')).then((_) => SamiMaterialLocalizations());

  @override
  bool shouldReload(_SamiMaterialDelegate old) => false;
}

/// Saamelle suomen pohja muille Flutterin osille (tekstin suunta, iOS-tyyliset osat).
class _FinnishFallback<T> extends LocalizationsDelegate<T> {
  final LocalizationsDelegate<T> inner;
  const _FinnishFallback(this.inner);
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'se';
  @override
  Future<T> load(Locale locale) => inner.load(const Locale('fi'));
  @override
  bool shouldReload(_FinnishFallback<T> old) => false;
}

/// Sovelluksen lokalisoinnit: saame ensin, sitten Flutterin omat (suomi, englanti).
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  _SamiMaterialDelegate(),
  _FinnishFallback<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
  _FinnishFallback<CupertinoLocalizations>(GlobalCupertinoLocalizations.delegate),
  ...GlobalMaterialLocalizations.delegates,
];

/// Flutterin osien kieli käyttöliittymän kielen mukaan (englanti: brittienglanti, 24 h).
Locale flutterLocale(String uiLang) => switch (uiLang) {
  'en' => const Locale('en', 'GB'),
  'se' => const Locale('se'),
  _ => const Locale('fi'),
};

const appSupportedLocales = [Locale('fi'), Locale('en', 'GB'), Locale('se')];
