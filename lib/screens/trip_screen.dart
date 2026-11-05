import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ledger/money.dart';
import '../ledger/trip_state.dart';
import '../providers/ledger_controller.dart';
import '../services/preferences.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ad_banner.dart';
import '../widgets/ui.dart';
import 'common.dart';

class TripScreen extends StatelessWidget {
  final String tripId;
  final bool justCreated;
  const TripScreen({super.key, required this.tripId, this.justCreated = false});

  Future<void> _share(BuildContext context, {String? headline}) async {
    try {
      await context.read<LedgerController>().share(tripId, headline: headline);
    } on Exception catch (e) {
      if (context.mounted) showToast(context, 'Could not share: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    final t = ledger.trip(tripId);
    if (t == null) {
      return const AppFrame(child: StateMessage(icon: Icons.receipt_long_outlined, title: 'Trip not found'));
    }
    final me = ledger.myId;
    final member = t.isMember(me);
    final pending = t.pendingFor(me);
    final bal = t.balances[me] ?? 0;

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
              title: t.name,
              subtitle: '${t.members.length} people · ${formatMoney(t.totalSpent, t.currency)} agreed spending',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!member)
                  _JoinCard(tripId: tripId)
                else ...[
                  if (justCreated) ...[
                    const InfoBanner('Invite your group: share this trip to your WhatsApp group. Friends open the file in LocalDrop and join.',
                        icon: Icons.group_add_outlined),
                    const SizedBox(height: 12),
                  ],
                  _BalanceCard(amount: bal, currency: t.currency),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: PrimaryButton(
                        key: const Key('addExpense'),
                        label: 'Add expense',
                        icon: Icons.add,
                        onPressed: () => _addExpense(context, t, me),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 54,
                      child: OutlinedButton.icon(
                        key: const Key('shareTrip'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _share(context),
                        icon: const Icon(Icons.share_rounded, color: AppColors.green, size: 18),
                        label: const Text('Share', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  const Text('Share after each change so everyone’s copy stays in sync.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11)),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    SectionTitle('Needs your approval (${pending.length})'),
                    const SizedBox(height: 10),
                    for (final p in pending) _ApprovalCard(trip: t, proposal: p, me: me, onShare: () => _share(context)),
                  ],
                  const SizedBox(height: 22),
                  if (t.settlements.isNotEmpty) ...[
                    const SectionTitle('Settle up'),
                    const SizedBox(height: 10),
                    for (final s in t.settlements) _SettlementRow(trip: t, s: s, me: me),
                    const SizedBox(height: 22),
                  ],
                  SectionTitle('Expenses (${t.expenses.length})'),
                  const SizedBox(height: 6),
                  if (t.expenses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('No expenses yet. Add the first one.', style: TextStyle(color: AppColors.muted)),
                    ),
                  for (final e in t.expenses) _ExpenseRow(trip: t, e: e, me: me),
                  if (t.payments.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const SectionTitle('Repayments'),
                    const SizedBox(height: 6),
                    for (final p in t.payments) _PaymentRow(trip: t, p: p),
                  ],
                ],
                const SizedBox(height: 22),
                const SectionTitle('People'),
                const SizedBox(height: 8),
                for (final m in t.members.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Avatar(initialsOf(m.name)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('${m.name}${m.id == me ? ' (you)' : ''}${m.id == t.createdBy ? ' · organiser' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      if (member)
                        Text(formatMoney(t.balances[m.id] ?? 0, t.currency),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: (t.balances[m.id] ?? 0) > 0
                                    ? AppColors.green
                                    : ((t.balances[m.id] ?? 0) < 0 ? AppColors.red : AppColors.muted))),
                    ]),
                  ),
                const SizedBox(height: 18),
                Text(
                  '${t.eventCount} signed entries on this phone${t.ignored > 0 ? ' · ${t.ignored} ignored (not valid)' : ''}. '
                  'Stored only on your devices; nothing goes to a server.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4),
                ),
              ]),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: const AdBanner(),
    );
  }

  Future<void> _addExpense(BuildContext context, TripState t, String me) async {
    final ledger = context.read<LedgerController>();
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ChangeNotifierProvider.value(value: ledger, child: AddExpenseSheet(trip: t, me: me)),
    );
    if (added == true && context.mounted) {
      final ok = await confirmDialog(context,
          title: 'Share with the group?',
          message: 'Send this expense to your trip’s WhatsApp group so everyone involved can approve it.',
          confirm: 'Share');
      if (ok && context.mounted) await _share(context, headline: '💸 New expense in ${t.name}');
    }
  }
}

