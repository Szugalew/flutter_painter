part of 'flutter_painter.dart';

/// Flutter widget to detect user input and request drawing [FreeStyleDrawable]s.
class _FreeStyleWidget extends StatefulWidget {
  /// Child widget.
  final Widget child;

  /// Creates a [_FreeStyleWidget] with the given [controller], [child] widget.
  const _FreeStyleWidget({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  _FreeStyleWidgetState createState() => _FreeStyleWidgetState();
}

/// State class
class _FreeStyleWidgetState extends State<_FreeStyleWidget> {
  /// The current drawable being drawn.
  PathDrawable? drawable;

  int _pointers = 0;

  @override
  Widget build(BuildContext context) {
    if (!painterMode.isAFreestyleMode || shapeSettings.factory != null) {
      return widget.child;
    }

    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) {
        _pointers++;
        if (_pointers >= 2) {
          _handleTwoPointersDown();
        }
      },
      onPointerCancel: (_) {
        _pointers--;
      },
      onPointerUp: (_) {
        _pointers--;
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _DragGestureDetector: GestureRecognizerFactoryWithHandlers<_DragGestureDetector>(
            () => _DragGestureDetector(
              onHorizontalDragDown: _handleHorizontalDragDown,
              onHorizontalDragUpdate: _handleHorizontalDragUpdate,
              onHorizontalDragUp: _handleHorizontalDragUp,
            ),
            (_) {},
          ),
        },
        child: PainterController.of(context).painterMode.isAFreestyleMode
            ? IgnorePointer(
                child: widget.child,
              )
            : widget.child,
      ),
    );
  }

  /// Getter for [FreeStyleSettings] from `widget.controller.value` to make code more readable.
  FreeStyleSettings get settings => PainterController.of(context).value.settings.freeStyle;

  /// Getter for [PainterMode] from `widget.controller.value` to make code more readable.
  PainterMode get painterMode => PainterController.of(context).value.settings.painterMode;

  /// Getter for [PaintBrushStyle] from `widget.controller.value` to make code more readable.
  PaintBrushStyle get paintBrushStyle => PainterController.of(context).value.settings.freeStyle.paintBrushStyle;

  /// Getter for [ShapeSettings] from `widget.controller.value` to make code more readable.
  ShapeSettings get shapeSettings => PainterController.of(context).value.settings.shape;

  /// Callback when the user holds their pointer(s) down onto the widget.
  void _handleHorizontalDragDown(Offset globalPosition, {bool newDrag = true}) {
    // If the user is already drawing, don't create a new drawing
    if (this.drawable != null) return;

    // Create a new free-style drawable representing the current drawing
    final PathDrawable drawable;
    if (painterMode == PainterMode.eraser) {
      drawable = EraseDrawable(
        path: [_globalToLocal(globalPosition)],
        strokeWidth: settings.strokeWidth,
      );
      PainterController.of(context).groupDrawables(newAction: newDrag);
      // Add the drawable to the controller's drawables
      PainterController.of(context).addDrawables(paintLevelDrawables: [drawable], topLevelDrawables: [], newAction: false,);
    } else if (painterMode == PainterMode.paintBrush) {
      drawable = paintBrushStyle.getDrawable([_globalToLocal(globalPosition)], settings.strokeWidth, settings.color);
      // Add the drawable to the controller's drawables
      PainterController.of(context).addDrawables(paintLevelDrawables: [drawable], topLevelDrawables: [], newAction: newDrag);
    } else {
      return;
    }

    // Set the drawable as the current drawable
    this.drawable = drawable;
  }

  /// Callback when the user moves, rotates or scales the pointer(s).
  void _handleHorizontalDragUpdate(Offset globalPosition) {
    final drawable = this.drawable;
    // If there is no current drawable, ignore user input
    if (drawable == null) return;

    // Update the path in a copy of the current drawable
    final PathDrawable newDrawable = drawable.copyWith(
      path: List<Offset>.from(drawable.path)..add(_globalToLocal(globalPosition)),
    );
    // Replace the current drawable with the copy with the added point
    PainterController.of(context).replaceDrawable(drawable, newDrawable, true, newAction: false);

    if (newDrawable.path.length > 100) {
      // If drawable is too big, break apart
      this.drawable = null;
      //Todo, should the group logic be somewhere else?
      if (PainterController.of(context).value.paintLevelDrawables.length > 10) {
        PainterController.of(context).groupDrawables(newAction: false);
      }
      _handleHorizontalDragDown(globalPosition, newDrag: false);
    } else {
      // Update the current drawable to be the new copy
      this.drawable = newDrawable;
    }
  }

  /// Callback when the user removes all pointers from the widget.
  void _handleHorizontalDragUp() {
    if (drawable == null) return;
    //Todo, should the group logic be somewhere else?
    if (PainterController.of(context).value.paintLevelDrawables.length > 10) {
      PainterController.of(context).groupDrawables(newAction: false);
    }
    DrawableCreatedNotification(drawable).dispatch(context);

    /// Reset the current drawable for the user to draw a new one next time
    drawable = null;
  }

  void _handleTwoPointersDown() {
    final drawable = this.drawable;
    if (drawable == null) return;
    int length = drawable.path.length;
    if (length < 100) {
      PainterController.of(context).removeDrawable(drawable, true, newAction: false);
    }
    this.drawable = null;
  }

  Offset _globalToLocal(Offset globalPosition) {
    final getBox = context.findRenderObject() as RenderBox;

    return getBox.globalToLocal(globalPosition);
  }
}

/// A custom recognizer that recognize at most only one gesture sequence.
class _DragGestureDetector extends OneSequenceGestureRecognizer {
  _DragGestureDetector({
    required this.onHorizontalDragDown,
    required this.onHorizontalDragUpdate,
    required this.onHorizontalDragUp,
  });

  final ValueSetter<Offset> onHorizontalDragDown;
  final ValueSetter<Offset> onHorizontalDragUpdate;
  final VoidCallback onHorizontalDragUp;

  bool _isTrackingGesture = false;

  @override
  void addPointer(PointerEvent event) {
    if (!_isTrackingGesture) {
      resolve(GestureDisposition.accepted);
      startTrackingPointer(event.pointer);
      _isTrackingGesture = true;
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      onHorizontalDragDown(event.position);
    } else if (event is PointerMoveEvent) {
      onHorizontalDragUpdate(event.position);
    } else if (event is PointerUpEvent) {
      onHorizontalDragUp();
      stopTrackingPointer(event.pointer);
      _isTrackingGesture = false;
    }
  }

  @override
  String get debugDescription => '_DragGestureDetector';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}
