# Copyright 2018 The Bazel Authors. All rights reserved.
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

"""Implementation of watchOS rules."""

load(
    "@build_bazel_apple_support//lib:xcode_support.bzl",
    "xcode_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:apple_product_type.bzl",
    "apple_product_type",
)
load(
    "@build_bazel_rules_apple//apple/internal:apple_toolchains.bzl",
    "AppleMacToolsToolchainInfo",
    "AppleXPlatToolsToolchainInfo",
)
load(
    "@build_bazel_rules_apple//apple/internal:bundling_support.bzl",
    "bundling_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:codesigning_support.bzl",
    "codesigning_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:cc_info_support.bzl",
    "cc_info_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:entitlements_support.bzl",
    "entitlements_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:features_support.bzl",
    "features_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:linking_support.bzl",
    "linking_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:outputs.bzl",
    "outputs",
)
load(
    "@build_bazel_rules_apple//apple/internal:partials.bzl",
    "partials",
)
load(
    "@build_bazel_rules_apple//apple/internal:platform_support.bzl",
    "platform_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:processor.bzl",
    "processor",
)
load(
    "@build_bazel_rules_apple//apple/internal:resources.bzl",
    "resources",
)
load(
    "@build_bazel_rules_apple//apple/internal:rule_factory.bzl",
    "rule_factory",
)
load(
    "@build_bazel_rules_apple//apple/internal:rule_support.bzl",
    "rule_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:stub_support.bzl",
    "stub_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:swift_support.bzl",
    "swift_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:transition_support.bzl",
    "transition_support",
)
load(
    "@build_bazel_rules_apple//apple/internal/utils:clang_rt_dylibs.bzl",
    "clang_rt_dylibs",
)
load(
    "@build_bazel_rules_apple//apple/internal:framework_import_support.bzl",
    "libraries_to_link_for_dynamic_framework",
)
load(
    "@build_bazel_rules_apple//apple:providers.bzl",
    "AppleFrameworkBundleInfo",
    "WatchosApplicationBundleInfo",
    "WatchosExtensionBundleInfo",
    "WatchosFrameworkBundleInfo",
    "WatchosStaticFrameworkBundleInfo",
)
load(
    "@build_bazel_rules_apple//apple/internal/aspects:swift_dynamic_framework_aspect.bzl",
    "SwiftDynamicFrameworkInfo",
)
load(
    "@build_bazel_rules_swift//swift:swift.bzl",
    "SwiftInfo",
)
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

