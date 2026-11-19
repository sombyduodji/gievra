import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
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

  // Muut Flutterin tekstit, jotka näkyvät tai jotka ruudunlukija lukee (esim. ponnahdusikkunan tausta "Gidde",
  // ennen suomeksi "Ohita"). Gievran oma käännös, Voikolla tarkistettu; puhujan tarkistettavana (14.11).
  // Näppäimistön näppäinten nimet (vain fyysinen näppäimistö) jäävät suomeksi.
  @override
  String get aboutListTileTitleRaw => r'Dieđut: $applicationName';
  @override
  String get alertDialogLabel => 'Dieđáhus';
  @override
  String get bottomSheetLabel => 'Vuollepanela';
  @override
  String get calendarModeButtonLabel => 'Molsso kaleandarii';
  @override
  String get clearButtonTooltip => 'Sihko teavstta';
  @override
  String get collapsedHint => 'Viiddiduvvon';
  @override
  String get collapsedIconTapHint => 'Viiddit';
  @override
  String get continueButtonLabel => 'Joatkke';
  @override
  String get currentDateLabel => 'Odne';
  @override
  String get dateHelpText => 'bb/mm/jjjj';
  @override
  String get dateInputLabel => 'Čále beaivemeari';
  @override
  String get dateOutOfRangeLabel => 'Beaivemearri ii heive';
  @override
  String get dateRangeEndDateSemanticLabelRaw => r'Loahppabeaivi $fullDate';
  @override
  String get dateRangeEndLabel => 'Loahppabeaivi';
  @override
  String get dateRangeStartDateSemanticLabelRaw => r'Álgobeaivi $fullDate';
  @override
  String get dateRangeStartLabel => 'Álgobeaivi';
  @override
  String get dialModeButtonLabel => 'Vállje diibmogovas';
  @override
  String get dialogLabel => 'Ságastallanláse';
  @override
  String get drawerLabel => 'Fálaldat';
  @override
  String get expandedHint => 'Unniduvvon';
  @override
  String get expandedIconTapHint => 'Unnit';
  @override
  String get expansionTileCollapsedHint => 'deaddil guktii viiddidit';
  @override
  String get expansionTileCollapsedTapHint => 'Viiddit eanet dieđuid oaidnin dihte';
  @override
  String get expansionTileExpandedHint => 'deaddil guktii unnidit';
  @override
  String get expansionTileExpandedTapHint => 'Unnit';
  @override
  String get firstPageTooltip => 'Vuosttaš siidu';
  @override
  String get inputDateModeButtonLabel => 'Molsso teakstačállimii';
  @override
  String get inputTimeModeButtonLabel => 'Čále áiggi teakstan';
  @override
  String get invalidDateFormatLabel => 'Boastut hápmi';
  @override
  String get invalidDateRangeLabel => 'Boastut áigodat';
  @override
  String get invalidTimeLabel => 'Čále gustovaš áiggi';
  @override
  String get lastPageTooltip => 'Maŋimuš siidu';
  @override
  String? get licensesPackageDetailTextOne => '1 liseansa';
  @override
  String get licensesPackageDetailTextOther => r'$licenseCount liseanssa';
  @override
  String? get licensesPackageDetailTextZero => 'Ii liseansa';
  @override
  String get licensesPageTitle => 'Liseanssat';
  @override
  String get lookUpButtonLabel => 'Oza';
  @override
  String get menuBarMenuLabel => 'Fálaldatsárgá';
  @override
  String get menuDismissLabel => 'Gidde fálaldaga';
  @override
  String get modalBarrierDismissLabel => 'Gidde';
  @override
  String get nextPageTooltip => 'Boahtte siidu';
  @override
  String get popupMenuLabel => 'Fálaldat';
  @override
  String get previousPageTooltip => 'Ovddit siidu';
  @override
  String get refreshIndicatorSemanticLabel => 'Ođasmahttin';
  @override
  String? get remainingTextFieldCharacterCountOne => '1 mearka báhcá';
  @override
  String get remainingTextFieldCharacterCountOther => r'$remainingCount mearkka báhcet';
  @override
  String get reorderItemDown => 'Sirdde vulos';
  @override
  String get reorderItemLeft => 'Sirdde gurutbeallái';
  @override
  String get reorderItemRight => 'Sirdde olgešbeallái';
  @override
  String get reorderItemToEnd => 'Sirdde loahpas';
  @override
  String get reorderItemToStart => 'Sirdde álgui';
  @override
  String get reorderItemUp => 'Sirdde bajás';
  @override
  String get saveButtonLabel => 'Vurke';
  @override
  String get scanTextButtonLabel => 'Skánne teavstta';
  @override
  String get scrimLabel => 'Suodji';
  @override
  String get scrimOnTapHintRaw => r'Gidde: $modalRouteContentName';
  @override
  String get searchWebButtonLabel => 'Oza neahtas';
  @override
  String get selectedDateLabel => 'Válljejuvvon';
  @override
  String? get selectedRowCountTitleOne => '1 válljejuvvon';
  @override
  String get selectedRowCountTitleOther => r'$selectedRowCount válljejuvvon';
  @override
  String get tabLabelRaw => r'Siidu $tabIndex / $tabCount';
  @override
  String get timePickerHourLabel => 'Diibmu';
  @override
  String get timePickerHourModeAnnouncement => 'Vállje diimmu';
  @override
  String get timePickerMinuteLabel => 'Minuhtta';
  @override
  String get timePickerMinuteModeAnnouncement => 'Vállje minuhtaid';
  @override
  String get unspecifiedDate => 'Beaivemearri';
  @override
  String get unspecifiedDateRange => 'Áigodat';
  @override
  String get viewLicensesButtonLabel => 'Čájet liseanssaid';
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

