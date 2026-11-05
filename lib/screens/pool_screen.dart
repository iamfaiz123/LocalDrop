import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pool_controller.dart';
import '../providers/session_controller.dart';
import '../services/device_library.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ad_banner.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'gallery_screen.dart' show pickAndUpload;

/// "Drop to pool": swipe through your own photos (right = share, left = skip)
/// or select several at once. Items sent here appear in the shared gallery
/// for everyone once uploaded.
class PoolScreen extends StatefulWidget {
  const PoolScreen({super.key});
  @override
  State<PoolScreen> createState() => _PoolScreenState();
}

class _PoolScreenState extends State<PoolScreen> {
  bool _swipeMode = true;
  late final PoolController _pool = context.read<PoolController>();

  @override
  void initState() {
    super.initState();
    final id = context.read<SessionController>().session?.id;
    if (id != null) WidgetsBinding.instance.addPostFrameCallback((_) => _pool.open(id));
    _pool.addListener(_showNotice);
  }

  @override
  void dispose() {
    _pool.removeListener(_showNotice);
    super.dispose();
  }

  void _showNotice() {
    final n = _pool.notice;
    if (n != null && mounted) {
      _pool.clearNotice();
      showToast(context, n, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pool = context.watch<PoolController>();
    final s = context.watch<SessionController>();
    final canUpload = s.isHost || (s.session?.uploadsOpen ?? true);
    Widget body;
    if (!canUpload) {
      body = const StateMessage(
          icon: Icons.block, title: 'Uploads are turned off', detail: 'The host has turned off sharing for participants.');
    } else if (pool.access == null || (pool.loading && pool.deck.isEmpty && pool.libraryCount == 0)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!pool.hasAccess) {
      body = _NoAccess(library: pool.library, onRetry: pool.reload);
    } else {
      body = _swipeMode ? const _SwipeDeck() : const _SelectGrid();
    }
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Drop to pool', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.7)),
              const SizedBox(height: 5),
              Text(
                _swipeMode ? 'Swipe right to share, left to skip.' : 'Tap photos and videos to share them.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Pill('Swipe', selected: _swipeMode, onTap: () => setState(() => _swipeMode = true)),
                const SizedBox(width: 8),
                Pill('Select', selected: !_swipeMode, onTap: () => setState(() => _swipeMode = false)),
                const Spacer(),
                if (pool.hasAccess)
                  Text('${pool.shared.length} shared',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
              if (pool.access == LibraryAccess.limited) ...[
                const SizedBox(height: 12),
                InfoBanner('LocalDrop can only see the photos you allowed.', action: 'Manage', onAction: () async {
                  await pool.library.manageLimitedSelection();
                  await pool.reload();
                }),
              ],
            ]),
          ),
          Expanded(child: body),
        ]),
      ),
      // Ad-friendly: reserved slot, renders nothing while ads are off.
      bottomNavigationBar: const AdBanner(),
    );
  }
}

class _NoAccess extends StatelessWidget {
  final DeviceLibrary library;
  final Future<void> Function() onRetry;
  const _NoAccess({required this.library, required this.onRetry});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const StateMessage(
            icon: Icons.photo_library_outlined,
            title: 'Allow access to your photos',
            detail: 'LocalDrop shows your photos and videos here so you can swipe the ones you want to share. '
                'Nothing leaves your phone until you swipe right.',
          ),
          PrimaryButton(
              label: 'Open settings',
              icon: Icons.settings_outlined,
              onPressed: () async {
                await library.openSettings();
              }),
          const SizedBox(height: 10),
          OutlineAction(label: 'Try again', icon: Icons.refresh, onPressed: onRetry),
          const SizedBox(height: 10),
          TextButton(onPressed: () => pickAndUpload(context), child: const Text('Choose files instead')),
        ]),
      );
}

// ---------------------------------------------------------------- swipe

class _SwipeDeck extends StatelessWidget {
  const _SwipeDeck();

