// 공식 자료를 확인한 후 이 파일에만 등록합니다. 현재 등록 자료는 없습니다.
// YOLO 클래스/가중치와 별개인 사용자 선택용 안내 데이터입니다.
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
  });
  final List<String> actions;
  final List<String> cautions;
  final String institution;
  final String documentTitle;
  final String usageTerms;
  // 실제 자료에서 확인한 작성일/기준일만 입력합니다. 확인되지 않으면 null.
  final String? verifiedReferenceDate;
  final String? officialImageUrl;
  final String? sourceUrl;

  bool get isRegistered =>
      actions.isNotEmpty &&
      institution.trim().isNotEmpty &&
      documentTitle.trim().isNotEmpty &&
      usageTerms.trim().isNotEmpty;
}

// Key: items.dart의 실제 품목 ID. 확인되지 않은 문구·이미지·링크는 넣지 않습니다.
const disposalGuides = <String, DisposalGuide>{};

DisposalGuide? guideFor(String itemId) {
  final guide = disposalGuides[itemId];
  return guide != null && guide.isRegistered ? guide : null;
}

Uri? officialWebUri(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty ||
      (uri.scheme != 'https' && uri.scheme != 'http')) return null;
  return uri;
}
