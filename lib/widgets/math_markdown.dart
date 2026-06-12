import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import '../state/formula_display_notifier.dart';
import 'formula_viewer.dart';
import 'svg_block.dart';

/// Renders markdown content with LaTeX math, tables, and SVG support.
class MathMarkdown extends StatelessWidget {
  final String data;
  final MarkdownStyleSheet? styleSheet;
  final bool selectable;

  const MathMarkdown({
    super.key,
    required this.data,
    this.styleSheet,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    try {
      // Step 1: extract block specials (display math, SVG)
      final blocks = _findBlockSpecials(data);

      // Step 2: interleave text segments with block widgets
      if (blocks.isEmpty) {
        return _renderTextSegment(data, styleSheet, selectable);
      }

      final children = <Widget>[];
      int pos = 0;
      for (final b in blocks) {
        if (b.start > pos) {
          children.add(_renderTextSegment(
              data.substring(pos, b.start), styleSheet, selectable));
        }
        children.add(b.widget);
        pos = b.end;
      }
      if (pos < data.length) {
        children.add(_renderTextSegment(
            data.substring(pos), styleSheet, selectable));
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    } catch (_) {
      // Fallback: protect LaTeX underscores so MarkdownBody doesn't
      // break formulas like \mu_0 into \mu*0*.
      final safe = _InlineRichSegment._protectUnderscoresInMath(data);
      return MarkdownBody(
        data: safe,
        selectable: selectable,
        styleSheet: styleSheet,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Text-segment dispatcher — detects tables, delegates to MarkdownBody or
// inline-rich rendering
// ---------------------------------------------------------------------------

/// Renders a text segment.  If it contains a markdown table, the table is
/// extracted and rendered with [_TableBlock]; surrounding text is handled
/// recursively.
Widget _renderTextSegment(
  String text,
  MarkdownStyleSheet? styleSheet,
  bool selectable,
) {
  if (text.isEmpty) return const SizedBox.shrink();

  // Try to find a table in this segment
  final tableInfo = _findTableInText(text);
  if (tableInfo != null) {
    final children = <Widget>[];
    if (tableInfo.before.isNotEmpty) {
      children.add(_renderTextSegment(
          tableInfo.before, styleSheet, selectable));
    }
    children.add(_TableBlock(
      tableMarkdown: tableInfo.table,
      styleSheet: styleSheet,
      selectable: selectable,
    ));
    if (tableInfo.after.isNotEmpty) {
      children.add(_renderTextSegment(
          tableInfo.after, styleSheet, selectable));
    }
    if (children.length == 1) return children.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  // No table — delegate to the inline-rich segment
  return _InlineRichSegment(
    text: text,
    styleSheet: styleSheet,
    selectable: selectable,
  );
}

// ---------------------------------------------------------------------------
// Table detection (no placeholder — scan the real text)
// ---------------------------------------------------------------------------

/// Scans [text] for a markdown table block (header `|...|` + separator `|---|`
/// + body `|...|` lines). Returns null if no table is found.
_TableInfo? _findTableInText(String text) {
  final lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    final t = lines[i].trim();
    if (_isTableHeader(t) && i + 1 < lines.length) {
      final sep = lines[i + 1].trim();
      if (_isTableSeparator(sep)) {
        // Build the table block
        final tableLines = <String>[lines[i], lines[i + 1]];
        int j = i + 2;
        while (j < lines.length && _isTableRow(lines[j].trim())) {
          tableLines.add(lines[j]);
          j++;
        }

        final before = lines.sublist(0, i).join('\n');
        final after = lines.sublist(j).join('\n');
        final table = tableLines.join('\n');

        return _TableInfo(
          before: before,
          table: table,
          after: after,
        );
      }
    }
  }
  return null;
}

class _TableInfo {
  final String before;
  final String table;
  final String after;
  const _TableInfo({required this.before, required this.table, required this.after});
}

bool _isTableHeader(String line) {
  return line.startsWith('|') && line.endsWith('|');
}

bool _isTableSeparator(String line) {
  if (!line.startsWith('|') || !line.endsWith('|')) return false;
  return RegExp(r'^[\|\-\:\s]+$').hasMatch(line) && line.contains('---');
}

bool _isTableRow(String line) {
  return line.startsWith('|') && line.endsWith('|');
}

// ---------------------------------------------------------------------------
// Table rendering — each cell rendered as an individual Math.tex widget
// ---------------------------------------------------------------------------

/// Parses a markdown table and renders it with a [Table] widget using
/// [IntrinsicColumnWidth] so every row shares the same column widths —
/// fixing column misalignment.  The table scrolls horizontally inside
/// a [SingleChildScrollView]; tapping it opens a fullscreen viewer with
/// [InteractiveViewer] for pinch-to-zoom.
class _TableBlock extends StatelessWidget {
  final String tableMarkdown;
  final MarkdownStyleSheet? styleSheet;
  final bool selectable;

  const _TableBlock({
    required this.tableMarkdown,
    this.styleSheet,
    this.selectable = true,
  });

  /// Build the actual [Table] widget (shared by inline and fullscreen).
  Table _buildTable(ThemeData theme, TextStyle baseStyle) {
    final lines = tableMarkdown
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final headers = _splitRow(lines[0]);
    final colCount = headers.length;
    final bodyRows = <List<String>>[];
    for (int i = 2; i < lines.length; i++) {
      bodyRows.add(_splitRow(lines[i]));
    }

    // Ensure all rows have the same column count
    final normBodyRows = bodyRows.map((row) {
      if (row.length < colCount) {
        return [...row, ...List.filled(colCount - row.length, '')];
      } else if (row.length > colCount) {
        final merged = row.sublist(colCount - 1).join(' / ');
        return [...row.sublist(0, colCount - 1), merged];
      }
      return row;
    }).toList();

    final headerBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.18);

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(
            color: headerBg,
            borderRadius: BorderRadius.circular(6),
          ),
          children: List.generate(colCount, (c) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: _MathCell(
                content: c < headers.length ? headers[c].trim() : '',
                baseStyle: baseStyle,
                bold: true,
              ),
            );
          }),
        ),
        // Data rows
        ...normBodyRows.map((row) {
          return TableRow(
            children: List.generate(colCount, (c) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: _MathCell(
                  content: c < row.length ? row[c].trim() : '',
                  baseStyle: baseStyle,
                  bold: false,
                ),
              );
            }),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = tableMarkdown
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return _renderTextSegment(tableMarkdown, styleSheet, selectable);
    }

    final baseStyle = styleSheet?.p ??
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);

    final table = _buildTable(theme, baseStyle);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () => _showTableFullscreen(context, theme, baseStyle),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      ),
    );
  }

  void _showTableFullscreen(BuildContext context, ThemeData theme, TextStyle baseStyle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            title: const Text('表格 — 双指缩放'),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          body: SafeArea(
            child: InteractiveViewer(
              minScale: 0.15,
              maxScale: 10.0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: _buildTable(theme, baseStyle),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single table cell rendered as a [Math.tex] widget.
///
/// Converts markdown cell content to a LaTeX math expression:
/// - `$...$` markers are stripped, leaving raw LaTeX
/// - Plain text is wrapped in `\text{...}` for proper rendering
class _MathCell extends StatelessWidget {
  final String content;
  final TextStyle baseStyle;
  final bool bold;

  const _MathCell({
    required this.content,
    required this.baseStyle,
    required this.bold,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final formulaMode = ref.watch(formulaDisplayProvider);

      final style = baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 14) * 0.93,
        fontWeight: bold ? FontWeight.w600 : null,
      );

      // Off mode → plain text only
      if (formulaMode == FormulaDisplayMode.off) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(content, style: style, softWrap: true),
        );
      }

      // Plain text cells (no formulas) → render as Text directly.
      // Math.tex wraps text in \text{} which truncates long text and
      // can't handle underscores (e.g. Chinese text with _ ).
      if (!content.contains(r'$')) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(content, style: style, softWrap: true),
        );
      }

      final rawLatex = _cellToLatex(content);
      if (rawLatex.isEmpty) return const SizedBox(width: 40);

      // Preprocess to strip unsupported commands before rendering
      final latex = _preprocessLatex(rawLatex);

      try {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Math.tex(
              latex,
              mathStyle: MathStyle.text,
              textStyle: style,
            ),
          ),
        );
      } catch (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(content, style: style, softWrap: true),
        );
      }
    });
  }
}

