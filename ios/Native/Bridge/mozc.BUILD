load("@rules_cc//cc:cc_static_library.bzl", "cc_static_library")
load("@build_bazel_rules_apple//apple:apple_static_library.bzl", "apple_static_library")
mozc_cc_library(
    name = "fusion_bridge", srcs = ["FusionMozc.cc"], hdrs = ["FusionMozc.h"],
    deps = [":ios_engine", "//base:system_util", "//data_manager", "//protocol:commands_cc_proto", "//protocol:config_cc_proto"],
)
cc_static_library(name = "FusionMozcMac", deps = [":fusion_bridge"])
apple_static_library(name = "FusionMozcIOS", deps = [":fusion_bridge"], platform_type = "ios", minimum_os_version = "16.0")
