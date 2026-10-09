import 'package:flutter/material.dart';

class BotanicalMarkdownText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final Color primaryColor;

  const BotanicalMarkdownText({
    super.key,
    required this.text,
    this.baseStyle,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final defaultStyle = baseStyle ?? Theme.of(context).textTheme.bodyMedium!;
    final List<Widget> widgets = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      // Headers (### or ##)
      if (trimmed.startsWith('###')) {
        final content = trimmed.substring(3).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            content,
            style: defaultStyle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: primaryColor,
              letterSpacing: -0.2,
            ),
          ),
        ));
      } else if (trimmed.startsWith('##')) {
        final content = trimmed.substring(2).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            content,
            style: defaultStyle.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: primaryColor,
              letterSpacing: -0.3,
            ),
          ),
        ));
      }
      // Blockquote
      else if (trimmed.startsWith('>')) {
        final content = trimmed.substring(1).trim();
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: primaryColor, width: 3)),
          ),
          child: Text(
            content,
            style: defaultStyle.copyWith(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: defaultStyle.color?.withOpacity(0.85),
            ),
          ),
        ));
      }
      // Bullet point
      else if (trimmed.startsWith('•') || trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final content = trimmed.startsWith('•')
            ? trimmed.substring(1).trim()
            : trimmed.substring(2).trim();

        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 3, bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• ',
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Expanded(
                child: _buildRichInline(content, defaultStyle, primaryColor),
              ),
            ],
          ),
        ));
      }
      // Standard line
      else {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _buildRichInline(trimmed, defaultStyle, primaryColor),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildRichInline(String text, TextStyle base, Color accent) {
    // Parse **bold** and *italic*
    final spans = <InlineSpan>[];
    final regExp = RegExp(r'(\*\*([^*]+)\*\*)|(\*([^*]+)\*)');
    int lastMatchEnd = 0;

    for (final match in regExp.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }

      if (match.group(2) != null) {
        // **bold**
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(4) != null) {
        // *italic*
        spans.add(TextSpan(
          text: match.group(4),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    }

    return Text.rich(
      TextSpan(children: spans, style: base),
    );
  }
}
