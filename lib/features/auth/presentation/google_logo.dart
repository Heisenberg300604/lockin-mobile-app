/// The four-colour Google "G" used on the "Continue with Google" button.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#4285F4" d="M43.6 24.5c0-1.4-.1-2.8-.4-4.1H24v7.8h11a9.4 9.4 0 0 1-4.1 6.2v5h6.7c3.9-3.6 6-8.9 6-14.9Z"/>
  <path fill="#34A853" d="M24 44c5.5 0 10.1-1.8 13.5-4.9l-6.7-5c-1.9 1.2-4.2 2-6.8 2-5.3 0-9.7-3.5-11.3-8.2H5.8v5.2C9.2 39.5 16.1 44 24 44Z"/>
  <path fill="#FBBC05" d="M12.7 27.9a12 12 0 0 1 0-7.8v-5.2H5.8a20 20 0 0 0 0 18.2l6.9-5.2Z"/>
  <path fill="#EA4335" d="M24 11.9c3 0 5.6 1 7.7 3l5.8-5.8A19.3 19.3 0 0 0 24 4C16.1 4 9.2 8.5 5.8 14.9l6.9 5.2A12 12 0 0 1 24 11.9Z"/>
</svg>
''';

/// Google "G" logo at [size] pixels.
class GoogleLogo extends StatelessWidget {
  /// Creates the logo.
  const GoogleLogo({super.key, this.size = 19});

  /// Width and height.
  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_svg, width: size, height: size, excludeFromSemantics: true);
}
