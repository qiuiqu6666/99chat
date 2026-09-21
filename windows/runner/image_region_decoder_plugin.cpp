#include "image_region_decoder_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  std::wstring out(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, out.data(), size);
  if (!out.empty() && out.back() == L'\0') {
    out.pop_back();
  }
  return out;
}

class ImageRegionDecoderPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "ninechat/image_region_decoder",
            &flutter::StandardMethodCodec::GetInstance());
    auto plugin = std::make_unique<ImageRegionDecoderPlugin>();
    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });
    registrar->AddPlugin(std::move(plugin));
  }

  ImageRegionDecoderPlugin() = default;
  ~ImageRegionDecoderPlugin() override = default;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (method_call.method_name() != "decodeRegion") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) {
      result->Error("invalid_args", "map required");
      return;
    }
    auto string_at = [&](const char* key) -> std::string {
      const auto it = args->find(flutter::EncodableValue(key));
      if (it == args->end()) {
        return {};
      }
      if (const auto* value = std::get_if<std::string>(&it->second)) {
        return *value;
      }
      return {};
    };
    auto int_at = [&](const char* key) -> int {
      const auto it = args->find(flutter::EncodableValue(key));
      if (it == args->end()) {
        return 0;
      }
      if (const auto* value = std::get_if<int32_t>(&it->second)) {
        return *value;
      }
      if (const auto* value = std::get_if<int64_t>(&it->second)) {
        return static_cast<int>(*value);
      }
      return 0;
    };
    const std::string path = string_at("path");
    const int src_left = int_at("srcLeft");
    const int src_top = int_at("srcTop");
    const int src_width = int_at("srcWidth");
    const int src_height = int_at("srcHeight");
    const int dst_width = std::max(1, int_at("dstWidth"));
    const int dst_height = std::max(1, int_at("dstHeight"));
    if (path.empty() || src_width <= 0 || src_height <= 0) {
      result->Error("invalid_args", "region required");
      return;
    }

    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool did_init = SUCCEEDED(hr);
    ComPtr<IWICImagingFactory> factory;
    hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&factory));
    if (FAILED(hr)) {
      if (did_init) {
        CoUninitialize();
      }
      result->Error("decode_failed", "WIC factory");
      return;
    }
    ComPtr<IWICBitmapDecoder> decoder;
    hr = factory->CreateDecoderFromFilename(Utf8ToWide(path).c_str(), nullptr,
                                            GENERIC_READ,
                                            WICDecodeMetadataCacheOnDemand,
                                            &decoder);
    if (FAILED(hr)) {
      if (did_init) {
        CoUninitialize();
      }
      result->Error("unsupported_format", "decoder");
      return;
    }
    ComPtr<IWICBitmapFrameDecode> frame;
    hr = decoder->GetFrame(0, &frame);
    ComPtr<IWICBitmapClipper> clipper;
    if (SUCCEEDED(hr)) {
      hr = factory->CreateBitmapClipper(&clipper);
    }
    WICRect rect{src_left, src_top, src_width, src_height};
    if (SUCCEEDED(hr)) {
      hr = clipper->Initialize(frame.Get(), &rect);
    }
    ComPtr<IWICBitmapScaler> scaler;
    if (SUCCEEDED(hr)) {
      hr = factory->CreateBitmapScaler(&scaler);
    }
    if (SUCCEEDED(hr)) {
      hr = scaler->Initialize(clipper.Get(), static_cast<UINT>(dst_width),
                              static_cast<UINT>(dst_height),
                              WICBitmapInterpolationModeFant);
    }
    ComPtr<IWICFormatConverter> converter;
    if (SUCCEEDED(hr)) {
      hr = factory->CreateFormatConverter(&converter);
    }
    if (SUCCEEDED(hr)) {
      hr = converter->Initialize(scaler.Get(), GUID_WICPixelFormat32bppRGBA,
                                 WICBitmapDitherTypeNone, nullptr, 0.0,
                                 WICBitmapPaletteTypeCustom);
    }
    std::vector<uint8_t> pixels(static_cast<size_t>(dst_width * dst_height * 4));
    if (SUCCEEDED(hr)) {
      hr = converter->CopyPixels(nullptr, static_cast<UINT>(dst_width * 4),
                                 static_cast<UINT>(pixels.size()), pixels.data());
    }
    if (did_init) {
      CoUninitialize();
    }
    if (FAILED(hr)) {
      result->Error("decode_failed", "copy pixels");
      return;
    }
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("bytes")] =
        flutter::EncodableValue(pixels);
    payload[flutter::EncodableValue("width")] = flutter::EncodableValue(dst_width);
    payload[flutter::EncodableValue("height")] =
        flutter::EncodableValue(dst_height);
    result->Success(flutter::EncodableValue(payload));
  }
};

}  // namespace

void ImageRegionDecoderPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  ImageRegionDecoderPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
