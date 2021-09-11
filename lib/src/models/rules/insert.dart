import 'package:tuple/tuple.dart';

import '../documents/attribute.dart';
import '../documents/style.dart';
import '../quill_delta.dart';
import 'rule.dart';

abstract class InsertRule extends Rule {
  const InsertRule();

  @override
  RuleType get type => RuleType.INSERT;

  @override
  void validateArgs(int? len, Object? data, Attribute? attribute) {
    assert(data != null);
    assert(attribute == null);
  }
}

class PreserveLineStyleOnSplitRule extends InsertRule {
  const PreserveLineStyleOnSplitRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data != '\n') {
      return null;
    }

    final itr = DeltaIterator(document);
    final before = itr.skip(index);
    if (before == null ||
        before.data is! String ||
        (before.data as String).endsWith('\n')) {
      return null;
    }
    final after = itr.next();
    if (after.data is! String || (after.data as String).startsWith('\n')) {
      return null;
    }

    final text = after.data as String;

    final delta = Delta()..retain(index + (len ?? 0));
    if (text.contains('\n')) {
      assert(after.isPlain);
      delta.insert('\n');
      return delta;
    }
    final nextNewLine = _getNextNewLine(itr);
    final attributes = nextNewLine.item1?.attributes;

    return delta..insert('\n', attributes);
  }
}

/// Preserves block style when user inserts text containing newlines.
///
/// This rule handles:
///
///   * inserting a new line in a block
///   * pasting text containing multiple lines of text in a block
///
/// This rule may also be activated for changes triggered by auto-correct.
class PreserveBlockStyleOnInsertRule extends InsertRule {
  const PreserveBlockStyleOnInsertRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || !data.contains('\n')) {
      // Only interested in text containing at least one newline character.
      return null;
    }

    final itr = DeltaIterator(document)..skip(index);

    // Look for the next newline.
    final nextNewLine = _getNextNewLine(itr);
    final lineStyle =
        Style.fromJson(nextNewLine.item1?.attributes ?? <String, dynamic>{});

    final blockStyle = lineStyle.getBlocksExceptHeader();
    // Are we currently in a block? If not then ignore.
    if (blockStyle.isEmpty) {
      return null;
    }

    Map<String, dynamic>? resetStyle;
    // If current line had heading style applied to it we'll need to move this
    // style to the newly inserted line before it and reset style of the
    // original line.
    if (lineStyle.containsKey(Attribute.header.key)) {
      resetStyle = Attribute.header.toJson();
    } else if (lineStyle.containsKey(Attribute.checked.key) &&
        lineStyle.attributes[Attribute.checked.key]! == Attribute.checked) {
      resetStyle = Attribute.unchecked.toJson();
    }
    if (lineStyle.containsKey(Attribute.checked.key) &&
        (lineStyle.attributes[Attribute.checked.key]! == Attribute.checked ||
            lineStyle.attributes[Attribute.checked.key]! ==
                Attribute.unchecked)) {
      resetStyle ??= {};

      if (lineStyle.containsKey(Attribute.date.key)) {
        resetStyle.addAll(DateAttribute('new').toJson());
      }
      if (lineStyle.containsKey(Attribute.mentionBlock.key)) {
        resetStyle.addAll(MentionBlockAttribute('new').toJson());
      }
    } else {}

    // Go over each inserted line and ensure block style is applied.
    final lines = data.split('\n');
    final delta = Delta()..retain(index + (len ?? 0));
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isNotEmpty) {
        delta.insert(line);
      }
      if (i == 0) {
        // The first line should inherit the lineStyle entirely.
        delta.insert('\n', lineStyle.toJson());
      } else if (i < lines.length - 1) {
        // we don't want to insert a newline after the last chunk of text, so -1
        delta.insert('\n', blockStyle);
      }
    }

    // Reset style of the original newline character if needed.
    if (resetStyle != null) {
      delta
        ..retain(nextNewLine.item2!)
        ..retain((nextNewLine.item1!.data as String).indexOf('\n'))
        ..retain(1, resetStyle);
    }

    return delta;
  }
}

/// Heuristic rule to exit current block when user inserts two consecutive
/// newlines.
///
/// This rule is only applied when the cursor is on the last line of a block.
/// When the cursor is in the middle of a block we allow adding empty lines
/// and preserving the block's style.
class AutoExitBlockRule extends InsertRule {
  const AutoExitBlockRule();