class _BalanceCard extends StatelessWidget {
  final int amount;
  final String currency;
  const _BalanceCard({required this.amount, required this.currency});
  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = amount > 0
        ? ('You are owed', AppColors.green, const Color(0xFFEAF8F2))
        : amount < 0
            ? ('You owe', AppColors.red, const Color(0xFFFFF1F1))
            : ('You are all settled', AppColors.primary, AppColors.lavender);
    return Container(
      key: const Key('balance'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 4),
        Text(amount == 0 ? formatMoney(0, currency) : formatMoney(amount.abs(), currency),
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: -.5)),
        const SizedBox(height: 2),
        const Text('Counts only expenses everyone involved approved.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
      ]),
    );
  }
}

class _JoinCard extends StatefulWidget {
  final String tripId;
  const _JoinCard({required this.tripId});
  @override
  State<_JoinCard> createState() => _JoinCardState();
}

class _JoinCardState extends State<_JoinCard> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<Preferences>().lastName().then((n) {
      if (mounted && n != null && _name.text.isEmpty) _name.text = n;
    });
  }

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('You were invited to this trip', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Join to see expenses, approve your share and add what you paid.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('joinTripName'),
            controller: _name,
            maxLength: 40,
            decoration: const InputDecoration(hintText: 'Your name', prefixIcon: Icon(Icons.person_outline), counterText: ''),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            key: const Key('joinTrip'),
            label: 'Join trip',
            icon: Icons.arrow_forward_rounded,
            loading: _busy,
            onPressed: () async {
              if (_name.text.trim().isEmpty) return showToast(context, 'Enter your name', error: true);
              final ledger = context.read<LedgerController>();
              setState(() => _busy = true);
              await ledger.join(widget.tripId, _name.text.trim());
              if (!context.mounted) return;
              setState(() => _busy = false);
              final ok = await confirmDialog(context,
                  title: 'Let the group know',
                  message: 'Share to the trip’s WhatsApp group so others can add you to expenses.',
                  confirm: 'Share');
              if (ok) await ledger.share(widget.tripId, headline: '👋 ${_name.text.trim()} joined the trip expenses');
            },
          ),
        ]),
      );
}

String _statusLabel(Proposal p, TripState t) => switch (p.status) {
      ProposalStatus.confirmed => 'Agreed',
      ProposalStatus.rejected => 'Rejected',
      ProposalStatus.pending => 'Waiting for ${p.waitingFor.map(t.nameOf).join(', ')}',
    };