/// Convert cell content to a LaTeX inline-math expression.
///
/// `$E=mc^2$`   → `E=mc^2`
/// `点电荷`       → `\text{点电荷}`
/// `电场 $E$ 强度` → `\text{电场 }\,E\,\text{ 强度}`
String _cellToLatex(String cell) {
  final re = RegExp(r'\$(.+?)\$');
  final parts = <String>[];
  int pos = 0;
  for (final m in re.allMatches(cell)) {
    if (m.start > pos) {
      final text = _cleanFormula(cell.substring(pos, m.start)).trim();
      if (text.isNotEmpty) {
        parts.add(r'\text{' '$text' '}');  // adjacent literals → one string
      }
    }
    parts.add(_cleanFormula(m.group(1)!).trim());
    pos = m.end;
  }
  if (pos < cell.length) {
    final text = _cleanFormula(cell.substring(pos)).trim();
    if (text.isNotEmpty) {
      parts.add(r'\text{' '$text' '}');
    }
  }
  if (parts.isEmpty) {
    final t = _cleanFormula(cell).trim();
    if (t.isEmpty) return '';
    return r'\text{' '$t' '}';
  }
  return parts.join(r'\,');
}

List<String> _splitRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').toList();
}

// ---------------------------------------------------------------------------
// Block-level specials (display math + SVG only)
// ---------------------------------------------------------------------------

class _Block {
  final int start, end;
  final Widget widget;
  const _Block(this.start, this.end, this.widget);
}

final _displayMathRe = RegExp(r'\$\$([\s\S]+?)\$\$');
final _displayBracketRe = RegExp(r'\\\[([\s\S]+?)\\\]');
final _svgRe = RegExp(r'<svg\b[\s\S]+?</svg>', caseSensitive: false);

