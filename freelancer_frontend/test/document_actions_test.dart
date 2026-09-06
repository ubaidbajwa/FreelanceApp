// Pure document decision logic (F-M8) — the validation / icon-mapping / size- and
// filename-formatting functions that live OUTSIDE the widget tree in
// message_actions.dart. Each is a client-side mirror of a server rule (extension +
// size allowlist) or a deterministic display calc (icon family, human size, middle
// ellipsis) — so every one is a plain tested function here, not a scattered widget if.

import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer_frontend/features/messaging/application/message_actions.dart';
import 'package:freelancer_frontend/features/messaging/messaging_strings.dart';

void main() {
  const mb = 1024 * 1024;

  // ── validateDocumentFile ───────────────────────────────────────────────────────
  // Mirrors the server: extension must be on the allowlist, size ≤ 25 MB. Returns
  // null when acceptable, else the specific user-facing limit message. Magic-byte
  // checks are server-only — a file can pass here and still be 400'd.
  group('validateDocumentFile', () {
    test('each allowed extension → accepted (null)', () {
      for (final ext in ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
        'txt', 'csv']) {
        expect(
          validateDocumentFile(fileName: 'report.$ext', lengthBytes: 1),
          isNull,
          reason: '.$ext should be allowed',
        );
      }
    });

    test('zip is rejected (deliberately not allowed)', () {
      expect(
        validateDocumentFile(fileName: 'archive.zip', lengthBytes: 1),
        MessagingStrings.documentUnsupportedType,
      );
    });

    test('executable is rejected', () {
      expect(
        validateDocumentFile(fileName: 'malware.exe', lengthBytes: 1),
        MessagingStrings.documentUnsupportedType,
      );
    });

    test('no extension → unsupported', () {
      expect(
        validateDocumentFile(fileName: 'README', lengthBytes: 1),
        MessagingStrings.documentUnsupportedType,
      );
    });

    test('over 25 MB → too-large message (naming the limit)', () {
      expect(
        validateDocumentFile(fileName: 'big.pdf', lengthBytes: 25 * mb + 1),
        MessagingStrings.documentTooLarge(),
      );
    });

    test('exactly 25 MB → accepted (boundary is inclusive)', () {
      expect(
        validateDocumentFile(fileName: 'edge.pdf', lengthBytes: 25 * mb),
        isNull,
      );
    });

    test('unsupported type is checked BEFORE size', () {
      // A 40 MB .zip reports the type problem, not the size problem — the type is
      // the actionable failure.
      expect(
        validateDocumentFile(fileName: 'huge.zip', lengthBytes: 40 * mb),
        MessagingStrings.documentUnsupportedType,
      );
    });

    test('extension match is case-insensitive', () {
      expect(
        validateDocumentFile(fileName: 'Q3_REPORT.PDF', lengthBytes: 1),
        isNull,
      );
    });
  });

  // ── documentKindForName ────────────────────────────────────────────────────────
  // Extension → visual family so a list of attachments is readable. pdf / Word /
  // Excel / PowerPoint / text each distinct; anything else generic. CSV rides with
  // the spreadsheet family (Excel) because spreadsheet apps are what open it.
  group('documentKindForName', () {
    test('pdf → pdf', () {
      expect(documentKindForName('a.pdf'), DocumentKind.pdf);
    });
    test('doc and docx → word', () {
      expect(documentKindForName('a.doc'), DocumentKind.word);
      expect(documentKindForName('a.docx'), DocumentKind.word);
    });
    test('xls, xlsx and csv → excel', () {
      expect(documentKindForName('a.xls'), DocumentKind.excel);
      expect(documentKindForName('a.xlsx'), DocumentKind.excel);
      expect(documentKindForName('a.csv'), DocumentKind.excel);
    });
    test('ppt and pptx → powerpoint', () {
      expect(documentKindForName('a.ppt'), DocumentKind.powerpoint);
      expect(documentKindForName('a.pptx'), DocumentKind.powerpoint);
    });
    test('txt → text', () {
      expect(documentKindForName('a.txt'), DocumentKind.text);
    });
    test('unknown / no extension → generic', () {
      expect(documentKindForName('a.rtf'), DocumentKind.generic);
      expect(documentKindForName('noext'), DocumentKind.generic);
    });
    test('case-insensitive', () {
      expect(documentKindForName('A.PDF'), DocumentKind.pdf);
    });
  });

  // ── documentExtensionLabel ─────────────────────────────────────────────────────
  // The uppercase extension shown next to the size (e.g. "PDF", "DOCX"). Empty for a
  // name with no extension (the bubble simply shows nothing there).
  group('documentExtensionLabel', () {
    test('lowercases → uppercase', () {
      expect(documentExtensionLabel('report.pdf'), 'PDF');
      expect(documentExtensionLabel('sheet.xlsx'), 'XLSX');
    });
    test('takes the LAST segment for a dotted name', () {
      expect(documentExtensionLabel('my.backup.tar.gz'), 'GZ');
    });
    test('no extension → empty', () {
      expect(documentExtensionLabel('README'), '');
    });
  });

  // ── formatFileSize ─────────────────────────────────────────────────────────────
  // Human byte magnitude: B / KB / MB (one decimal for MB). NOT formatCount — this is
  // a size with an intrinsic unit, not a localised item count. Null/negative → 0 B.
  group('formatFileSize', () {
    test('bytes under 1 KB → B', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(850), '850 B');
      expect(formatFileSize(1023), '1023 B');
    });
    test('1 KB boundary → KB', () {
      expect(formatFileSize(1024), '1 KB');
    });
    test('kilobytes rounded to whole KB', () {
      expect(formatFileSize(12 * 1024), '12 KB');
      expect(formatFileSize(1536), '2 KB'); // 1.5 KB rounds to 2
    });
    test('megabytes with one decimal', () {
      expect(formatFileSize(1024 * 1024), '1.0 MB');
      expect(formatFileSize((3.4 * 1024 * 1024).round()), '3.4 MB');
    });
    test('null → 0 B (never throws)', () {
      expect(formatFileSize(null), '0 B');
    });
    test('negative → 0 B (clamped)', () {
      expect(formatFileSize(-10), '0 B');
    });
  });

  // ── middleEllipsize ────────────────────────────────────────────────────────────
  // Ellipsise in the MIDDLE so the extension stays visible — end-truncation hides
  // ".pdf", exactly what the user needs to see. Short names unchanged.
  group('middleEllipsize', () {
    test('name at or under the limit is unchanged', () {
      expect(middleEllipsize('short.pdf', maxChars: 28), 'short.pdf');
      expect(
        middleEllipsize('exactly_twenty_eight_chars!!', maxChars: 28).length,
        28,
      );
    });

    test('long name keeps head and tail with a middle ellipsis', () {
      final out = middleEllipsize('Q3_financial_report_final_v2.pdf', maxChars: 20);
      expect(out.contains('…'), isTrue);
      expect(out.length, lessThanOrEqualTo(20));
      // The extension survives — this is the whole point.
      expect(out.endsWith('.pdf'), isTrue);
      expect(out.startsWith('Q3'), isTrue);
    });

    test('the result never exceeds maxChars', () {
      final out = middleEllipsize('a' * 200, maxChars: 15);
      expect(out.length, lessThanOrEqualTo(15));
    });

    test('very small maxChars degrades to just the ellipsis, never throws', () {
      expect(middleEllipsize('longfilename.pdf', maxChars: 2), '…');
    });
  });
}
