import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() => runApp(const FastPollApp());

class FastPollApp extends StatelessWidget {
  const FastPollApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ImDownForWhatever',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