  bool _isEmptyLine(Operation? before, Operation? after) {
    if (before == null) {
      return true;
    }
    return before.data is String &&
        (before.data as String).endsWith('\n') &&
        after!.data is String &&
        (after.data as String).startsWith('\n');
  }

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data != '\n') {
      return null;
    }

    final itr = DeltaIterator(document);
    final prev = itr.skip(index), cur = itr.next();
    final blockStyle = Style.fromJson(cur.attributes).getBlockExceptHeader();
    // We are not in a block, ignore.
    if (cur.isPlain || blockStyle == null) {
      return null;
    }
    // We are not on an empty line, ignore.
    if (!_isEmptyLine(prev, cur)) {
      return null;
    }

    // We are on an empty line. Now we need to determine if we are on the
    // last line of a block.
    // First check if `cur` length is greater than 1, this would indicate
    // that it contains multiple newline characters which share the same style.
    // This would mean we are not on the last line yet.
    // `cur.value as String` is safe since we already called isEmptyLine and
    // know it contains a newline
    if ((cur.value as String).length > 1) {
      // We are not on the last line of this block, ignore.
      return null;
    }

    // Keep looking for the next newline character to see if it shares the same
    // block style as `cur`.
    final nextNewLine = _getNextNewLine(itr);
    if (nextNewLine.item1 != null &&
        nextNewLine.item1!.attributes != null &&
        Style.fromJson(nextNewLine.item1!.attributes).getBlockExceptHeader() ==
            blockStyle) {
      // We are not at the end of this block, ignore.
      return null;
    }

    // Here we now know that the line after `cur` is not in the same block
    // therefore we can exit this block.
    final attributes = cur.attributes ?? <String, dynamic>{};

    if (attributes.containsKey(Attribute.checked.key) &&
        (attributes[Attribute.checked.key] == Attribute.checked.value ||
            attributes[Attribute.checked.key] == Attribute.unchecked.value)) {
      if (attributes.containsKey(Attribute.date.key)) {
        attributes[Attribute.date.key] = null;
      }
      if (attributes.containsKey(Attribute.mentionBlock.key)) {
        attributes[Attribute.mentionBlock.key] = null;
      }
      attributes[Attribute.checked.key] = null;
    } else {
      final k =
          attributes.keys.firstWhere(Attribute.blockKeysExceptHeader.contains);
      attributes[k] = null;
    }

    // retain(1) should be '\n', set it with no attribute
    return Delta()
      ..retain(index + (len ?? 0))
      ..retain(1, attributes);
  }
}

class ResetLineFormatOnNewLineRule extends InsertRule {
  const ResetLineFormatOnNewLineRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data != '\n') {
      return null;
    }

    final itr = DeltaIterator(document)..skip(index);
    final cur = itr.next();
    if (cur.data is! String || !(cur.data as String).startsWith('\n')) {
      return null;
    }

    Map<String, dynamic>? resetStyle;
    if (cur.attributes != null &&
        cur.attributes!.containsKey(Attribute.header.key)) {
      resetStyle = Attribute.header.toJson();
    }
    return Delta()
      ..retain(index + (len ?? 0))
      ..insert('\n', cur.attributes)
      ..retain(1, resetStyle)
      ..trim();
  }
}

class InsertEmbedsRule extends InsertRule {
  const InsertEmbedsRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is String) {
      return null;
    }

    final delta = Delta()..retain(index + (len ?? 0));
    final itr = DeltaIterator(document);
    final prev = itr.skip(index), cur = itr.next();

    final textBefore = prev?.data is String ? prev!.data as String? : '';
    final textAfter = cur.data is String ? (cur.data as String?)! : '';

    final isNewlineBefore = prev == null || textBefore!.endsWith('\n');
    final isNewlineAfter = textAfter.startsWith('\n');

    if (isNewlineBefore && isNewlineAfter) {
      return delta..insert(data);
    }

    Map<String, dynamic>? lineStyle;
    if (textAfter.contains('\n')) {
      lineStyle = cur.attributes;
    } else {
      while (itr.hasNext) {
        final op = itr.next();
        if ((op.data is String ? op.data as String? : '')!.contains('\n')) {
          lineStyle = op.attributes;
          break;
        }
      }
    }

    if (!isNewlineBefore) {
      delta.insert('\n', lineStyle);
    }
    delta.insert(data);
    if (!isNewlineAfter) {
      delta.insert('\n');
    }
    return delta;
  }
}

