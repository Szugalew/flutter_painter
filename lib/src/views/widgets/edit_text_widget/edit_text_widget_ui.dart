import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../flutter_painter.dart';
import 'color_selection_row.dart';
import 'font_style_selection_row.dart';

/// A dialog-like widget to edit text drawables in.
class EditTextWidgetUI extends StatefulWidget {
  /// The controller for the current [FlutterPainter].
  final PainterController controller;

  /// The text drawable currently being edited.
  final TextDrawable drawable;

  /// Text editing controller for the [TextField].
  final TextEditingController textEditingController;

  /// The focus node of the [TextField].
  ///
  /// The node provided from the [TextSettings] will be used if provided
  /// Otherwise, it will be initialized to an inner [FocusNode].
  final FocusNode textFieldNode;

  /// If the text drawable being edited is new or not.
  /// If it is new, the update action is not marked as a new action, so it is merged with
  /// the previous action.
  final bool isNew;

  final Widget? Function(BuildContext, {required int currentLength, required bool isFocused, required int? maxLength})?
      buildEmptyCounter;

  final void Function()? onEditingComplete;

  const EditTextWidgetUI({
    Key? key,
    required this.controller,
    required this.drawable,
    required this.textFieldNode,
    required this.textEditingController,
    this.isNew = false,
    this.buildEmptyCounter,
    this.onEditingComplete,
  }) : super(key: key);

  @override
  EditTextWidgetUIState createState() => EditTextWidgetUIState();
}

class EditTextWidgetUIState extends State<EditTextWidgetUI> with WidgetsBindingObserver {
  TextStyle get textStyle => widget.controller.textStyle;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // If the background is tapped, un-focus the text field
      onTap: () => widget.textFieldNode.unfocus(),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withOpacity(0.25),
                Colors.black.withOpacity(0.25),
              ],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(
                children: [
                  buildTop(),
                  Expanded(
                    child: ShaderMask(
                      shaderCallback: (rect) {
                        return LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0), // Fade top edge
                            Colors.black.withOpacity(1),
                            Colors.black.withOpacity(1),
                            Colors.black.withOpacity(1),
                            Colors.black.withOpacity(1), // Middle weight 8
                            Colors.black.withOpacity(1),
                            Colors.black.withOpacity(1),
                            Colors.black.withOpacity(1),
                            Colors.black.withOpacity(1),
                            Colors.black.withOpacity(0), // Fade bottom edge
                          ],
                        ).createShader(Rect.fromLTRB(0, 0, rect.width, rect.height));
                      },
                      blendMode: BlendMode.dstIn,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: TextField(
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            cursorColor: Colors.white,
                            buildCounter: widget.buildEmptyCounter,
                            maxLength: 1000,
                            minLines: 1,
                            maxLines: 10,
                            controller: widget.textEditingController,
                            focusNode: widget.textFieldNode,
                            style: widget.controller.textStyle,
                            textAlign: TextAlign.center,
                            textAlignVertical: TextAlignVertical.center,
                            onEditingComplete: widget.onEditingComplete,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withOpacity(0.5), Colors.black.withOpacity(0)])),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Column(
                        children: [
                          FontStyleSelectionRow(
                            controller: widget.controller,
                            changeStyle: () => updateTextBackgroundColor(true),
                          ),
                          const SizedBox(height: 12),
                          ColorSelectionRow(
                            onColorChange: (color) => widget.controller.textStyle = textStyle.copyWith(color: color),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTop() {
    return Row(
      children: [
        Expanded(
          child: Container(),
        ),
        TextButton(
          onPressed: () => widget.textFieldNode.unfocus(),
          child: const Text(
            "Done",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  void updateTextBackgroundColor(bool swap) {
    if (swap) {
      if (textStyle.background == null || textStyle.background?.color == Colors.transparent) {
        widget.controller.textStyle = textStyle.copyWith(background: getTextStyleBackground());
      } else {
        widget.controller.textStyle = textStyle.copyWith(background: Paint()..color = Colors.transparent);
      }
    } else {
      if (textStyle.background == null || textStyle.background?.color == Colors.transparent) {
        return;
      }
      widget.controller.textStyle = textStyle.copyWith(background: getTextStyleBackground());
    }
  }

  Paint? getTextStyleBackground() {
    return Paint()
      ..color = (textStyle.color!.computeLuminance() > 0.5 ? Colors.black : Colors.white)
      ..strokeWidth = (textStyle.height ?? 1) * (textStyle.fontSize ?? 20) * 1.45
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
  }
}
