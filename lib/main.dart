import 'package:flutter/material.dart';
import 'package:thermo_sim/thermosim_old.dart';
import 'softbody/simulation.dart';
//import 'cannon_physics/thermosim.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ThermoSim(),
    );
  }
}
