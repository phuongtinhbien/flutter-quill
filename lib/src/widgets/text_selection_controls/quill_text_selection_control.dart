import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import '../../../flutter_quill.dart';

class QuillTextSelectionControl extends CupertinoTextSelectionControls {
  QuillTextSelectionControl(this.controller);

  final QuillController controller;


  @override
  void handleCopy(TextSelectionDelegate delegate,
      ClipboardStatusNotifier? clipboardStatus) {
    final value = delegate.textEditingValue;
    controller.copy();
    clipboardStatus?.update();
    delegate.bringIntoView(delegate.textEditingValue.selection.extent);

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        // Hide the toolbar, but keep the selection and keep the handles.
        delegate.hideToolbar(false);
        return;
      case TargetPlatform.macOS:
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        // Collapse the selection and hide the toolbar and handles.
        delegate.userUpdateTextEditingValue(
          TextEditingValue(
            text: value.text,
            selection: TextSelection.collapsed(offset: value.selection.end),
          ),
          SelectionChangedCause.toolBar,
        );
        delegate.hideToolbar();
        return;
    }
  }
}
