import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_painter/src/controllers/drawables/path/picture_brushes/generic_picture_brush_drawable.dart';

import '../views/painters/painter.dart';
import '../views/widgets/painter_controller_widget.dart';
import 'actions/actions.dart';
import 'drawables/background/background_drawable.dart';
import 'drawables/drawable.dart';
import 'drawables/image_drawable.dart';
import 'drawables/object_drawable.dart';
import 'events/events.dart';
import 'events/selected_object_drawable_removed_event.dart';
import 'settings/settings.dart';

/// Controller used to control a [FlutterPainter] widget.
///
/// * IMPORTANT: *
/// Each [FlutterPainter] should have its own controller.
class PainterController extends ValueNotifier<PainterControllerValue> {
  List<Color> colorHistory = [Colors.black];

  /// A controller for an event stream which widgets will listen to.
  ///
  /// This will dispatch events that represent actions, such as adding a new text drawable.
  final StreamController<PainterEvent> _eventsSteamController;

  /// This key will be used by the [FlutterPainter] widget assigned this controller.
  ///
  /// * IMPORTANT: *
  /// DO NOT ASSIGN this key on any widget,
  /// it is automatically used inside the [FlutterPainter] controlled by `this`.
  ///
  /// However, you can use to to grab information about the render object, etc...
  final GlobalKey painterKey;

  final GlobalKey screenshotKey = GlobalKey();

  /// This controller will be used by the [InteractiveViewer] in [FlutterPainter] to notify
  /// children widgets of transformation changes.
  ///
  /// * IMPORTANT: *
  /// DO NOT ASSIGN this controller to any widget,
  /// it is automatically used inside the [InteractiveViewer] in [FlutterPainter] controller by `this`.
  ///
  /// However, you can use it to grab information about the transformations.
  final TransformationController transformationController;

  final GlobalKey transformationWidgetKey = GlobalKey();

  /// Create a [PainterController].
  ///
  /// The behavior of a [FlutterPainter] widget is controlled by [settings].
  /// The controller can be initialized with a list of [drawables]
  /// to be painted without user interaction.
  /// It can also accept a [background] to be painted.
  /// Without it, the background will be transparent.
  /// Also preloads the [PictureBrushDrawable] assets
  PainterController({
    PainterSettings settings = const PainterSettings(),
    List<Drawable>? paintLevelDrawables = const [],
    List<Drawable>? topLevelDrawables = const [],
    BackgroundDrawable? background,
  }) : this.fromValue(PainterControllerValue(
          settings: settings,
          paintLevelDrawables: paintLevelDrawables ?? const [],
          topLevelDrawables: topLevelDrawables ?? const [],
          background: background,
        ));

  /// Create a [PainterController] from a [PainterControllerValue].
  PainterController.fromValue(PainterControllerValue value)
      : _eventsSteamController = StreamController<PainterEvent>.broadcast(),
        painterKey = GlobalKey(),
        transformationController = TransformationController(),
        super(value) {
    PictureBrushDrawable.preLoadBrushImages();
  }

  /// The stream of [PainterEvent]s dispatched from this controller.
  ///
  /// This stream is for children widgets of [FlutterPainter] to listen to external events.
  /// For example, adding a new text drawable.
  Stream<PainterEvent> get events => _eventsSteamController.stream;

  /// Setting this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this value should only be set between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  set background(BackgroundDrawable? background) => value = value.copyWith(background: background);

  /// Queues used to track the actions performed on drawables in the controller.
  /// This is used to [undo] and [redo] actions.
  Queue<ControllerAction> performedActions = DoubleLinkedQueue(), unperformedActions = DoubleLinkedQueue();

  /// Uses the [PainterControllerWidget] inherited widget to fetch the [PainterController] instance in this context.
  /// This is used internally in the library to fetch the controller at different widgets.
  static PainterController of(BuildContext context) {
    return PainterControllerWidget.of(context).controller;
  }

