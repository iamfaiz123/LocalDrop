import 'event.dart';

class Member {
  final String id;
  final String name;
  final int joinedAt;
  const Member(this.id, this.name, this.joinedAt);
}

enum ProposalStatus { pending, confirmed, rejected }

/// Something that needs everyone involved to agree: an expense, the removal
/// of an expense, or a repayment.
class Proposal {
  final LedgerEvent event;
  final Set<String> required;
  final Set<String> approvals = {};
  final Map<String, String> rejections = {};
  Proposal(this.event, this.required) {
    if (required.contains(event.author)) approvals.add(event.author);
  }

  String get id => event.id;
  ProposalStatus get status => rejections.isNotEmpty
      ? ProposalStatus.rejected
      : approvals.containsAll(required)
          ? ProposalStatus.confirmed
          : ProposalStatus.pending;
  Set<String> get waitingFor => required.difference(approvals).difference(rejections.keys.toSet());
}

class Expense extends Proposal {
  final String title;
  final int amount;
  final String paidBy;
  final Map<String, int> shares;
  final int date;
  Proposal? removal;
  Expense(super.event, super.required,
      {required this.title, required this.amount, required this.paidBy, required this.shares, required this.date});

  /// Counted in balances: agreed by everyone and not removed.
  bool get effective => status == ProposalStatus.confirmed && removal?.status != ProposalStatus.confirmed;
  bool get removed => removal?.status == ProposalStatus.confirmed;
}

class Payment extends Proposal {
  final String from;
  final String to;
  final int amount;
  final String note;
  Payment(super.event, super.required, {required this.from, required this.to, required this.amount, required this.note});
}

class Settlement {
  final String from;
  final String to;
  final int amount;
  const Settlement(this.from, this.to, this.amount);
}

/// The agreed state of a trip, derived deterministically from its events.
/// The same set of events always yields the same state, whatever order they
/// arrived in — that is what lets phones converge by exchanging messages.
class TripState {
  final String id;
  final String name;
  final String currency;
  final String createdBy;
  final int createdAt;
  final Map<String, Member> members;
  final List<Expense> expenses;
  final List<Payment> payments;

  /// Signed entries that break the rules (e.g. an approval by someone not
  /// involved, a split that doesn't add up). Ignored, but counted.
  final int ignored;
  final int eventCount;

  TripState._(this.id, this.name, this.currency, this.createdBy, this.createdAt, this.members, this.expenses, this.payments,
      this.ignored, this.eventCount);

  /// Positive: the member is owed money. Negative: the member owes.
  Map<String, int> get balances {
    final b = {for (final m in members.keys) m: 0};
    for (final e in expenses.where((e) => e.effective)) {
      b[e.paidBy] = (b[e.paidBy] ?? 0) + e.amount;
      e.shares.forEach((m, s) => b[m] = (b[m] ?? 0) - s);
    }
    for (final p in payments.where((p) => p.status == ProposalStatus.confirmed)) {
      b[p.from] = (b[p.from] ?? 0) + p.amount;
      b[p.to] = (b[p.to] ?? 0) - p.amount;
    }
    return b;
  }

  int get totalSpent => expenses.where((e) => e.effective).fold(0, (s, e) => s + e.amount);

  /// Fewest payments that settle everyone (greedy largest-first).
  List<Settlement> get settlements {
    final debtors = <MapEntry<String, int>>[];
    final creditors = <MapEntry<String, int>>[];
    balances.forEach((m, v) {
      if (v < 0) debtors.add(MapEntry(m, -v));
      if (v > 0) creditors.add(MapEntry(m, v));
    });
    int cmp(MapEntry<String, int> a, MapEntry<String, int> b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key);
    debtors.sort(cmp);
    creditors.sort(cmp);
    final out = <Settlement>[];
    var i = 0, j = 0;
    final d = debtors.map((e) => [e.key, e.value]).toList();
    final c = creditors.map((e) => [e.key, e.value]).toList();
    while (i < d.length && j < c.length) {
      final pay = (d[i][1] as int) < (c[j][1] as int) ? d[i][1] as int : c[j][1] as int;
      out.add(Settlement(d[i][0] as String, c[j][0] as String, pay));
      d[i][1] = (d[i][1] as int) - pay;
      c[j][1] = (c[j][1] as int) - pay;
      if (d[i][1] == 0) i++;
      if (c[j][1] == 0) j++;
    }
    return out;
  }

  /// Proposals waiting for [memberId]'s decision.
  List<Proposal> pendingFor(String memberId) => [
        for (final e in expenses) ...[
          if (e.status == ProposalStatus.pending && e.waitingFor.contains(memberId)) e,
          if (e.removal != null && e.removal!.status == ProposalStatus.pending && e.removal!.waitingFor.contains(memberId)) e.removal!,
        ],
        for (final p in payments)
          if (p.status == ProposalStatus.pending && p.waitingFor.contains(memberId)) p,
      ];

  bool isMember(String id) => members.containsKey(id);
  String nameOf(String id) => members[id]?.name ?? 'Unknown';