def _watchos_framework_impl(ctx):
    """Experimental implementation of watchos_framework."""
    actions = ctx.actions
    apple_mac_toolchain_info = ctx.attr._mac_toolchain[AppleMacToolsToolchainInfo]
    apple_xplat_toolchain_info = ctx.attr._xplat_toolchain[AppleXPlatToolsToolchainInfo]
    bin_root_path = ctx.bin_dir.path
    bundle_id = ctx.attr.bundle_id
    bundle_name, bundle_extension = bundling_support.bundle_full_name_from_rule_ctx(ctx)
    executable_name = bundling_support.executable_name(ctx)
    cc_toolchain = find_cpp_toolchain(ctx)
    cc_features = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        language = "objc",
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    features = features_support.compute_enabled_features(
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    label = ctx.label
    platform_prerequisites = platform_support.platform_prerequisites_from_rule_ctx(ctx)
    predeclared_outputs = ctx.outputs
    provisioning_profile = ctx.file.provisioning_profile
    resource_deps = ctx.attr.deps + ctx.attr.resources
    rule_descriptor = rule_support.rule_descriptor(ctx)
    signed_frameworks = []
    if provisioning_profile:
        signed_frameworks = [
            bundle_name + rule_descriptor.bundle_extension,
        ]
    top_level_infoplists = resources.collect(
        attr = ctx.attr,
        res_attrs = ["infoplists"],
    )
    top_level_resources = resources.collect(
        attr = ctx.attr,
        res_attrs = ["resources"],
    )

    extra_linkopts = [
        "-dynamiclib",
        "-Wl,-install_name,@rpath/{name}{extension}/{name}".format(
            extension = bundle_extension,
            name = bundle_name,
        ),
    ]
    if ctx.attr.extension_safe:
        extra_linkopts.append("-fapplication-extension")

    link_result = linking_support.register_binary_linking_action(
        ctx,
        avoid_deps = ctx.attr.frameworks,
        # Frameworks do not have entitlements.
        entitlements = None,
        extra_linkopts = extra_linkopts,
        platform_prerequisites = platform_prerequisites,
        stamp = ctx.attr.stamp,
    )
    binary_artifact = link_result.binary
    debug_outputs = linking_support.debug_outputs_by_architecture(link_result.outputs)

    archive_for_embedding = outputs.archive_for_embedding(
        actions = actions,
        bundle_name = bundle_name,
        bundle_extension = bundle_extension,
        executable_name = executable_name,
        label_name = label.name,
        rule_descriptor = rule_descriptor,
        platform_prerequisites = platform_prerequisites,
        predeclared_outputs = predeclared_outputs,
    )

    processor_partials = [
        partials.apple_bundle_info_partial(
            actions = actions,
            bundle_extension = bundle_extension,
            bundle_id = bundle_id,
            bundle_name = bundle_name,
            executable_name = executable_name,
            extension_safe = ctx.attr.extension_safe,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            predeclared_outputs = predeclared_outputs,
            product_type = rule_descriptor.product_type,
        ),
        partials.binary_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            bundle_name = bundle_name,
            executable_name = executable_name,
            label_name = label.name,
        ),
        partials.bitcode_symbols_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            bitcode_symbol_maps = debug_outputs.bitcode_symbol_maps,
            dependency_targets = ctx.attr.frameworks,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.codesigning_dossier_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_location = processor.location.framework,
            bundle_name = bundle_name,
            embed_target_dossiers = False,
            embedded_targets = ctx.attr.frameworks,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            provisioning_profile = provisioning_profile,
            rule_descriptor = rule_descriptor,
        ),
        partials.clang_rt_dylibs_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            binary_artifact = binary_artifact,
            features = features,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            dylibs = clang_rt_dylibs.get_from_toolchain(ctx),
        ),
        partials.debug_symbols_partial(
            actions = actions,
            bundle_extension = bundle_extension,
            bundle_name = bundle_name,
            debug_dependencies = ctx.attr.frameworks,
            dsym_binaries = debug_outputs.dsym_binaries,
            dsym_info_plist_template = apple_mac_toolchain_info.dsym_info_plist_template,
            executable_name = executable_name,
            linkmaps = debug_outputs.linkmaps,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.embedded_bundles_partial(
            frameworks = [archive_for_embedding],
            embeddable_targets = ctx.attr.frameworks,
            platform_prerequisites = platform_prerequisites,
            signed_frameworks = depset(signed_frameworks),
        ),
        partials.extension_safe_validation_partial(
            is_extension_safe = ctx.attr.extension_safe,
            rule_label = label,
            targets_to_validate = ctx.attr.frameworks,
        ),
        partials.framework_headers_partial(hdrs = ctx.files.hdrs),
        partials.framework_provider_partial(
            actions = actions,
            bin_root_path = bin_root_path,
            binary_artifact = binary_artifact,
            bundle_name = bundle_name,
            bundle_only = ctx.attr.bundle_only,
            cc_features = cc_features,
            cc_info = link_result.cc_info,
            cc_toolchain = cc_toolchain,
            objc_provider = link_result.objc,
            rule_label = label,
        ),
        partials.resources_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_id = bundle_id,
            bundle_name = bundle_name,
            environment_plist = ctx.file._environment_plist,
            executable_name = executable_name,
            launch_storyboard = None,
            platform_prerequisites = platform_prerequisites,
            resource_deps = resource_deps,
            rule_descriptor = rule_descriptor,
            rule_label = label,
            targets_to_avoid = ctx.attr.frameworks,
            top_level_infoplists = top_level_infoplists,
            top_level_resources = top_level_resources,
            version = ctx.attr.version,
            version_keys_required = False,
        ),
        partials.swift_dylibs_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            binary_artifact = binary_artifact,
            dependency_targets = ctx.attr.frameworks,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.apple_symbols_file_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            dependency_targets = ctx.attr.frameworks,
            dsym_binaries = debug_outputs.dsym_binaries,
            label_name = label.name,
            include_symbols_in_bundle = False,
            platform_prerequisites = platform_prerequisites,
        ),
    ]

    processor_result = processor.process(
        actions = actions,
        apple_mac_toolchain_info = apple_mac_toolchain_info,
        apple_xplat_toolchain_info = apple_xplat_toolchain_info,
        bundle_extension = bundle_extension,
        bundle_name = bundle_name,
        codesign_inputs = ctx.files.codesign_inputs,
        codesignopts = codesigning_support.codesignopts_from_rule_ctx(ctx),
        executable_name = executable_name,
        features = features,
        ipa_post_processor = ctx.executable.ipa_post_processor,
        partials = processor_partials,
        platform_prerequisites = platform_prerequisites,
        predeclared_outputs = predeclared_outputs,
        process_and_sign_template = apple_mac_toolchain_info.process_and_sign_template,
        provisioning_profile = provisioning_profile,
        rule_descriptor = rule_descriptor,
        rule_label = label,
    )

    return [
        DefaultInfo(files = processor_result.output_files),
        AppleFrameworkBundleInfo(),
        WatchosFrameworkBundleInfo(),
        OutputGroupInfo(
            **outputs.merge_output_groups(
                link_result.output_groups,
                processor_result.output_groups,
            )
        ),
        # TODO(b/228856372): Remove when downstream users are migrated off this provider.
        link_result.debug_outputs_provider,
    ] + processor_result.providers

