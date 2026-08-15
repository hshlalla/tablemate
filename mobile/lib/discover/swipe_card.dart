import 'package:flutter/material.dart';

class SwipeCard extends StatelessWidget {
  const SwipeCard({super.key, required this.name, this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null)
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          Align(
            alignment: url != null ? Alignment.bottomCenter : Alignment.center,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: url != null ? Colors.black54 : null,
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: url != null ? Colors.white : null,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
