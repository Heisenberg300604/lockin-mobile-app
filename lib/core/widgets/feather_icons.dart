/// The icons used by the app, from the Feather icon font.
///
/// The original React Native app drew its icons with `@expo/vector-icons`
/// (Feather). We bundle the very same `Feather.ttf` (see `pubspec.yaml`) and
/// list only the glyphs we use, so every icon is pixel-identical to the
/// reference. Code points come from Feather's glyph map.
library;

import 'package:flutter/widgets.dart';

/// Named Feather glyphs.
abstract final class Feather {
  static const _family = 'Feather';

  static const lock = IconData(0xf193, fontFamily: _family);
  static const user = IconData(0xf205, fontFamily: _family);
  static const arrowLeft = IconData(0xf110, fontFamily: _family);
  static const arrowRight = IconData(0xf112, fontFamily: _family);
  static const plus = IconData(0xf1c0, fontFamily: _family);
  static const minus = IconData(0xf1a3, fontFamily: _family);
  static const plusCircle = IconData(0xf1c1, fontFamily: _family);
  static const minusCircle = IconData(0xf1a4, fontFamily: _family);
  static const calendar = IconData(0xf127, fontFamily: _family);
  static const sliders = IconData(0xf1e0, fontFamily: _family);
  static const checkSquare = IconData(0xf12d, fontFamily: _family);
  static const check = IconData(0xf12b, fontFamily: _family);
  static const x = IconData(0xf216, fontFamily: _family);
  static const pause = IconData(0xf1b2, fontFamily: _family);
  static const play = IconData(0xf1be, fontFamily: _family);
  static const pauseCircle = IconData(0xf1b3, fontFamily: _family);
  static const xCircle = IconData(0xf217, fontFamily: _family);
  static const checkCircle = IconData(0xf12c, fontFamily: _family);
  static const circle = IconData(0xf137, fontFamily: _family);
  static const gift = IconData(0xf175, fontFamily: _family);
  static const award = IconData(0xf119, fontFamily: _family);
  static const rotateCcw = IconData(0xf1cb, fontFamily: _family);
  static const maximize = IconData(0xf199, fontFamily: _family);
  static const settings = IconData(0xf1d3, fontFamily: _family);
  static const chevronLeft = IconData(0xf12f, fontFamily: _family);
  static const chevronRight = IconData(0xf130, fontFamily: _family);
}