  /// Returns null if the trip's creating event is missing.
  static TripState? build(String tripId, Iterable<LedgerEvent> all) {
    final events = all.where((e) => e.tripId == tripId).toList()
      ..sort((a, b) => a.ts != b.ts ? a.ts.compareTo(b.ts) : a.id.compareTo(b.id));
    final genesis = events.where((e) => e.type == EventType.tripCreate && e.id == tripId).firstOrNull;
    if (genesis == null) return null;
    var ignored = 0;
    final name = (genesis.body['name'] as String?)?.trim() ?? 'Trip';
    final currency = (genesis.body['currency'] as String?) ?? 'INR';
    final members = <String, Member>{
      genesis.author: Member(genesis.author, _name(genesis.body['creator_name']), genesis.ts),
    };
    // Members first (so order of arrival never matters).
    for (final e in events.where((e) => e.type == EventType.memberJoin)) {
      final n = _name(e.body['name']);
      final existing = members[e.author];
      members[e.author] = Member(e.author, n, existing?.joinedAt ?? e.ts);
    }

    final proposals = <String, Proposal>{};
    final expenses = <Expense>[];
    final payments = <Payment>[];
    for (final e in events) {
      if (!members.containsKey(e.author) && e.type != EventType.tripCreate) {
        ignored++;
        continue;
      }
      switch (e.type) {
        case EventType.expenseAdd:
          final x = _expense(e, members);
          if (x == null) {
            ignored++;
          } else {
            expenses.add(x);
            proposals[x.id] = x;
          }
        case EventType.paymentAdd:
          final p = _payment(e, members);
          if (p == null) {
            ignored++;
          } else {
            payments.add(p);
            proposals[p.id] = p;
          }
        default:
          break;
      }
    }
    final decisions = events.where((e) => e.type == EventType.approve || e.type == EventType.reject).toList();
    final used = <String>{};
    void applyDecisions() {
      for (final e in decisions) {
        if (used.contains(e.id)) continue;
        final target = proposals[e.body['target']];
        if (target == null) continue;
        used.add(e.id);
        if (!target.required.contains(e.author)) {
          ignored++;
          continue;
        }
        if (e.type == EventType.approve) {
          target.approvals.add(e.author);
        } else {
          final reason = (e.body['reason'] as String?)?.trim() ?? '';
          target.rejections[e.author] = reason.length > 200 ? reason.substring(0, 200) : reason;
        }
      }
    }

    // 1) Decisions on expenses and payments.
    applyDecisions();
    // 2) Removals: judged against the expense's agreed state, so the result
    //    does not depend on the order entries arrived in.
    for (final e in events.where((e) => e.type == EventType.expenseVoid)) {
      final target = proposals[e.body['target']];
      if (target is! Expense || target.removal != null || (e.author != target.event.author && e.author != target.paidBy)) {
        ignored++;
        continue;
      }
      // Withdrawing an expense nobody has agreed to yet needs no approval.
      final req = target.status == ProposalStatus.confirmed ? target.required : {e.author};
      final r = Proposal(e, req);
      target.removal = r;
      proposals[r.id] = r;
    }
    // 3) Decisions on removals; anything still unmatched points nowhere.
    applyDecisions();
    ignored += decisions.where((e) => !used.contains(e.id)).length;
    return TripState._(tripId, name.isEmpty ? 'Trip' : name, currency, genesis.author, genesis.ts, members,
        expenses.reversed.toList(), payments.reversed.toList(), ignored, events.length);
  }

  static String _name(Object? v) {
    final s = (v is String ? v : '').trim();
    if (s.isEmpty) return 'Someone';
    return s.length > 40 ? s.substring(0, 40) : s;
  }

  static Expense? _expense(LedgerEvent e, Map<String, Member> members) {
    final b = e.body;
    final title = (b['title'] as String?)?.trim() ?? '';
    final amount = b['amount'];
    final paidBy = b['paid_by'];
    final rawShares = b['shares'];
    if (title.isEmpty || title.length > 80 || amount is! int || amount <= 0 || amount > 100000000000) return null;
    if (paidBy is! String || !members.containsKey(paidBy) || rawShares is! Map) return null;
    final shares = <String, int>{};
    for (final entry in rawShares.entries) {
      final v = entry.value;
      if (entry.key is! String || !members.containsKey(entry.key) || v is! int || v < 0) return null;
      if (v > 0) shares[entry.key as String] = v;
    }
    if (shares.isEmpty || shares.values.fold(0, (a, b) => a + b) != amount) return null;
    final required = {paidBy, ...shares.keys};
    final date = b['date'] is int ? b['date'] as int : e.ts;
    return Expense(e, required, title: title, amount: amount, paidBy: paidBy, shares: shares, date: date);
  }

  static Payment? _payment(LedgerEvent e, Map<String, Member> members) {
    final b = e.body;
    final from = b['from'], to = b['to'], amount = b['amount'];
    if (from is! String || to is! String || from == to || !members.containsKey(from) || !members.containsKey(to)) return null;
    if (amount is! int || amount <= 0 || amount > 100000000000) return null;
    if (e.author != from && e.author != to) return null;
    final note = (b['note'] as String?)?.trim() ?? '';
    return Payment(e, {from, to}, from: from, to: to, amount: amount, note: note.length > 80 ? note.substring(0, 80) : note);
  }
}