class AutoFormatLinksRule extends InsertRule {
  const AutoFormatLinksRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data != ' ') {
      return null;
    }

    final itr = DeltaIterator(document);
    final prev = itr.skip(index);
    if (prev == null || prev.data is! String) {
      return null;
    }

    try {
      final cand = (prev.data as String).split('\n').last.split(' ').last;
      final link = Uri.parse(cand);
      if (!['https', 'http'].contains(link.scheme)) {
        return null;
      }
      final attributes = prev.attributes ?? <String, dynamic>{};

      if (attributes.containsKey(Attribute.link.key)) {
        return null;
      }

      attributes.addAll(LinkAttribute(link.toString()).toJson());
      return Delta()
        ..retain(index + (len ?? 0) - cand.length)
        ..retain(cand.length, attributes)
        ..insert(data, prev.attributes);
    } on FormatException {
      return null;
    }
  }
}

class AutoListDashRule extends InsertRule {
  const AutoListDashRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data != ' ') {
      return null;
    }

    final itr = DeltaIterator(document);
    final prev = itr.skip(index), cur = itr.next();

    if (prev == null || prev.data is! String) {
      return null;
    }

    final textBefore = prev.data is String ? prev.data as String : '';
    final textAfter = cur.data is String ? cur.data as String : '';

    // print('textBefore: $textBefore');
    // print('textAfter: $textAfter');
    final isNewlineBefore = textBefore.endsWith('\n-') || (textBefore == '-');
    final isNewlineAfter = textAfter.startsWith('\n');
    //
    //
    // print('isNewlineBefore: $isNewlineBefore');
    // print('isNewlineAfter: $isNewlineAfter');
    if (isNewlineBefore && isNewlineAfter) {
      final copyDocument = Delta.fromJson(document.toJson());
      final before = copyDocument.slice(0, index).toList();
      final after = copyDocument.slice(index);
      final text = before.last.data.toString().trimRight();
      final newText = text.substring(0, text.length - 1);
      final attributes = before.last.attributes;
      final newOperation = Operation.insert('$newText\n ', attributes);
      before
        ..removeLast()
        ..add(newOperation)
        // ..add(Operation.insert(''))
        ..add(Operation.insert('\n', Attribute.dash.toJson()))
        ..addAll(after.toList());

      final newData = Delta.fromJson(before.map((e) => e.toJson()).toList());
      final diff = document.diff(newData);
      return diff..delete(1);
    }
    // if (isNewlineBefore) {
    //   delta.retain(1, Attribute.dash.toJson());
    // }
    // if (!isNewlineAfter) {
    //   delta.insert('\n');
    // }
    // final deltaLast = document.compose(delta);
    //
    // print(document.diff(deltaLast));

    return null;
  }
}

class AutoListBulletRule extends InsertRule {
  const AutoListBulletRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data != ' ') {
      return null;
    }

    final itr = DeltaIterator(document);

    final prev = itr.skip(index), cur = itr.next();

    if (prev == null || prev.data is! String) {
      return null;
    }

    final textBefore = prev.data is String ? prev.data as String : '';
    final textAfter = cur.data is String ? cur.data as String : '';

    // print('textAfter: $textAfter');

    final isNewlineBefore = textBefore.endsWith('\n*') || (textBefore == '*');
    final isNewlineAfter = textAfter.startsWith('\n');
    //
    //
    // print('isNewlineBefore: $isNewlineBefore');
    // print('isNewlineAfter: $isNewlineAfter');
    if (isNewlineBefore && isNewlineAfter) {
      final copyDocument = Delta.fromJson(document.toJson());
      final before = copyDocument.slice(0, index).toList();
      final after = copyDocument.slice(index);
      final text = before.last.data.toString().trimRight();
      final newText = text.substring(0, text.length - 1);
      final attributes = before.last.attributes;
      final newOperation = Operation.insert('$newText\n ', attributes);
      before
        ..removeLast()
        ..add(newOperation)
        // ..add(Operation.insert(''))
        ..add(Operation.insert('\n', Attribute.ul.toJson()))
        ..addAll(after.toList());

      final newData = Delta.fromJson(before.map((e) => e.toJson()).toList());
      final diff = document.diff(newData);
      return diff..delete(1);
    }
    // if (isNewlineBefore) {
    //   delta.retain(1, Attribute.dash.toJson());
    // }
    // if (!isNewlineAfter) {
    //   delta.insert('\n');
    // }
    // final deltaLast = document.compose(delta);
    //
    // print(document.diff(deltaLast));

    return null;
  }
}

