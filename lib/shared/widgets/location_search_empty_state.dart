import 'package:flutter/material.dart';

import 'citiride_empty_state.dart';

class LocationSearchEmptyState extends StatelessWidget {
  const LocationSearchEmptyState({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final query = this.query.trim();

    return CitirideEmptyState(
      icon: Icons.travel_explore_rounded,
      title: 'No result found for your search',
      subtitle: 'Try another place name, address, or landmark.',
      detail: query.isEmpty ? null : query,
    );
  }
}
