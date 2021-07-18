import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/models/documents/attribute.dart';
import 'package:flutter_quill/models/documents/nodes/line.dart';
import 'package:flutter_quill/models/documents/nodes/node.dart';
import 'package:flutter_quill/models/documents/style.dart';
import 'package:flutter_quill/models/quill_delta.dart';

bool isHeading2(Operation operation) {
  return operation.hasAttribute(Attribute.h2.key) &&
      operation.attributes![Attribute.h2.key] == 2;
}

bool isHeading3(Operation operation) {
  return operation.hasAttribute(Attribute.h2.key) &&
      operation.attributes![Attribute.h2.key] == 3;
}

bool isCheckList(Operation operation) {
  return operation.hasAttribute(Attribute.list.key) &&
      (operation.attributes![Attribute.list.key] == 'unchecked' ||
          operation.attributes![Attribute.list.key] == 'checked');
}

bool isUnCheckedList(Operation operation) {
  return operation.hasAttribute(Attribute.list.key) &&
      (operation.attributes![Attribute.list.key] == 'unchecked');
}

bool isCheckedList(Operation operation) {
  return operation.hasAttribute(Attribute.list.key) &&
      (operation.attributes![Attribute.list.key] == 'checked');
}

bool isBlockStyle(Operation operation) {
  var isTrue = false;
  for (var i = 0; i < Attribute.blockKeys.length; i++) {
    final curr = Attribute.blockKeys.elementAt(i);
    if (operation.attributes != null &&
        operation.attributes!.containsKey(curr)) {
      isTrue = true;
      break;
    }
  }
  return isTrue;
}

String textOfOutline(Operation operation) {
  var text = '';
  if (operation.value != null && operation.value.toString().contains('\n')) {
    text = operation.value.toString().split('\n').last.trim();
  } else {
    text = operation.value.toString().trim();
  }
  return text;
}

bool hasTag(Operation operation, List<String> tags) {
  if (operation.value is String) {
    return false;
  }
  final _opValue = operation.value as Map<String, dynamic>;
  final List<String> _opTags = _opValue['tag']!.split(',');
  return _opTags.any((element) => tags.contains(element));
}

extension DocumentExt on Document {
  List<Operation> get checkList {
    final res = <Operation>[];
    final data = root.children.where((element) {
      return element.isCheckedNode || element.isUnCheckedNode;
    });
    data.forEach((element) {
      res.addAll(element.toDelta().toList()
        ..removeWhere((element) =>
            !element.hasAttribute('list') &&
            element.value.toString().trim().isEmpty));
    });
    return res;
  }

  List<Operation> get checkedList {
    final res = <Operation>[];
    final data = root.children.where((element) => element.isCheckedNode);
    data.forEach((element) {
      res.addAll(element.toDelta().toList()
        ..removeWhere((element) =>
            !element.hasAttribute('list') &&
            element.value.toString().trim().isEmpty));
    });
    return res;
  }

  List<Operation> get unCheckedList {
    final res = <Operation>[];
    final data = root.children.where((element) => element.isUnCheckedNode);
    data.forEach((element) {
      res.addAll(element.toDelta().toList()
        ..removeWhere((element) =>
            !element.hasAttribute('list') &&
            element.value.toString().trim().isEmpty));
    });
    return res;
  }
}

extension NodeExt on Node {
  bool get isUnCheckedNode {
    return style.containsKey(Attribute.list.key) &&
        (style.attributes[Attribute.list.key] == Attribute.unchecked);
  }

  bool get isCheckedNode {
    return style.containsKey(Attribute.list.key) &&
        (style.attributes[Attribute.list.key] == Attribute.checked);
  }

  bool get isHeading2 {
    return style.containsKey(Attribute.header.key) &&
        style.attributes[Attribute.header.key] == Attribute.h2;
  }

  bool get isHeading3 {
    return style.containsKey(Attribute.header.key) &&
        style.attributes[Attribute.header.key] == Attribute.h3;
  }
  bool get isHeading1 {
    return style.containsKey(Attribute.header.key) &&
        style.attributes[Attribute.header.key] == Attribute.h1;
  }

  bool get isHeading{
    return isHeading1 || isHeading2 || isHeading3;
  }

  bool get isTag {
    if (this is Line) {
      final emded = this as Line;
      if (emded.hasEmbed) {
        return (emded.children.single as Embed)
            .value
            .toJson()
            .containsKey('tag');
      }
    }
    return false;
  }

  bool containTag(List<String> ids) {
    if (this is Line) {
      final emded = this as Line;
      if (emded.hasEmbed) {
        final temp = (emded.children.single as Embed).value.toJson();
        if (temp.containsKey('tag')) {
          return ids.any((element) => temp['tag'].toString().contains(element));
        }
      }
    }
    return false;
  }
}

extension StyleExt on Style {
  bool get isEmbedded =>
      isNotEmpty && values.every((item) => item.scope == AttributeScope.EMBEDS);
}