  /// Add the [drawables] to the controller value drawables.
  ///
  /// If [newAction] is `true`, the action is added as an independent action
  /// and can be [undo]ne in the future. If it is `false`, the action is connected to the
  /// previous action and is merged with it.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void addDrawables({
    required Iterable<Drawable> paintLevelDrawables,
    required Iterable<Drawable> topLevelDrawables,
    bool newAction = true,
  }) {
    final action = AddDrawablesAction(paintLevelDrawables.toList(), topLevelDrawables.toList());
    action.perform(this);
    _addAction(action, newAction);
  }

  /// Inserts the [drawables] to the controller value drawables at the provided [index].
  ///
  /// If [newAction] is `true`, the action is added as an independent action
  /// and can be [undo]ne in the future. If it is `false`, the action is connected to the
  /// previous action and is merged with it.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void insertDrawables(
    int index, {
    required Iterable<Drawable> paintLevelDrawables,
    required Iterable<Drawable> topLevelDrawables,
    bool newAction = true,
  }) {
    final action = InsertDrawablesAction(index, paintLevelDrawables.toList(), topLevelDrawables.toList());
    action.perform(this);
    _addAction(action, newAction);
  }

  /// Replace [oldDrawable] with [newDrawable] in the controller value.
  ///
  /// Returns `true` if [oldDrawable] was found and replaced, `false` otherwise.
  /// If the return value is `false`, the controller value is unaffected.
  ///
  /// If [newAction] is `true`, the action is added as an independent action
  /// and can be [undo]ne in the future. If it is `false`, the action is connected to the
  /// previous action and is merged with it.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  ///
  /// [notifyListeners] will not be called if the return value is `false`.
  bool replaceDrawable(Drawable oldDrawable, Drawable newDrawable, bool isPaintLevel, {bool newAction = true}) {
    final action = ReplaceDrawableAction(oldDrawable, newDrawable, isPaintLevel);
    final value = action.perform(this);
    if (value) _addAction(action, newAction);
    return value;
  }

  /// Removes the first occurrence of [drawable] from the controller value.
  ///
  /// Returns `true` if [drawable] was in the controller value, `false` otherwise.
  ///
  /// If [newAction] is `true`, the action is added as an independent action
  /// and can be [undo]ne in the future. If it is `false`, the action is connected to the
  /// previous action and is merged with it.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  ///
  /// [notifyListeners] will not be called if the return value is `false`.
  bool removeDrawable(Drawable drawable, bool isPaintLevel, {bool newAction = true}) {
    final action = RemoveDrawableAction(drawable, isPaintLevel);
    final value = action.perform(this);
    _addAction(action, newAction);
    return value;
  }

  /// Removes the last drawable from the controller value.
  ///
  /// If [newAction] is `true`, the action is added as an independent action
  /// and can be [undo]ne in the future. If it is `false`, the action is connected to the
  /// previous action and is merged with it.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  ///
  /// [notifyListeners] will not be called if there are no drawables in the controller value.
  void removeLastDrawable(bool isPaintLevel, {bool newAction = true}) {
    removeDrawable(isPaintLevel ? value.paintLevelDrawables.last : value.topLevelDrawables.last, isPaintLevel);
  }

  /// Removes all drawables from the controller value.
  ///
  /// If [newAction] is `true`, the action is added as an independent action
  /// and can be [undo]ne in the future. If it is `false`, the action is connected to the
  /// previous action and is merged with it.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void clearDrawables({bool newAction = true}) {
    final action = ClearDrawablesAction();
    action.perform(this);
    _addAction(action, newAction);
  }

  /// Groups all paint level drawables in the controller into one drawable.
  ///
  /// This is used when an erase drawable is added, to prevent modifications to previous drawables.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void groupDrawables({bool newAction = true}) {
    final action = MergeDrawablesAction();
    action.perform(this);
    _addAction(action, newAction);
  }

  void _addAction(ControllerAction action, bool newAction) {
    performedActions.add(action);
    if (!newAction) _mergeAction();
    unperformedActions.clear();
  }

  /// Whether an [undo] operation can be performed or not.
  bool get canUndo => performedActions.isNotEmpty;

  /// Whether a [redo] operation can be performed or not.
  bool get canRedo => unperformedActions.isNotEmpty;

  /// Undoes the last action performed on drawables. The action can later be [redo]ne.
  ///
  /// If [canUndo] is `false`, nothing happens and [notifyListeners] is not called.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void undo() {
    if (!canUndo) return;
    final action = performedActions.removeLast();
    action.unperform(this);
    unperformedActions.add(action);
  }

  /// Redoes the last [undo]ne action. The redo operation can be [undo]ne.
  ///
  /// If [canRedo] is `false`, nothing happens and [notifyListeners] is not called.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void redo() {
    if (!canRedo) return;
    final action = unperformedActions.removeLast();
    action.perform(this);
    performedActions.add(action);
  }

  /// Merges a newly added action with the previous action.
  void _mergeAction() {
    if (performedActions.length < 2) return;
    final second = performedActions.removeLast();
    final first = performedActions.removeLast();
    final groupedAction = second.merge(first);

    if (groupedAction != null) performedActions.add(groupedAction);
  }

  /// Dispatches a [AddTextPainterEvent] on `events` stream.
  void addText() {
    _eventsSteamController.add(const AddTextPainterEvent());
  }

  /// Adds an [ImageDrawable] to the center of the painter.
  ///
  /// If [size] is provided, the drawable will scaled to fit that size.
  /// If not, it will take the original image's size.
  ///
  /// Note that if the painter is not rendered yet (for example, this method was used in the initState method),
  /// the drawable position will be [Offset.zero].
  /// If you face this issue, call this method in a post-frame callback.
  /// ```dart
  /// void initState(){
  ///   super.initState();
  ///   WidgetsBinding.instance?.addPostFrameCallback((timestamp){
  ///     controller.addImage(myImage);
  ///   });
  /// }
  /// ```
  void addImage(ui.Image image, {Size? size, bool? fillCanvas, bool paintLevel = false}) {
    // Calculate the center of the painter
    final renderBox = painterKey.currentContext?.findRenderObject() as RenderBox?;
    final center = renderBox == null
        ? Offset.zero
        : Offset(
            renderBox.size.width / 2,
            renderBox.size.height / 2,
          );

    final ImageDrawable drawable;

    if (fillCanvas == true) {
      drawable = ImageDrawable(image: image, position: center, fillCanvas: true);
    } else if (size == null) {
      drawable = ImageDrawable(image: image, position: center);
    } else {
      drawable = ImageDrawable.fittedToSize(image: image, position: center, size: size);
    }

    if (paintLevel) {
      clearDrawables(newAction: true);
      addDrawables(paintLevelDrawables: [drawable], topLevelDrawables: [], newAction: false);
    } else {
      addDrawables(paintLevelDrawables: [], topLevelDrawables: [drawable]);
    }
  }

  /// Renders the background and all other drawables to a [ui.Image] object.
  ///
  /// The size of the output image is controlled by [size].
  /// All drawables will be scaled according to that image size.
  Future<ui.Image> renderImage(Size size) async {
    if (false) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = Painter(
        drawables: value.paintLevelDrawables + value.topLevelDrawables,
        scale: painterKey.currentContext?.size ?? size,
        background: value.background,
      );
      print("render image");
      painter.paint(canvas, size);
      return await recorder.endRecording().toImage(size.width.floor(), size.height.floor());
    } else {
      RenderRepaintBoundary boundary = screenshotKey.currentContext?.findRenderObject() as RenderRepaintBoundary;
      ui.Image image =
          await boundary.toImage(pixelRatio: max(size.width / boundary.size.width, size.height / boundary.size.height));
      return image;
    }
  }

  /// The currently selected object drawable.
  ObjectDrawable? get selectedObjectDrawable => value.selectedObjectDrawable;

  /// Selects an object drawable from the list of top level drawables.
  ///
  /// If the [drawable] is not in the list of drawables or is the same as
  /// [selectedObjectDrawable], nothing happens and [notifyListeners] is not called.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void selectObjectDrawable(ObjectDrawable? drawable) {
    if (drawable == value.selectedObjectDrawable) return;
    if (drawable != null && !value.topLevelDrawables.contains(drawable)) return;
    value = value.copyWith(
      selectedObjectDrawable: drawable,
    );
  }

  /// Deselects the object drawable from the drawables.
  ///
  /// [isRemoved] is whether the deselection happened because the selected
  /// object drawable was deleted. If so, the controller will send a
  /// [SelectedObjectDrawableRemovedEvent] to listening widgets.
  ///
  /// If [selectedObjectDrawable] is already `null`, nothing happens
  /// and [notifyListeners] is not called.
  ///
  /// Calling this will notify all the listeners of this [PainterController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void deselectObjectDrawable({bool isRemoved = false}) {
    if (selectedObjectDrawable != null && isRemoved) {
      _eventsSteamController.add(const SelectedObjectDrawableRemovedEvent());
    }
    selectObjectDrawable(null);
  }
}

