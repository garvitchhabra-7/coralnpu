// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <stdint.h>
#include <stdio.h>

#include <cstring>

// RVV-optimized kernels (comment out for scalar-only build)
#ifndef SCALAR_ONLY
#include "sw/opt/litert-micro/conv.h"
#include "sw/opt/litert-micro/depthwise_conv.h"
#include "sw/opt/rvv_opt.h"
#endif
#include "tensorflow/lite/core/c/common.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/micro/system_setup.h"
#include "demos/npu_image_classification/mobilenet_v1_0_25_224_int8.h"

namespace {
using MobilenetOpResolver = tflite::MicroMutableOpResolver<9>;
#ifndef SCALAR_ONLY
using coralnpu_v2::opt::litert_micro::Register_CONV_2D;
using coralnpu_v2::opt::litert_micro::Register_DEPTHWISE_CONV_2D;
#endif
TfLiteStatus RegisterOps(MobilenetOpResolver& op_resolver) {
#ifdef SCALAR_ONLY
  // Stock reference kernels — pure C, no vector instructions
  TF_LITE_ENSURE_STATUS(op_resolver.AddConv2D());
  TF_LITE_ENSURE_STATUS(op_resolver.AddDepthwiseConv2D());
#else
  // RVV-optimized kernels
  TF_LITE_ENSURE_STATUS(op_resolver.AddConv2D(Register_CONV_2D()));
  TF_LITE_ENSURE_STATUS(
      op_resolver.AddDepthwiseConv2D(Register_DEPTHWISE_CONV_2D()));
#endif
  TF_LITE_ENSURE_STATUS(op_resolver.AddReshape());
  TF_LITE_ENSURE_STATUS(op_resolver.AddSoftmax());
  TF_LITE_ENSURE_STATUS(op_resolver.AddStridedSlice());
  TF_LITE_ENSURE_STATUS(op_resolver.AddPad());
  TF_LITE_ENSURE_STATUS(op_resolver.AddMean());
  TF_LITE_ENSURE_STATUS(op_resolver.AddShape());
  TF_LITE_ENSURE_STATUS(op_resolver.AddPack());
  return kTfLiteOk;
}
}  // namespace

extern "C" {
constexpr size_t kTensorArenaSize = 4 * 1024 * 1024;
int8_t inference_status = -1;
int8_t inference_input[224 * 224 * 3]
    __attribute__((section(".data"), aligned(16)));
int8_t inference_output[1000]
    __attribute__((section(".data"), aligned(16)));
uint8_t tensor_arena[kTensorArenaSize]
    __attribute__((section(".extdata"), aligned(16)));
}

int main(int argc, char** argv) {
  const tflite::Model* model =
      tflite::GetModel(g_25_224_int8_model_data);
  MobilenetOpResolver op_resolver;
  RegisterOps(op_resolver);
  printf("Op resolver ready\n");

  tflite::MicroInterpreter interpreter(model, op_resolver, tensor_arena,
                                       kTensorArenaSize);
  printf("Interpreter created\n");

  if (interpreter.AllocateTensors() != kTfLiteOk) {
    printf("Error during AllocateTensors\n");
    return -1;
  }

  TfLiteTensor* input = interpreter.input(0);
  if (input == nullptr) {
    printf("Error getting input tensor\n");
    return -1;
  }
#ifdef SCALAR_ONLY
  std::memcpy(input->data.data, inference_input, input->bytes);
#else
  coralnpu_v2::opt::Memcpy(input->data.data, inference_input, input->bytes);
#endif

  if (interpreter.Invoke() != kTfLiteOk) {
    printf("Error during Invoke\n");
    return -1;
  }

  TfLiteTensor* output = interpreter.output(0);
  if (output == nullptr) {
    printf("Error getting output tensor\n");
    return -1;
  }
#ifdef SCALAR_ONLY
  std::memcpy(inference_output, output->data.data, 1000);
#else
  coralnpu_v2::opt::Memcpy(inference_output, output->data.data, 1000);
#endif

  printf("Invoke successful\n");
  inference_status = 0;
  return 0;
}