class AutoListNumberRule extends InsertRule {
  const AutoListNumberRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data != ' ') {
      return null;
    }

    final itr = DeltaIterator(document);

    final prev = itr.skip(index), cur = itr.next();

    if (prev == null || prev.data is! String) {
      return null;
    }

    final textBefore = prev.data is String ? prev.data as String : '';
    final textAfter = cur.data is String ? cur.data as String : '';

    // print('textAfter: $textAfter');
    print('textBefore: $textBefore');

    final matches = RegExp(r'.*\n\d\.$');
    var textMatched = matches.stringMatch(textBefore) ?? '';

    if (textMatched.isEmpty) {
      textMatched =  RegExp(r'.*\d\.$').stringMatch(textBefore) ??'';
    }
    if (textMatched.isEmpty) {
      return null;
    }

    print(textMatched);

    final isNewlineBefore =
        textBefore.endsWith(textMatched) || (textBefore == textMatched);
    final isNewlineAfter = textAfter.startsWith('\n');
    // print('isNewlineBefore: $isNewlineBefore');
    // print('isNewlineAfter: $isNewlineAfter');
    if (isNewlineBefore && isNewlineAfter) {
      final copyDocument = Delta.fromJson(document.toJson());
      final before = copyDocument.slice(0, index).toList();
      final after = copyDocument.slice(index);
      final text = before.last.data.toString().trimRight();
      var newText = text.substring(0, text.length - textMatched.length );
      final attributes = before.last.attributes;
      if (textMatched.length >2) {
        newText += '\n ';
      } else  {
        newText += ' \n ';
      }
      final newOperation = Operation.insert(newText, attributes);
      before
        ..removeLast()
        ..add(newOperation)
        // ..add(Operation.insert(''))
        ..add(Operation.insert('\n', Attribute.ol.toJson()))
        ..addAll(after.toList());

      final newData = Delta.fromJson(before.map((e) => e.toJson()).toList());
      final diff = document.diff(newData);
      return diff..delete(1);
    }
    // if (isNewlineBefore) {
    //   delta.retain(1, Attribute.dash.toJson());
    // }
    // if (!isNewlineAfter) {
    //   delta.insert('\n');
    // }
    // final deltaLast = document.compose(delta);
    //
    // print(document.diff(deltaLast));

    return null;
  }
}

class AutoFormatMentionRule extends InsertRule {
  final Map<String, String> mentions;

  // ignore: sort_constructors_first
  const AutoFormatMentionRule(this.mentions);

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data != ' ') {
      return null;
    }

    final itr = DeltaIterator(document);
    final prev = itr.skip(index);
    if (prev == null || prev.data is! String || prev.data == ' ') {
      return null;
    }

    try {
      final cand = (prev.data as String).split('\n').last.split(' ').last;
      final exp = RegExp(r'(@|#)[a-zA-Z0-9]+');
      final allMatches = exp.allMatches(cand).toList();
      var tag = '';
      if (allMatches.isEmpty) {
        return null;
      } else {
        tag = allMatches.first.group(0)!;
      }

      final attributes = prev.attributes ?? <String, dynamic>{};
      if (attributes.containsKey(Attribute.mention.key)) {
        return null;
      }
      var value = '';
      var temp = tag.replaceAll('@', '');
      // print (tag);
      if (mentions.containsKey(temp)) {
        value = mentions[temp]!;
      } else {
        return null;
      }

      // print(value);
      attributes.addAll(MentionAttribute(value).toJson());
      return Delta()
        ..retain(index + (len ?? 0) - cand.length)
        ..retain(tag.length, attributes)
        ..insert(data, prev.attributes);
      // print (delta.toString());
    } on FormatException {
      return null;
    }
  }
}

