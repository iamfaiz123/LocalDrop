import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../providers/session_controller.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'join_details_screen.dart';

class JoinSessionScreen extends StatefulWidget {
  /// Disable the camera (widget tests / devices without a camera).
  final bool enableCamera;
  const JoinSessionScreen({super.key, this.enableCamera = true});
  @override
  State<JoinSessionScreen> createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends State<JoinSessionScreen> {
  late bool _scan = widget.enableCamera;
  final _address = TextEditingController();
  bool _busy = false;
  String? _error;
  MobileScannerController? _scanner;

  @override
  void initState() {
    super.initState();
    if (_scan) _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  }

  @override
  void dispose() {
    _scanner?.dispose();
    _address.dispose();
    super.dispose();
  }

  void _setScan(bool on) {
    if (on == _scan) return;
    setState(() {
      _scan = on;
      _error = null;
      if (on) {
        _scanner ??= MobileScannerController(formats: const [BarcodeFormat.qrCode]);
      } else {
        _scanner?.dispose();
        _scanner = null;
      }
    });
  }

  Future<void> _connect(String address) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<SessionController>();
    await _scanner?.stop();
    try {
      final (base, info) = await session.probe(address);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => JoinDetailsScreen(base: base, info: info)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_scan) await _scanner?.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppFrame(
        child: PageShell(
          title: 'Join session',
          subtitle: 'Scan your friend’s QR code to join.',
          child: Column(children: [
            Row(children: [
              Pill('Scan QR', selected: _scan, onTap: widget.enableCamera ? () => _setScan(true) : null),
              const SizedBox(width: 8),
              Pill('Enter address', selected: !_scan, onTap: () => _setScan(false)),
            ]),
            const SizedBox(height: 20),
            if (_scan)
              Container(
                height: 310,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: const Color(0xFF242333), borderRadius: BorderRadius.circular(24)),
                child: Stack(alignment: Alignment.center, children: [
                  if (_scanner != null)
                    Positioned.fill(
                      child: MobileScanner(
                        controller: _scanner,
                        onDetect: (capture) {
                          final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                          if (raw != null && !_busy) _connect(raw);
                        },
                        errorBuilder: (context, error) => _CameraError(error: error, onManual: () => _setScan(false)),
                        placeholderBuilder: (_) => const Icon(Icons.qr_code_2, size: 170, color: Colors.white24),
                      ),
                    ),
                  IgnorePointer(
                    child: Container(
                        width: 210,
                        height: 210,
                        decoration:
                            BoxDecoration(border: Border.all(color: AppColors.primary, width: 4), borderRadius: BorderRadius.circular(24))),
                  ),
                  Positioned(
                    bottom: 23,
                    child: _busy
                        ? const Row(children: [
                            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 8),
                            Text('Connecting…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                          ])
                        : const Text('Align the QR code within the frame',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ]),
              ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              InfoBanner(_error!, error: true, icon: Icons.wifi_off_rounded),
            ],
            const SizedBox(height: 18),
            Text(_scan ? 'Or enter the session address manually' : 'Enter the address shown on the host’s screen',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              key: const Key('address'),
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              onTap: () => _setScan(false),
              onSubmitted: _connect,
              decoration: const InputDecoration(hintText: 'http://192.168.x.x:8080', prefixIcon: Icon(Icons.link)),
            ),
            if (!_scan) ...[
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Connect',
                icon: Icons.arrow_forward_rounded,
                loading: _busy,
                onPressed: () => _connect(_address.text),
              ),
              const SizedBox(height: 14),
              const Text(
                'Make sure you are connected to the host’s hotspot or the same Wi-Fi network.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ]),
        ),
      );
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onManual;
  const _CameraError({required this.error, required this.onManual});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 40),
        const SizedBox(height: 12),
        Text(
          denied
              ? 'Camera access is off. Allow it in Settings to scan, or enter the address instead.'
              : 'The camera is unavailable (${error.errorCode.name}). Enter the address instead.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: onManual, child: const Text('Enter address')),
      ]),
    );
  }
}
