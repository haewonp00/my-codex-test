// 이미지·문구는 제공된 자료만 사용합니다. 확인되지 않은 원문 URL은 등록하지 않습니다.
class DisposalGuide {
  const DisposalGuide({
    required this.actions,
    required this.cautions,
    required this.institution,
    required this.documentTitle,
    required this.usageTerms,
    this.verifiedReferenceDate,
    this.officialImageUrl,
    this.sourceUrl,
    this.assetImagePath,
    this.sourceNote,
    this.sourceVerified = false,
  });
  final List<String> actions;
  final List<String> cautions;
  final String institution;
  final String documentTitle;
  final String usageTerms;
  // 원문에서 직접 확인한 날짜만 입력. 이미지에 적힌 날짜는 sourceNote에 구분.
  final String? verifiedReferenceDate;
  final String? officialImageUrl;
  final String? sourceUrl;
  final String? assetImagePath;
  final String? sourceNote;
  final bool sourceVerified;

  bool get hasImage =>
      (assetImagePath?.isNotEmpty ?? false) ||
      officialWebUri(officialImageUrl) != null;

  bool get isRegistered =>
      (actions.isNotEmpty || hasImage) &&
      institution.trim().isNotEmpty &&
      documentTitle.trim().isNotEmpty &&
      usageTerms.trim().isNotEmpty;
}

const _institution = '용인시 자원순환과 (제공 이미지 내 표기)';
const _terms = '공공누리 제1유형·일부 발췌 및 편집 (이미지 내 표기, 원문 미확인)';
const _sourceNote = '사용자 제공 편집 이미지입니다. 원자료 날짜는 이미지에 '
    '2025/07/03으로 표기되어 있으며, 원문·이용 조건·적용 지역은 별도 확인이 필요합니다.';

const _paper = DisposalGuide(
  actions: [], cautions: [], institution: _institution,
  documentTitle: '종이류 — 사용자 제공 편집본', usageTerms: _terms,
  assetImagePath: 'assets/guides/paper.png',
  sourceNote: '$_sourceNote 추가 문구 참고 표기: 법제처 찾기쉬운 생활법령정보. '
      '종이·상자·종이팩이 함께 있는 공통 이미지이므로 해당 품목 문구를 구분해서 확인해 주세요.',
);
const _metalCan = DisposalGuide(
  actions: [], cautions: [], institution: _institution,
  documentTitle: '금속캔 — 사용자 제공 편집본', usageTerms: _terms,
  assetImagePath: 'assets/guides/metal_can.png',
  sourceNote: '$_sourceNote 추가 문구 참고 표기: 용산구청 재활용품 분리배출 가이드라인.',
);
const _clearPet = DisposalGuide(
  actions: [], cautions: [], institution: _institution,
  documentTitle: '투명(무색) 페트병 — 사용자 제공 편집본', usageTerms: _terms,
  assetImagePath: 'assets/guides/clear_pet.png', sourceNote: _sourceNote,
);
const _plastic = DisposalGuide(
  actions: [], cautions: [], institution: _institution,
  documentTitle: '플라스틱류 — 사용자 제공 편집본', usageTerms: _terms,
  assetImagePath: 'assets/guides/plastic.png', sourceNote: _sourceNote,
);

// 사용자 확인 품목에만 연결. 모르겠어요/비닐/유리/혼합재질/가스용기 등은 미등록.
const disposalGuides = <String, DisposalGuide>{
  'paper_general': _paper,
  'paper_cardboard': _paper,
  'paper_carton': _paper,
  'plastic_clear_pet': _clearPet,
  'plastic_container': _plastic,
  'plastic_other': _plastic,
  'metal_can': _metalCan,
};

DisposalGuide? guideFor(String itemId) {
  final guide = disposalGuides[itemId];
  return guide != null && guide.isRegistered ? guide : null;
}

Uri? officialWebUri(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return uri;
}