/// The current paint mode, drawables and background values of a [FlutterPainter] widget.
@immutable
class PainterControllerValue {
  /// The current paint mode of the widget.
  final PainterSettings settings;

  /// The list of drawables currently present to be painted in the drawing layer.
  final List<Drawable> _paintLevelDrawables;

  /// The list of drawables currently present to be painted that cannot be drawn over.
  final List<Drawable> _topLevelDrawables;

  /// The current background drawable of the widget.
  final BackgroundDrawable? background;

  /// The currently selected object drawable.
  final ObjectDrawable? selectedObjectDrawable;

  /// Creates a new [PainterControllerValue] with the provided [settings] and [background].
  ///
  /// The user can pass a list of initial [drawables] which will be drawn without user interaction.
  const PainterControllerValue({
    required this.settings,
    List<Drawable> paintLevelDrawables = const [],
    List<Drawable> topLevelDrawables = const [],
    this.background,
    this.selectedObjectDrawable,
  })  : _paintLevelDrawables = paintLevelDrawables,
        _topLevelDrawables = topLevelDrawables;

  /// Getter for the current paint level drawables.
  ///
  /// The returned list is unmodifiable.
  List<Drawable> get paintLevelDrawables => List.unmodifiable(_paintLevelDrawables);

  /// Getter for the current top level drawables.
  ///
  /// The returned list is unmodifiable.
  List<Drawable> get topLevelDrawables => List.unmodifiable(_topLevelDrawables);

