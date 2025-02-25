# Copyright 2019 The Bazel Authors. All rights reserved.
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

"""ios_extensionkit_extension Starlark tests."""

load(
    ":common.bzl",
    "common",
)
load(
    ":rules/apple_verification_test.bzl",
    "apple_verification_test",
)
load(
    ":rules/common_verification_tests.bzl",
    "archive_contents_test",
    "bitcode_symbol_map_test",
    "entry_point_test",
)
load(
    ":rules/dsyms_test.bzl",
    "dsyms_test",
)
load(
    ":rules/infoplist_contents_test.bzl",
    "infoplist_contents_test",
)
load(
    ":rules/linkmap_test.bzl",
    "linkmap_test",
)

def ios_extensionkit_extension_test_suite(name):
    """Test suite for ios_extension.

    Args:
      name: the base name to be used in things created by this macro
    """
    apple_verification_test(
        name = "{}_codesign_test".format(name),
        build_type = "simulator",
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension",
        verifier_script = "verifier_scripts/codesign_verifier.sh",
        tags = [name],
    )

    apple_verification_test(
        name = "{}_fmwk_provisioned_codesign_test".format(name),
        build_type = "simulator",
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension_with_fmwk_provisioned",
        verifier_script = "verifier_scripts/codesign_verifier.sh",
        tags = [name],
    )

    apple_verification_test(
        name = "{}_fmwk_provisioned_codesign_asan_test".format(name),
        build_type = "simulator",
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension_with_fmwk_provisioned",
        verifier_script = "verifier_scripts/codesign_verifier.sh",
        sanitizer = "asan",
        tags = [name],
    )

    apple_verification_test(
        name = "{}_entitlements_simulator_test".format(name),
        build_type = "simulator",
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension",
        verifier_script = "verifier_scripts/entitlements_verifier.sh",
        tags = [name],
    )

    apple_verification_test(
        name = "{}_entitlements_device_test".format(name),
        build_type = "device",
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension",
        verifier_script = "verifier_scripts/entitlements_verifier.sh",
        tags = [name],
    )

    dsyms_test(
        name = "{}_dsyms_test".format(name),
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension",
        expected_direct_dsyms = ["exappextension.appex"],
        expected_transitive_dsyms = ["exappextension.appex"],
        tags = [name],
    )

    infoplist_contents_test(
        name = "{}_plist_test".format(name),
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension",
        expected_values = {
            "BuildMachineOSBuild": "*",
            "CFBundleExecutable": "exappextension",
            "CFBundleIdentifier": "com.google.example.exappextension",
            "CFBundleName": "exappextension",
            "CFBundlePackageType": "XPC!",
            "CFBundleSupportedPlatforms:0": "iPhone*",
            "DTCompiler": "com.apple.compilers.llvm.clang.1_0",
            "DTPlatformBuild": "*",
            "DTPlatformName": "iphone*",
            "DTPlatformVersion": "*",
            "DTSDKBuild": "*",
            "DTSDKName": "iphone*",
            "DTXcode": "*",
            "DTXcodeBuild": "*",
            "MinimumOSVersion": common.min_os_ios.baseline,
            "UIDeviceFamily:0": "1",
        },
        tags = [name],
    )

    infoplist_contents_test(
        name = "{}_multiple_plist_test".format(name),
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension_multiple_infoplists",
        expected_values = {
            "AnotherKey": "AnotherValue",
            "CFBundleExecutable": "exappextension_multiple_infoplists",
        },
        tags = [name],
    )

    # Tests that the archive contains Bitcode symbol maps when Bitcode is
    # enabled.
    bitcode_symbol_map_test(
        name = "{}_archive_contains_bitcode_symbol_maps_test".format(name),
        binary_paths = [
            "Payload/app_with_exappextension.app/app_with_exappextension",
            "Payload/app_with_exappextension.app/Extensions/exappextension.appex/exappextension",
        ],
        target_under_test = "//test/starlark_tests/targets_under_test/ios:app_with_exappextension",
        tags = [name],
    )

    # Tests that the linkmap outputs are produced when `--objc_generate_linkmap`
    # is present.
    linkmap_test(
        name = "{}_linkmap_test".format(name),
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension",
        tags = [name],
    )

    # Tests that the provisioning profile is present when built for device.
    archive_contents_test(
        name = "{}_contains_provisioning_profile_test".format(name),
        build_type = "device",
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension",
        contains = [
            "$BUNDLE_ROOT/embedded.mobileprovision",
        ],
        tags = [name],
    )

    archive_contents_test(
        name = "{}_correct_rpath_header_value_test".format(name),
        build_type = "device",
        binary_test_file = "$CONTENT_ROOT/exappextension",
        macho_load_commands_contain = [
            "path @executable_path/Frameworks (offset 12)",
            "path @executable_path/../../Frameworks (offset 12)",
        ],
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension",
        tags = [name],
    )

    entry_point_test(
        name = "{}_entry_point_nsextensionmain_test".format(name),
        build_type = "simulator",
        entry_point = "_NSExtensionMain",
        target_under_test = "//test/starlark_tests/targets_under_test/ios:exappextension",
        tags = [name],
    )

    # Verify that Swift dylibs are packaged with the application, not with the extension, when only
    # an extension uses Swift. And to be safe, verify that they aren't packaged with the extension.
    archive_contents_test(
        name = "{}_device_swift_dylibs_present".format(name),
        build_type = "device",
        target_under_test = "//test/starlark_tests/targets_under_test/ios:app_with_swift_exappextension",
        not_contains = ["$BUNDLE_ROOT/Extensions/exappextension.appex/Frameworks/libswiftCore.dylib"],
        contains = [
            "$BUNDLE_ROOT/Frameworks/libswiftCore.dylib",
            "$ARCHIVE_ROOT/SwiftSupport/iphoneos/libswiftCore.dylib",
        ],
        tags = [name],
    )
    archive_contents_test(
        name = "{}_simulator_swift_dylibs_present".format(name),
        build_type = "simulator",
        target_under_test = "//test/starlark_tests/targets_under_test/ios:app_with_swift_exappextension",
        contains = ["$BUNDLE_ROOT/Frameworks/libswiftCore.dylib"],
        not_contains = ["$BUNDLE_ROOT/Extensions/exappextension.appex/Frameworks/libswiftCore.dylib"],
        tags = [name],
    )

    native.test_suite(
        name = name,
        tags = [name],
    )
