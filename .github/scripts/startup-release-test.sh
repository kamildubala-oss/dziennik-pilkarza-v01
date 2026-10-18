#!/usr/bin/env bash
# Logi muszą powstać przed wyłączeniem emulatora przez action.
set +e
timeout --signal=TERM 8m bash ./android/gradlew -p android \
  :app:connectedReleaseAndroidTest -PstartupSmoke=true \
  "-Ptarget=$GITHUB_WORKSPACE/integration_test/startup_test.dart" \
  -Ptarget-platform=android-x64 -Pdart-obfuscation=true \
  "-Psplit-debug-info=$GITHUB_WORKSPACE/build/smoke-symbols" \
  -Pandroid.testInstrumentationRunnerArguments.timeout_msec=90000 --stacktrace
result=$?
mkdir -p build/startup-diagnostics
timeout 10s adb logcat -d > build/startup-diagnostics/emulator-logcat.txt 2>&1
exit "$result"