def _watchos_dynamic_framework_impl(ctx):
    """Experimental implementation of watchos_dynamic_framework."""

    # This rule should only have one swift_library dependency. This means len(ctx.attr.deps) should be 1
    swiftdeps = [x for x in ctx.attr.deps if SwiftInfo in x]
    if len(swiftdeps) != 1 or len(ctx.attr.deps) > 1:
        fail(
            """\
    error: Swift dynamic frameworks expect a single swift_library dependency.
    """,
        )

    binary_target = ctx.attr.deps[0]

    actions = ctx.actions
    apple_mac_toolchain_info = ctx.attr._mac_toolchain[AppleMacToolsToolchainInfo]
    apple_xplat_toolchain_info = ctx.attr._xplat_toolchain[AppleXPlatToolsToolchainInfo]
    bin_root_path = ctx.bin_dir.path
    bundle_id = ctx.attr.bundle_id
    bundle_name, bundle_extension = bundling_support.bundle_full_name_from_rule_ctx(ctx)
    executable_name = bundling_support.executable_name(ctx)
    cc_toolchain = find_cpp_toolchain(ctx)
    cc_features = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        language = "objc",
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    features = features_support.compute_enabled_features(
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    label = ctx.label
    platform_prerequisites = platform_support.platform_prerequisites_from_rule_ctx(ctx)
    predeclared_outputs = ctx.outputs
    provisioning_profile = ctx.file.provisioning_profile
    resource_deps = ctx.attr.deps + ctx.attr.resources
    rule_descriptor = rule_support.rule_descriptor(ctx)
    top_level_infoplists = resources.collect(
        attr = ctx.attr,
        res_attrs = ["infoplists"],
    )
    top_level_resources = resources.collect(
        attr = ctx.attr,
        res_attrs = [
            "app_icons",
            "storyboards",
            "strings",
            "resources",
        ],
    )

    signed_frameworks = []
    if getattr(ctx.file, "provisioning_profile", None):
        signed_frameworks = [
            bundle_name + rule_descriptor.bundle_extension,
        ]

    extra_linkopts = [
        "-dynamiclib",
        "-Wl,-install_name,@rpath/{name}{extension}/{name}".format(
            extension = bundle_extension,
            name = bundle_name,
        ),
    ]
    if ctx.attr.extension_safe:
        extra_linkopts.append("-fapplication-extension")

    link_result = linking_support.register_binary_linking_action(
        ctx,
        avoid_deps = ctx.attr.frameworks,
        # Frameworks do not have entitlements.
        entitlements = None,
        extra_linkopts = extra_linkopts,
        platform_prerequisites = platform_prerequisites,
        stamp = ctx.attr.stamp,
    )
    binary_artifact = link_result.binary
    debug_outputs = linking_support.debug_outputs_by_architecture(link_result.outputs)

    archive_for_embedding = outputs.archive_for_embedding(
        actions = actions,
        bundle_name = bundle_name,
        bundle_extension = bundle_extension,
        executable_name = executable_name,
        label_name = label.name,
        rule_descriptor = rule_descriptor,
        platform_prerequisites = platform_prerequisites,
        predeclared_outputs = predeclared_outputs,
    )

    processor_partials = [
        partials.apple_bundle_info_partial(
            actions = actions,
            bundle_extension = bundle_extension,
            bundle_id = bundle_id,
            bundle_name = bundle_name,
            executable_name = executable_name,
            extension_safe = ctx.attr.extension_safe,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            predeclared_outputs = predeclared_outputs,
            product_type = rule_descriptor.product_type,
        ),
        partials.binary_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            bundle_name = bundle_name,
            executable_name = executable_name,
            label_name = label.name,
        ),
        partials.bitcode_symbols_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            bitcode_symbol_maps = debug_outputs.bitcode_symbol_maps,
            dependency_targets = ctx.attr.frameworks,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.codesigning_dossier_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_location = processor.location.framework,
            bundle_name = bundle_name,
            embed_target_dossiers = False,
            embedded_targets = ctx.attr.frameworks,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            provisioning_profile = provisioning_profile,
            rule_descriptor = rule_descriptor,
        ),
        partials.clang_rt_dylibs_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            binary_artifact = binary_artifact,
            features = features,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            dylibs = clang_rt_dylibs.get_from_toolchain(ctx),
        ),
        partials.debug_symbols_partial(
            actions = actions,
            bundle_extension = bundle_extension,
            bundle_name = bundle_name,
            debug_dependencies = ctx.attr.frameworks,
            dsym_binaries = debug_outputs.dsym_binaries,
            dsym_info_plist_template = apple_mac_toolchain_info.dsym_info_plist_template,
            executable_name = executable_name,
            linkmaps = debug_outputs.linkmaps,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.embedded_bundles_partial(
            frameworks = [archive_for_embedding],
            embeddable_targets = ctx.attr.frameworks,
            platform_prerequisites = platform_prerequisites,
            signed_frameworks = depset(signed_frameworks),
        ),
        partials.extension_safe_validation_partial(
            is_extension_safe = ctx.attr.extension_safe,
            rule_label = label,
            targets_to_validate = ctx.attr.frameworks,
        ),
        partials.framework_provider_partial(
            actions = actions,
            bin_root_path = bin_root_path,
            binary_artifact = binary_artifact,
            bundle_name = bundle_name,
            bundle_only = ctx.attr.bundle_only,
            cc_features = cc_features,
            cc_info = link_result.cc_info,
            cc_toolchain = cc_toolchain,
            objc_provider = link_result.objc,
            rule_label = label,
        ),
        partials.resources_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_id = bundle_id,
            bundle_name = bundle_name,
            environment_plist = ctx.file._environment_plist,
            executable_name = executable_name,
            launch_storyboard = None,
            platform_prerequisites = platform_prerequisites,
            resource_deps = resource_deps,
            rule_descriptor = rule_descriptor,
            rule_label = label,
            targets_to_avoid = ctx.attr.frameworks,
            top_level_infoplists = top_level_infoplists,
            top_level_resources = top_level_resources,
            version = ctx.attr.version,
            version_keys_required = False,
        ),
        partials.swift_dylibs_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            binary_artifact = binary_artifact,
            dependency_targets = ctx.attr.frameworks,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.swift_dynamic_framework_partial(
            actions = actions,
            bundle_name = bundle_name,
            label_name = label.name,
            swift_dynamic_framework_info = binary_target[SwiftDynamicFrameworkInfo],
        ),
    ]

    processor_result = processor.process(
        actions = actions,
        apple_mac_toolchain_info = apple_mac_toolchain_info,
        apple_xplat_toolchain_info = apple_xplat_toolchain_info,
        bundle_extension = bundle_extension,
        bundle_name = bundle_name,
        codesign_inputs = ctx.files.codesign_inputs,
        codesignopts = codesigning_support.codesignopts_from_rule_ctx(ctx),
        executable_name = executable_name,
        features = features,
        ipa_post_processor = ctx.executable.ipa_post_processor,
        partials = processor_partials,
        platform_prerequisites = platform_prerequisites,
        predeclared_outputs = predeclared_outputs,
        process_and_sign_template = apple_mac_toolchain_info.process_and_sign_template,
        provisioning_profile = provisioning_profile,
        rule_descriptor = rule_descriptor,
        rule_label = label,
    )

    providers = processor_result.providers
    additional_providers = []
    for provider in providers:
        if type(provider) == "AppleDynamicFramework":
            # Make the ObjC provider using the framework_files depset found
            # in the AppleDynamicFramework provider. This is to make the
            # watchos_dynamic_framework usable as a dependency in swift_library
            libraries_to_link = libraries_to_link_for_dynamic_framework(
                actions = actions,
                cc_toolchain = cc_toolchain,
                feature_configuration = cc_features,
                libraries = provider.framework_files.to_list(),
            )
            additional_providers.extend([
                apple_common.new_objc_provider(
                    dynamic_framework_file = provider.framework_files,
                ),
                CcInfo(
                    linking_context = cc_common.create_linking_context(
                        linker_inputs = depset([
                            cc_common.create_linker_input(
                                owner = label,
                                libraries = depset(libraries_to_link),
                            ),
                        ]),
                    ),
                ),
            ])
    providers.extend(additional_providers)

    return [
        DefaultInfo(files = processor_result.output_files),
        WatchosFrameworkBundleInfo(),
        OutputGroupInfo(
            **outputs.merge_output_groups(
                link_result.output_groups,
                processor_result.output_groups,
            )
        ),
    ] + providers

