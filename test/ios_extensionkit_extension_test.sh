#!/bin/bash

# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

# Integration tests for bundling iOS apps with extensions.

function set_up() {
  mkdir -p app
}

function tear_down() {
  rm -rf app
}

# Creates common source, targets, and basic plist for iOS applications.
function create_common_files() {
  cat > app/BUILD <<EOF
load("@build_bazel_rules_apple//apple:ios.bzl",
     "ios_application",
     "ios_extension",
    )
load("@build_bazel_rules_apple//apple:apple.bzl",
     "apple_dynamic_framework_import",
     "apple_static_framework_import",
    )
objc_library(
    name = "lib",
    hdrs = ["Foo.h"],
    srcs = ["main.m"],
)
EOF

  cat > app/Foo.h <<EOF
#import <Foundation/Foundation.h>
// This dummy class is needed to generate code in the extension target,
// which does not take main() from here, rather from an SDK.
@interface Foo: NSObject
- (void)doSomething;
@end
EOF

  cat > app/main.m <<EOF
#import <Foundation/Foundation.h>
#import "app/Foo.h"
@implementation Foo
- (void)doSomething { }
@end
int main(int argc, char **argv) {
  return 0;
}
EOF

  cat > app/Info-App.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "APPL";
  CFBundleShortVersionString = "1.0";
  CFBundleVersion = "1.0";
}
EOF

  cat > app/Info-Ext.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "XPC!";
  CFBundleShortVersionString = "1.0";
  CFBundleVersion = "1.0";
  EXAppExtensionAttributes = {
    EXExtensionPointIdentifier = "com.apple.appintents-extension";
  };
}
EOF
}

