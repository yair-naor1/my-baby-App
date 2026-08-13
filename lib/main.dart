import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyFirstApp());
}

class MyFirstApp extends StatelessWidget {
  const MyFirstApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color.fromARGB(255, 34, 12, 201),
        appBar: AppBar(
          backgroundColor: const Color.fromARGB(255, 231, 118, 221),
          foregroundColor: const Color.fromARGB(255, 3, 8, 1),
          title: const Text('My First App'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'A needed moment for every Gever.',
                style: TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 216, 205, 205),
                foregroundColor: const Color.fromARGB(153, 76, 162, 212),
              ),
                onPressed: () {
                  print('You pressed the button!, Balls are not itchy anymoree');
                },
                child: const Text('Itch them balls'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}