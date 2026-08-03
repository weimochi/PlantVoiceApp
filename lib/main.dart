import 'package:flutter/material.dart';
import 'screens/home_page.dart';

void main() {
  runApp(const PlantVoiceApp());
}

class PlantVoiceApp extends StatelessWidget {
  const PlantVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '生態樣區語音辨識系統',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const HomePage(),
    );
  }
}