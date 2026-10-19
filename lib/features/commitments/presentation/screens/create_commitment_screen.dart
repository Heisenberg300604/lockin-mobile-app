/// The six-step "lock in a commitment" wizard.
///
/// 1. Path (Build / Quit)   2. Target + description   3. Duration
/// 4. Pace                  5. Reward                 6. Review and lock
///
/// ## Things worth knowing
///
/// * **Draft recovery.** Every change is written to device storage. If the
///   user left mid-way, the next visit offers "Continue draft / Start new".
/// * **Idempotency.** A `requestId` (random UUID) is created per draft and
///   sent when locking. If the request is retried it cannot create a second
///   commitment. It is regenerated whenever the draft changes.
/// * **Back handling.** Back goes to the previous step; only from step 1 does
///   it leave the wizard.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers.dart';
import '../../../../core/motion/reduced_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/app_field.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/choice_card.dart';
import '../../../../core/widgets/containers.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/modal_card.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/typography.dart';
import '../../../auth/application/session_controller.dart';
import '../../application/commitments_controller.dart';
import '../../data/draft_store.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../domain/validation.dart';
import '../widgets/calendar_view.dart';
import 'pace_editor_modal.dart';

const _titles = [
  'Choose your\nPath',
  'Define your\ncommitment',
  'Lock in the\ntimeline',
  'How often will you\nexecute?',
  'Secure your\nmotivation',
  'Review your\ncommitment',
];
const _actions = [
  'SET COMMITMENT →',
  'SET TIMELINE →',
  'SET EXECUTION PACE →',
  'SET REWARD →',
  'LOCK IN COMMITMENT →',
  'CONFIRM & LOCK',
];
const _rewards = ['A Good Coffee', 'Favorite Meal', 'Watch a movie', 'Take a Nap'];

/// The creation wizard (`/commitment/new`).
class CreateCommitmentScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CreateCommitmentScreen({super.key});

  @override
  ConsumerState<CreateCommitmentScreen> createState() => _CreateCommitmentScreenState();
}

class _CreateCommitmentScreenState extends ConsumerState<CreateCommitmentScreen> {
  late Draft _draft = freshDraft();
  int _step = 1;
  int _direction = 1; // 1 = moving forward, -1 = back (drives the slide)
  bool _ready = false;
  bool _busy = false;
  bool _showingDialog = false;
  bool _finished = false; // locked successfully: stop saving the draft
  bool _submitLock = false;
  String _error = '';

  // Inline "custom duration" editor (step 3).
  bool _editingDates = false;
  late String _start = _draft.startDate;
  late String _end = draftEndDate(_draft);
  bool _pickingEnd = false;
  String _editorError = '';

  late String _requestId = ref.read(uuidProvider)();
  late final DraftStore _drafts;
  Future<void> _writes = Future<void>.value();

  @override
  void initState() {
    super.initState();
    final identity = ref.read(sessionProvider).identity!;
    _drafts = DraftStore(ref.read(keyValueStoreProvider), 'lockin.draft.${identity.key}');
    unawaited(_restore());
  }

  // ---------------------------------------------------------------------------
  // Draft persistence
  // ---------------------------------------------------------------------------

