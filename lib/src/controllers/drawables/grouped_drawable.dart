import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../../views/painters/painter.dart';
import 'drawable.dart';
import 'dart:ui' as ui;

class GroupedDrawable extends Drawable {
  /// The list of drawables in this group.
  final List<Drawable> drawables;

  /// The renderedImage as background.
  ui.Image? myBackground;

  GlobalKey key = GlobalKey();

  /// Creates a new [GroupedDrawable] with the list of [drawables].
  GroupedDrawable({
    required List<Drawable> drawables,
    bool hidden = false,
  })  : drawables = List.unmodifiable(drawables),
        super(hidden: hidden);

  bool captureNotStarted = true;
  /// Draw all the drawables in the group on [canvas] of [size].
  @override
  void draw(Canvas canvas, Size size) {
    if (myBackground == null && captureNotStarted) {
      captureNotStarted = false;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      var dpr = ui.window.devicePixelRatio;
      canvas.scale(dpr);
      final painter = Painter(
        drawables: drawables,
        scale: size
      );
      print("drawing grouped drawable children: ${drawables.length} to save " + key.toString());
      painter.paint(canvas, size);
      recorder.endRecording().toImage((size.width * dpr).floor(), (size.height * dpr).floor()).then((value) => myBackground = value);
    } else if (myBackground != null) {
      print("drawing grouped drawable background " + key.toString());
      canvas.drawImageRect(myBackground!, Rect.fromPoints(Offset.zero, Offset(myBackground!.width.toDouble(), myBackground!.height.toDouble())),
          Rect.fromPoints(Offset.zero, Offset(size.width, size.height)), Paint());
      return;
    }

    if (myBackground == null) {
      print("drawing grouped drawable children: ${drawables.length} " + key.toString());
      for (final drawable in drawables) {
        drawable.draw(canvas, size);
      }
    }
  }

  /// Compares two [GroupedDrawable]s for equality.
// @override
// bool operator ==(Object other) {
//   return other is GroupedDrawable &&
//       super == other &&
//       ListEquality().equals(drawables, other.drawables);
// }
//
// @override
// int get hashCode => hashValues(hidden, hashList(drawables));
}