class PreserveInlineStylesRule extends InsertRule {
  const PreserveInlineStylesRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data.contains('\n')) {
      return null;
    }

    final itr = DeltaIterator(document);
    final prev = itr.skip(index);
    if (prev == null ||
        prev.data is! String ||
        (prev.data as String).contains('\n')) {
      return null;
    }
    final attributes = prev.attributes;
    final text = data;
    if (attributes == null || !attributes.containsKey(Attribute.link.key)) {
      return Delta()
        ..retain(index + (len ?? 0))
        ..insert(text, attributes);
    }

    attributes.remove(Attribute.link.key);
    final delta = Delta()
      ..retain(index + (len ?? 0))
      ..insert(text, attributes.isEmpty ? null : attributes);
    final next = itr.next();

    final nextAttributes = next.attributes ?? const <String, dynamic>{};
    if (!nextAttributes.containsKey(Attribute.link.key)) {
      return delta;
    }
    if (attributes[Attribute.link.key] == nextAttributes[Attribute.link.key]) {
      return Delta()
        ..retain(index + (len ?? 0))
        ..insert(text, attributes);
    }
    return delta;
  }
}

class PreserveInlineMentionStylesRule extends InsertRule {
  const PreserveInlineMentionStylesRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data.contains('\n')) {
      return null;
    }

    final itr = DeltaIterator(document);
    final prev = itr.skip(index);
    if (prev == null ||
        prev.data is! String ||
        (prev.data as String).contains('\n')) {
      return null;
    }
    final attributes = prev.attributes;
    final text = data;
    if (attributes == null || !attributes.containsKey(Attribute.mention.key)) {
      return Delta()
        ..retain(index + (len ?? 0))
        ..insert(text, attributes);
    }
    attributes.remove(Attribute.mention.key);
    final delta = Delta()
      ..retain(index + (len ?? 0))
      ..insert(text, attributes.isEmpty ? null : attributes);
    final next = itr.next();

    final nextAttributes = next.attributes ?? const <String, dynamic>{};

    if (!nextAttributes.containsKey(Attribute.mention.key)) {
      return delta;
    }
    if (attributes[Attribute.mention.key] ==
        nextAttributes[Attribute.mention.key]) {
      return Delta()
        ..retain(index + (len ?? 0))
        ..insert(text, attributes);
    }
    return delta;
  }
}

class PreserveInlineHashStylesRule extends InsertRule {
  const PreserveInlineHashStylesRule();

  @override
  Delta? applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    if (data is! String || data.contains('\n')) {
      return null;
    }

    final itr = DeltaIterator(document);
    final prev = itr.skip(index);
    if (prev == null ||
        prev.data is! String ||
        (prev.data as String).contains('\n')) {
      return null;
    }
    final attributes = prev.attributes;
    final text = data;
    if (attributes == null || !attributes.containsKey(Attribute.hashtag.key)) {
      return Delta()
        ..retain(index + (len ?? 0))
        ..insert(text, attributes);
    }
    attributes.remove(Attribute.hashtag.key);
    final delta = Delta()
      ..retain(index + (len ?? 0))
      ..insert(text, attributes.isEmpty ? null : attributes);
    final next = itr.next();

    final nextAttributes = next.attributes ?? const <String, dynamic>{};

    if (!nextAttributes.containsKey(Attribute.hashtag.key)) {
      return delta;
    }
    if (attributes[Attribute.hashtag.key] ==
        nextAttributes[Attribute.hashtag.key]) {
      return Delta()
        ..retain(index + (len ?? 0))
        ..insert(text, attributes);
    }
    return delta;
  }
}

class CatchAllInsertRule extends InsertRule {
  const CatchAllInsertRule();

  @override
  Delta applyRule(Delta document, int index,
      {int? len, Object? data, Attribute? attribute}) {
    return Delta()
      ..retain(index + (len ?? 0))
      ..insert(data);
  }
}

Tuple2<Operation?, int?> _getNextNewLine(DeltaIterator iterator) {
  Operation op;
  for (var skipped = 0; iterator.hasNext; skipped += op.length!) {
    op = iterator.next();
    final lineBreak =
        (op.data is String ? op.data as String? : '')!.indexOf('\n');
    if (lineBreak >= 0) {
      return Tuple2(op, skipped);
    }
  }
  return const Tuple2(null, null);
}