def _watchos_application_impl(ctx):
    """Implementation of watchos_application."""
    actions = ctx.actions
    apple_mac_toolchain_info = ctx.attr._mac_toolchain[AppleMacToolsToolchainInfo]
    apple_xplat_toolchain_info = ctx.attr._xplat_toolchain[AppleXPlatToolsToolchainInfo]
    bundle_id = ctx.attr.bundle_id
    bundle_name, bundle_extension = bundling_support.bundle_full_name_from_rule_ctx(ctx)
    executable_name = bundling_support.executable_name(ctx)
    features = features_support.compute_enabled_features(
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    label = ctx.label
    platform_prerequisites = platform_support.platform_prerequisites_from_rule_ctx(ctx)
    predeclared_outputs = ctx.outputs
    provisioning_profile = ctx.file.provisioning_profile
    resource_deps = ctx.attr.resources
    rule_descriptor = rule_support.rule_descriptor(ctx)
    top_level_infoplists = resources.collect(
        attr = ctx.attr,
        res_attrs = ["infoplists"],
    )
    top_level_resources = resources.collect(
        attr = ctx.attr,
        res_attrs = [
            "app_icons",
            "storyboards",
            "strings",
            "resources",
        ],
    )

    entitlements = entitlements_support.process_entitlements(
        actions = actions,
        apple_mac_toolchain_info = apple_mac_toolchain_info,
        bundle_id = bundle_id,
        entitlements_file = ctx.file.entitlements,
        platform_prerequisites = platform_prerequisites,
        product_type = rule_descriptor.product_type,
        provisioning_profile = provisioning_profile,
        rule_label = label,
        validation_mode = ctx.attr.entitlements_validation,
    )

    binary_artifact = stub_support.create_stub_binary(
        actions = actions,
        platform_prerequisites = platform_prerequisites,
        rule_label = label,
        xcode_stub_path = rule_descriptor.stub_binary_path,
    )

    bundle_verification_targets = [
        struct(
            target = ctx.attr.extension,
            parent_bundle_id_reference = [
                "NSExtension",
                "NSExtensionAttributes",
                "WKAppBundleIdentifier",
            ],
        ),
    ]

    archive = outputs.archive(
        actions = actions,
        bundle_extension = bundle_extension,
        bundle_name = bundle_name,
        platform_prerequisites = platform_prerequisites,
        predeclared_outputs = predeclared_outputs,
    )

    processor_partials = [
        partials.apple_bundle_info_partial(
            actions = actions,
            bundle_extension = bundle_extension,
            bundle_name = bundle_name,
            executable_name = executable_name,
            bundle_id = bundle_id,
            entitlements = entitlements.bundle,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            predeclared_outputs = predeclared_outputs,
            product_type = rule_descriptor.product_type,
        ),
        partials.binary_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            bundle_name = bundle_name,
            executable_name = executable_name,
            label_name = label.name,
        ),
        partials.bitcode_symbols_partial(
            actions = actions,
            dependency_targets = [ctx.attr.extension],
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.clang_rt_dylibs_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            binary_artifact = binary_artifact,
            features = features,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            dylibs = clang_rt_dylibs.get_from_toolchain(ctx),
        ),
        partials.codesigning_dossier_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_location = processor.location.watch,
            bundle_name = bundle_name,
            embed_target_dossiers = True,
            embedded_targets = [ctx.attr.extension],
            entitlements = entitlements.codesigning,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            provisioning_profile = provisioning_profile,
            rule_descriptor = rule_descriptor,
        ),
        partials.debug_symbols_partial(
            actions = actions,
            bundle_extension = bundle_extension,
            bundle_name = bundle_name,
            debug_dependencies = [ctx.attr.extension],
            dsym_info_plist_template = apple_mac_toolchain_info.dsym_info_plist_template,
            executable_name = executable_name,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.embedded_bundles_partial(
            bundle_embedded_bundles = True,
            embeddable_targets = [ctx.attr.extension],
            platform_prerequisites = platform_prerequisites,
            watch_bundles = [archive],
        ),
        partials.resources_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_id = bundle_id,
            bundle_name = bundle_name,
            executable_name = executable_name,
            bundle_verification_targets = bundle_verification_targets,
            environment_plist = ctx.file._environment_plist,
            launch_storyboard = None,
            platform_prerequisites = platform_prerequisites,
            resource_deps = resource_deps,
            rule_descriptor = rule_descriptor,
            rule_label = label,
            top_level_infoplists = top_level_infoplists,
            top_level_resources = top_level_resources,
            version = ctx.attr.version,
        ),
        partials.swift_dylibs_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            binary_artifact = binary_artifact,
            bundle_dylibs = True,
            dependency_targets = [ctx.attr.extension],
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.watchos_stub_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            label_name = label.name,
        ),
    ]

    if platform_prerequisites.platform.is_device:
        processor_partials.append(
            partials.provisioning_profile_partial(
                actions = actions,
                profile_artifact = provisioning_profile,
                rule_label = label,
            ),
        )

    processor_result = processor.process(
        actions = actions,
        apple_mac_toolchain_info = apple_mac_toolchain_info,
        apple_xplat_toolchain_info = apple_xplat_toolchain_info,
        bundle_extension = bundle_extension,
        bundle_name = bundle_name,
        entitlements = entitlements.codesigning,
        executable_name = executable_name,
        features = features,
        ipa_post_processor = ctx.executable.ipa_post_processor,
        partials = processor_partials,
        platform_prerequisites = platform_prerequisites,
        predeclared_outputs = predeclared_outputs,
        process_and_sign_template = apple_mac_toolchain_info.process_and_sign_template,
        provisioning_profile = provisioning_profile,
        rule_descriptor = rule_descriptor,
        rule_label = label,
    )

    return [
        DefaultInfo(
            files = processor_result.output_files,
        ),
        OutputGroupInfo(**processor_result.output_groups),
        WatchosApplicationBundleInfo(),
    ] + processor_result.providers