List<_Block> _findBlockSpecials(String input) {
  final blocks = <_Block>[];
  final candidates = <_BlockCandidate>[];

  for (final m in _svgRe.allMatches(input)) {
    candidates.add(_BlockCandidate(m.start, m.end, 'svg', m.group(0)!));
  }
  for (final m in _displayMathRe.allMatches(input)) {
    // Only treat $$...$$ as a block when it sits on its own line(s).
    // If text appears before/after on the same line, it belongs inline.
    if (_isBlockLevel(input, m.start, m.end)) {
      candidates.add(_BlockCandidate(m.start, m.end, 'dm', m.group(1)!.trim()));
    }
  }
  for (final m in _displayBracketRe.allMatches(input)) {
    if (_isBlockLevel(input, m.start, m.end)) {
      candidates.add(_BlockCandidate(m.start, m.end, 'dm', m.group(1)!.trim()));
    }
  }

  candidates.sort((a, b) => a.start.compareTo(b.start));
  final filtered = <_BlockCandidate>[];
  for (final c in candidates) {
    if (filtered.isEmpty || c.start >= filtered.last.end) {
      filtered.add(c);
    }
  }

  for (final c in filtered) {
    switch (c.kind) {
      case 'svg':
        blocks.add(_Block(c.start, c.end, SvgBlock(svgString: c.content)));
        break;
      case 'dm':
        blocks.add(_Block(c.start, c.end, _DisplayMathBox(formula: c.content)));
        break;
    }
  }

  return blocks;
}

/// True when [start..end] has no non-space text on the same line as the
/// opening/closing delimiters — i.e. the formula sits on its own line(s).
bool _isBlockLevel(String input, int start, int end) {
  // Check text before start: must be at line start (or only whitespace)
  final lineStart = input.lastIndexOf('\n', start);
  final before = input.substring(lineStart + 1, start);
  if (before.trim().isNotEmpty) return false;

  // Check text after end: must be at line end (or only whitespace)
  final lineEnd = input.indexOf('\n', end);
  final after = input.substring(end, lineEnd < 0 ? input.length : lineEnd);
  if (after.trim().isNotEmpty) return false;

  return true;
}

class _BlockCandidate {
  final int start, end;
  final String kind;
  final String content;
  const _BlockCandidate(this.start, this.end, this.kind, this.content);
}

// ---------------------------------------------------------------------------
// Inline-rich text segment
// ---------------------------------------------------------------------------

final _inlineMathDollarRe = RegExp(r'(?<!\$)\$(?!\$)([^$]+?)\$(?!\$)');
final _inlineMathParenRe = RegExp(r'\\\(([\s\S]+?)\\\)');
// $$...$$ that were not extracted as blocks (text before/after on same line)
final _inlineDisplayMathRe = RegExp(r'\$\$([^$]+?)\$\$');

/// Clean formula source: strip invisible Unicode, full-width spaces,
/// stray outer parentheses, and normalise internal whitespace.
String _cleanFormula(String raw) {
  var s = raw
      // Invisible / zero-width characters
      .replaceAll('​', '')  // zero-width space
      .replaceAll('‌', '')  // zero-width non-joiner
      .replaceAll('‍', '')  // zero-width joiner
      .replaceAll('⁠', '')  // word joiner
      .replaceAll('﻿', '')  // BOM / zero-width no-break space
      // Full-width spaces
      .replaceAll('　', ' ')
      // Other common invisible chars
      .replaceAll(' ', ' ')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();

  // Strip one layer of surrounding parentheses only when they don't
  // belong to LaTeX grouping (e.g. \frac{}{} needs its braces).
  // Skip stripping when the content contains LaTeX commands (\),
  // because outer () are mathematically significant there.
  if (s.startsWith('(') && s.endsWith(')') && !s.contains('\\')) {
    final inner = s.substring(1, s.length - 1);
    // Only strip if the inner content is balanced at the top level
    if (_parensBalanced(inner)) {
      s = inner.trim();
    }
  }
  return s;
}

// ---------------------------------------------------------------------------
// LaTeX preprocessing — simplify to basic syntax that flutter_math_fork
// reliably renders.  Strip unsupported niche commands, convert environments,
// remove redundant markup.  Called before every Math.tex() invocation.
// ---------------------------------------------------------------------------

