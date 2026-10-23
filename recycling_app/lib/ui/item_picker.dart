import 'package:flutter/material.dart';
import '../data/items.dart';

Future<ItemSelection?> showItemPicker(BuildContext context, {
  ItemSelection? initialSelection, ItemCategory? initialCategory,
  String title = '종류 확인 / 세부 품목 선택',
}) {
  var category = initialSelection?.category ?? initialCategory;
  String? itemId = initialSelection?.itemId;
  return showModalBottomSheet<ItemSelection>(
    context: context, isScrollControlled: true, showDragHandle: true,
    builder: (context) => StatefulBuilder(builder: (context, update) {
      return SafeArea(child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20,
          MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SizedBox(height: MediaQuery.sizeOf(context).height * 0.65,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(child: ListView(children: [
              const Text('종류를 선택해 주세요.'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final value in ItemCategory.values)
                  ChoiceChip(label: Text(value.label), selected: category == value,
                    onSelected: (_) => update(() {
                      if (category != value) {
                        category = value;
                        itemId = null; // 다른 종류의 이전 품목·안내 선택을 재사용하지 않음
                      }
                    })),
              ]),
              const SizedBox(height: 16),
              if (category != null) ...[
                const Text('세부 품목을 선택해 주세요.'),
                for (final item in disposalItems.where((i) => i.category == category))
                  ListTile(key: ValueKey('item-${item.id}'),
                    title: Text(item.name),
                    leading: Icon(itemId == item.id ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: itemId == item.id ? const Color(0xFF20845A) : null),
                    onTap: () => update(() => itemId = item.id)),
              ],
            ])),
            const SizedBox(height: 8),
            FilledButton(onPressed: category == null || itemId == null ? null : () {
              Navigator.pop(context, ItemSelection(category: category!, itemId: itemId!));
            }, child: const Text('이 품목으로 확인')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          ]),
        ),
      ));
    }),
  );
}
