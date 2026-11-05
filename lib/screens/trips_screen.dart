import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ledger/money.dart';
import '../ledger/trip_state.dart';
import '../providers/ledger_controller.dart';
import '../services/preferences.dart';
import '../theme.dart';
import '../widgets/ad_banner.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'plan_section.dart' show formatRange;
import 'trip_screen.dart';

/// Shared trip expenses: list of trips on this phone.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});
  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<LedgerController>().init();
  }

  Future<void> _create() async {
    final ledger = context.read<LedgerController>();
    final lastName = await context.read<Preferences>().lastName();
    if (!mounted) return;
    final r = await showModalBottomSheet<(String, String, String, String, DateTimeRange?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _NewTripSheet(myName: lastName ?? ''),
    );
    if (r == null || !mounted) return;
    final t = await ledger.createTrip(
      name: r.$1,
      myName: r.$2,
      currency: r.$3,
      destination: r.$4,
      start: r.$5 == null ? null : LedgerController.dayString(r.$5!.start),
      end: r.$5 == null ? null : LedgerController.dayString(r.$5!.end),
    );
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: t.id, justCreated: true)));
  }

  Future<void> _paste() async {
    final ledger = context.read<LedgerController>();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    await openImported(context, ledger, data?.text ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    final trips = ledger.trips;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          AppHeader(
            leading: IconButton(
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          Expanded(
            child: PageShell(
              title: 'Trips',
              subtitle: 'Plan together and split costs. Share on WhatsApp; your group votes, joins and approves.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PrimaryButton(key: const Key('newTrip'), label: 'New trip', icon: Icons.add, onPressed: ledger.ready ? _create : null),
                const SizedBox(height: 10),
                OutlineAction(label: 'Paste from WhatsApp', icon: Icons.content_paste_rounded, onPressed: ledger.ready ? _paste : null),
                const SizedBox(height: 24),
                if (!ledger.ready)
                  const Center(child: CircularProgressIndicator())
                else if (trips.isEmpty) ...[
                  const Text('How it works', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  const NumberedStep(
                      number: '1',
                      title: 'Create a trip and invite',
                      detail: 'Share the invite to your trip’s WhatsApp group. Friends open it in LocalDrop and join.'),
                  const NumberedStep(
                      number: '2',
                      title: 'Plan it together',
                      detail: 'Add ideas day by day. A plan is confirmed when most of the group votes yes; people tap “I’m in” to join.'),
                  const NumberedStep(
                      number: '3',
                      title: 'Split what you spend',
                      detail: 'An expense only counts once the payer and everyone in the split agree. Nobody can change it later.'),
                  const NumberedStep(
                      number: '4', title: 'Settle up', detail: 'LocalDrop works out the fewest payments to clear all debts.'),
                ] else ...[
                  SectionTitle('${trips.length} trip${trips.length == 1 ? '' : 's'}'),
                  const SizedBox(height: 12),
                  for (final t in trips) _TripCard(trip: t, me: ledger.myId),
                ],
              ]),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: const AdBanner(),
    );
  }
}

/// Imports pasted/opened content and opens the trip. Shared with the global
/// incoming-file handler.
Future<void> openImported(BuildContext context, LedgerController ledger, String text) async {
  final r = await ledger.importText(text);
  if (!context.mounted) return;
  if (!r.found) {
    showToast(context, 'No LocalDrop trip found. Copy the whole WhatsApp message, then try again.', error: true);
    return;
  }
  final parts = [
    r.added == 0 ? 'Already up to date' : '${r.added} update${r.added == 1 ? '' : 's'} added to ${r.tripName}',
    if (r.rejected > 0) '${r.rejected} ignored (signature did not match)',
  ];
  showToast(context, parts.join(' · '), error: r.rejected > 0);
  Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: r.tripId!)));
}

class _TripCard extends StatelessWidget {
  final TripState trip;
  final String me;
  const _TripCard({required this.trip, required this.me});

  @override
  Widget build(BuildContext context) {
    final bal = trip.balances[me] ?? 0;
    final pending = trip.pendingFor(me).length + trip.planVotesNeeded(me).length;
    final member = trip.isMember(me);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: trip.id))),
        child: SurfaceCard(
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trip.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  !member
                      ? 'Invitation · tap to see the plan and join'
                      : [
                          if (trip.destination.isNotEmpty) trip.destination,
                          '${trip.members.length} people',
                          '${trip.plan.where((p) => p.status == PlanStatus.confirmed).length} plans',
                          '${formatMoney(trip.totalSpent, trip.currency)} spent',
                        ].join(' · '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ]),
            ),
            if (pending > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                child: Text('$pending to review', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              )
            else if (member)
              Text(
                bal == 0 ? 'Settled' : (bal > 0 ? '+${formatMoney(bal, trip.currency)}' : formatMoney(bal, trip.currency)),
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: bal > 0 ? AppColors.green : (bal < 0 ? AppColors.red : AppColors.muted)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _NewTripSheet extends StatefulWidget {
  final String myName;
  const _NewTripSheet({required this.myName});
  @override
  State<_NewTripSheet> createState() => _NewTripSheetState();
}

class _NewTripSheetState extends State<_NewTripSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController();
  late final _me = TextEditingController(text: widget.myName);
  final _dest = TextEditingController();
  String _currency = 'INR';
  DateTimeRange? _dates;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('New trip', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            const FieldLabel('Trip name'),
            TextFormField(
              key: const Key('tripName'),
              controller: _name,
              maxLength: 60,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a trip name' : null,
              decoration: const InputDecoration(hintText: 'e.g. Manali Trip 2026', counterText: ''),
            ),
            const SizedBox(height: 12),
            const FieldLabel('Where to? (optional)'),
            TextFormField(
              key: const Key('tripDestination'),
              controller: _dest,
              maxLength: 80,
              decoration: const InputDecoration(hintText: 'e.g. Manali, Himachal', counterText: ''),
            ),
            const SizedBox(height: 12),
            const FieldLabel('Dates (optional)'),
            OutlineAction(
              label: _dates == null ? 'Pick dates' : formatRange(_dates!),
              icon: Icons.date_range_rounded,
              onPressed: () async {
                final now = DateTime.now();
                final r = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 3),
                  initialDateRange: _dates,
                );
                if (r != null) setState(() => _dates = r);
              },
            ),
            const SizedBox(height: 12),
            const FieldLabel('Your name'),
            TextFormField(
              key: const Key('tripMyName'),
              controller: _me,
              maxLength: 40,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
              decoration: const InputDecoration(hintText: 'Your name', counterText: ''),
            ),
            const SizedBox(height: 12),
            const FieldLabel('Currency'),
            Wrap(spacing: 7, runSpacing: 7, children: [
              for (final c in Currency.all.take(5))
                Pill('${c.symbol.trim()} ${c.code}', selected: _currency == c.code, onTap: () => setState(() => _currency = c.code)),
            ]),
            const SizedBox(height: 20),
            PrimaryButton(
              key: const Key('createTrip'),
              label: 'Create trip',
              icon: Icons.arrow_forward_rounded,
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, (_name.text.trim(), _me.text.trim(), _currency, _dest.text.trim(), _dates));
                }
              },
            ),
          ]),
        ),
      );
}
