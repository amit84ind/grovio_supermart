import 'package:flutter/material.dart';
import 'grovio_shared.dart';
import 'dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GrovioConfig.initFirebase();
  runApp(const GrovioCorporateDashboard());
}

class GrovioCorporateDashboard extends StatelessWidget {
  const GrovioCorporateDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grovio SuperMart | Store Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        primaryColor: const Color(0xFF2E7D32),
        useMaterial3: true,
      ),
      home: const UniversalDashboard(),
    );
  }
}