/// Preprocess LaTeX source so that flutter_math_fork can render it.
///
/// Operations (order matters):
/// 1. Strip package-level declarations and macros
/// 2. Convert unsupported align/equation environments → aligned/gathered
/// 3. Strip \label, \ref, \cite, \nonumber, \tag
/// 4. Convert \bm → \boldsymbol, \textsf → \mathsf etc.
/// 5. Strip \displaystyle / \textstyle / \scriptstyle (redundant context)
/// 6. Remove stray \left. / \right. invisible delimiters
/// 7. Normalise whitespace inside the formula
String _preprocessLatex(String latex) {
  var s = latex;

  // --- 1. Strip whole-line declarations (must precede env detection) ---
  s = s.replaceAll(RegExp(r'\\DeclareMathOperator\s*\*?\s*\{\\.+?\}\s*\{[^}]*\}'), '');
  s = s.replaceAll(RegExp(r'\\newcommand\s*\*?\s*\{\\.+?\}\s*(\[\d+\])?\s*\{[^}]*\}'), '');
  s = s.replaceAll(RegExp(r'\\renewcommand\s*\*?\s*\{\\.+?\}\s*(\[\d+\])?\s*\{[^}]*\}'), '');
  s = s.replaceAll(RegExp(r'\\def\s*\\.+?\{[^}]*\}'), '');
  s = s.replaceAll(RegExp(r'\\newenvironment\s*\{[^}]*\}\s*(\[\d+\])?\s*\{[^}]*\}\s*\{[^}]*\}'), '');
  s = s.replaceAll(RegExp(r'\\usepackage\s*(\[[^]]*\])?\s*\{[^}]*\}'), '');

  // --- 2. Convert unsupported top-level environments ---
  // align / align* → aligned (already inside display math $$…$$)
  s = s.replaceAllMapped(
    RegExp(r'\\begin\{align\*?\}([\s\S]*?)\\end\{align\*?\}'),
    (m) => '\\begin{aligned}${m.group(1) ?? ''}\\end{aligned}',
  );
  // equation / equation* → just content (already display mode)
  s = s.replaceAllMapped(
    RegExp(r'\\begin\{equation\*?\}([\s\S]*?)\\end\{equation\*?\}'),
    (m) => (m.group(1) ?? '').trim(),
  );
  // eqnarray / eqnarray* → aligned
  s = s.replaceAllMapped(
    RegExp(r'\\begin\{eqnarray\*?\}([\s\S]*?)\\end\{eqnarray\*?\}'),
    (m) => '\\begin{aligned}${m.group(1) ?? ''}\\end{aligned}',
  );
  // gather / gather* → gathered
  s = s.replaceAllMapped(
    RegExp(r'\\begin\{gather\*?\}([\s\S]*?)\\end\{gather\*?\}'),
    (m) => '\\begin{gathered}${m.group(1) ?? ''}\\end{gathered}',
  );
  // multline / multline* → gathered (closest supported)
  s = s.replaceAllMapped(
    RegExp(r'\\begin\{multline\*?\}([\s\S]*?)\\end\{multline\*?\}'),
    (m) => '\\begin{gathered}${m.group(1) ?? ''}\\end{gathered}',
  );

  // --- 3. Strip \label, \ref, \cite, \nonumber, \tag ---
  s = s.replaceAll(RegExp(r'\\label\s*\{[^}]*\}'), '');
  s = s.replaceAll(RegExp(r'\\ref\s*\{[^}]*\}'), '?');
  s = s.replaceAll(RegExp(r'\\eqref\s*\{[^}]*\}'), '(?)');
  s = s.replaceAll(RegExp(r'\\cite\s*(\[[^\]]*\])?\s*\{[^}]*\}'), '');
  s = s.replaceAll(RegExp(r'\\nonumber'), '');
  s = s.replaceAll(RegExp(r'\\tag\s*\{[^}]*\}'), '');
  s = s.replaceAll(RegExp(r'\\notag'), '');

  // --- 4. Command aliases ---
  s = s.replaceAll(RegExp(r'\\bm\s*\{'), r'\boldsymbol{');
  s = s.replaceAll(RegExp(r'\\bf\b'), r'\mathbf');
  s = s.replaceAll(RegExp(r'\\it\b'), r'\mathit');
  s = s.replaceAll(RegExp(r'\\rm\b'), r'\mathrm');
  s = s.replaceAll(RegExp(r'\\textsf\b'), r'\mathsf');
  s = s.replaceAll(RegExp(r'\\texttt\b'), r'\mathtt');

  // --- 5. Strip redundant style commands (context already dictates) ---
  s = s.replaceAll(RegExp(r'\\displaystyle\b'), '');
  s = s.replaceAll(RegExp(r'\\textstyle\b'), '');
  s = s.replaceAll(RegExp(r'\\scriptstyle\b'), '');
  s = s.replaceAll(RegExp(r'\\scriptscriptstyle\b'), '');
  s = s.replaceAll(RegExp(r'\\limits\b'), '');
  s = s.replaceAll(RegExp(r'\\nolimits\b'), '');

  // --- 6. Remove invisible fence pairs  \left. … \right. ---
  s = s.replaceAll(RegExp(r'\\left\.\s*'), '');
  s = s.replaceAll(RegExp(r'\\right\.\s*'), '');

  // --- 7. Strip unsupported niche commands (keep their argument) ---
  // \xrightarrow{…}, \xleftarrow{…} → \rightarrow / \leftarrow
  s = s.replaceAllMapped(
    RegExp(r'\\xrightarrow\s*(\[[^\]]*\])?\s*\{([^}]*)\}'),
    (m) => '\\xrightarrow{${m.group(2) ?? ''}}',
  );
  s = s.replaceAllMapped(
    RegExp(r'\\xleftarrow\s*(\[[^\]]*\])?\s*\{([^}]*)\}'),
    (m) => '\\xleftarrow{${m.group(2) ?? ''}}',
  );
  // \overset{…}{…} / \underset{…}{…} — keep (flutter_math_fork supports them)
  // \substack{…} — keep (supported)
  // \ce{…} (chemistry) — strip command, keep content
  s = s.replaceAllMapped(
    RegExp(r'\\ce\s*\{([^}]*)\}'),
    (m) => '\\mathrm{${m.group(1) ?? ''}}',
  );
  // \SI{…}{…} (siunitx) — keep number
  s = s.replaceAllMapped(
    RegExp(r'\\SI\s*\{([^}]*)\}\s*\{([^}]*)\}'),
    (m) => '${m.group(1) ?? ''}\\,${m.group(2) ?? ''}',
  );
  // \cancel, \bcancel, \xcancel — strip command, keep content
  s = s.replaceAllMapped(RegExp(r'\\cancel\s*\{([^}]*)\}'), (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(RegExp(r'\\bcancel\s*\{([^}]*)\}'), (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(RegExp(r'\\xcancel\s*\{([^}]*)\}'), (m) => m.group(1) ?? '');
  // \operatorname{…} → \mathrm{…}
  s = s.replaceAllMapped(
    RegExp(r'\\operatorname\s*\{([^}]*)\}'),
    (m) => '\\mathrm{${m.group(1) ?? ''}}',
  );
  // \text{…} inside math — keep (supported), but ensure nested braces are safe
  // \hspace / \vspace → remove (layout commands)
  s = s.replaceAll(RegExp(r'\\hspace\s*(\*?)\s*\{[^}]*\}'), '');
  s = s.replaceAll(RegExp(r'\\vspace\s*(\*?)\s*\{[^}]*\}'), '');
  // \hfill, \vfill → remove
  s = s.replaceAll(RegExp(r'\\[hv]fill\b'), '');
  // \\[dim] line break with optional spacing → \\
  s = s.replaceAll(RegExp(r'\\\\\s*\[[^\]]*\]'), r'\\');
  // \big, \Big, \bigg, \Bigg — keep (supported as delimiters)
  // \left, \right — keep (supported)

  // --- 8. Normalise whitespace ---
  // Collapse multiple spaces/tabs
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  // Remove leading/trailing whitespace on each line
  s = s.split('\n').map((l) => l.trim()).join('\n');
  // Collapse 3+ blank lines into 2
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  // Remove trailing whitespace
  s = s.trim();

  return s;
}

/// Full cleaning pipeline: invisible chars → parenthese strip → LaTeX
/// simplification.  Use this for every formula before passing to Math.tex.
String _safeLatex(String raw) {
  final cleaned = _cleanFormula(raw);
  if (cleaned.isEmpty) return '';
  return _preprocessLatex(cleaned);
}

bool _parensBalanced(String s) {
  int depth = 0;
  for (int i = 0; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') depth--;
    if (depth < 0) return false;
  }
  return depth == 0;
}

typedef _MdBuilder = InlineSpan Function(Match m, TextStyle style);

class _MdPattern {
  final RegExp re;
  final _MdBuilder builder;
  const _MdPattern(this.re, this.builder);
}

class _InlineRichSegment extends StatelessWidget {
  final String text;
  final MarkdownStyleSheet? styleSheet;
  final bool selectable;
  final bool forceInlineOnly;

  const _InlineRichSegment({
    required this.text,
    this.styleSheet,
    this.selectable = true,
    this.forceInlineOnly = false,
  });

  /// Detect code fences / blockquotes that must go to MarkdownBody.
  static bool _hasCodeOrQuote(String t) {
    final lines = t.split('\n');
    for (final line in lines) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```') || trimmed.startsWith('> ')) {
        return true;
      }
    }
    return false;
  }

  /// Escape underscores inside $...$ and $$...$$ so that MarkdownBody
  /// doesn't interpret them as italic markers (e.g. \mu_0 → \mu*0*).
  /// Uses \_ which flutter_math_fork renders as a literal underscore,
  /// preventing the "Parser Error: Expected '}', got '_'" crash.
  static String _protectUnderscoresInMath(String text) {
    return text
        // Inline $...$
        .replaceAllMapped(
          RegExp(r'(?<!\$)\$(?!\$)(.+?)\$(?!\$)'),
          (m) {
            final inner = (m.group(1) ?? '').replaceAll('_', r'\_');
            return '\$$inner\$';
          },
        )
        // Display $$...$$
        .replaceAllMapped(
          RegExp(r'\$\$(.+?)\$\$'),
          (m) {
            final inner = (m.group(1) ?? '').replaceAll('_', r'\_');
            return '\$\$$inner\$\$';
          },
        );
  }

  /// Extract fenced code blocks from [text] and return:
  /// - [segments]: alternating text / code-block widgets (text first)
  /// Returns null if no fenced code blocks found.
  static ({List<Widget> children, bool hasContent})? _extractFencedCode(
    String text, MarkdownStyleSheet? styleSheet, bool selectable, ThemeData theme) {
    final fenceRe = RegExp(r'^```', multiLine: true);
    final matches = fenceRe.allMatches(text).toList();
    if (matches.length < 2) return null;

    final children = <Widget>[];
    int pos = 0;
    for (int i = 0; i < matches.length - 1; i += 2) {
      final open = matches[i];
      final close = matches[i + 1];
      if (open.start < pos) continue;

      // Text before this code block
      if (open.start > pos) {
        children.add(_renderTextSegment(
            text.substring(pos, open.start), styleSheet, selectable));
      }

      // Extract code content (skip opening ``` line, extract until closing ```)
      final codeStart = text.indexOf('\n', open.start) + 1;
      final codeContent = codeStart > 0 && codeStart < close.start
          ? text.substring(codeStart, close.start).trimRight()
          : '';
      final lang = text.substring(open.start + 3, open.end).trim();

      children.add(_CodeBlockWidget(
        code: codeContent,
        language: lang,
        styleSheet: styleSheet,
        theme: theme,
      ));

      pos = close.end;
      // Skip newline after closing ```
      if (pos < text.length && text[pos] == '\n') pos++;
    }

    // Remaining text after last code block
    if (pos < text.length) {
      children.add(_renderTextSegment(
          text.substring(pos), styleSheet, selectable));
    }

    return (children: children, hasContent: true);
  }

  /// True when [t] contains at least one markdown blockquote line.
  static bool _hasBlockquote(String t) {
    return t.split('\n').any((line) => line.trimLeft().startsWith('> '));
  }

  /// Strips the leading "> " (or ">" at end of line) from every line of a
  /// blockquote so that the content can be rendered with inline-formula
  /// processing.  Preserves indentation level for nested blockquotes.
  static String _stripBlockquotePrefix(String t) {
    return t.split('\n').map((line) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('> ')) {
        return trimmed.substring(2);
      } else if (trimmed == '>') {
        return '';
      }
      return line;
    }).join('\n');
  }

  /// Detect headings / list markers that we can strip ourselves.
  static bool _hasListOrHeading(String t) {
    final lines = t.split('\n');
    for (final line in lines) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#') ||
          trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.startsWith('+ ') ||
          (trimmed.startsWith('1.') && trimmed.length > 2)) {
        return true;
      }
    }
    return false;
  }

  /// Strip markdown block-formatting prefixes so the content can be rendered
  /// with inline-formula processing.  Headings become bold; bullets use '•'.
  static String _stripBlockFormats(String t) {
    return t.split('\n').map((line) {
      final trimmed = line.trimLeft();
      final indent = line.substring(0, line.length - trimmed.length);
      if (trimmed.startsWith('### ')) {
        return '$indent**${trimmed.substring(4)}**';
      } else if (trimmed.startsWith('## ')) {
        return '$indent**${trimmed.substring(3)}**';
      } else if (trimmed.startsWith('# ')) {
        return '$indent**${trimmed.substring(2)}**';
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('+ ')) {
        return '• ${trimmed.substring(2)}';
      }
      return line;
    }).join('\n');
  }

  static TextSpan _parseInlineMd(String s, TextStyle base, Color? linkColor) {
    final patterns = <_MdPattern>[
      _MdPattern(RegExp(r'\*\*(.+?)\*\*'), (m, style) {
        return TextSpan(
            text: m.group(1), style: style.copyWith(fontWeight: FontWeight.bold));
      }),
      _MdPattern(RegExp(r'\*(.+?)\*'), (m, style) {
        return TextSpan(
            text: m.group(1), style: style.copyWith(fontStyle: FontStyle.italic));
      }),
      _MdPattern(RegExp(r'`([^`]+)`'), (m, style) {
        return TextSpan(
          text: m.group(1),
          style: style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Colors.grey.withValues(alpha: 0.15),
            fontSize: (style.fontSize ?? 14) * 0.93,
          ),
        );
      }),
      _MdPattern(RegExp(r'~~(.+?)~~'), (m, style) {
        return TextSpan(
            text: m.group(1),
            style: style.copyWith(decoration: TextDecoration.lineThrough));
      }),
      _MdPattern(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), (m, style) {
        return TextSpan(
          text: m.group(1) ?? '',
          style: style.copyWith(
            color: linkColor ?? Colors.blue,
            decoration: TextDecoration.underline,
          ),
        );
      }),
    ];
    return _parseMdRecursive(s, base, linkColor, patterns);
  }

  static TextSpan _parseMdRecursive(
    String s, TextStyle base, Color? linkColor, List<_MdPattern> patterns,
  ) {
    if (s.isEmpty) return const TextSpan(text: '');

    Match? best;
    _MdPattern? bestPat;
    for (final pat in patterns) {
      final m = pat.re.firstMatch(s);
      if (m != null && (best == null || m.start < best.start)) {
        best = m;
        bestPat = pat;
      }
    }

    if (best == null || bestPat == null) {
      return TextSpan(text: s, style: base);
    }

    final children = <InlineSpan>[];
    if (best.start > 0) {
      children.add(_parseMdRecursive(
          s.substring(0, best.start), base, linkColor, patterns));
    }
    children.add(bestPat.builder(best, base));
    if (best.end < s.length) {
      children.add(_parseMdRecursive(
          s.substring(best.end), base, linkColor, patterns));
    }
    return TextSpan(children: children);
  }
  /// Collapse repeated blank lines, strip redundant horizontal rules,
  /// and normalise separators so Flutter's flow layout doesn't fragment.
  static String _normalizeText(String t) {
    // Treat \r\n and lone \r
    var s = t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Remove trailing spaces/tabs on each line
    s = s.split('\n').map((l) => l.trimRight()).join('\n');
    // Collapse lines that are only whitespace
    s = s.replaceAll(RegExp(r'\n[ \t]+\n'), '\n\n');
    // Collapse 3+ consecutive line breaks into 2 (one blank line max)
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // Collapse consecutive horizontal-rule lines (---, ***, ___ with
    // optional spaces) — keep at most one
    final hrRe = RegExp(r'^[ \t]*[-*_]{3,}[ \t]*$');
    final lines = s.split('\n');
    final cleaned = <String>[];
    bool lastWasHr = false;
    for (final line in lines) {
      final isHr = hrRe.hasMatch(line);
      if (isHr && lastWasHr) continue; // skip consecutive hr
      // Strip hr lines that appear immediately after a blank line at the
      // very beginning or end (they're decorative, not structural)
      if (isHr && cleaned.isEmpty) continue;
      cleaned.add(line);
      lastWasHr = isHr;
    }
    // Remove trailing hr at end
    while (cleaned.isNotEmpty && hrRe.hasMatch(cleaned.last)) {
      cleaned.removeLast();
      // Also remove the blank line that preceded it
      if (cleaned.isNotEmpty && cleaned.last.trim().isEmpty) {
        cleaned.removeLast();
      }
    }
    s = cleaned.join('\n');
    // Final trim — never start or end with blank lines
    return s.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final formulaMode = ref.watch(formulaDisplayProvider);
      final s = _normalizeText(text);
      if (s.isEmpty) return const SizedBox.shrink();

      final theme = Theme.of(context);

      final baseStyle = styleSheet?.p ??
          theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
      final linkColor = theme.colorScheme.primary;

      // Code blocks / blockquotes → handle with protections
      if (!forceInlineOnly && _hasCodeOrQuote(s)) {
        // 1. Extract fenced code blocks first — render without scroll wrapper
        //    so all code content is visible at full height.
        final extracted = _extractFencedCode(s, styleSheet, selectable, theme);
        if (extracted != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: extracted.children,
          );
        }

        // 2. For blockquotes — strip the "> " prefix and render with inline
        //    formula support.  MarkdownBody would treat $...$ as plain text,
        //    so we must handle blockquotes ourselves to preserve LaTeX.
        if (_hasBlockquote(s)) {
          final stripped = _stripBlockquotePrefix(s);
          final rendered = _buildInlineWrap(stripped, baseStyle, linkColor);
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                  width: 3,
                ),
              ),
            ),
            child: rendered,
          );
        }

        // 3. Fallback: protect LaTeX underscores so \mu_0 doesn't become
        //    \mu*0* (markdown italic), then delegate to MarkdownBody.
        final safe = _protectUnderscoresInMath(s);
        return MarkdownBody(
          data: safe, selectable: selectable, styleSheet: styleSheet);
      }

      if (formulaMode == FormulaDisplayMode.off) {
        return RichText(
          text: _parseInlineMd(s, baseStyle, linkColor),
          textWidthBasis: TextWidthBasis.longestLine);
      }

      final hasF = _inlineMathDollarRe.hasMatch(s) ||
          _inlineMathParenRe.hasMatch(s) ||
          _inlineDisplayMathRe.hasMatch(s);
      final hasLH = _hasListOrHeading(s);

      if (hasF && hasLH) {
        return _buildInlineWrap(_stripBlockFormats(s), baseStyle, linkColor);
      }
      if (hasLH) {
        final safe = _protectUnderscoresInMath(s);
        return MarkdownBody(
          data: safe, selectable: selectable, styleSheet: styleSheet);
      }
      return _buildInlineWrap(s, baseStyle, linkColor);
    });
  }

  /// Renders [s] as a [RichText] with [WidgetSpan] for inline formulas,
  /// so formulas truly flow with the text instead of appearing on separate lines.
  static Widget _buildInlineWrap(String s, TextStyle baseStyle, Color linkColor) {
    // Merge inline-math matches — $...$ , \(...\), and $$...$$ leftover after
    // block extraction (these are inline-display formulas, e.g. in paragraphs).
    final matches = <_InlineMatch>[];
    for (final m in _inlineMathDollarRe.allMatches(s)) {
      matches.add(_InlineMatch(m.start, m.end, m.group(1)!.trim()));
    }
    for (final m in _inlineMathParenRe.allMatches(s)) {
      matches.add(_InlineMatch(m.start, m.end, m.group(1)!.trim()));
    }
    for (final m in _inlineDisplayMathRe.allMatches(s)) {
      matches.add(_InlineMatch(m.start, m.end, m.group(1)!.trim()));
    }
    matches.sort((a, b) => a.start.compareTo(b.start));

    final filtered = <_InlineMatch>[];
    for (final m in matches) {
      if (filtered.isEmpty || m.start >= filtered.last.end) {
        filtered.add(m);
      }
    }

    if (filtered.isEmpty) {
      return RichText(
        text: _parseInlineMd(s, baseStyle, linkColor),
        textWidthBasis: TextWidthBasis.longestLine,
      );
    }

    // Build RichText with WidgetSpan for true inline embedding.
    // formulaStyle inherits color and fontSize from baseStyle so formulas
    // blend with surrounding text instead of showing in accent colour.
    final formulaStyle = baseStyle.copyWith(
      fontSize: baseStyle.fontSize ?? 14,
    );
    final spans = <InlineSpan>[];
    int pos = 0;
    for (final m in filtered) {
      if (m.start > pos) {
        spans.add(_parseInlineMd(
            s.substring(pos, m.start), baseStyle, linkColor));
      }
      final safeLatex = _safeLatex(m.formula);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          safeLatex,
          mathStyle: MathStyle.text,
          textStyle: formulaStyle,
        ),
      ));
      pos = m.end;
    }
    if (pos < s.length) {
      spans.add(_parseInlineMd(
          s.substring(pos), baseStyle, linkColor));
    }

    return RichText(
      text: TextSpan(children: spans),
      textWidthBasis: TextWidthBasis.longestLine,
    );
  }
}

