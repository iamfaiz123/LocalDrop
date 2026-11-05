import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ad unit configuration. Real IDs are injected at build time:
///
///   flutter build apk --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-xxx/yyy \
///                     --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-xxx/zzz
///
/// Without them Google's official *test* units are used, which always serve
/// test ads and never earn money. Ads are OFF by default (planned for a
/// later phase); `--dart-define=ADS_ENABLED=true` turns them on. Ad slots stay
/// in the layout and take no space while ads are off.
class AdConfig {
  /// Off until the advertising phase; build with --dart-define=ADS_ENABLED=true to turn on.
  static const enabled = bool.fromEnvironment('ADS_ENABLED', defaultValue: false);

  // Google sample ad units: https://developers.google.com/admob/flutter/test-ads
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/9214589741';
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2435281174';
  static const _testInterstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';

  static const _bannerAndroid = String.fromEnvironment('ADMOB_BANNER_ANDROID', defaultValue: _testBannerAndroid);
  static const _bannerIos = String.fromEnvironment('ADMOB_BANNER_IOS', defaultValue: _testBannerIos);
  static const _interstitialAndroid =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID', defaultValue: _testInterstitialAndroid);
  static const _interstitialIos = String.fromEnvironment('ADMOB_INTERSTITIAL_IOS', defaultValue: _testInterstitialIos);

  static String get bannerUnitId => Platform.isIOS ? _bannerIos : _bannerAndroid;
  static String get interstitialUnitId => Platform.isIOS ? _interstitialIos : _interstitialAndroid;
  static bool get usingTestUnits => bannerUnitId == _testBannerAndroid || bannerUnitId == _testBannerIos;

  /// Minimum time between full-screen ads.
  static const interstitialInterval = Duration(minutes: 3);
}

/// Advertising abstraction so the app (and tests) work without an ad SDK.
abstract class AdService extends ChangeNotifier {
  /// True once consent is resolved and the SDK can serve ads.
  bool get ready;

  /// Whether a "Privacy settings" entry must be offered (GDPR regions).
  bool get privacyOptionsRequired;

  String get bannerUnitId;

  Future<void> initialize();

  /// Shows a full-screen ad at a natural break (e.g. after a session ends),
  /// respecting the frequency cap. Completes when the ad is dismissed or
  /// immediately if none is available. Never throws.
  Future<void> showInterstitialAtBreak();

  Future<void> showPrivacyOptions();
}

/// Used in tests, on unsupported platforms and when ads are disabled.
class NoAdService extends AdService {
  @override
  bool get ready => false;
  @override
  bool get privacyOptionsRequired => false;
  @override
  String get bannerUnitId => '';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> showInterstitialAtBreak() async {}
  @override
  Future<void> showPrivacyOptions() async {}
}

/// Google AdMob with the User Messaging Platform (GDPR/consent) flow.
///
/// LocalDrop works offline: when there is no internet (typical on a hotspot
/// without mobile data) ads simply don't load and take no space. Ads never
/// block or delay sharing.
class AdMobService extends AdService with WidgetsBindingObserver {
  bool _ready = false;
  bool _initializing = false;
  bool _privacyRequired = false;
  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;
  DateTime? _lastInterstitial;

  @override
  bool get ready => _ready;
  @override
  bool get privacyOptionsRequired => _privacyRequired;
  @override
  String get bannerUnitId => AdConfig.bannerUnitId;

  @override
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    await _gatherConsentAndStart();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Connectivity often appears later (e.g. host turns mobile data on).
    if (state == AppLifecycleState.resumed && !_ready) unawaited(_gatherConsentAndStart());
  }

  Future<void> _gatherConsentAndStart() async {
    if (_ready || _initializing) return;
    _initializing = true;
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
          if (error != null) debugPrint('LocalDrop ads: consent form error ${error.message}');
        });
        if (!done.isCompleted) done.complete();
      },
      (FormError error) {
        // Usually "offline": fall back to consent cached from a previous run.
        debugPrint('LocalDrop ads: consent update failed (${error.message})');
        if (!done.isCompleted) done.complete();
      },
    );
    try {
      await done.future.timeout(const Duration(seconds: 20));
      if (await ConsentInformation.instance.canRequestAds()) {
        await MobileAds.instance.initialize();
        _ready = true;
        _privacyRequired = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
            PrivacyOptionsRequirementStatus.required;
        _loadInterstitial();
        notifyListeners();
      }
    } on Exception catch (e) {
      debugPrint('LocalDrop ads: not started ($e)');
    } finally {
      _initializing = false;
    }
  }

  void _loadInterstitial() {
    if (!_ready || _interstitial != null || _loadingInterstitial) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          debugPrint('LocalDrop ads: interstitial not loaded (${error.message})');
        },
      ),
    );
  }

  @override
  Future<void> showInterstitialAtBreak() async {
    final ad = _interstitial;
    final last = _lastInterstitial;
    if (!_ready || ad == null) {
      _loadInterstitial();
      return;
    }
    if (last != null && DateTime.now().difference(last) < AdConfig.interstitialInterval) return;
    _interstitial = null;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
        _loadInterstitial();
      },
    );
    _lastInterstitial = DateTime.now();
    await ad.show();
    await closed.future.timeout(const Duration(minutes: 2), onTimeout: () {});
  }

  @override
  Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (error != null) debugPrint('LocalDrop ads: privacy form error ${error.message}');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _interstitial?.dispose();
    super.dispose();
  }
}

/// Picks the right implementation for this platform/build.
AdService createAdService() =>
    (AdConfig.enabled && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) ? AdMobService() : NoAdService();
