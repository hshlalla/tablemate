import 'package:flutter/material.dart';

class SwipeCard extends StatelessWidget {
  const SwipeCard({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(child: Text(name, style: Theme.of(context).textTheme.headlineMedium)),
    );
  }
}
