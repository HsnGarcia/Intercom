import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/intercom_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MotoMeshApp());
}

class MotoMeshApp extends StatelessWidget {
  const MotoMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => IntercomController()..initialize(),
      child: MaterialApp(
        title: 'MotoMesh Intercom',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF6B00),
            secondary: Color(0xFF00E676),
            surface: Color(0xFF161B22),
            error: Color(0xFFFF3B30),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF161B22),
            elevation: 0,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