  Future<void> _restore() async {
    SavedDraft? saved;
    try {
      saved = await _drafts.load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Your previous draft could not be restored. You can start a new one.');
      }
    }
    if (!mounted) return;
    setState(() => _ready = saved == null);
    if (saved == null) {
      setState(() => _ready = true);
      return;
    }
    _showingDialog = true;
    final choice = await showAppModal<String>(
      context,
      builder: (_) => ModalCard(
        title: 'Your promise is waiting',
        onClose: () => Navigator.of(context).pop('leave'),
        children: [
          const Label('Continue where you left off, or begin a new commitment.'),
          LockButton(title: 'CONTINUE DRAFT', onPressed: () => Navigator.of(context).pop('continue')),
          LockButton(light: true, title: 'Start new', onPressed: () => Navigator.of(context).pop('new')),
        ],
      ),
    );
    _showingDialog = false;
    if (!mounted) return;
    switch (choice) {
      case 'continue':
        setState(() {
          _requestId = saved!.requestId;
          _draft = withCurrentStart(saved.draft);
          _step = saved.step;
          _ready = true;
        });
      case 'new':
        setState(() {
          _requestId = ref.read(uuidProvider)();
          _draft = freshDraft();
          _step = 1;
          _ready = true;
        });
      default:
        _leave();
    }
    _syncDates();
  }

  void _persist() {
    if (!_ready || _finished) return;
    final snapshot = SavedDraft(draft: _draft, step: _step, requestId: _requestId);
    _writes = _writes.catchError((Object _) {}).then((_) => _drafts.save(snapshot)).catchError((Object _) {
      if (mounted) setState(() => _error = 'Your draft could not be saved on this device.');
    });
  }

  void _syncDates() {
    _start = _draft.startDate;
    _end = draftEndDate(_draft);
  }

  void _update(Draft Function(Draft d) change) {
    setState(() {
      _requestId = ref.read(uuidProvider)(); // a changed draft is a new request
      _error = '';
      _draft = change(_draft);
    });
    _persist();
  }

  // ---------------------------------------------------------------------------
  // Navigation between steps
  // ---------------------------------------------------------------------------

  void _leave() => context.canPop() ? context.pop() : context.go('/');

  void _back() {
    if (_busy) return;
    setState(() => _editingDates = false);
    if (_step > 1) {
      setState(() {
        _error = '';
        _direction = -1;
        _step -= 1;
      });
      _persist();
    } else {
      _leave();
    }
  }

  void _next() {
    setState(() => _error = '');
    if (_step == 3 && _editingDates) {
      _applyDates();
      return;
    }
    String? problem;
    switch (_step) {
      case 1:
        if (_draft.path == null) problem = 'Choose Build or Quit to continue.';
      case 2:
        if (_draft.name.trim().isEmpty || _draft.name.trim().length > 80 || _draft.description.length > 300) {
          problem = 'Enter a target up to 80 characters and a description up to 300.';
        }
      case 3:
        if (!isValidDate(_draft.startDate) ||
            _draft.startDate.compareTo(dateInZone(DateTime.now())) < 0 ||
            _draft.duration < 1 ||
            _draft.duration > 365) {
          problem = 'Choose today or later, with a duration of 1–365 days.';
        }
      case 4:
        problem = validateDraft(
          _draft.reward.isEmpty ? _draft.copyWith(reward: 'Reward') : _draft,
        );
      case 5:
        if (_draft.reward.trim().isEmpty) problem = 'Choose or enter your reward.';
      case 6:
        problem = validateDraft(_draft);
    }
    if (problem != null) {
      setState(() => _error = problem!);
      return;
    }
    if (_step == 6) {
      unawaited(_confirmAndLock());
    } else {
      setState(() {
        _direction = 1;
        _step += 1;
      });
      _persist();
    }
  }

  // ---------------------------------------------------------------------------
  // Locking
  // ---------------------------------------------------------------------------

  Future<void> _confirmAndLock() async {
    final created = await showAppModal<Commitment>(
      context,
      builder: (_) => _LockConfirmModal(onLock: _lock),
    );
    if (created != null && mounted) {
      context.pushReplacement('/commitment/${created.id}?locked=1');
    }
  }

  /// Creates the commitment. Throws on failure so the dialog can close and the
  /// message can be shown here.
  Future<Commitment> _lock() async {
    if (_submitLock) throw const LockInException('Already saving.');
    _submitLock = true;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final created = await ref.read(commitmentsProvider.notifier).create(_draft, _requestId);
      _finished = true;
      await _writes.catchError((Object _) {});
      await _drafts.clear().catchError((Object _) {});
      return created;
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e is LockInException ? e.message : 'Your commitment was not saved. Please retry.');
      }
      rethrow;
    } finally {
      _submitLock = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Duration editing
  // ---------------------------------------------------------------------------

  void _applyDates() {
    if (!isValidDate(_start) ||
        !isValidDate(_end) ||
        _start.compareTo(dateInZone(DateTime.now())) < 0 ||
        _end.compareTo(_start) < 0 ||
        dayDifference(_start, _end) >= 365) {
      setState(() => _editorError = 'Select a valid range of 1–365 days starting today or later.');
      return;
    }
    _update((d) => d.copyWith(startDate: _start, duration: dayDifference(_start, _end) + 1));
    setState(() {
      _editingDates = false;
      _step = 4;
      _direction = 1;
    });
    _persist();
  }

  Future<void> _openPaceEditor(PaceEditorMode mode) async {
    final pace = await showPaceEditor(context, draft: _draft, mode: mode);
    if (pace != null) _update((d) => d.copyWith(pace: pace));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final reduced = ref.watch(reducedMotionProvider);
    final canLeave = _step == 1 && !_busy && !_showingDialog && !_editingDates;
    return PopScope(
      // Android back / iOS swipe: step back instead of leaving the wizard.
      canPop: canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AppScreen(
        setup: true,
        header: AppHeader(back: true, onBack: _back),
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
        footer: Row(
          spacing: 20,
          children: [
            if (_step > 1)
              SizedBox(
                width: 56,
                child: LockButton(
                  light: true,
                  icon: Feather.arrowLeft,
                  title: '',
                  semanticLabel: 'Previous step',
                  disabled: _busy,
                  onPressed: _back,
                ),
              ),
            Expanded(
              child: LockButton(
                title: _actions[_step - 1],
                disabled: !_ready || _busy,
                onPressed: _next,
              ),
            ),
          ],
        ),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StepProgress(step: _step),
                AnimatedSwitcher(
                  duration: reduced ? Motion.reduced : Motion.stepEnter,
                  reverseDuration: reduced ? Motion.reduced : Motion.stepExit,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) {
                    final incoming = child.key == ValueKey<int>(_step);
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) => Opacity(
                        opacity: animation.value,
                        child: Transform.translate(
                          offset: reduced
                              ? Offset.zero
                              : Offset((1 - animation.value) * 16 * (incoming ? _direction : -_direction), 0),
                          child: child,
                        ),
                      ),
                      child: child,
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_step),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 480),
                      child: _buildStep(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 16), child: ErrorNote(_error)),
        ],
      ),
    );
  }

  Widget _buildStep() {
    final heading = _step == 3 && _editingDates ? 'Select custom duration' : _titles[_step - 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 44, bottom: 40),
          child: ScreenTitle(heading),
        ),
        switch (_step) {
          1 => _stepPath(),
          2 => _stepTarget(),
          3 => _editingDates ? _stepCustomDates() : _stepDuration(),
          4 => _stepPace(),
          5 => _stepReward(),
          _ => _stepReview(),
        },
      ],
    );
  }

  Widget _stepPath() => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          spacing: 44,
          children: [
            ChoiceCard(
              title: 'Build',
              description: 'Establish a new positive ritual.',
              icon: Feather.plusCircle,
              selected: _draft.path == HabitPath.build,
              onPressed: () => _update((d) => d.copyWith(path: HabitPath.build)),
            ),
            ChoiceCard(
              title: 'Quit',
              description: 'Break away from a negative cycle.',
              icon: Feather.minusCircle,
              selected: _draft.path == HabitPath.quit,
              // A quit habit is a single yes/no per day: reset a daily count.
              onPressed: () => _update(
                (d) => d.copyWith(
                  path: HabitPath.quit,
                  pace: d.pace is DailyPace ? const DailyPace(1) : d.pace,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _stepTarget() => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          spacing: 28,
          children: [
            AppField(
              label: 'What is your target?',
              placeholder: 'e.g., Daily Yoga Practice',
              value: _draft.name,
              maxLength: 80,
              onChanged: (v) => _update((d) => d.copyWith(name: v)),
            ),
            AppField(
              label: 'Description (Optional)',
              placeholder: 'Any specific details...',
              value: _draft.description,
              multiline: true,
              maxLength: 300,
              onChanged: (v) => _update((d) => d.copyWith(description: v)),
            ),
          ],
        ),
      );

  Widget _stepDuration() {
    final today = dateInZone(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 20,
        children: [
          const Label('Challenge Duration', bold: true),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final days in const [7, 30, 45, 90])
                FractionallySizedBox(
                  widthFactor: 0.46,
                  child: LockButton(
                    light: true,
                    title: '$days days',
                    selected: _draft.duration == days && _draft.startDate == today,
                    onPressed: () => _update((d) => d.copyWith(duration: days, startDate: today)),
                  ),
                ),
            ],
          ),
          LockButton(
            light: true,
            icon: Feather.calendar,
            title: 'Custom Duration',
            onPressed: () => setState(() {
              _syncDates();
              _pickingEnd = false;
              _editorError = '';
              _editingDates = true;
            }),
          ),
          Label('${formatDate(_draft.startDate)} – ${formatDate(draftEndDate(_draft))}', size: 12, muted: true),
        ],
      ),
    );
  }

  Widget _stepCustomDates() => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: LockButton(
                    light: true,
                    title: formatShortDate(_start),
                    selected: !_pickingEnd,
                    onPressed: () => setState(() => _pickingEnd = false),
                  ),
                ),
                Expanded(
                  child: LockButton(
                    light: true,
                    title: formatShortDate(_end),
                    selected: _pickingEnd,
                    onPressed: () => setState(() => _pickingEnd = true),
                  ),
                ),
              ],
            ),
            Label('Select ${_pickingEnd ? 'end' : 'start'} date', size: 12, muted: true),
            CalendarView(
              selected: _pickingEnd ? _end : _start,
              rangeStart: _start,
              rangeEnd: _end,
              onSelect: (date) => setState(() {
                if (!_pickingEnd) {
                  _start = date;
                  if (date.compareTo(_end) > 0) _end = date;
                  _pickingEnd = true;
                } else {
                  _end = date;
                }
                _editorError = '';
              }),
            ),
            if (_editorError.isNotEmpty) ErrorNote(_editorError),
          ],
        ),
      );

  Widget _stepPace() {
    final pace = _draft.pace;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 18,
        children: [
          ChoiceCard(
            compact: true,
            title: 'Everyday',
            description: 'No days off. Build relentless momentum.',
            icon: Feather.calendar,
            selected: pace is DailyPace && pace.count == 1,
            onPressed: () => _update((d) => d.copyWith(pace: const DailyPace(1))),
          ),
          ChoiceCard(
            compact: true,
            title: 'Flexible Pace',
            description: 'Set a target, e.g., 3 times a week.',
            icon: Feather.sliders,
            selected: pace is WeeklyPace || (pace is DailyPace && pace.count > 1),
            onPressed: () => _openPaceEditor(PaceEditorMode.flexible),
          ),
          ChoiceCard(
            compact: true,
            title: 'Custom Days',
            description: 'Pick specific days of the week.',
            icon: Feather.checkSquare,
            selected: pace is CustomPace,
            onPressed: () => _openPaceEditor(PaceEditorMode.customDays),
          ),
          Label(paceLabel(pace), size: 12, muted: true),
        ],
      ),
    );
  }

  Widget _stepReward() => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 30,
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final reward in _rewards)
                  FractionallySizedBox(
                    widthFactor: 0.46,
                    child: LockButton(
                      light: true,
                      title: reward,
                      selected: _draft.reward == reward,
                      onPressed: () => _update((d) => d.copyWith(reward: reward)),
                    ),
                  ),
              ],
            ),
            AppField(
              semanticLabel: 'Custom reward',
              placeholder: 'Or type a custom reward...',
              value: _rewards.contains(_draft.reward) ? '' : _draft.reward,
              maxLength: 120,
              onChanged: (v) => _update((d) => d.copyWith(reward: v)),
            ),
          ],
        ),
      );

  Widget _stepReview() {
    final rows = [
      ('COMMITMENT NAME', _draft.name),
      (
        'TOTAL DURATION',
        '${_draft.duration} Days (${formatDate(_draft.startDate)} – ${formatDate(draftEndDate(_draft))})',
      ),
      ('EXECUTION PACE', paceLabel(_draft.pace)),
      ('LOCKED MOTIVATION', _draft.reward),
    ];
    final weekly = _draft.pace;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Label(rows[i].$1, size: 11, muted: true),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Label(rows[i].$2, bold: true),
            ),
            if (i < rows.length - 1) const AppDivider(),
          ],
          if (weekly is WeeklyPace && _draft.duration % 7 != 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Label(
                'Final ${_draft.duration % 7}-day period: '
                '${(weekly.count * (_draft.duration % 7) + 6) ~/ 7} successful days required.',
                size: 12,
                muted: true,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Lock this commitment?" confirmation. Runs [onLock] when confirmed and pops
/// with the created [Commitment] on success (or with `null` on failure; the
/// error message is shown by the wizard).
class _LockConfirmModal extends StatefulWidget {
  const _LockConfirmModal({required this.onLock});

  final Future<Commitment> Function() onLock;

  @override
  State<_LockConfirmModal> createState() => _LockConfirmModalState();
}

class _LockConfirmModalState extends State<_LockConfirmModal> {
  bool _busy = false;

  Future<void> _lock() async {
    setState(() => _busy = true);
    try {
      final created = await widget.onLock();
      if (mounted) Navigator.of(context).pop(created);
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => ModalCard(
        title: 'Lock this commitment?',
        busy: _busy,
        children: [
          const Label('This will finalize your rules and start the timeline.', muted: true),
          Row(
            spacing: 16,
            children: [
              Expanded(
                child: LockButton(
                  light: true,
                  title: 'GO BACK',
                  disabled: _busy,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(child: LockButton(title: 'YES, LOCK IT', loading: _busy, onPressed: _lock)),
            ],
          ),
        ],
      );
}
