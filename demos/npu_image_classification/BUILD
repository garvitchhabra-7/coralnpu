# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@coralnpu_hw//third_party/python:requirements.bzl", "requirement")
load("//rules:coralnpu_v2.bzl", "collect_coralnpu_elfs", "coralnpu_v2_binary")
load("//rules:utils.bzl", "generate_cc_arrays")

generate_cc_arrays(
    name = "mobilenet_v1_0_25_224_int8_cc",
    src = "models/mobilenet_v1_0.25_224_int8.tflite",
    out = "mobilenet_v1_0_25_224_int8.cc",
)

generate_cc_arrays(
    name = "mobilenet_v1_0_25_224_int8_h",
    src = "models/mobilenet_v1_0.25_224_int8.tflite",
    out = "mobilenet_v1_0_25_224_int8.h",
)

cc_library(
    name = "mobilenet_v1_0_25_224_int8_lib",
    srcs = [":mobilenet_v1_0_25_224_int8_cc"],
    hdrs = [":mobilenet_v1_0_25_224_int8_h"],
    visibility = ["//visibility:public"],
)

coralnpu_v2_binary(
    name = "classify_npu_binary",
    srcs = [
        "classify_npu.cc",
    ],
    hdrs = [":mobilenet_v1_0_25_224_int8_h"],
    dtcm_size_kbytes = 1024,
    itcm_size_kbytes = 1024,
    semihosting = True,
    visibility = ["//visibility:public"],
    deps = [
        ":mobilenet_v1_0_25_224_int8_lib",
        "//sw/opt:rvv_opt",
        "//sw/opt/litert-micro:conv",
        "//sw/opt/litert-micro:depthwise_conv",
        "@tflite_micro//tensorflow/lite/micro:micro_framework",
        "@tflite_micro//tensorflow/lite/micro:micro_log",
        "@tflite_micro//tensorflow/lite/micro:op_resolvers",
        "@tflite_micro//tensorflow/lite/micro:system_setup",
    ],
)

coralnpu_v2_binary(
    name = "classify_npu_scalar_binary",
    srcs = [
        "classify_npu.cc",
    ],
    copts = ["-DSCALAR_ONLY"],
    hdrs = [":mobilenet_v1_0_25_224_int8_h"],
    dtcm_size_kbytes = 1024,
    itcm_size_kbytes = 1024,
    semihosting = True,
    visibility = ["//visibility:public"],
    deps = [
        ":mobilenet_v1_0_25_224_int8_lib",
        "@tflite_micro//tensorflow/lite/micro:micro_framework",
        "@tflite_micro//tensorflow/lite/micro:micro_log",
        "@tflite_micro//tensorflow/lite/micro:op_resolvers",
        "@tflite_micro//tensorflow/lite/micro:system_setup",
    ],
)

py_binary(
    name = "run_on_npusim",
    srcs = ["run_on_npusim.py"],
    data = [
        ":classify_npu_binary",
        "models/imagenet_labels.txt",
    ],
    deps = [
        "//sw/coralnpu_sim:coralnpu_v2_sim_utils_lib",
        "@bazel_tools//tools/python/runfiles",
        requirement("numpy"),
        requirement("Pillow"),
    ],
)

py_binary(
    name = "run_on_npusim_scalar",
    srcs = ["run_on_npusim.py"],
    main = "run_on_npusim.py",
    data = [
        ":classify_npu_scalar_binary",
        "models/imagenet_labels.txt",
    ],
    deps = [
        "//sw/coralnpu_sim:coralnpu_v2_sim_utils_lib",
        "@bazel_tools//tools/python/runfiles",
        requirement("numpy"),
        requirement("Pillow"),
    ],
)

collect_coralnpu_elfs()
