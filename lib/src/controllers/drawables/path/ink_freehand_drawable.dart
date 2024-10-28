import 'dart:ui';

import 'package:flutter/material.dart';

import 'path_drawable.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Free-style Drawable (hand scribble).
class InkFreehandDrawable extends PathDrawable {
  /// The color the path will be drawn with.
  final Color color;

  /// Creates a [InkFreehandDrawable] to draw [path].
  ///
  /// The path will be drawn with the passed [color] and [strokeWidth] if provided.
  InkFreehandDrawable({
    required List<Offset> path,
    double strokeWidth = 1,
    this.color = Colors.black,
    bool hidden = false,
  })  :
        // An empty path cannot be drawn, so it is an invalid argument.
        assert(path.isNotEmpty, 'The path cannot be an empty list'),

        // The line cannot have a non-positive stroke width.
        assert(strokeWidth > 0, 'The stroke width cannot be less than or equal to 0'),
        super(path: path, strokeWidth: strokeWidth, hidden: hidden);

  /// Creates a copy of this but with the given fields replaced with the new values.
  @override
  InkFreehandDrawable copyWith({
    bool? hidden,
    List<Offset>? path,
    Color? color,
    double? strokeWidth,
  }) {
    return InkFreehandDrawable(
      path: path ?? this.path,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      hidden: hidden ?? this.hidden,
    );
  }

  @protected
  @override
  Paint get paint => Paint()..color = color;

  /// Draws the free-style [path] on the provided [canvas] of size [size].
  @override
  void draw(Canvas canvas, Size size) {
    // 1. Get the outline points from the input points
    final outlinePoints = getStroke(
      this.path.map((e) => Point(e.dx, e.dy)).toList(),
      options: StrokeOptions(
        size: strokeWidth,
      ),
    );

    // 2. Render the points as a path
    final path = Path();

    if (outlinePoints.isEmpty) {
      // If the list is empty, don't do anything.
      return;
    } else if (outlinePoints.length < 2) {
      // If the list only has one point, draw a dot.
      path.addOval(Rect.fromCircle(center: Offset(outlinePoints[0].dx, outlinePoints[0].dy), radius: 1));
    } else {
      // Otherwise, draw a line that connects each point with a bezier curve segment.
      path.moveTo(outlinePoints[0].dx, outlinePoints[0].dy);

      for (int i = 1; i < outlinePoints.length - 1; ++i) {
        final p0 = outlinePoints[i];
        final p1 = outlinePoints[i + 1];
        path.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      }
    }

    // 3. Draw the path to the canvas
    canvas.drawPath(path, paint);
  }
}
