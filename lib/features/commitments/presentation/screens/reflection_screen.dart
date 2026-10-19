/// "Why did it unlock?": an optional private note, then restart.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers.dart';
import '../../../../core/widgets/app_field.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/containers.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/tappable.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/models.dart';
import '../widgets/status_chip.dart';

/// Reflection + restart for a broken attempt (`/commitment/:id/reflect`).
class ReflectionScreen extends ConsumerStatefulWidget {
  /// Creates the screen for commitment [id].
  const ReflectionScreen({super.key, required this.id});

  /// Commitment id from the route.
  final String id;

  @override
  ConsumerState<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends ConsumerState<ReflectionScreen> {
  static const _reasons = ['Low Energy', 'Time Crunch', 'Lack of focus', 'Social Plans'];

  String _reason = '';
  String _note = '';
  String _error = '';
  bool _busy = false;
  late final String _requestId = ref.read(uuidProvider)();

  Future<void> _start(Commitment c, {bool skip = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final next = await ref
          .read(commitmentsProvider.notifier)
          .restart(c, _requestId, skip ? '' : _reason, skip ? '' : _note);
      if (mounted) context.pushReplacement('/commitment/${next.id}');
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e is LockInException ? e.message : 'Your restart was not saved. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(commitmentsProvider);
    final c = data.snapshot.commitments.where((x) => x.id == widget.id).firstOrNull;

    if (data.loading || c == null || c.status != CommitmentStatus.broken) {
      return AppScreen(
        header: const AppHeader(back: true),
        children: [
          Label(
            data.loading
                ? 'Loading your commitment…'
                : 'This reflection is available for a broken attempt.',
          ),
        ],
      );
    }

    final restarted = c.restartedBy != null;
    return AppScreen(
      setup: true,
      header: const AppHeader(back: true),
      gap: 24,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      footer: LockButton(
        title: restarted ? 'VIEW NEW ATTEMPT' : 'Secure Log & Restart',
        loading: _busy,
        onPressed: () => restarted
            ? context.pushReplacement('/commitment/${c.restartedBy}')
            : unawaited(_start(c)),
      ),
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenTitle('Why did it Unlock?'),
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Label(
                'No judgment here. This is your private space to document the friction so you can adapt tomorrow.',
                muted: true,
                size: 13,
              ),
            ),
          ],
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Expanded(child: ScreenTitle(c.name)),
                  const StatusChip(CommitmentStatus.broken),
                ],
              ),
              if (c.description.isNotEmpty) Label(c.description, size: 13, muted: true),
              if (restarted)
                const Label('Your reflection and previous attempt are preserved in History.')
              else ...[
                const SizedBox(height: 24),
                // Two rows of two buttons (no LayoutBuilder: see AppScreen).
                for (var row = 0; row < _reasons.length; row += 2)
                  Padding(
                    padding: EdgeInsets.only(top: row == 0 ? 0 : 12),
                    child: Row(
                      spacing: 12,
                      children: [
                        for (final r in _reasons.skip(row).take(2))
                          Expanded(
                            child: LockButton(
                              light: true,
                              title: r,
                              selected: _reason == r,
                              disabled: _busy,
                              onPressed: () => setState(() {
                                _reason = _reason == r ? '' : r;
                                _note = '';
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Label('OR', size: 12, muted: true, align: TextAlign.center),
                ),
                AppField(
                  semanticLabel: 'Your reflection (optional)',
                  placeholder: 'What got in the way?',
                  multiline: true,
                  minHeight: 72,
                  maxLength: 500,
                  value: _note,
                  enabled: !_busy,
                  onChanged: (v) => setState(() {
                    _note = v;
                    _reason = '';
                  }),
                ),
                const SizedBox(height: 8),
                Label('${_note.length}/500', size: 11, muted: true),
              ],
            ],
          ),
        ),
        const Label(
          'Your reflection stays with this attempt in your private history on this device.',
          muted: true,
          size: 13,
          align: TextAlign.center,
        ),
        if (!restarted)
          Tappable(
            semanticLabel: 'SKIP REFLECTION & RESTART',
            enabled: !_busy,
            onTap: () => unawaited(_start(c, skip: true)),
            child: const SizedBox(
              height: 48,
              child: Center(child: Label('Skip reflection & restart', size: 12)),
            ),
          ),
        if (_error.isNotEmpty) ErrorNote(_error),
      ],
    );
  }
}
