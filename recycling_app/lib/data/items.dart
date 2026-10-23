enum ItemCategory { paper, plastic, metal, other }

extension ItemCategoryLabel on ItemCategory {
  String get label => switch (this) {
        ItemCategory.paper => '종이',
        ItemCategory.plastic => '플라스틱',
        ItemCategory.metal => '금속',
        ItemCategory.other => '기타',
      };
}

class DisposalItem {
  const DisposalItem(this.id, this.category, this.name);
  final String id;
  final ItemCategory category;
  final String name;
}

const disposalItems = <DisposalItem>[
  DisposalItem('paper_general', ItemCategory.paper, '종이·신문'),
  DisposalItem('paper_cardboard', ItemCategory.paper, '상자·골판지'),
  DisposalItem('paper_carton', ItemCategory.paper, '음료용 종이팩'),
  DisposalItem('paper_unknown', ItemCategory.paper, '모르겠어요'),
  DisposalItem('plastic_clear_pet', ItemCategory.plastic, '투명 음료·생수 페트병'),
  DisposalItem('plastic_container', ItemCategory.plastic, '기타 병·용기'),
  DisposalItem('plastic_other', ItemCategory.plastic, '기타 플라스틱'),
  DisposalItem('plastic_unknown', ItemCategory.plastic, '모르겠어요'),
  DisposalItem('metal_can', ItemCategory.metal, '음료·식품 캔'),
  DisposalItem('metal_pressurized', ItemCategory.metal, '스프레이·부탄가스 용기'),
  DisposalItem('metal_other', ItemCategory.metal, '기타 금속'),
  DisposalItem('metal_unknown', ItemCategory.metal, '모르겠어요'),
  DisposalItem('other_film', ItemCategory.other, '비닐'),
  DisposalItem('other_glass', ItemCategory.other, '유리'),
  DisposalItem('other_mixed', ItemCategory.other, '여러 재질이 섞인 포장'),
  DisposalItem('other_unknown', ItemCategory.other, '모르겠어요'),
];

DisposalItem itemById(String id) =>
    disposalItems.firstWhere((item) => item.id == id);

class ItemSelection {
  ItemSelection({required this.category, required this.itemId}) {
    if (itemById(itemId).category != category) {
      throw ArgumentError('종류와 세부 품목이 일치하지 않습니다.');
    }
  }
  final ItemCategory category;
  final String itemId;
  DisposalItem get item => itemById(itemId);
}
