import 'package:intl/intl.dart';

/// Count (int) ko device locale ke hisab se localize karta hai.
/// `'$value'` interpolation Western Arabic digits (123) force kar deta hai;
/// Arabic locale ٣٢١ chahta hai, Urdu-locale rendering bhi farq hai. Skillora
/// har mulk ke users ke liye hai — digits locale-dependent data hain, neutral
/// nahi. NumberFormat device locale se grouping + digit-shapes handle karta hai.
///
/// [locale] null ho to current/default locale use hoti hai.
String formatCount(int value, {String? locale}) =>
    NumberFormat.decimalPattern(locale).format(value);