class _StatusChip extends StatelessWidget {
  final Proposal p;
  final TripState trip;
  final bool removed;
  const _StatusChip(this.p, this.trip, {this.removed = false});
  @override
  Widget build(BuildContext context) {
    final (text, color) = removed
        ? ('Removed', AppColors.muted)
        : switch (p.status) {
            ProposalStatus.confirmed => ('Agreed ✓', AppColors.green),
            ProposalStatus.rejected => ('Rejected', AppColors.red),
            ProposalStatus.pending => ('${p.approvals.length}/${p.required.length} approved', const Color(0xFFB07A00)),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final TripState trip;
  final Proposal proposal;
  final String me;
  final VoidCallback onShare;
  const _ApprovalCard({required this.trip, required this.proposal, required this.me, required this.onShare});

  @override
  Widget build(BuildContext context) {
    final ledger = context.read<LedgerController>();
    final p = proposal;
    String title, detail;
    if (p is Expense) {
      title = '${p.title} · ${formatMoney(p.amount, trip.currency)}';
      detail = '${trip.nameOf(p.paidBy)} paid · your share ${formatMoney(p.shares[me] ?? 0, trip.currency)}';
    } else if (p is Payment) {
      title = 'Repayment · ${formatMoney(p.amount, trip.currency)}';
      detail = '${trip.nameOf(p.from)} paid ${trip.nameOf(p.to)}${p.note.isEmpty ? '' : ' · ${p.note}'}';
    } else {
      final target = trip.expenses.firstWhere((e) => e.removal?.id == p.id);
      title = 'Remove “${target.title}”?';
      detail = '${trip.nameOf(p.event.author)} wants to remove it: ${p.event.body['reason'] ?? ''}';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Text('Added by ${trip.nameOf(p.event.author)} · ${formatTimestamp(p.event.ts)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: Key('reject-${p.id}'),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFFD2D5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final reason = await _askReason(context);
                  if (reason == null) return;
                  await ledger.reject(trip.id, p.id, reason);
                  onShare();
                },
                child: const Text('Reject', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: Key('approve-${p.id}'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  await ledger.approve(trip.id, p.id);
                  if (context.mounted) showToast(context, 'Approved. Share so the group sees it.');
                },
                child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Why are you rejecting?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      content: TextField(controller: c, autofocus: true, maxLength: 120, decoration: const InputDecoration(hintText: 'e.g. It was ₹700, not ₹900')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(d, c.text.trim()),
          child: const Text('Reject', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
}

class _ExpenseRow extends StatelessWidget {
  final TripState trip;
  final Expense e;
  final String me;
  const _ExpenseRow({required this.trip, required this.e, required this.me});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => _details(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.receipt_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13, decoration: e.removed ? TextDecoration.lineThrough : null)),
                Text('${trip.nameOf(e.paidBy)} paid · ${formatTimestamp(e.date)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoney(e.amount, trip.currency), style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              _StatusChip(e, trip, removed: e.removed),
            ]),
          ]),
        ),
      );

  void _details(BuildContext context) {
    final ledger = context.read<LedgerController>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          Text('${formatMoney(e.amount, trip.currency)} · paid by ${trip.nameOf(e.paidBy)}',
              style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          for (final m in e.required)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(
                  e.rejections.containsKey(m)
                      ? Icons.cancel
                      : (e.approvals.contains(m) ? Icons.verified_rounded : Icons.hourglass_top_rounded),
                  size: 18,
                  color: e.rejections.containsKey(m)
                      ? AppColors.red
                      : (e.approvals.contains(m) ? AppColors.green : const Color(0xFFB07A00)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(trip.nameOf(m), style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(e.shares[m] == null ? 'paid' : 'share ${formatMoney(e.shares[m]!, trip.currency)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
          for (final r in e.rejections.entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${trip.nameOf(r.key)}: “${r.value}”', style: const TextStyle(color: AppColors.red, fontSize: 12)),
            ),
          const SizedBox(height: 10),
          Text(_statusLabel(e, trip), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const Text('Signed by everyone who approved. It cannot be edited; remove and re-add instead.',
              style: TextStyle(color: AppColors.muted, fontSize: 11)),
          if ((e.event.author == me || e.paidBy == me) && e.removal == null && e.status != ProposalStatus.rejected) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () async {
                final reason = await _askReason(sheet);
                if (reason == null) return;
                await ledger.removeExpense(trip.id, e.id, reason);
                if (sheet.mounted) Navigator.pop(sheet);
              },
              icon: const Icon(Icons.delete_outline, color: AppColors.red),
              label: Text(e.status == ProposalStatus.confirmed ? 'Ask to remove' : 'Withdraw',
                  style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final TripState trip;
  final Payment p;
  const _PaymentRow({required this.trip, required this.p});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${trip.nameOf(p.from)} → ${trip.nameOf(p.to)}${p.note.isEmpty ? '' : ' · ${p.note}'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Text(formatMoney(p.amount, trip.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          _StatusChip(p, trip),
        ]),
      );
}

class _SettlementRow extends StatelessWidget {
  final TripState trip;
  final Settlement s;
  final String me;
  const _SettlementRow({required this.trip, required this.s, required this.me});

  @override
  Widget build(BuildContext context) {
    final involved = s.from == me || s.to == me;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: s.from == me ? 'You' : trip.nameOf(s.from), style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: ' pay '),
              TextSpan(text: s.to == me ? 'you' : trip.nameOf(s.to), style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: '  ${formatMoney(s.amount, trip.currency)}', style: const TextStyle(fontWeight: FontWeight.w900)),
            ])),
          ),
          if (involved)
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Record this payment?',
                    message: '${trip.nameOf(s.from)} paid ${trip.nameOf(s.to)} ${formatMoney(s.amount, trip.currency)} '
                        '(cash, UPI…). ${s.from == me ? trip.nameOf(s.to) : trip.nameOf(s.from)} will confirm it.',
                    confirm: 'Record');
                if (!ok || !context.mounted) return;
                await context.read<LedgerController>().recordPayment(trip.id, from: s.from, to: s.to, amount: s.amount);
              },
              child: const Text('Mark paid', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
        ]),
      ),
    );
  }
}