  /// Creates a copy of this value but with the given fields replaced with the new values.
  PainterControllerValue copyWith({
    PainterSettings? settings,
    List<Drawable>? paintLevelDrawables,
    List<Drawable>? topLevelDrawables,
    BackgroundDrawable? background = _NoBackgroundPassedBackgroundDrawable.instance,
    ObjectDrawable? selectedObjectDrawable = _NoObjectPassedBackgroundDrawable.instance,
  }) {
    return PainterControllerValue(
      settings: settings ?? this.settings,
      paintLevelDrawables: paintLevelDrawables ?? _paintLevelDrawables,
      topLevelDrawables: topLevelDrawables ?? _topLevelDrawables,
      background: background == _NoBackgroundPassedBackgroundDrawable.instance ? this.background : background,
      selectedObjectDrawable: selectedObjectDrawable == _NoObjectPassedBackgroundDrawable.instance
          ? this.selectedObjectDrawable
          : selectedObjectDrawable,
    );
  }

  /// Checks if two [PainterControllerValue] objects are equal or not.
  @override
  bool operator ==(Object other) {
    return other is PainterControllerValue &&
        (const ListEquality().equals(_paintLevelDrawables, other._paintLevelDrawables) &&
            (const ListEquality().equals(_topLevelDrawables, other._topLevelDrawables) &&
                background == other.background &&
                settings == other.settings &&
                selectedObjectDrawable == other.selectedObjectDrawable));
  }

  @override
  int get hashCode => Object.hash(
      Object.hashAll(_paintLevelDrawables), Object.hashAll(_topLevelDrawables), background, settings, selectedObjectDrawable);
}

/// Private class that is used internally to represent no
/// [BackgroundDrawable] argument passed for [PainterControllerValue.copyWith].
class _NoBackgroundPassedBackgroundDrawable extends BackgroundDrawable {
  /// Single instance.
  static const _NoBackgroundPassedBackgroundDrawable instance = _NoBackgroundPassedBackgroundDrawable._();

  /// Private constructor.
  const _NoBackgroundPassedBackgroundDrawable._() : super();

  /// Unimplemented implementation of the draw method.
  @override
  void draw(ui.Canvas canvas, ui.Size size) {
    throw UnimplementedError(
        "This background drawable is only to hold the default value in the PainterControllerValue copyWith method, and must not be used otherwise.");
  }

  @override
  ui.Size getSize() {
    throw UnimplementedError(
        "This background drawable is only to hold the default value in the PainterControllerValue copyWith method, and must not be used otherwise.");
  }
}

/// Private class that is used internally to represent no
/// [BackgroundDrawable] argument passed for [PainterControllerValue.copyWith].
class _NoObjectPassedBackgroundDrawable extends ObjectDrawable {
  /// Single instance.
  static const _NoObjectPassedBackgroundDrawable instance = _NoObjectPassedBackgroundDrawable._();

  /// Private constructor.
  const _NoObjectPassedBackgroundDrawable._()
      : super(
          position: const Offset(0, 0),
        );

  @override
  ObjectDrawable copyWith(
      {bool? hidden,
      Set<ObjectDrawableAssist>? assists,
      ui.Offset? position,
      double? rotation,
      double? scale,
      bool? locked}) {
    throw UnimplementedError(
        "This object drawable is only to hold the default value in the PainterControllerValue copyWith method, and must not be used otherwise.");
  }

  @override
  void drawObject(ui.Canvas canvas, ui.Size size) {
    throw UnimplementedError(
        "This object drawable is only to hold the default value in the PainterControllerValue copyWith method, and must not be used otherwise.");
  }

  @override
  ui.Size getSize({double minWidth = 0.0, double maxWidth = double.infinity}) {
    throw UnimplementedError(
        "This object drawable is only to hold the default value in the PainterControllerValue copyWith method, and must not be used otherwise.");
  }
}
