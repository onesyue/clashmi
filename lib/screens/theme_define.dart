import 'package:flutter/material.dart';

class ThemeDefine {
  static const kColorBlue = MaterialColor(0xFF4F46E5, {
    50: Color(0xFFEEF2FF),
    100: Color(0xFFE0E7FF),
    200: Color(0xFFC7D2FE),
    300: Color(0xFFA5B4FC),
    400: Color(0xFF818CF8),
    500: Color(0xFF6366F1),
    600: Color(0xFF4F46E5),
    700: Color(0xFF4338CA),
    800: Color(0xFF3730A3),
    900: Color(0xFF312E81),
  });
  static const kColorIndigo = Color(0xFF4F46E5);
  static const kColorBgDark = Color(0xFF0D0D1A);
  static const kColorGrey = Colors.grey;
  static const kColorGreenBright = Color.fromARGB(255, 8, 199, 15);

  static const String kThemeSystem = "system";
  static const String kThemeLight = "light";
  static const String kThemeDark = "dark";

  static const BorderRadiusGeometry kBorderRadius = BorderRadius.all(
    Radius.circular(0),
  );
}