/// Add an expense: who paid, how much, and who it is split between.
class AddExpenseSheet extends StatefulWidget {
  final TripState trip;
  final String me;
  const AddExpenseSheet({super.key, required this.trip, required this.me});
  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  late String _paidBy = widget.me;
  late final Set<String> _split = widget.trip.members.keys.toSet();
  bool _custom = false;
  final Map<String, TextEditingController> _customCtl = {};
  String? _error;
  bool _busy = false;

  TextEditingController _ctl(String id) => _customCtl.putIfAbsent(id, TextEditingController.new);

  Future<void> _save() async {
    final amount = parseMoney(_amount.text);
    final title = _title.text.trim();
    setState(() => _error = null);
    if (title.isEmpty) return setState(() => _error = 'Add what it was for');
    if (amount == null) return setState(() => _error = 'Enter an amount like 500 or 499.50');
    Map<String, int> shares;
    if (_custom) {
      shares = {};
      for (final m in widget.trip.members.keys) {
        final t = _ctl(m).text.trim();
        if (t.isEmpty) continue;
        final v = parseMoney(t);
        if (v == null) return setState(() => _error = 'Check the amount for ${widget.trip.nameOf(m)}');
        shares[m] = v;
      }
      final sum = shares.values.fold(0, (a, b) => a + b);
      if (sum != amount) {
        return setState(() => _error =
            'Shares add up to ${formatMoney(sum, widget.trip.currency)}, not ${formatMoney(amount, widget.trip.currency)}');
      }
    } else {
      if (_split.isEmpty) return setState(() => _error = 'Pick who this was for');
      shares = equalSplit(amount, _split);
    }
    setState(() => _busy = true);
    await context.read<LedgerController>().addExpense(widget.trip.id, title: title, amount: amount, paidBy: _paidBy, shares: shares);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final amount = parseMoney(_amount.text);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add expense', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          const FieldLabel('What was it for?'),
          TextField(
              key: const Key('expenseTitle'),
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(hintText: 'e.g. Dinner at Johnson’s Cafe', counterText: '')),
          const SizedBox(height: 12),
          const FieldLabel('Amount'),
          TextField(
            key: const Key('expenseAmount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: '0', prefixText: Currency.of(t.currency).symbol),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Paid by'),
          Wrap(spacing: 7, runSpacing: 7, children: [
            for (final m in t.members.values)
              Pill(m.id == widget.me ? 'You' : m.name, selected: _paidBy == m.id, onTap: () => setState(() => _paidBy = m.id)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: FieldLabel('Split between')),
            Pill('Equally', selected: !_custom, onTap: () => setState(() => _custom = false)),
            const SizedBox(width: 6),
            Pill('Custom', selected: _custom, onTap: () => setState(() => _custom = true)),
          ]),
          const SizedBox(height: 6),
          for (final m in t.members.values)
            _custom
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text(m.id == widget.me ? 'You' : m.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: _ctl(m.id),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                              isDense: true, hintText: '0', prefixText: Currency.of(t.currency).symbol),
                        ),
                      ),
                    ]),
                  )
                : CheckboxListTile(
                    key: Key('split-${m.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _split.contains(m.id),
                    onChanged: (v) => setState(() => v == true ? _split.add(m.id) : _split.remove(m.id)),
                    title: Text(m.id == widget.me ? 'You' : m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    secondary: amount == null || !_split.contains(m.id)
                        ? null
                        : Text(formatMoney(equalSplit(amount, _split)[m.id]!, t.currency),
                            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            InfoBanner(_error!, error: true),
          ],
          const SizedBox(height: 16),
          PrimaryButton(key: const Key('saveExpense'), label: 'Add expense', icon: Icons.check, loading: _busy, onPressed: _save),
          const SizedBox(height: 6),
          const Center(
            child: Text('The payer and everyone in the split must approve it.',
                style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}