class _InlineMatch {
  final int start, end;
  final String formula;
  const _InlineMatch(this.start, this.end, this.formula);
}

// ---------------------------------------------------------------------------
// Code block — rendered WITHOUT scroll wrapper so all content is visible
// ---------------------------------------------------------------------------

class _CodeBlockWidget extends StatelessWidget {
  final String code;
  final String language;
  final MarkdownStyleSheet? styleSheet;
  final ThemeData theme;

  const _CodeBlockWidget({
    required this.code,
    required this.language,
    this.styleSheet,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final codeStyle = styleSheet?.code ??
        theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace') ??
        const TextStyle(fontFamily: 'monospace', fontSize: 13);
    final decoration = styleSheet?.codeblockDecoration ??
        BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () => _openFullscreen(context, codeStyle),
        child: Container(
          width: double.infinity,
          decoration: decoration,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (language.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        language,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.zoom_in, size: 13,
                          color: theme.colorScheme.outline),
                    ],
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  code,
                  style: codeStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context, TextStyle codeStyle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CodeViewerPage(
          code: code,
          language: language,
          codeStyle: codeStyle,
          theme: theme,
        ),
      ),
    );
  }
}

class _CodeViewerPage extends StatelessWidget {
  final String code;
  final String language;
  final TextStyle codeStyle;
  final ThemeData theme;

