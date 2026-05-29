import 'dart:ffi';

import 'package:jni/jni.dart';
import 'package:maplibre_android/src/jni.g.dart' as jni;

/// JNI bridge for native glTF location model rendering on Android.
abstract final class LocationModelBridge {
  static final _registryClass = JClass.forName(
    'com.github.josxha.maplibre.MapLibreRegistry',
  );
  static final _managerClass = JClass.forName(
    'com.github.josxha.maplibre.location.LocationModelManager',
  );

  static final _registerPlatformView = _registryClass.staticMethodId(
    'registerPlatformView',
    '(ILandroid/widget/FrameLayout;)V',
  );
  static final _unregisterPlatformView = _registryClass.staticMethodId(
    'unregisterPlatformView',
    '(I)V',
  );
  static final _attach = _managerClass.staticMethodId(
    'attach',
    '(I[BLjava/lang/String;F)V',
  );
  static final _update = _managerClass.staticMethodId('update', '(IFFFZ)V');
  static final _detach = _managerClass.staticMethodId('detach', '(I)V');

  static void registerPlatformView(int viewId, jni.FrameLayout view) {
    _callStaticVoid2IntObject(
      _registryClass.reference.pointer,
      _registerPlatformView.pointer,
      viewId,
      view.reference.pointer,
    );
  }

  static void unregisterPlatformView(int viewId) {
    _callStaticVoidInt(
      _registryClass.reference.pointer,
      _unregisterPlatformView.pointer,
      viewId,
    );
  }

  static void attach({
    required int viewId,
    required List<int> modelBytes,
    required String fileName,
    required double scale,
  }) {
    using((arena) {
      final bytes = JByteArray.from(modelBytes)..releasedBy(arena);
      final name = fileName.toJString()..releasedBy(arena);
      _callStaticAttach(
        _managerClass.reference.pointer,
        _attach.pointer,
        viewId,
        bytes.reference.pointer,
        name.reference.pointer,
        scale,
      );
    });
  }

  static void update({
    required int viewId,
    required double screenX,
    required double screenY,
    required double bearing,
    required bool visible,
  }) {
    _callStaticUpdate(
      _managerClass.reference.pointer,
      _update.pointer,
      viewId,
      screenX,
      screenY,
      bearing,
      visible,
    );
  }

  static void detach(int viewId) {
    _callStaticVoidInt(
      _managerClass.reference.pointer,
      _detach.pointer,
      viewId,
    );
  }
}

void _callStaticVoidInt(
  Pointer<Void> clazz,
  Pointer<JMethodID> method,
  int arg,
) {
  final fn =
      ProtectedJniExtensions.lookup<
            NativeFunction<
              JThrowablePtr Function(Pointer<Void>, Pointer<JMethodID>, Int32)
            >
          >('globalEnv_CallStaticVoidMethod')
          .asFunction<
            JThrowablePtr Function(Pointer<Void>, Pointer<JMethodID>, int)
          >();
  fn(clazz, method, arg).check();
}

void _callStaticVoid2IntObject(
  Pointer<Void> clazz,
  Pointer<JMethodID> method,
  int viewId,
  Pointer<Void> frameLayout,
) {
  final fn =
      ProtectedJniExtensions.lookup<
            NativeFunction<
              JThrowablePtr Function(
                Pointer<Void>,
                Pointer<JMethodID>,
                Int32,
                Pointer<Void>,
              )
            >
          >('globalEnv_CallStaticVoidMethod')
          .asFunction<
            JThrowablePtr Function(
              Pointer<Void>,
              Pointer<JMethodID>,
              int,
              Pointer<Void>,
            )
          >();
  fn(clazz, method, viewId, frameLayout).check();
}

void _callStaticAttach(
  Pointer<Void> clazz,
  Pointer<JMethodID> method,
  int viewId,
  Pointer<Void> bytes,
  Pointer<Void> fileName,
  double scale,
) {
  final fn =
      ProtectedJniExtensions.lookup<
            NativeFunction<
              JThrowablePtr Function(
                Pointer<Void>,
                Pointer<JMethodID>,
                Int32,
                Pointer<Void>,
                Pointer<Void>,
                Float,
              )
            >
          >('globalEnv_CallStaticVoidMethod')
          .asFunction<
            JThrowablePtr Function(
              Pointer<Void>,
              Pointer<JMethodID>,
              int,
              Pointer<Void>,
              Pointer<Void>,
              double,
            )
          >();
  fn(clazz, method, viewId, bytes, fileName, scale).check();
}

void _callStaticUpdate(
  Pointer<Void> clazz,
  Pointer<JMethodID> method,
  int viewId,
  double x,
  double y,
  double bearing,
  bool visible,
) {
  final fn =
      ProtectedJniExtensions.lookup<
            NativeFunction<
              JThrowablePtr Function(
                Pointer<Void>,
                Pointer<JMethodID>,
                Int32,
                Float,
                Float,
                Float,
                Int8,
              )
            >
          >('globalEnv_CallStaticVoidMethod')
          .asFunction<
            JThrowablePtr Function(
              Pointer<Void>,
              Pointer<JMethodID>,
              int,
              double,
              double,
              double,
              int,
            )
          >();
  fn(clazz, method, viewId, x, y, bearing, visible ? 1 : 0).check();
}

extension on JThrowablePtr {
  void check() {
    if (address != 0) {
      JThrowable.fromReference(this).throwException();
    }
  }
}
