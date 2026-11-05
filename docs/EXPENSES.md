# Trips: plan together & split expenses (no server)

Split costs with your group. Nothing is stored on a server: every phone keeps its own copy of
the trip's ledger, and copies are kept in sync by sharing a small file through WhatsApp (or any
messenger).

## How it works for users
1. **Create a trip** (Home › *Split trip expenses* › *New trip*) and tap **Share**. Pick the
   trip's WhatsApp group. The message includes a `.ldtrip` file.
2. Friends tap the file › **Open with LocalDrop** › **Join trip**, then share back.
3. **Add expense**: what, how much, who paid, split equally or custom. Share to the group.
4. Everyone **involved** (the payer and everyone in the split) taps **Approve**, or **Reject**
   with a reason, and shares back. The expense counts only once all of them approve.
5. **Settle up** shows the fewest payments that clear all debts. Record a payment with
   **Mark paid**; the receiver confirms it.

If a file can't be opened directly, long-press the WhatsApp message › Copy, then tap
**Paste from WhatsApp** in LocalDrop: the message contains an `LD1:` code with the same data.

## Trip planner
* **Trip details**: destination and dates (set when creating the trip; the organiser can edit).
* **Add to plan**: what, which day (pick "Day 1/2/3…" when dates are set), optional time, place
  and notes. Share the plan to WhatsApp; the message lists the itinerary with ✅ confirmed and 🗳️
  open items.
* **Vote** 👍 / 👎. An item is **confirmed when more than half of the trip's members vote yes**
  and **dropped when more than half vote no**. Votes can be changed; the latest counts. The
  proposer votes yes automatically and can withdraw their own item.
* **Join an activity** ("I'm in") separately from voting, so you can see who is coming even to
  things everyone agreed on.
* People who were invited but haven't joined can already **see the plan**, then join to vote.
* The Plan and Expenses tabs show what's waiting for you ("Plan · 2 to vote",
  "Expenses · 1 to approve").

Plan entries use the same signed ledger and the same `.ldtrip` file as expenses, so one share
syncs both.

## Why it can be trusted without a server
Blockchain ideas without mining:

* **Signed entries.** Each phone has an Ed25519 key pair (private key in the Keychain /
  Android Keystore-backed storage). Every entry is signed by its author, so nobody can add an
  approval in someone else's name.
* **Content-addressed.** An entry's id is the SHA-256 of its content. Editing an amount in a
  forwarded file changes the hash, and the signature no longer matches. Such entries are
  dropped on import ("ignored, signature did not match").
* **Linked history.** Each entry lists the entries its author had seen (`prev`), forming a
  chain of who-knew-what.
* **Same result everywhere.** Balances are derived from the set of entries with deterministic
  rules, so all phones that have the same entries show the same numbers, regardless of the
  order messages arrived in. Every share carries all entries, so one forwarded message brings
  anyone fully up to date.
* **Plans use a majority vote** of current members (see above); one vote per person, signed.
* **Consensus for money = everyone involved agrees.** Expenses and their removal need every involved
  person's approval; a single rejection blocks it. Repayments need the receiver. Entries cannot
  be edited; they are removed (with approval) and re-added.

## Limits to know
* **WhatsApp cannot be automated.** The app opens the share sheet; a person picks the group
  and taps send. Approvals reach others only when someone shares.
* **Joining is open to whoever has the invite file.** A trip is as private as the WhatsApp
  group you share it in. A stranger who joins can't touch money: they can't approve or reject
  expenses they aren't part of.
* **Lost phone = lost signing key.** Your history stays on others' phones, but you'd join
  again as a new person. Key backup/transfer is not implemented yet.
* **Not end-to-end private by itself.** The `.ldtrip` file is readable JSON; privacy comes from
  WhatsApp's encryption. It is integrity-protected (signatures), not encrypted.
* Clock times come from each phone and are only used for display.
* Not tested on physical devices yet (iOS "Open in LocalDrop" from WhatsApp in particular).

Code: `lib/ledger/` (events, signatures, state, codec, storage),
`lib/providers/ledger_controller.dart`, tests in `test/unit/ledger_test.dart` and
`test/widgets/expenses_test.dart`.
