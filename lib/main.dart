import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/home_screen.dart';
import 'services/document_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final storage = DocumentStorage();
  await storage.init();
  runApp(MoneApp(storage: storage));
}

class MoneApp extends StatelessWidget {
  const MoneApp({super.key, required this.storage});

  final DocumentStorage storage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mone App · Документы и техкарты',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A1525),
          primary: const Color(0xFF4A1525),
          secondary: const Color(0xFF8B263E),
          surface: Colors.white,
        ),
      ),
      home: HomeScreen(storage: storage),
    );
  }
}