def _watchos_extension_impl(ctx):
    """Implementation of watchos_extension."""
    actions = ctx.actions
    apple_mac_toolchain_info = ctx.attr._mac_toolchain[AppleMacToolsToolchainInfo]
    apple_xplat_toolchain_info = ctx.attr._xplat_toolchain[AppleXPlatToolsToolchainInfo]
    bundle_id = ctx.attr.bundle_id
    bundle_name, bundle_extension = bundling_support.bundle_full_name_from_rule_ctx(ctx)
    embeddable_targets = (
        ctx.attr.extensions + ctx.attr.frameworks + ctx.attr.deps
    )
    executable_name = bundling_support.executable_name(ctx)
    features = features_support.compute_enabled_features(
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    label = ctx.label
    platform_prerequisites = platform_support.platform_prerequisites_from_rule_ctx(ctx)
    predeclared_outputs = ctx.outputs
    provisioning_profile = ctx.file.provisioning_profile
    resource_deps = ctx.attr.deps + ctx.attr.resources
    rule_descriptor = rule_support.rule_descriptor(ctx)
    top_level_infoplists = resources.collect(
        attr = ctx.attr,
        res_attrs = ["infoplists"],
    )
    top_level_resources = resources.collect(
        attr = ctx.attr,
        res_attrs = [
            "app_icons",
            "strings",
            "resources",
        ],
    )
    product_type = rule_descriptor.product_type
    if ctx.attr.extensionkit_extension:
        bundle_location = processor.location.extension
        product_type = apple_product_type.extensionkit_extension
    else:
        bundle_location = processor.location.plugin

    # Xcode 11 requires this flag to be passed to the linker, but it is not accepted by earlier
    # versions.
    # TODO(min(Xcode) >= 11): Make this unconditional when the minimum supported Xcode is Xcode 11.
    xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]
    if xcode_support.is_xcode_at_least_version(xcode_config, "11"):
        # This extension should be treated as an App Extension instead of a WatchKit Extension.
        if ctx.attr.application_extension:
            extra_linkopts = ["-e", "_NSExtensionMain"]
            product_type = apple_product_type.app_extension
        elif ctx.attr.extensionkit_extension:
            extra_linkopts = ["-e", "_NSExtensionMain"]
            product_type = apple_product_type.extensionkit_extension
        else:
            extra_linkopts = ["-e", "_WKExtensionMain"]

        # This is required when building with watchOS SDK 6.0 or higher but with a minimum
        # deployment version lower than 6.0. See
        # https://developer.apple.com/documentation/xcode_release_notes/xcode_11_release_notes.
        minimum_os = apple_common.dotted_version(ctx.attr.minimum_os_version)
        if minimum_os < apple_common.dotted_version("6.0"):
            extra_linkopts.append(
                # The linker will search for this library relative to sysroot, which will already
                # be the watchOS SDK directory.
                #
                # This is a force-load (unlike Xcode, which uses a standard `-l`) because we can't
                # easily control where it appears in the link order relative to WatchKit.framework
                # (where this symbol also lives, in watchOS 6+), so we need to guarantee that the
                # linker doesn't skip the static library's implementation of `WKExtensionMain` if
                # it already resolved the symbol from the framework.
                "-Wl,-force_load,/usr/lib/libWKExtensionMainLegacy.a",
            )
    else:
        extra_linkopts = []

    entitlements = entitlements_support.process_entitlements(
        actions = actions,
        apple_mac_toolchain_info = apple_mac_toolchain_info,
        bundle_id = bundle_id,
        entitlements_file = ctx.file.entitlements,
        platform_prerequisites = platform_prerequisites,
        product_type = product_type,
        provisioning_profile = provisioning_profile,
        rule_label = label,
        validation_mode = ctx.attr.entitlements_validation,
    )

    link_result = linking_support.register_binary_linking_action(
        ctx,
        avoid_deps = ctx.attr.frameworks,
        entitlements = entitlements.linking,
        extra_linkopts = extra_linkopts,
        platform_prerequisites = platform_prerequisites,
        stamp = ctx.attr.stamp,
    )
    binary_artifact = link_result.binary
    debug_outputs = linking_support.debug_outputs_by_architecture(link_result.outputs)

    archive_for_embedding = outputs.archive(
        actions = actions,
        bundle_extension = bundle_extension,
        bundle_name = bundle_name,
        platform_prerequisites = platform_prerequisites,
        predeclared_outputs = predeclared_outputs,
    )

    if ctx.attr.extensionkit_extension:
        plugins = []
        extensions = [archive_for_embedding]
    else:
        plugins = [archive_for_embedding]
        extensions = []

    bundle_verification_targets = [struct(target = ext) for ext in ctx.attr.extensions]

    processor_partials = [
        partials.apple_bundle_info_partial(
            actions = actions,
            bundle_extension = bundle_extension,
            bundle_id = bundle_id,
            bundle_name = bundle_name,
            entitlements = entitlements.bundle,
            executable_name = executable_name,
            extension_safe = True,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            predeclared_outputs = predeclared_outputs,
            product_type = product_type,
        ),
        partials.binary_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            bundle_name = bundle_name,
            executable_name = executable_name,
            label_name = ctx.label.name,
        ),
        partials.bitcode_symbols_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            bitcode_symbol_maps = debug_outputs.bitcode_symbol_maps,
            dependency_targets = embeddable_targets,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.clang_rt_dylibs_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            binary_artifact = binary_artifact,
            features = features,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            dylibs = clang_rt_dylibs.get_from_toolchain(ctx),
        ),
        partials.codesigning_dossier_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_location = bundle_location,
            bundle_name = bundle_name,
            embed_target_dossiers = True,
            embedded_targets = embeddable_targets,
            entitlements = entitlements.codesigning,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            provisioning_profile = provisioning_profile,
            rule_descriptor = rule_descriptor,
        ),
        partials.debug_symbols_partial(
            actions = actions,
            bundle_extension = bundle_extension,
            bundle_name = bundle_name,
            debug_dependencies = embeddable_targets,
            dsym_binaries = debug_outputs.dsym_binaries,
            dsym_info_plist_template = apple_mac_toolchain_info.dsym_info_plist_template,
            executable_name = executable_name,
            linkmaps = debug_outputs.linkmaps,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.embedded_bundles_partial(
            bundle_embedded_bundles = True,
            platform_prerequisites = platform_prerequisites,
            embeddable_targets = embeddable_targets,
            plugins = plugins,
            extensions = extensions,
        ),
        partials.extension_safe_validation_partial(
            is_extension_safe = True,
            rule_label = label,
            targets_to_validate = ctx.attr.frameworks,
        ),
        # Following guidance of the watchOS 2 migration guide's recommendations for placement of a
        # framework, scoping dynamic frameworks only to the watch extension bundles:
        # https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleWatch2TransitionGuide/ConfiguretheXcodeProject.html
        partials.framework_import_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            features = features,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            provisioning_profile = provisioning_profile,
            rule_descriptor = rule_descriptor,
            targets = ctx.attr.deps + ctx.attr.extensions + ctx.attr.frameworks,
        ),
        partials.resources_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_verification_targets = bundle_verification_targets,
            bundle_id = bundle_id,
            bundle_name = bundle_name,
            environment_plist = ctx.file._environment_plist,
            executable_name = executable_name,
            launch_storyboard = None,
            platform_prerequisites = platform_prerequisites,
            resource_deps = resource_deps,
            rule_descriptor = rule_descriptor,
            rule_label = label,
            targets_to_avoid = ctx.attr.frameworks,
            top_level_infoplists = top_level_infoplists,
            top_level_resources = top_level_resources,
            version = ctx.attr.version,
        ),
        partials.swift_dylibs_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            binary_artifact = binary_artifact,
            label_name = label.name,
            dependency_targets = embeddable_targets,
            platform_prerequisites = platform_prerequisites,
        ),
        partials.apple_symbols_file_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            dependency_targets = embeddable_targets,
            dsym_binaries = debug_outputs.dsym_binaries,
            label_name = label.name,
            include_symbols_in_bundle = False,
            platform_prerequisites = platform_prerequisites,
        ),
    ]

    if platform_prerequisites.platform.is_device:
        processor_partials.append(
            partials.provisioning_profile_partial(
                actions = actions,
                profile_artifact = provisioning_profile,
                rule_label = label,
            ),
        )

    processor_result = processor.process(
        actions = actions,
        apple_mac_toolchain_info = apple_mac_toolchain_info,
        apple_xplat_toolchain_info = apple_xplat_toolchain_info,
        bundle_extension = bundle_extension,
        bundle_name = bundle_name,
        codesign_inputs = ctx.files.codesign_inputs,
        codesignopts = codesigning_support.codesignopts_from_rule_ctx(ctx),
        entitlements = entitlements.codesigning,
        executable_name = executable_name,
        features = features,
        ipa_post_processor = ctx.executable.ipa_post_processor,
        partials = processor_partials,
        platform_prerequisites = platform_prerequisites,
        predeclared_outputs = predeclared_outputs,
        process_and_sign_template = apple_mac_toolchain_info.process_and_sign_template,
        provisioning_profile = provisioning_profile,
        rule_descriptor = rule_descriptor,
        rule_label = label,
    )

    return [
        DefaultInfo(
            files = processor_result.output_files,
        ),
        OutputGroupInfo(
            **outputs.merge_output_groups(
                link_result.output_groups,
                processor_result.output_groups,
            )
        ),
        WatchosExtensionBundleInfo(),
        # TODO(b/228856372): Remove when downstream users are migrated off this provider.
        link_result.debug_outputs_provider,
    ] + processor_result.providers

