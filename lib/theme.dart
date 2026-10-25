import 'package:flutter/material.dart';

const ink = Color(0xff070c09);
const green = Color(0xffbdff59);
const white = Color(0xfff4f8f1);
const muted = Color(0xff99ab9c);
const surface = Color(0xff121c15);
const raised = Color(0xff202d23);
const artwork = Color(0xff17251b);

ThemeData dremioTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: ink,
    colorScheme: base.colorScheme.copyWith(primary: green, onPrimary: ink, surface: const Color(0xff0e1611), onSurface: white),
    dialogTheme: const DialogThemeData(backgroundColor: Color(0xff0e1611)),
    textTheme: base.textTheme.apply(bodyColor: white, displayColor: white, fontFamily: 'Roboto'),
    focusColor: Colors.transparent,
    hoverColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    sliderTheme: const SliderThemeData(activeTrackColor: green, thumbColor: green, inactiveTrackColor: Color(0x40f4f8f1), overlayColor: Color(0x22bdff59), trackHeight: 3),
  );
}

TextStyle text(double size, {Color color = white, FontWeight weight = FontWeight.w400, double? height, double spacing = 0}) =>
    TextStyle(fontSize: size, color: color, fontWeight: weight, height: height, letterSpacing: spacing);
