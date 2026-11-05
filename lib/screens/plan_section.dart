import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ledger/trip_state.dart';
import '../providers/ledger_controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'common.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String formatDay(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
String formatRange(DateTimeRange r) => r.start == r.end ? formatDay(r.start) : '${formatDay(r.start)} – ${formatDay(r.end)}';

/// The trip itinerary: grouped by day, with group votes and "I'm in".
class PlanSection extends StatelessWidget {
  final TripState trip;
  final String me;

  /// For people who haven't joined yet: they see the plan but can't vote.
  final bool readOnly;
  const PlanSection({super.key, required this.trip, required this.me, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    final ledger = context.read<LedgerController>();
    final items = trip.plan;
    final organiser = trip.createdBy == me;
    final start = trip.startDay == null ? null : DateTime.parse(trip.startDay!);
    final byDay = <String, List<PlanItem>>{};
    for (final p in items) {
      (byDay[p.day] ??= []).add(p);
    }
    final toVote = trip.planVotesNeeded(me);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SurfaceCard(
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.map_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trip.destination.isEmpty ? 'Destination not set' : trip.destination,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                start == null
                    ? 'Dates not set'
                    : formatRange(DateTimeRange(start: start, end: DateTime.parse(trip.endDay ?? trip.startDay!))),
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ]),
          ),
          if (organiser && !readOnly)
            IconButton(
              key: const Key('editTripDetails'),
              tooltip: 'Edit destination and dates',
              icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
              onPressed: () => _editDetails(context),
            ),
        ]),
      ),
      if (!readOnly) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: PrimaryButton(
              key: const Key('addPlan'),
              label: 'Add to plan',
              icon: Icons.add,
              onPressed: () => _addItem(context),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 54,
            child: OutlinedButton.icon(
              key: const Key('sharePlan'),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => ledger.sharePlan(trip.id),
              icon: const Icon(Icons.share_rounded, color: AppColors.green, size: 18),
              label: const Text('Share', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'A plan is confirmed when more than half of the ${trip.members.length} people vote yes.',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
      if (toVote.isNotEmpty && !readOnly) ...[
        const SizedBox(height: 14),
        InfoBanner('${toVote.length} plan idea${toVote.length == 1 ? '' : 's'} waiting for your vote.', icon: Icons.how_to_vote_outlined),
      ],
      const SizedBox(height: 18),
      if (items.isEmpty)
        StateMessage(
          icon: Icons.event_note_outlined,
          title: 'No plans yet',
          detail: readOnly
              ? 'Join to suggest places and activities.'
              : 'Add the first idea: a place, a meal, a ride. Then share it to the group.',
        ),
      for (final day in byDay.keys) ...[
        _DayHeader(day: DateTime.parse(day), start: start),
        for (final p in byDay[day]!) _PlanCard(trip: trip, item: p, me: me, readOnly: readOnly),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Future<void> _addItem(BuildContext context) async {
    final ledger = context.read<LedgerController>();
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ChangeNotifierProvider.value(value: ledger, child: AddPlanSheet(trip: trip)),
    );
    if (added == true && context.mounted) {
      final ok = await confirmDialog(context,
          title: 'Share with the group?', message: 'Send the plan to your trip’s WhatsApp group so everyone can vote.', confirm: 'Share');
      if (ok) await ledger.sharePlan(trip.id);
    }
  }

  Future<void> _editDetails(BuildContext context) async {
    final ledger = context.read<LedgerController>();
    final dest = TextEditingController(text: trip.destination);
    DateTimeRange? range = trip.startDay == null
        ? null
        : DateTimeRange(start: DateTime.parse(trip.startDay!), end: DateTime.parse(trip.endDay ?? trip.startDay!));
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Trip details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            const FieldLabel('Destination'),
            TextField(controller: dest, maxLength: 80, decoration: const InputDecoration(hintText: 'e.g. Manali', counterText: '')),
            const SizedBox(height: 12),
            const FieldLabel('Dates'),
            OutlineAction(
              label: range == null ? 'Pick dates' : formatRange(range!),
              icon: Icons.date_range_rounded,
              onPressed: () async {
                final now = DateTime.now();
                final r = await showDateRangePicker(
                    context: sheet, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3), initialDateRange: range);
                if (r != null) set(() => range = r);
              },
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Save', icon: Icons.check, onPressed: () => Navigator.pop(sheet, true)),
          ]),
        ),
      ),
    );
    if (save != true) return;
    await ledger.setTripDetails(trip.id,
        destination: dest.text,
        start: range == null ? null : LedgerController.dayString(range!.start),
        end: range == null ? null : LedgerController.dayString(range!.end));
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final DateTime? start;
  const _DayHeader({required this.day, required this.start});
  @override
  Widget build(BuildContext context) {
    final n = start == null ? null : day.difference(start!).inDays + 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        if (n != null && n >= 1)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
            child:
                Text('DAY $n', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .6)),
          ),
        Text(formatDay(day), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final TripState trip;
  final PlanItem item;
  final String me;
  final bool readOnly;
  const _PlanCard({required this.trip, required this.item, required this.me, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    final ledger = context.read<LedgerController>();
    final p = item;
    final myVote = p.votes[me];
    final going = p.going.contains(me);
    final dropped = p.status == PlanStatus.dropped;
    final (chip, chipColor) = switch (p.status) {
      PlanStatus.confirmed => ('Confirmed', AppColors.green),
      PlanStatus.dropped => (p.withdrawn ? 'Withdrawn' : 'Dropped', AppColors.muted),
      PlanStatus.proposed => ('${p.yes}/${p.memberCount} yes', const Color(0xFFB07A00)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: dropped ? .55 : 1,
        child: SurfaceCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 50,
                child: Text(p.time ?? 'Any time',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: p.time == null ? 10 : 13, color: AppColors.primary)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.title, style: TextStyle(fontWeight: FontWeight.w800, decoration: dropped ? TextDecoration.lineThrough : null)),
                  if (p.place.isNotEmpty)
                    Row(children: [
                      const Icon(Icons.place_outlined, size: 13, color: AppColors.muted),
                      const SizedBox(width: 3),
                      Flexible(child: Text(p.place, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
                    ]),
                  if (p.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(p.note, style: const TextStyle(fontSize: 12, height: 1.35)),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Suggested by ${trip.nameOf(p.event.author)} · ${p.going.length} going'
                    '${p.going.isEmpty ? '' : ': ${p.going.map((g) => g == me ? 'you' : trip.nameOf(g)).join(', ')}'}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: chipColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (p.status == PlanStatus.confirmed) ...[
                    Icon(Icons.check_rounded, size: 12, color: chipColor),
                    const SizedBox(width: 3),
                  ],
                  Text(chip, style: TextStyle(color: chipColor, fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
            if (!readOnly && !p.withdrawn)
              Row(children: [
                const SizedBox(width: 42),
                _VoteButton(
                  key: Key('yes-${p.id}'),
                  icon: Icons.thumb_up_alt_rounded,
                  label: '${p.yes}',
                  active: myVote == true,
                  color: AppColors.green,
                  onTap: () => ledger.votePlan(trip.id, p.id, true),
                ),
                _VoteButton(
                  key: Key('no-${p.id}'),
                  icon: Icons.thumb_down_alt_rounded,
                  label: '${p.no}',
                  active: myVote == false,
                  color: AppColors.red,
                  onTap: () => ledger.votePlan(trip.id, p.id, false),
                ),
                const Spacer(),
                TextButton.icon(
                  key: Key('going-${p.id}'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: () => ledger.rsvp(trip.id, p.id, !going),
                  icon: Icon(going ? Icons.check_circle : Icons.add_circle_outline,
                      size: 18, color: going ? AppColors.green : AppColors.primary),
                  label: Text(going ? 'I’m in' : 'Join',
                      style: TextStyle(fontWeight: FontWeight.w800, color: going ? AppColors.green : AppColors.primary)),
                ),
                if (p.event.author == me)
                  IconButton(
                    tooltip: 'Withdraw',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 19, color: AppColors.muted),
                    onPressed: () async {
                      final ok = await confirmDialog(context,
                          title: 'Withdraw “${p.title}”?',
                          message: 'It will be removed from everyone’s plan when you share.',
                          confirm: 'Withdraw',
                          destructive: true);
                      if (ok) await ledger.withdrawPlanItem(trip.id, p.id);
                    },
                  ),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _VoteButton({super.key, required this.icon, required this.label, required this.active, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 17, color: active ? color : const Color(0xFFC9C5D8)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: active ? color : AppColors.muted)),
          ]),
        ),
      );
}

/// Suggest a plan item: what, which day, optional time, place and notes.
class AddPlanSheet extends StatefulWidget {
  final TripState trip;
  const AddPlanSheet({super.key, required this.trip});
  @override
  State<AddPlanSheet> createState() => _AddPlanSheetState();
}

class _AddPlanSheetState extends State<AddPlanSheet> {
  final _title = TextEditingController();
  final _place = TextEditingController();
  final _note = TextEditingController();
  late DateTime _day = widget.trip.startDay == null ? DateTime.now() : DateTime.parse(widget.trip.startDay!);
  TimeOfDay? _time;
  String? _error;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final start = t.startDay == null ? null : DateTime.parse(t.startDay!);
    final end = t.endDay == null ? null : DateTime.parse(t.endDay!);
    final tripDays = (start != null && end != null && !end.isBefore(start) && end.difference(start).inDays < 31)
        ? [for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) d]
        : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add to plan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          const FieldLabel('What?'),
          TextField(
            key: const Key('planTitle'),
            controller: _title,
            maxLength: 80,
            decoration: const InputDecoration(hintText: 'e.g. Paragliding at Solang', counterText: ''),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Which day?'),
          if (tripDays != null)
            Wrap(spacing: 7, runSpacing: 7, children: [
              for (final (i, d) in tripDays.indexed)
                Pill('Day ${i + 1} · ${d.day} ${_months[d.month - 1]}',
                    selected: LedgerController.dayString(d) == LedgerController.dayString(_day), onTap: () => setState(() => _day = d)),
            ])
          else
            OutlineAction(
              label: formatDay(_day),
              icon: Icons.event_rounded,
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                    context: context, initialDate: _day, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3));
                if (d != null) setState(() => _day = d);
              },
            ),
          const SizedBox(height: 12),
          const FieldLabel('Time (optional)'),
          Row(children: [
            Pill(_time == null ? 'Any time' : _time!.format(context), selected: _time != null, onTap: () async {
              final tm = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0));
              if (tm != null) setState(() => _time = tm);
            }),
            if (_time != null) TextButton(onPressed: () => setState(() => _time = null), child: const Text('Clear')),
          ]),
          const SizedBox(height: 12),
          const FieldLabel('Place (optional)'),
          TextField(controller: _place, maxLength: 80, decoration: const InputDecoration(hintText: 'e.g. Solang Valley', counterText: '')),
          const SizedBox(height: 12),
          const FieldLabel('Notes (optional)'),
          TextField(
            controller: _note,
            maxLength: 300,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(hintText: 'Cost, what to bring, booking link…', counterText: ''),
          ),
          if (_error != null) ...[const SizedBox(height: 8), InfoBanner(_error!, error: true)],
          const SizedBox(height: 16),
          PrimaryButton(
            key: const Key('savePlan'),
            label: 'Add to plan',
            icon: Icons.check,
            loading: _busy,
            onPressed: () async {
              if (_title.text.trim().isEmpty) return setState(() => _error = 'Say what the plan is');
              setState(() => _busy = true);
              final tm = _time;
              await context.read<LedgerController>().addPlanItem(
                    t.id,
                    title: _title.text,
                    day: _day,
                    time: tm == null ? null : '${tm.hour.toString().padLeft(2, '0')}:${tm.minute.toString().padLeft(2, '0')}',
                    place: _place.text,
                    note: _note.text,
                  );
              if (context.mounted) Navigator.pop(context, true);
            },
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('You vote yes automatically. Others vote when you share.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}