def _watchos_static_framework_impl(ctx):
    """Implementation of watchos_static_framework."""

    actions = ctx.actions
    apple_mac_toolchain_info = ctx.attr._mac_toolchain[AppleMacToolsToolchainInfo]
    apple_xplat_toolchain_info = ctx.attr._xplat_toolchain[AppleXPlatToolsToolchainInfo]
    avoid_deps = ctx.attr.avoid_deps
    deps = ctx.attr.deps
    label = ctx.label
    predeclared_outputs = ctx.outputs
    split_deps = ctx.split_attr.deps
    bundle_name, bundle_extension = bundling_support.bundle_full_name_from_rule_ctx(ctx)
    executable_name = bundling_support.executable_name(ctx)
    features = features_support.compute_enabled_features(
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    label = ctx.label
    platform_prerequisites = platform_support.platform_prerequisites_from_rule_ctx(ctx)
    predeclared_outputs = ctx.outputs
    rule_descriptor = rule_support.rule_descriptor(ctx)

    link_result = linking_support.register_static_library_linking_action(ctx = ctx)
    binary_artifact = link_result.library

    processor_partials = [
        partials.apple_bundle_info_partial(
            actions = actions,
            bundle_extension = bundle_extension,
            bundle_name = bundle_name,
            executable_name = executable_name,
            label_name = label.name,
            platform_prerequisites = platform_prerequisites,
            predeclared_outputs = predeclared_outputs,
            product_type = rule_descriptor.product_type,
        ),
        partials.binary_partial(
            actions = actions,
            binary_artifact = binary_artifact,
            bundle_name = bundle_name,
            executable_name = executable_name,
            label_name = label.name,
        ),
    ]

    swift_infos = {}
    if swift_support.uses_swift(deps):
        for link_output in link_result.outputs:
            split_attr_key = transition_support.apple_common_multi_arch_split_key(
                cpu = link_output.architecture,
                environment = link_output.environment,
                platform_type = link_output.platform,
            )
            for dep in split_deps[split_attr_key]:
                if SwiftInfo in dep:
                    swift_infos[link_output.architecture] = dep[SwiftInfo]

    # If there's any Swift dependencies on the static framework rule, treat it as a Swift static
    # framework.
    if swift_infos:
        processor_partials.append(
            partials.swift_framework_partial(
                actions = actions,
                avoid_deps = avoid_deps,
                bundle_name = bundle_name,
                label_name = label.name,
                swift_infos = swift_infos,
            ),
        )
    else:
        processor_partials.append(
            partials.framework_header_modulemap_partial(
                actions = actions,
                bundle_name = bundle_name,
                hdrs = ctx.files.hdrs,
                label_name = label.name,
                sdk_dylibs = cc_info_support.get_sdk_dylibs(deps = deps),
                sdk_frameworks = cc_info_support.get_sdk_frameworks(deps = deps),
                umbrella_header = ctx.file.umbrella_header,
            ),
        )

    if not ctx.attr.exclude_resources:
        resource_deps = ctx.attr.deps + ctx.attr.resources
        top_level_infoplists = resources.collect(
            attr = ctx.attr,
            res_attrs = ["infoplists"],
        )
        top_level_resources = resources.collect(
            attr = ctx.attr,
            res_attrs = [
                "app_icons",
                "strings",
                "resources",
            ],
        )

        processor_partials.append(partials.resources_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_name = bundle_name,
            environment_plist = ctx.file._environment_plist,
            executable_name = executable_name,
            launch_storyboard = None,
            platform_prerequisites = platform_prerequisites,
            resource_deps = resource_deps,
            rule_descriptor = rule_descriptor,
            rule_label = label,
            top_level_infoplists = top_level_infoplists,
            top_level_resources = top_level_resources,
            version = None,
        ))

    processor_result = processor.process(
        actions = actions,
        apple_mac_toolchain_info = apple_mac_toolchain_info,
        apple_xplat_toolchain_info = apple_xplat_toolchain_info,
        bundle_extension = bundle_extension,
        bundle_name = bundle_name,
        codesign_inputs = ctx.files.codesign_inputs,
        codesignopts = codesigning_support.codesignopts_from_rule_ctx(ctx),
        executable_name = executable_name,
        features = features,
        ipa_post_processor = ctx.executable.ipa_post_processor,
        partials = processor_partials,
        platform_prerequisites = platform_prerequisites,
        predeclared_outputs = predeclared_outputs,
        process_and_sign_template = apple_mac_toolchain_info.process_and_sign_template,
        rule_descriptor = rule_descriptor,
        rule_label = label,
    )

    return [
        DefaultInfo(files = processor_result.output_files),
        WatchosStaticFrameworkBundleInfo(),
    ] + processor_result.providers

