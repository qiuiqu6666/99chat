class AiAssistantMarkdown {
  AiAssistantMarkdown._();

  static final _numberedTitle = RegExp(
    r'\*\*(\d+\s*[\.、．][^*]{1,40})\*\*',
  );
  static final _jammedBullet = RegExp(
    r'(?:(?<=\n)|(?<=[。！？]))-\s*(`|[A-Za-z][A-Za-z0-9]{5,})',
  );
  static final _closingBeat = RegExp(
    r'。(整体看|需要提醒)',
  );

  static String normalize(String raw) {
    var text = raw.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) {
      return text;
    }
    text = text.replaceAllMapped(_numberedTitle, (match) {
      final title = match.group(1)!.trim();
      return '\n\n**$title**\n\n';
    });
    text = text.replaceAllMapped(_jammedBullet, (match) {
      return '\n- ${match.group(1)}';
    });
    text = text.replaceAllMapped(_closingBeat, (match) {
      return '。\n\n${match.group(1)}';
    });
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
