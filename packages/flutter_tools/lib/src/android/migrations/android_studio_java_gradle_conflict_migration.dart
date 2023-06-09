// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import '../../base/file_system.dart';
import '../../base/os.dart';
import '../../base/platform.dart';
import '../../base/process.dart';
import '../../base/project_migrator.dart';
import '../../base/version.dart';
import '../../project.dart';
import '../android_sdk.dart';
import '../android_studio.dart';
import '../gradle_utils.dart';

// Android Studio 2022.2 "Flamingo" is the first to bundle a Java 17 JDK.
// Previous versions bundled a Java 11 JDK.
@visibleForTesting
final Version androidStudioFlamingo = Version(2022, 2, 0);

const String _gradleVersion7_6_1 = r'7.6.1';

// String that can be placed in the gradle-wrapper.properties to opt out of this
// migrator.
@visibleForTesting
const String optOutFlag = 'NoFlutterGradleWrapperUpgrade';
// Only the major version matters.
final Version flamingoBundledJava = Version(17, 0, 0);

// These gradle versions were chosen because they
// 1. Were output by 'flutter create' at some point in flutter's history and
// 2. Are less than 7.3, the lowest supported gradle version for JDK 17
const List<String> gradleVersionsToUpgradeFrom =
    <String>['5.6.2', '6.7'];

// Define log messages as constants to re-use in testing.
@visibleForTesting
const String gradleWrapperNotFound =
    'gradle-wrapper.properties not found, skipping Gradle-Java version compatibility check.';
@visibleForTesting
const String androidStudioNotFound =
    'Android Studio version could not be detected, '
    'skipping Gradle-Java version compatibility check.';
@visibleForTesting
const String androidStudioVersionBelowFlamingo =
    'Version of Android Studio is less than Flamingo (the first impacted version),'
    ' no migration attempted.';
@visibleForTesting
const String javaVersionNot17 =
    'Version of Java is different than impacted version, no migration attempted.';
@visibleForTesting
const String javaVersionNotFound =
    'Version of Java not found, no migration attempted.';
@visibleForTesting
const String conflictDetected = 'Conflict detected between versions of Android Studio '
    'and Gradle, upgrading Gradle version from current to 7.4';
@visibleForTesting
const String gradleVersionNotFound = 'Failed to parse Gradle version from distribution url, '
    'skipping Gradle-Java version compatibility check.';
@visibleForTesting
const String optOutFlagEnabled = 'Skipping Android Studio Java-Gradle compatibility '
    "because opt out flag: '$optOutFlag' is enabled in gradle-wrapper.properties file.";


/// Migrate to a newer version of Gradle when the existing one does not support
/// the version of Java provided by the detected Android Studio version.
///
/// For more info see the Gradle-Java compatibility matrix:
/// https://docs.gradle.org/current/userguide/compatibility.html
class AndroidStudioJavaGradleConflictMigration extends ProjectMigrator {
  AndroidStudioJavaGradleConflictMigration(
    super.logger,
    {required AndroidProject project,
    AndroidStudio? androidStudio,
    required FileSystem fileSystem,
    required ProcessUtils processUtils,
    required Platform platform,
    required OperatingSystemUtils os,
    AndroidSdk? androidSdk,
  }) : _gradleWrapperPropertiesFile = getGradleWrapperFile(project.hostAppGradleRoot),
       _androidStudio = androidStudio,
       _fileSystem = fileSystem,
       _processUtils = processUtils,
       _platform = platform,
       _os = os,
       _androidSdk = androidSdk;
  final File _gradleWrapperPropertiesFile;
  final AndroidStudio? _androidStudio;
  final FileSystem _fileSystem;
  final ProcessUtils _processUtils;
  final Platform _platform;
  final OperatingSystemUtils _os;
  final AndroidSdk? _androidSdk;

  @override
  void migrate() {
    if (!_gradleWrapperPropertiesFile.existsSync()) {
      logger.printTrace(gradleWrapperNotFound);
      return;
    }

    if (_androidStudio == null) {
      logger.printTrace(androidStudioNotFound);
      return;
    } else if (_androidStudio!.version!.major < androidStudioFlamingo.major) {
      logger.printTrace(androidStudioVersionBelowFlamingo);
      return;
    }

    final String? javaVersionString = _androidSdk?.getJavaVersion(
      androidStudio: _androidStudio,
      fileSystem: _fileSystem,
      operatingSystemUtils: _os,
      platform: _platform,
      processUtils: _processUtils,
    );
    final Version? javaVersion = Version.parse(javaVersionString);
    if (javaVersion == null) {
      logger.printTrace(javaVersionNotFound);
      return;
    }

    if (javaVersion.major != flamingoBundledJava.major) {
      logger.printTrace(javaVersionNot17);
      return;
    }

    processFileLines(_gradleWrapperPropertiesFile);
  }

  @override
  String migrateFileContents(String fileContents) {
    if (fileContents.contains(optOutFlag)) {
      logger.printTrace(optOutFlagEnabled);
      return fileContents;
    }
    final RegExpMatch? gradleDistributionUrl = gradleOrgVersionMatch.firstMatch(fileContents);
    if (gradleDistributionUrl == null || gradleDistributionUrl.groupCount < 1) {
      logger.printTrace(gradleVersionNotFound);
      return fileContents;
    }
    final String existingVersionString = gradleDistributionUrl[1]!;
    if (gradleVersionsToUpgradeFrom.contains(existingVersionString)) {
      logger.printStatus('Conflict detected between Android Studio Java version and Gradle version, '
          'upgrading Gradle version from $existingVersionString to $_gradleVersion7_6_1.');
      final String gradleDistributionUrlString = gradleDistributionUrl.group(0)!;
      final String upgradedDistributionUrl =
        gradleDistributionUrlString.replaceAll(existingVersionString, _gradleVersion7_6_1);
      fileContents = fileContents.replaceFirst(gradleOrgVersionMatch, upgradedDistributionUrl);
    }
    return fileContents;
  }
}
