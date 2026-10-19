/// "BUILDING HABITS            View all →"
library;

import 'package:flutter/widgets.dart';

import '../../../../core/widgets/tappable.dart';
import '../../../../core/widgets/typography.dart';

/// A section title with a "View all →" link on the right.
class SectionHeader extends StatelessWidget {
  /// Creates a header.
  const SectionHeader({super.key, required this.title, required this.onViewAll});

  /// Section title.
  final String title;

  /// Called when "View all →" is tapped.
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SectionLabel(title),
          Tappable(
            semanticLabel: 'View all ${title.toLowerCase()}',
            onTap: onViewAll,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Label('View all →', size: 10, muted: true),
            ),
          ),
        ],
      );
}
