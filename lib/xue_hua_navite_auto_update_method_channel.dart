import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/models.dart';
import 'src/sha256.dart';
import 'xue_hua_navite_auto_update_platform_interface.dart';

/// An implementation of [XueHuaNaviteAutoUpdatePlatform] that uses method channels.
class MethodChannelXueHuaNaviteAutoUpdate
    extends XueHuaNaviteAutoUpdatePlatform {
  /// The method channel used to interact with the native desktop platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('xue_hua_navite_auto_update');

  @override
  Future<UpdateEnvironmentInfo> checkEnvironment() async {
    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'checkEnvironment',
    );
    if (result == null) {
      throw PlatformException(
        code: 'NULL_ENVIRONMENT_RESPONSE',
        message: 'Native checkEnvironment returned null.',
      );
    }
    return UpdateEnvironmentInfo.fromMap(result);
  }

  @override
  Future<bool> verifyPackageChecksum({
    required String filePath,
    required String expectedSha256,
  }) async {
    final trimmedPath = filePath.trim();
    final trimmedExpected = expectedSha256.trim().toLowerCase();
    if (trimmedPath.isEmpty || trimmedExpected.length != 64) {
      return false;
    }

    try {
      final result = await methodChannel.invokeMethod<bool>(
        'verifyPackageChecksum',
        <String, Object?>{
          'filePath': trimmedPath,
          'expectedSha256': trimmedExpected,
        },
      );
      if (result != null) {
        return result;
      }
    } on MissingPluginException {
      // Fall back to pure-Dart streaming SHA-256 calculation when running in
      // pure Dart tests or environments without the native channel bound.
    }

    final file = File(trimmedPath);
    if (!await file.exists()) {
      return false;
    }
    final actualDigest = await StreamingSha256.computeFileSha256(trimmedPath);
    return StreamingSha256.equalsDigest(actualDigest, trimmedExpected);
  }

  @override
  Future<void> installAndRelaunch({
    required String packagePath,
    required UpdatePackageType packageType,
    bool showProgressDialog = true,
    UpdateProgressStrings strings = const UpdateProgressStrings(),
    List<String> relaunchArgs = const <String>[],
    bool exitCurrentApp = true,
  }) async {
    await methodChannel.invokeMethod<void>(
      'installAndRelaunch',
      <String, Object?>{
        'packagePath': packagePath,
        'packageType': packageType.wireValue,
        'showProgressDialog': showProgressDialog,
        'strings': strings.toMap(),
        'relaunchArgs': relaunchArgs,
        'exitCurrentApp': exitCurrentApp,
      },
    );
  }
}