# Usage: create_minimal_ios_application_extension [product type]
#
# Creates a minimal iOS application extension target. The optional product type
# is the Starlark constant that should be set on the extension using the
# `product_type` attribute.
function create_minimal_ios_application_extension() {
  if [[ ! -f app/BUILD ]]; then
    fail "create_common_files must be called first."
  fi

  product_type="${1:-}"

  cat >> app/BUILD <<EOF
ios_extension(
    name = "ext",
    extensionkit_extension = True,
    bundle_id = "my.bundle.id.extension",
    families = ["iphone"],
    infoplists = ["Info-Ext.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
EOF

  if [[ -n "$product_type" ]]; then
  cat >> app/BUILD <<EOF
    product_type = $product_type,
EOF
  fi

  cat >> app/BUILD <<EOF
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
EOF
}

# Usage: create_minimal_ios_application_with_extension [product type]
#
# Creates a minimal iOS application target. The optional product type is
# the Starlark constant that should be set on the extension using the
# `product_type` attribute.
function create_minimal_ios_application_with_extension() {
  if [[ ! -f app/BUILD ]]; then
    fail "create_common_files must be called first."
  fi

  product_type="${1:-}"

  create_minimal_ios_application_extension "$product_type"

  cat >> app/BUILD <<EOF
ios_application(
    name = "app",
    bundle_id = "my.bundle.id",
    extensions = [":ext"],
    families = ["iphone"],
    infoplists = ["Info-App.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
EOF
}

# Usage: create_minimal_ios_application_and_extension_with_framework_import <dynamic> <import_rule>
#
# Creates minimal iOS application and extension targets that depends on a
# framework import target. The `dynamic` argument should be `True` or `False`
# and will be used to populate the framework's `is_dynamic` attribute.
function create_minimal_ios_application_and_extension_with_framework_import() {
  readonly framework_type="$1"
  readonly import_rule="$2"

  cat >> app/BUILD <<EOF
ios_application(
    name = "app",
    bundle_id = "my.bundle.id",
    families = ["iphone"],
    infoplists = ["Info-App.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [
        ":frameworkDependingLib",
        ":lib",
    ],
)
ios_extension(
    name = "ext",
    extensionkit_extension = True,
    bundle_id = "my.bundle.id.extension",
    families = ["iphone"],
    infoplists = ["Info-Ext.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
objc_library(
    name = "frameworkDependingLib",
    deps = [":fmwk"],
)
$import_rule(
    name = "fmwk",
    framework_imports = glob(["fmwk.framework/**"]),
    features = ["-parse_headers"],
)
EOF

  mkdir -p app/fmwk.framework
  if [[ $framework_type == dynamic ]]; then
    cp $(rlocation build_bazel_rules_apple/test/testdata/binaries/empty_dylib_lipobin.dylib) \
        app/fmwk.framework/fmwk
  else
    cp $(rlocation build_bazel_rules_apple/test/testdata/binaries/empty_staticlib_lipo.a) \
        app/fmwk.framework/fmwk
  fi

  cat > app/fmwk.framework/Info.plist <<EOF
Dummy plist
EOF

  cat > app/fmwk.framework/resource.txt <<EOF
Dummy resource
EOF

  mkdir -p app/fmwk.framework/Headers
  cat > app/fmwk.framework/Headers/fmwk.h <<EOF
This shouldn't get included
EOF

  mkdir -p app/fmwk.framework/Modules
  cat > app/fmwk.framework/Headers/module.modulemap <<EOF
This shouldn't get included
EOF
}

# Test missing the CFBundleVersion fails the build.
function test_missing_version_fails() {
  create_common_files
  create_minimal_ios_application_with_extension

  # Replace the file, but without CFBundleVersion.
  cat > app/Info-Ext.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "XPC!";
  CFBundleShortVersionString = "1.0";
  EXAppExtensionAttributes = {
    EXExtensionPointIdentifier = "com.apple.appintents-extension";
  };
}
EOF

  ! do_build ios //app:app \
    || fail "Should fail build"

  expect_log 'Target "//app:ext" is missing CFBundleVersion.'
}

# Test missing the CFBundleShortVersionString fails the build.
function test_missing_short_version_fails() {
  create_common_files
  create_minimal_ios_application_with_extension

  # Replace the file, but without CFBundleVersion.
  cat > app/Info-Ext.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "XPC!";
  CFBundleVersion = "1.0";
  EXAppExtensionAttributes = {
    EXExtensionPointIdentifier = "com.apple.appintents-extension";
  };
}
EOF

  ! do_build ios //app:app \
    || fail "Should fail build"

  expect_log 'Target "//app:ext" is missing CFBundleShortVersionString.'
}

# Tests that if an application contains an extension with a bundle ID that is
# not the app's ID followed by at least another component, the build fails.
function test_extension_with_mismatched_bundle_id_fails_to_build() {
  cat > app/BUILD <<EOF
load("@build_bazel_rules_apple//apple:ios.bzl",
     "ios_application",
     "ios_extension",
    )
objc_library(
    name = "lib",
    srcs = ["main.m"],
)
ios_application(
    name = "app",
    bundle_id = "my.bundle.id",
    extensions = [":ext"],
    families = ["iphone"],
    infoplists = ["Info-App.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
ios_extension(
    name = "ext",
    extensionkit_extension = True,
    bundle_id = "my.extension.bundle.id",
    families = ["iphone"],
    infoplists = ["Info-Ext.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
EOF

  cat > app/main.m <<EOF
int main(int argc, char **argv) {
  return 0;
}
EOF

  cat > app/Info-App.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "APPL";
  CFBundleShortVersionString = "1.0";
  CFBundleVersion = "1.0";
}
EOF

  cat > app/Info-Ext.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "XPC!";
  CFBundleShortVersionString = "1.0";
  CFBundleVersion = "1.0";
  EXAppExtensionAttributes = {
    EXExtensionPointIdentifier = "com.apple.appintents-extension";
  };
}
EOF

  ! do_build ios //app:app || fail "Should not build"
  expect_log 'While processing target "//app:app"; the CFBundleIdentifier of the child target "//app:ext" should have "my.bundle.id." as its prefix, but found "my.extension.bundle.id".'
}

# Tests that if an application contains an extension with different
# CFBundleShortVersionString the build fails.
function test_extension_with_mismatched_short_version_fails_to_build() {
  cat > app/BUILD <<EOF
load("@build_bazel_rules_apple//apple:ios.bzl",
     "ios_application",
     "ios_extension",
    )
objc_library(
    name = "lib",
    srcs = ["main.m"],
)
ios_application(
    name = "app",
    bundle_id = "my.bundle.id",
    extensions = [":ext"],
    families = ["iphone"],
    infoplists = ["Info-App.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
ios_extension(
    name = "ext",
    extensionkit_extension = True,
    bundle_id = "my.bundle.id.extension",
    families = ["iphone"],
    infoplists = ["Info-Ext.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
EOF

  cat > app/main.m <<EOF
int main(int argc, char **argv) {
  return 0;
}
EOF

  cat > app/Info-App.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "APPL";
  CFBundleShortVersionString = "1.0";
  CFBundleVersion = "1.0";
}
EOF

  cat > app/Info-Ext.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "XPC!";
  CFBundleShortVersionString = "1.1";
  CFBundleVersion = "1.0";
  EXAppExtensionAttributes = {
    EXExtensionPointIdentifier = "com.apple.appintents-extension";
  };
}
EOF

  ! do_build ios //app:app || fail "Should not build"
  expect_log "While processing target \"//app:app\"; the CFBundleShortVersionString of the child target \"//app:ext\" should be the same as its parent's version string \"1.0\", but found \"1.1\"."
}

# Tests that if an application contains an extension with different
# CFBundleVersion the build fails.
function test_extension_with_mismatched_version_fails_to_build() {
  cat > app/BUILD <<EOF
load("@build_bazel_rules_apple//apple:ios.bzl",
     "ios_application",
     "ios_extension",
    )
objc_library(
    name = "lib",
    srcs = ["main.m"],
)
ios_application(
    name = "app",
    bundle_id = "my.bundle.id",
    extensions = [":ext"],
    families = ["iphone"],
    infoplists = ["Info-App.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
ios_extension(
    name = "ext",
    extensionkit_extension = True,
    bundle_id = "my.bundle.id.extension",
    families = ["iphone"],
    infoplists = ["Info-Ext.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
EOF

  cat > app/main.m <<EOF
int main(int argc, char **argv) {
  return 0;
}
EOF

  cat > app/Info-App.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "APPL";
  CFBundleShortVersionString = "1.0";
  CFBundleVersion = "1.0";
}
EOF

  cat > app/Info-Ext.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "XPC!";
  CFBundleShortVersionString = "1.0";
  CFBundleVersion = "1.1";
  EXAppExtensionAttributes = {
    EXExtensionPointIdentifier = "com.apple.appintents-extension";
  };
}
EOF

  ! do_build ios //app:app || fail "Should not build"
  expect_log "While processing target \"//app:app\"; the CFBundleVersion of the child target \"//app:ext\" should be the same as its parent's version string \"1.0\", but found \"1.1\"."
}

# Tests that a prebuilt static framework (i.e., apple_static_framework_import)
# is not bundled with the application or extension.
function test_prebuilt_static_apple_framework_import_dependency() {
  create_common_files
  create_minimal_ios_application_and_extension_with_framework_import static apple_static_framework_import

  do_build ios //app:app || fail "Should build"

  # Verify that it's not bundled.
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Frameworks/fmwk.framework/fmwk"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Frameworks/fmwk.framework/Info.plist"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Frameworks/fmwk.framework/resource.txt"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Frameworks/fmwk.framework/Headers/fmwk.h"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/fmwk.framework/Modules/module.modulemap"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appex/Frameworks/fmwk.framework/fmwk"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appex/Frameworks/fmwk.framework/Info.plist"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appex/Frameworks/fmwk.framework/resource.txt"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appexFrameworks/fmwk.framework/Headers/fmwk.h"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appexFrameworks/fmwk.framework/Modules/module.modulemap"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appex/Frameworks/fmwk.framework/fmwk"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appex/Frameworks/fmwk.framework/Info.plist"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appex/Frameworks/fmwk.framework/resource.txt"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appexFrameworks/fmwk.framework/Headers/fmwk.h"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appexFrameworks/fmwk.framework/Modules/module.modulemap"
}

# Tests that a prebuilt dynamic framework (i.e., apple_dynamic_framework_import)
# is bundled properly with the application.
function test_prebuilt_dynamic_apple_framework_import_dependency() {
  create_common_files
  create_minimal_ios_application_and_extension_with_framework_import dynamic apple_dynamic_framework_import

  do_build ios //app:app || fail "Should build"

  # Verify that the framework is bundled with the application and that the
  # binary, plist, and resources are included.
  assert_zip_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Frameworks/fmwk.framework/fmwk"
  assert_zip_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Frameworks/fmwk.framework/Info.plist"
  assert_zip_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Frameworks/fmwk.framework/resource.txt"

  # Verify that Headers and Modules directories are excluded.
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Frameworks/fmwk.framework/Headers/fmwk.h"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Frameworks/fmwk.framework/Modules/module.modulemap"

  # Verify that the framework is not bundled with the extension.
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appex/Frameworks/fmwk.framework/fmwk"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appex/Frameworks/fmwk.framework/Info.plist"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appex/Frameworks/fmwk.framework/resource.txt"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appexFrameworks/fmwk.framework/Headers/fmwk.h"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/PlugIns/ext.appexFrameworks/fmwk.framework/Modules/module.modulemap"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appex/Frameworks/fmwk.framework/fmwk"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appex/Frameworks/fmwk.framework/Info.plist"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appex/Frameworks/fmwk.framework/resource.txt"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appexFrameworks/fmwk.framework/Headers/fmwk.h"
  assert_zip_not_contains "test-bin/app/app.ipa" \
      "Payload/app.app/Extensions/ext.appexFrameworks/fmwk.framework/Modules/module.modulemap"
}

# Tests that ios_extension cannot be a dependency of objc_library.
function test_extension_under_library() {
cat > app/BUILD <<EOF
load("@build_bazel_rules_apple//apple:ios.bzl",
     "ios_extension",
    )
objc_library(
    name = "lib",
    srcs = ["main.m"],
)
objc_library(
    name = "upperlib",
    srcs = ["upperlib.m"],
    deps = [":ext"],
)
ios_extension(
    name = "ext",
    extensionkit_extension = True,
    bundle_id = "my.extension.bundle.id",
    families = ["iphone"],
    infoplists = ["Info-Ext.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
EOF

  cat > app/upperlib.m <<EOF
int foo() { return 0; }
EOF

  cat > app/main.m <<EOF
int main(int argc, char **argv) { return 0; }
EOF

  cat > app/Info-Ext.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
  CFBundleName = "\${PRODUCT_NAME}";
  CFBundlePackageType = "XPC!";
  CFBundleShortVersionString = "1.0";
  CFBundleVersion = "1.0";
  EXAppExtensionAttributes = {
    EXExtensionPointIdentifier = "com.apple.appintents-extension";
  };
}
EOF

  ! do_build ios //app:upperlib || fail "Should not build"
  expect_log 'does not have mandatory providers'
}

function test_application_and_extension_different_minimum_os() {
  create_common_files

  cat >> app/BUILD <<EOF
ios_application(
    name = "app",
    bundle_id = "my.bundle.id",
    extensions = [":ext"],
    families = ["iphone"],
    infoplists = ["Info-App.plist"],
    minimum_os_version = "${MIN_OS_IOS_NPLUS1}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
ios_extension(
    name = "ext",
    extensionkit_extension = True,
    bundle_id = "my.bundle.id.extension",
    families = ["iphone"],
    infoplists = ["Info-Ext.plist"],
    minimum_os_version = "${MIN_OS_IOS}",
    provisioning_profile = "@build_bazel_rules_apple//test/testdata/provisioning:integration_testing_ios.mobileprovision",
    deps = [":lib"],
)
EOF

  do_build ios //app:app || fail "Should build"
}

# Tests that the dSYM outputs are produced when --apple_generate_dsym is
# present and that the dSYM outputs of the extension are also propagated when
# the flag is set.
function test_all_dsyms_propagated() {
  create_common_files
  create_minimal_ios_application_with_extension
  do_build ios \
      --apple_generate_dsym \
      --output_groups=+dsyms \
      //app:app || fail "Should build"

  assert_exists "test-bin/app/app.app.dSYM/Contents/Info.plist"
  assert_exists "test-bin/app/ext.appex.dSYM/Contents/Info.plist"

  assert_zip_contains "test-bin/app/app.ipa" \
    "Payload/app.app/Extensions/ext.appex"
  assert_zip_not_contains "test-bin/app/app.ipa" \
    "Payload/app.app/PlugIns/ext.appex"

  assert_exists \
      "test-bin/app/app.app.dSYM/Contents/Resources/DWARF/app"
  assert_exists \
      "test-bin/app/ext.appex.dSYM/Contents/Resources/DWARF/ext"
}

run_suite "ios_extensionkit_extension bundling tests"