  /// Buttons animate the card like a swipe; falls back to a direct decision.
  static void _decide(BuildContext context, String id, bool share) {
    final card = SwipeCard.of(context, id);
    if (card != null) {
      card.fling(share);
    } else {
      final pool = context.read<PoolController>();
      share ? pool.shareCurrent() : pool.skipCurrent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pool = context.watch<PoolController>();
    final current = pool.current;
    if (current == null) {
      if (pool.loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            StateMessage(
              icon: Icons.check_circle_outline,
              title: pool.libraryCount == 0 ? 'No photos or videos on this phone' : 'You’re all caught up',
              detail: pool.libraryCount == 0 ? null : 'You reviewed everything. ${pool.shared.length} shared to the pool.',
            ),
            if (pool.canUndo) TextButton(onPressed: pool.undo, child: const Text('Undo last')),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(children: [
        Expanded(
          child: Stack(alignment: Alignment.center, children: [
            if (pool.next != null)
              Positioned.fill(
                child: Transform.scale(scale: .94, child: _AssetCard(key: ValueKey('n-${pool.next!.id}'), asset: pool.next!)),
              ),
            Positioned.fill(
              child: SwipeCard(
                key: ValueKey(current.id),
                onSwipeRight: pool.shareCurrent,
                onSwipeLeft: pool.skipCurrent,
                child: _AssetCard(asset: current),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Text('${pool.remaining} left to review', style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _RoundButton(
            key: const Key('skip'),
            icon: Icons.close_rounded,
            color: AppColors.red,
            tooltip: 'Skip',
            onTap: () => _decide(context, current.id, false),
          ),
          const SizedBox(width: 22),
          _RoundButton(
            key: const Key('undo'),
            icon: Icons.undo_rounded,
            color: AppColors.muted,
            small: true,
            tooltip: 'Undo',
            onTap: pool.canUndo ? pool.undo : null,
          ),
          const SizedBox(width: 22),
          _RoundButton(
            key: const Key('share'),
            icon: Icons.check_rounded,
            color: AppColors.primary,
            filled: true,
            tooltip: 'Share to pool',
            onTap: () => _decide(context, current.id, true),
          ),
        ]),
      ]),
    );
  }
}

/// Draggable card: drag past a threshold (or fling) to decide.
class SwipeCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;
  const SwipeCard({super.key, required this.child, required this.onSwipeRight, required this.onSwipeLeft});

  static final _registry = <String, SwipeCardState>{};
  static SwipeCardState? of(BuildContext context, String id) => _registry[id];

  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard> with SingleTickerProviderStateMixin {
  Offset _drag = Offset.zero;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Offset>? _tween;
  bool _decided = false;

  String? get _id => (widget.key is ValueKey) ? (widget.key! as ValueKey).value.toString() : null;

  @override
  void initState() {
    super.initState();
    final id = _id;
    if (id != null) SwipeCard._registry[id] = this;
    _anim.addListener(() => setState(() => _drag = _tween?.value ?? _drag));
  }

  @override
  void dispose() {
    final id = _id;
    if (id != null && SwipeCard._registry[id] == this) SwipeCard._registry.remove(id);
    _anim.dispose();
    super.dispose();
  }

  void _animateTo(Offset target, VoidCallback? then) {
    _tween = Tween(begin: _drag, end: target).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0).whenComplete(() => then?.call());
  }

  /// Programmatic swipe (buttons). Returns null-safe for chaining.
  void fling(bool right) {
    if (_decided) return;
    _decided = true;
    final w = MediaQuery.sizeOf(context).width;
    _animateTo(Offset(right ? w * 1.5 : -w * 1.5, 40), right ? widget.onSwipeRight : widget.onSwipeLeft);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final progress = (_drag.dx / (w * .3)).clamp(-1.0, 1.0);
    return GestureDetector(
      onPanUpdate: _decided ? null : (d) => setState(() => _drag += d.delta),
      onPanEnd: _decided
          ? null
          : (d) {
              final v = d.velocity.pixelsPerSecond.dx;
              if (_drag.dx > w * .28 || v > 900) {
                fling(true);
              } else if (_drag.dx < -w * .28 || v < -900) {
                fling(false);
              } else {
                _animateTo(Offset.zero, null);
              }
            },
      child: Transform.translate(
        offset: _drag,
        child: Transform.rotate(
          angle: _drag.dx / w * .35,
          child: Stack(fit: StackFit.expand, children: [
            widget.child,
            if (progress > 0) _Stamp(label: 'SHARE', color: AppColors.green, opacity: progress, left: true),
            if (progress < 0) _Stamp(label: 'SKIP', color: AppColors.red, opacity: -progress, left: false),
          ]),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  final String label;
  final Color color;
  final double opacity;
  final bool left;
  const _Stamp({required this.label, required this.color, required this.opacity, required this.left});
  @override
  Widget build(BuildContext context) => Positioned(
        top: 28,
        left: left ? 24 : null,
        right: left ? null : 24,
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: left ? -.25 : .25,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: color, width: 4), borderRadius: BorderRadius.circular(12)),
              child: Text(label, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
          ),
        ),
      );
}

class _AssetCard extends StatelessWidget {
  final DeviceAsset asset;
  const _AssetCard({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    final pool = context.read<PoolController>();
    final dur = asset.duration;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x2239266F), blurRadius: 24, offset: Offset(0, 10))],
      ),
      padding: const EdgeInsets.all(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(fit: StackFit.expand, children: [
          FutureBuilder<Uint8List?>(
            future: pool.thumbnail(asset, 900),
            builder: (_, snap) => snap.data == null
                ? Container(
                    color: const Color(0xFFDCD6F5),
                    child: Icon(asset.isVideo ? Icons.movie_outlined : Icons.photo_outlined, color: AppColors.primary, size: 40),
                  )
                : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 110,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x99000000)])),
            ),
          ),
          if (asset.isVideo)
            const Center(
              child: CircleAvatar(
                  radius: 28, backgroundColor: Color(0x99000000), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34)),
            ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Row(children: [
              Expanded(
                child: Text(formatTimestamp(asset.createdAt.millisecondsSinceEpoch),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              if (asset.isVideo)
                Text('${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool filled;
  final bool small;
  final String tooltip;
  final VoidCallback? onTap;
  const _RoundButton(
      {super.key, required this.icon, required this.color, required this.tooltip, this.onTap, this.filled = false, this.small = false});
  @override
  Widget build(BuildContext context) {
    final size = small ? 48.0 : 66.0;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? .4 : 1,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: filled ? [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 16, offset: const Offset(0, 6))] : null,
          ),
          child: Material(
            color: filled ? color : Colors.white,
            shape: CircleBorder(side: BorderSide(color: filled ? color : AppColors.border, width: 1.5)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: size, height: size, child: Icon(icon, color: filled ? Colors.white : color, size: small ? 22 : 32)),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- select

class _SelectGrid extends StatefulWidget {
  const _SelectGrid();
  @override
  State<_SelectGrid> createState() => _SelectGridState();
}

class _SelectGridState extends State<_SelectGrid> {
  final List<DeviceAsset> _items = [];
  final Set<String> _selected = {};
  int _page = 0;
  bool _loading = false;
  bool _end = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _end) return;
    setState(() => _loading = true);
    final pool = context.read<PoolController>();
    try {
      final page = await pool.gridPage(_page++);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        if (page.length < 90) _end = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final pool = context.read<PoolController>();
    final list = _items.where((a) => _selected.contains(a.id)).toList();
    setState(() => _sending = true);
    final n = await pool.sendMany(list);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _selected.clear();
    });
    showToast(context, '$n item${n == 1 ? '' : 's'} added to the pool');
  }

  @override
  Widget build(BuildContext context) {
    final pool = context.watch<PoolController>();
    return Column(children: [
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) _more();
            return false;
          },
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: .82),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final a = _items[i];
              final inPool = pool.shared.contains(a.id);
              final sel = _selected.contains(a.id);
              return GestureDetector(
                key: ValueKey('grid-${a.id}'),
                onTap: inPool ? null : () => setState(() => sel ? _selected.remove(a.id) : _selected.add(a.id)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(fit: StackFit.expand, children: [
                    FutureBuilder<Uint8List?>(
                      future: pool.thumbnail(a, 300),
                      builder: (_, snap) => snap.data == null
                          ? Container(color: const Color(0xFFDCD6F5))
                          : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                    if (inPool) Container(color: Colors.white.withValues(alpha: .55)),
                    if (a.isVideo) const Positioned(left: 6, bottom: 6, child: Icon(Icons.videocam, color: Colors.white, size: 18)),
                    Positioned(
                      right: 7,
                      top: 7,
                      child: inPool
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(10)),
                              child: const Text('In pool', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                            )
                          : CircleAvatar(
                              radius: 11,
                              backgroundColor: sel ? AppColors.primary : Colors.black26,
                              child: sel
                                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                                  : Container(
                                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                            ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: PrimaryButton(
          label: _selected.isEmpty ? 'Select photos & videos' : 'Send ${_selected.length} to pool',
          icon: Icons.send_rounded,
          loading: _sending,
          onPressed: _selected.isEmpty ? null : _send,
        ),
      ),
    ]);
  }
}