  const _CodeViewerPage({
    required this.code,
    required this.language,
    required this.codeStyle,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      appBar: AppBar(
        title: Text(language.isNotEmpty ? language : '代码'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: InteractiveViewer(
        maxScale: 5.0,
        minScale: 0.5,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              code,
              style: codeStyle.copyWith(fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Display math box
// ---------------------------------------------------------------------------

class _DisplayMathBox extends ConsumerWidget {
  final String formula;
  const _DisplayMathBox({required this.formula});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final displayMode = ref.watch(formulaDisplayProvider);

    // Off mode: show raw LaTeX source in monospace (use cleaned version)
    if (displayMode == FormulaDisplayMode.off) {
      final safeF = _safeLatex(formula);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SelectableText(
          r'$$' '\n$safeF\n' r'$$',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    // Directly embedded — no fancy card, just the formula itself
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: GestureDetector(
        onTap: () => FormulaViewer.show(context, formula, displayMode),
        child: Center(child: _buildMath(theme, displayMode)),
      ),
    );
  }

  Widget _buildMath(ThemeData theme, FormulaDisplayMode mode) {
    final safeFormula = _safeLatex(formula);
    try {
      final mathWidget = Math.tex(
        safeFormula,
        textStyle: theme.textTheme.titleLarge?.copyWith(
            fontSize: 18, color: theme.colorScheme.onSurface),
        mathStyle: MathStyle.display,
      );
      return switch (mode) {
        FormulaDisplayMode.scroll => SingleChildScrollView(
            scrollDirection: Axis.horizontal, child: mathWidget),
        FormulaDisplayMode.scale =>
          FittedBox(fit: BoxFit.scaleDown, child: mathWidget),
        _ => SingleChildScrollView(
            scrollDirection: Axis.horizontal, child: mathWidget),
      };
    } catch (_) {
      return SelectableText(
        safeFormula,
        style: TextStyle(
          fontFamily: 'monospace', fontSize: 17, height: 1.6,
          color: theme.colorScheme.onSurface, letterSpacing: 0.3,
        ),
      );
    }
  }
}
