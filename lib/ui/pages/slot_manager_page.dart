import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../widgets/app_card.dart';
import '../widgets/section_header.dart';

class SlotManagerPage extends StatelessWidget {
  const SlotManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Slot Manager',
          subtitle: 'Organize, label, and switch active tag profiles.',
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width > 1200
                  ? 4
                  : width > 900
                  ? 3
                  : width > 640
                  ? 2
                  : 1;
              return GridView.builder(
                padding: const EdgeInsets.only(bottom: 12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.15,
                ),
                itemCount: 8,
                itemBuilder: (context, index) {
                  final slotNumber = index + 1;
                  final isActive = slotNumber == 3;
                  final isEmpty = slotNumber == 6 || slotNumber == 8;
                  return AppCard(
                    onTap: () {},
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Slot $slotNumber',
                              style: theme.textTheme.labelLarge,
                            ),
                            const Spacer(),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppPalette.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'ACTIVE',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppPalette.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isEmpty ? 'Empty slot' : 'MIFARE Classic 1K',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isEmpty
                              ? 'Tap to write or import a tag profile.'
                              : 'UID 04:A1:8B:${20 + slotNumber}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              isEmpty
                                  ? Icons.add_circle_outline
                                  : Icons.memory_rounded,
                              color: isEmpty
                                  ? AppPalette.secondary
                                  : AppPalette.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isEmpty ? 'Add profile' : 'Clone / Emulate',
                              style: theme.textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
