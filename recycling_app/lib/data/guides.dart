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
    this.manualSelectionOnly = false,
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
  final bool manualSelectionOnly;

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

const _film = DisposalGuide(
  actions: [], cautions: [], institution: _institution,
  documentTitle: '비닐류 — 사용자 제공 편집본', usageTerms: _terms,
  assetImagePath: 'assets/guides/film.png', manualSelectionOnly: true,
  sourceNote: '$_sourceNote 추가 문구 참고 표기: 수정구청·강동구청 분리배출 안내.',
);
const _mixedPackaging = DisposalGuide(
  actions: [], cautions: [],
  institution: '한국소비자원 (제공 이미지 내 내용 참고 표기)',
  documentTitle: '여러 재질이 섞인 포장 — 사용자 제공 안내',
  usageTerms: '제공 이미지에 원문 이용 조건 표기 없음 (원문 미확인)',
  assetImagePath: 'assets/guides/mixed_packaging.png', manualSelectionOnly: true,
  sourceNote: '사용자 제공 이미지입니다. 내용 참고 표기: 한국소비자원 「재질별 분리배출」. '
      '원문 URL·작성일·이용 조건은 확인되지 않았습니다.',
);

// 사용자 확인 품목에만 연결. 비닐/복합재질은 AI 클래스가 아닌 직접 선택 안내.
// 모르겠어요/유리/가스용기/기타 금속의 자료는 아직 미등록.
const disposalGuides = <String, DisposalGuide>{
  'paper_general': _paper,
  'paper_cardboard': _paper,
  'paper_carton': _paper,
  'plastic_clear_pet': _clearPet,
  'plastic_container': _plastic,
  'plastic_other': _plastic,
  'metal_can': _metalCan,
  'other_film': _film,
  'other_mixed': _mixedPackaging,
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