watchos_application = rule_factory.create_apple_bundling_rule(
    implementation = _watchos_application_impl,
    platform_type = "watchos",
    product_type = apple_product_type.watch2_application,
    doc = "Builds and bundles an watchOS Application.",
)

watchos_extension = rule_factory.create_apple_bundling_rule(
    implementation = _watchos_extension_impl,
    platform_type = "watchos",
    product_type = apple_product_type.watch2_extension,
    doc = """Builds and bundles an watchOS Extension.

**This rule only supports watchOS 2.0 and higher.**
Apple no longer supports or accepts submissions of apps written for watchOS 1.x,
so these bundling rules do not support that version of the platform.""",
)

watchos_framework = rule_factory.create_apple_bundling_rule(
    implementation = _watchos_framework_impl,
    platform_type = "watchos",
    product_type = apple_product_type.framework,
    doc = """Builds and bundles a watchOS Dynamic Framework.

To use this framework for your extensions, list it in the `frameworks` attributes of
those `watchos_extension` rules.""",
)

watchos_dynamic_framework = rule_factory.create_apple_bundling_rule(
    implementation = _watchos_dynamic_framework_impl,
    platform_type = "watchos",
    product_type = apple_product_type.framework,
    doc = "Builds and bundles a watchOS dynamic framework that is consumable by Xcode.",
)

watchos_static_framework = rule_factory.create_apple_bundling_rule(
    implementation = _watchos_static_framework_impl,
    platform_type = "watchos",
    product_type = apple_product_type.static_framework,
    doc = "Builds and bundles a watchOS Static Framework.",
)
