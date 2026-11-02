import 'package:flutter/material.dart';
import '../theme.dart';
import 'screens.dart';

class LocalDropApp extends StatelessWidget {
  const LocalDropApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LocalDrop',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const LocalDropHome(),
  );
}

class LocalDropHome extends StatefulWidget {
  const LocalDropHome({super.key});
  @override
  State<LocalDropHome> createState() => _LocalDropHomeState();
}

class _LocalDropHomeState extends State<LocalDropHome> {
  int selected = 0;

  final pages = const [
    LandingScreen(),
    CreateSessionScreen(),
    HostLobbyScreen(),
    GalleryScreen(),
    UploadsScreen(),
    DashboardScreen(),
    SettingsScreen(),
    JoinSessionScreen(),
    JoinDetailsScreen(),
    StartingScreen(),
    MediaViewerScreen(),
    SelectionScreen(),
  ];

  final names = const [
    'Home', 'Create session', 'Host lobby', 'Gallery', 'Uploads', 'Dashboard',
    'Host controls', 'Join session', 'Join details', 'Starting session',
    'Media viewer', 'Select & download'
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: const BoxDecoration(color: AppColors.bg),
          child: Row(children: [
            const Icon(Icons.cloud_outlined, color: AppColors.primary, size: 27),
            const SizedBox(width: 8),
            const Text('LocalDrop', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
              child: const Text('UI PREVIEW', style: TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w800, letterSpacing: .8)),
            ),
          ]),
        ),
        Expanded(child: pages[selected]),
        Container(
          height: 76,
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            scrollDirection: Axis.horizontal,
            itemCount: names.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => setState(() => selected = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(color: selected == i ? AppColors.lavender : Colors.transparent, borderRadius: BorderRadius.circular(13)),
                child: Center(child: Text(names[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected == i ? AppColors.primaryDark : AppColors.muted))),
              ),
            ),
          ),
        ),
      ]),
    ),
  );
}