/// Flutterin yleiset tekstit (WidgetsLocalizations: järjestely, kopioi/liitä, haku) saameksi; ruudunlukija lukee
/// järjestelyn tekstit tästä (Materialin vastaavat ovat vanhentuneita).
class SamiWidgetsLocalizations extends WidgetsLocalizationFi {
  const SamiWidgetsLocalizations();
  @override
  String get copyButtonLabel => 'Máŋge';
  @override
  String get cutButtonLabel => 'Čuohpa';
  @override
  String get lookUpButtonLabel => 'Oza';
  @override
  String get noResultsFound => 'Ii gávdnon mihkkege';
  @override
  String get pasteButtonLabel => 'Bija';
  @override
  String get radioButtonUnselectedLabel => 'Ii válljejuvvon';
  @override
  String get reorderItemDown => 'Sirdde vulos';
  @override
  String get reorderItemLeft => 'Sirdde gurutbeallái';
  @override
  String get reorderItemRight => 'Sirdde olgešbeallái';
  @override
  String get reorderItemToEnd => 'Sirdde loahpas';
  @override
  String get reorderItemToStart => 'Sirdde álgui';
  @override
  String get reorderItemUp => 'Sirdde bajás';
  @override
  String get searchResultsFound => 'Ohcanbohtosat gávdnojedje';
  @override
  String get searchWebButtonLabel => 'Oza neahtas';
  @override
  String get selectAllButtonLabel => 'Vállje buot';
  @override
  String get shareButtonLabel => 'Juogat';
}

class _SamiWidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _SamiWidgetsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'se';
  @override
  Future<WidgetsLocalizations> load(Locale locale) => SynchronousFuture(const SamiWidgetsLocalizations());
  @override
  bool shouldReload(_SamiWidgetsDelegate old) => false;
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

/// Flutterin suomi korjattuna: ruudunlukija luki välilehdet "Välilehti 1 kautta 5" (Nothing-testi 18.11.).
class FinnishMaterialLocalizations extends MaterialLocalizationFi {
  FinnishMaterialLocalizations()
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

  @override
  String get tabLabelRaw => r'Välilehti $tabIndex/$tabCount';
}

class _FinnishMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _FinnishMaterialDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'fi';
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('fi')).then((_) => FinnishMaterialLocalizations());
  @override
  bool shouldReload(_FinnishMaterialDelegate old) => false;
}

/// Sovelluksen lokalisoinnit: saame ensin, sitten korjattu suomi ja Flutterin omat (suomi, englanti).
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  _SamiMaterialDelegate(),
  _FinnishMaterialDelegate(),
  _SamiWidgetsDelegate(),
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
