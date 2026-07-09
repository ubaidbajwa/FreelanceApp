import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  // ProviderScope = Riverpod ka DI container (jaise Program.cs mein services register karna)
  runApp(const ProviderScope(child: FreelanceApp()));
}

class FreelanceApp extends StatelessWidget {
  const FreelanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FreelanceApp',
      debugShowCheckedModeBanner: false, // corner wala DEBUG banner hatao
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo, // ek color do, poori theme ban jati hai
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'FreelanceApp — Setup Complete ✅',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}