import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Supabase.initialize(
    url: 'https://bayhdtjxtvmefclngraf.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJheWhkdGp4dHZtZWZjbG5ncmFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDg0NTkzNDksImV4cCI6MjA2NDAzNTM0OX0.gwPzeh7k-x4y-vOYRvbsVupCFBQhzf9Q9CSTOA6nNAw',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'El Búho Turismo',
      debugShowCheckedModeBanner: false, // 👈 Esto elimina la cinta "DEBUG"
      home: AuthPageWrapper(),
    );
  }
}

class AuthPageWrapper extends StatefulWidget {
  const AuthPageWrapper({super.key});

  @override
  State<AuthPageWrapper> createState() => _AuthPageWrapperState();
}

class _AuthPageWrapperState extends State<AuthPageWrapper> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final session = Supabase.instance.client.auth.currentSession;

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      FlutterNativeSplash.remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const AuthPage();
  }
}
