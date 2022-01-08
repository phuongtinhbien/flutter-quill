import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/src/utils/delta_to_markdown/src/html_renderer.dart';
import 'package:flutter_quill/src/utils/markdown_quill/markdown_quill.dart';
import 'package:html2md/html2md.dart' as html2md;
import 'package:tuple/tuple.dart';
import 'package:markdown/markdown.dart' as md;
import 'delta_to_markdown/delta_markdown.dart';

class ClipboardUtils {
  static final clipboardChannel = MethodChannel('clipboard/data');

  static final mdDocument = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    // you can add custom syntax.
    blockSyntaxes: [const EmbeddableTableSyntax()],
  );

  static Future<String> getClipboardData() async {
    try {
      final result = await clipboardChannel.invokeMethod('getClipboardData');

      if (result != null) {
        final data = Uint8List.fromList(result);

        try {
          final decodeData = utf8.decode(data);
          // Clipboard.setData(ClipboardData(text: decodeData));
          return decodeData;
        } on FormatException {
          return '<img src="data:image/jpeg;base64,${base64.encode(data)}"/>';
        } catch (e) {
          // print("error in getting clipboard image");
          print(e);
        }
      }

      // callback(prov);
    } on PlatformException {
    } catch (e) {
      // print("error in getting clipboard image");
      print(e);
    }
    return '';
  }

  static Future<Tuple2<Delta, int>?> getClipboardDelta(
      TextSelection selection) async {
    final data = await ClipboardUtils.getClipboardData();
    final plaintText = await Clipboard.getData(Clipboard.kTextPlain);
    print('ClipboardData: ${data.toString()}');
    print('ClipboardData: ${plaintText}');

    final markdown = html2md.convert(data, ignore: [
      'style'
    ], rules: [
      html2md.Rule('parse_span', filters: ['span'], filterFn: (node) {
        return node.nodeName == 'span' &&
            (node.className.contains('s1') || node.className.contains('s2'));
      }, replacement: (content, node) {
        if (node.className.contains('s1') || node.className.contains('s2')) {
          final hLevel = int.parse(node.className.substring(1));
          final underline =
              List.filled(content.length, hLevel == 1 ? '=' : '-').join();
          return '\n\n$content\n$underline\n\n';
        } else if (node.className.contains('s4')) {
          return '**$content**';
        }
        if (node.isBlock) {
          return '\n$content\n';
        } else {
          return content;
        }
      })
    ]);

    if (markdown.isNotEmpty) {
      final deltaData =
          MarkdownToDelta(markdownDocument: mdDocument).convert(markdown);
      final retainOperation = Operation.retain(selection.start).toJson();
      return Tuple2(Delta.fromJson([retainOperation, ...deltaData.toJson()]),
          data.length);
    }
  }

  static void copy(Delta delta) {
    try {
      final data = DeltaToMarkdown().convert(delta);
      print(data);

      final htmlData = markdownToHtml(data);
      print(htmlData);


      Clipboard.setData(ClipboardData(text: htmlData));
    } catch (e) {
      print(e);
    }
  }
}
