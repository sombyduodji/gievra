import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/csv_export.dart';

// Yötesti 18.11.: CSV-kaavainjektio. Keksityt arvot.
void main() {
  test('kaavan alkumerkit saavat heittomerkin, luvut eivät', () {
    expect(csvCell('=HYPERLINK("http://x")'), startsWith("\"'=HYPERLINK"));
    expect(csvCell('@SUM(A1)'), "'@SUM(A1)");
    expect(csvCell('+cmd'), "'+cmd");
    expect(csvCell('-kevyt'), "'-kevyt");
    expect(csvCell('\tx'), "'\tx");
    expect(csvCell('-0,12'), '-0,12');
    expect(csvCell('+0,31'), '+0,31');
    expect(csvCell(-5), '-5');
    expect(csvCell(-2.5), '-2.5');
    expect(csvCell('Oura'), 'Oura');
    expect(csvCell(null), '');
  });
}
