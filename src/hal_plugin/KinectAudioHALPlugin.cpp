#include <CoreAudio/AudioHardware.h>
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreAudio/HostTime.h>
#include <CoreFoundation/CoreFoundation.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <os/log.h>
#include <string>
#include <thread>
#include <vector>
#include <sys/time.h>

#ifndef KINECT_HAVE_LIBFREENECT
#define KINECT_HAVE_LIBFREENECT 0
#endif

#if KINECT_HAVE_LIBFREENECT
#include <libfreenect.h>
#include <libfreenect_audio.h>
#endif

namespace {

constexpr AudioObjectID kObjectIDDevice = 2;
constexpr AudioObjectID kObjectIDStreamInput = 3;
constexpr UInt32 kClockDomain = 1;
constexpr Float64 kNativeMicSampleRate = 16'000.0;
constexpr UInt32 kDefaultBufferFrameSize = 256;

constexpr const char *kPlugInName = "Kinect";
constexpr const char *kManufacturerName = "macKinect";
constexpr const char *kDeviceUID = "com.mackinect.audiohal.device";
constexpr const char *kModelUID = "com.mackinect.audiohal.model";
static CFStringRef const kIntegrationDefaultsDomain = CFSTR("com.mackinect.integration");
static CFStringRef const kSystemMicModeKey = CFSTR("SystemMicrophoneMode");

enum class MicRoutingMode : UInt32 {
  kProcessedMono = 0,
  kRawArray4 = 1,
};

std::atomic<ULONG> gRefCount{1};
AudioServerPlugInHostRef gHost = nullptr;
std::mutex gStateMutex;
Float64 gSampleRate = kNativeMicSampleRate;
UInt32 gBufferFrameSize = kDefaultBufferFrameSize;
UInt32 gChannelCount = 1;
MicRoutingMode gMicRoutingMode = MicRoutingMode::kProcessedMono;
std::atomic<UInt32> gRunningIOClients{0};
UInt64 gZeroTimeStampSeed = 1;
UInt64 gZeroHostTime = 0;
Float64 gZeroSampleTime = 0.0;
os_log_t gLog = nullptr;

#if KINECT_HAVE_LIBFREENECT
std::mutex gMicMutex;
std::vector<Float32> gMicRing;
std::size_t gMicReadIndex = 0;
std::size_t gMicWriteIndex = 0;
std::size_t gMicAvailable = 0;

std::atomic<bool> gMicCaptureRunning{false};
std::atomic<bool> gMicCaptureReady{false};
std::atomic<std::uint64_t> gMicCallbackCount{0};
std::atomic<std::uint64_t> gMicDeliveredFrameCount{0};
std::atomic<std::uint64_t> gMicSilentReadCount{0};
freenect_context *gMicContext = nullptr;
freenect_device *gMicDevice = nullptr;
std::thread gMicEventThread;
#endif

UInt32 ChannelCountForMode(MicRoutingMode mode) {
  return mode == MicRoutingMode::kRawArray4 ? 4U : 1U;
}

const char *DeviceNameForMode(MicRoutingMode mode) {
  return mode == MicRoutingMode::kRawArray4 ? "Kinect Microphone Array" : "Kinect Microphone";
}

MicRoutingMode ParseMicRoutingMode(CFPropertyListRef value) {
  if (value == nullptr) {
    return MicRoutingMode::kProcessedMono;
  }
  if (CFGetTypeID(value) == CFNumberGetTypeID()) {
    int raw = 0;
    if (CFNumberGetValue(static_cast<CFNumberRef>(value), kCFNumberIntType, &raw) && raw == 1) {
      return MicRoutingMode::kRawArray4;
    }
    return MicRoutingMode::kProcessedMono;
  }
  if (CFGetTypeID(value) == CFStringGetTypeID()) {
    if (CFStringCompare(static_cast<CFStringRef>(value), CFSTR("rawArray4"), kCFCompareCaseInsensitive) == kCFCompareEqualTo ||
        CFStringCompare(static_cast<CFStringRef>(value), CFSTR("raw_array_4"), kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
      return MicRoutingMode::kRawArray4;
    }
  }
  return MicRoutingMode::kProcessedMono;
}

bool ReadMicRoutingModePreference(CFStringRef user_name, CFStringRef host_name, MicRoutingMode *out_mode) {
  if (out_mode == nullptr) {
    return false;
  }
  CFPropertyListRef value = CFPreferencesCopyValue(kSystemMicModeKey, kIntegrationDefaultsDomain, user_name, host_name);
  if (value == nullptr) {
    return false;
  }
  *out_mode = ParseMicRoutingMode(value);
  CFRelease(value);
  return true;
}

MicRoutingMode LoadMicRoutingModePreference() {
  CFPreferencesAppSynchronize(kIntegrationDefaultsDomain);
  MicRoutingMode mode = MicRoutingMode::kProcessedMono;
  // Prefer the shared /Library/Preferences domain written by the installer or
  // the app's explicit "Apply System Settings" action. The HAL normally runs
  // inside coreaudiod, not the interactive app user session.
  if (ReadMicRoutingModePreference(kCFPreferencesAnyUser, kCFPreferencesCurrentHost, &mode)) {
    return mode;
  }
  if (ReadMicRoutingModePreference(kCFPreferencesAnyUser, kCFPreferencesAnyHost, &mode)) {
    return mode;
  }
  if (ReadMicRoutingModePreference(kCFPreferencesCurrentUser, kCFPreferencesAnyHost, &mode)) {
    return mode;
  }
  return MicRoutingMode::kProcessedMono;
}

#if KINECT_HAVE_LIBFREENECT
void ResetMicRingLocked(std::size_t capacity);
#endif

void RefreshMicFormatLocked(bool reset_ring) {
  gMicRoutingMode = LoadMicRoutingModePreference();
  gChannelCount = ChannelCountForMode(gMicRoutingMode);
  gSampleRate = kNativeMicSampleRate;
  if (!reset_ring) {
    return;
  }
#if KINECT_HAVE_LIBFREENECT
  std::lock_guard<std::mutex> mic_lock(gMicMutex);
  ResetMicRingLocked(static_cast<std::size_t>(kNativeMicSampleRate) * gChannelCount * 4);
#endif
}

AudioStreamBasicDescription MakeFormat(Float64 sample_rate, UInt32 channel_count) {
  AudioStreamBasicDescription asbd{};
  asbd.mSampleRate = sample_rate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
  asbd.mBytesPerPacket = sizeof(Float32) * channel_count;
  asbd.mFramesPerPacket = 1;
  asbd.mBytesPerFrame = sizeof(Float32) * channel_count;
  asbd.mChannelsPerFrame = channel_count;
  asbd.mBitsPerChannel = 32;
  return asbd;
}

OSStatus UnknownProperty() {
  return kAudioHardwareUnknownPropertyError;
}

CFStringRef CopyCFString(const char *text) {
  return CFStringCreateWithCString(nullptr, text, kCFStringEncodingUTF8);
}

bool IsInputScope(const AudioObjectPropertyAddress *address) {
  if (address == nullptr) {
    return false;
  }
  return address->mScope == kAudioObjectPropertyScopeInput || address->mScope == kAudioObjectPropertyScopeGlobal;
}

const char *ScopeName(AudioObjectPropertyScope scope) {
  switch (scope) {
    case kAudioObjectPropertyScopeGlobal:
      return "global";
    case kAudioObjectPropertyScopeInput:
      return "input";
    case kAudioObjectPropertyScopeOutput:
      return "output";
    default:
      return "other";
  }
}

const char *FourCC(UInt32 value, char out[5]) {
  out[0] = static_cast<char>((value >> 24) & 0xff);
  out[1] = static_cast<char>((value >> 16) & 0xff);
  out[2] = static_cast<char>((value >> 8) & 0xff);
  out[3] = static_cast<char>(value & 0xff);
  out[4] = '\0';
  for (int i = 0; i < 4; ++i) {
    if (out[i] < 32 || out[i] > 126) {
      out[i] = '?';
    }
  }
  return out;
}

void LogUnknownProperty(const char *phase, AudioObjectID object_id, const AudioObjectPropertyAddress *address) {
  if (gLog == nullptr || address == nullptr) {
    return;
  }
  char selector[5];
  os_log_error(gLog, "%{public}s unsupported selector=%{public}s object=%u scope=%{public}s element=%u", phase,
               FourCC(address->mSelector, selector), static_cast<unsigned>(object_id), ScopeName(address->mScope),
               static_cast<unsigned>(address->mElement));
}

UInt32 ControlListSize() {
  return 0;
}

UInt32 StreamConfigurationSize(const AudioObjectPropertyAddress *address) {
  return IsInputScope(address) ? sizeof(AudioBufferList) : offsetof(AudioBufferList, mBuffers);
}

void FillStreamConfiguration(const AudioObjectPropertyAddress *address, void *out_data) {
  auto *buffer_list = reinterpret_cast<AudioBufferList *>(out_data);
  if (!IsInputScope(address)) {
    buffer_list->mNumberBuffers = 0;
    return;
  }

  UInt32 channel_count = 1;
  {
    std::lock_guard<std::mutex> lock(gStateMutex);
    channel_count = gChannelCount;
  }
  buffer_list->mNumberBuffers = 1;
  buffer_list->mBuffers[0].mNumberChannels = channel_count;
  buffer_list->mBuffers[0].mDataByteSize = 0;
  buffer_list->mBuffers[0].mData = nullptr;
}

UInt32 PreferredChannelLayoutSize() {
  return static_cast<UInt32>(offsetof(AudioChannelLayout, mChannelDescriptions));
}

void FillPreferredChannelLayout(void *out_data) {
  auto *layout = reinterpret_cast<AudioChannelLayout *>(out_data);
  UInt32 channel_count = 1;
  {
    std::lock_guard<std::mutex> lock(gStateMutex);
    channel_count = gChannelCount;
  }
  layout->mChannelLayoutTag = channel_count == 4 ? kAudioChannelLayoutTag_Quadraphonic : kAudioChannelLayoutTag_Mono;
  layout->mChannelBitmap = 0;
  layout->mNumberChannelDescriptions = 0;
}

#if KINECT_HAVE_LIBFREENECT
bool FirmwareExistsInDir(const std::string &dir) {
  if (dir.empty()) {
    return false;
  }
  std::error_code ec;
  return std::filesystem::exists(std::filesystem::path(dir) / "audios.bin", ec);
}

std::string FindFirmwareDirectory() {
  const char *env = std::getenv("LIBFREENECT_FIRMWARE_PATH");
  if (env != nullptr && FirmwareExistsInDir(env)) {
    return std::string(env);
  }

  const std::vector<std::string> candidates = {
      "/Library/Audio/Plug-Ins/HAL/KinectAudioHAL.driver/Contents/Resources/libfreenect",
      "/Library/Audio/Plug-Ins/HAL/KinectAudioHAL.driver/Contents/Resources",
      // User-domain fallback for ad-hoc local installs (1.1.1)
      std::string(std::getenv("HOME") ? std::string(std::getenv("HOME")) + "/Library/Audio/Plug-Ins/HAL/KinectAudioHAL.driver/Contents/Resources/libfreenect" : ""),
      std::string(std::getenv("HOME") ? std::string(std::getenv("HOME")) + "/Library/Audio/Plug-Ins/HAL/KinectAudioHAL.driver/Contents/Resources" : ""),
      "/opt/homebrew/share/libfreenect",
      "/usr/local/share/libfreenect",
      "/usr/share/libfreenect",
  };

  for (const auto &dir : candidates) {
    if (FirmwareExistsInDir(dir)) {
      return dir;
    }
  }
  return "";
}

void ResetMicRingLocked(std::size_t capacity) {
  gMicRing.assign(std::max<std::size_t>(capacity, static_cast<std::size_t>(kNativeMicSampleRate) * 4), 0.0f);
  gMicReadIndex = 0;
  gMicWriteIndex = 0;
  gMicAvailable = 0;
}

inline Float32 NormalizeCancelledSample(int16_t sample) {
  return static_cast<Float32>(sample / 32768.0f);
}

inline Float32 NormalizeRawSample(int32_t sample) {
  constexpr Float32 kScale = 1.0f / 2147483648.0f;
  const Float32 normalized = static_cast<Float32>(sample) * kScale;
  return std::max(-1.0f, std::min(1.0f, normalized));
}

void PushRingValueLocked(Float32 sample) {
  const std::size_t ring_size = gMicRing.size();
  if (gMicAvailable == ring_size) {
    gMicReadIndex = (gMicReadIndex + 1) % ring_size;
    --gMicAvailable;
  }
  gMicRing[gMicWriteIndex] = sample;
  gMicWriteIndex = (gMicWriteIndex + 1) % ring_size;
  ++gMicAvailable;
}

void EnsureMicRingCapacityLocked(UInt32 channel_count) {
  if (!gMicRing.empty()) {
    return;
  }
  ResetMicRingLocked(static_cast<std::size_t>(kNativeMicSampleRate) * channel_count * 4);
}

void PushProcessedMonoSamples(const int16_t *samples, int count) {
  if (samples == nullptr || count <= 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(gMicMutex);
  EnsureMicRingCapacityLocked(1);
  for (int i = 0; i < count; ++i) {
    PushRingValueLocked(NormalizeCancelledSample(samples[i]));
  }
}

void PushRawArraySamples(const int32_t *mic1, const int32_t *mic2, const int32_t *mic3, const int32_t *mic4, int count) {
  if (mic1 == nullptr || mic2 == nullptr || mic3 == nullptr || mic4 == nullptr || count <= 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(gMicMutex);
  EnsureMicRingCapacityLocked(4);
  for (int i = 0; i < count; ++i) {
    PushRingValueLocked(NormalizeRawSample(mic1[i]));
    PushRingValueLocked(NormalizeRawSample(mic2[i]));
    PushRingValueLocked(NormalizeRawSample(mic3[i]));
    PushRingValueLocked(NormalizeRawSample(mic4[i]));
  }
}

void PushFallbackMonoSamples(const int32_t *mic1, const int32_t *mic2, const int32_t *mic3, const int32_t *mic4, int count) {
  if (mic1 == nullptr || mic2 == nullptr || mic3 == nullptr || mic4 == nullptr || count <= 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(gMicMutex);
  EnsureMicRingCapacityLocked(1);
  for (int i = 0; i < count; ++i) {
    const Float32 mixed =
        (NormalizeRawSample(mic1[i]) + NormalizeRawSample(mic2[i]) + NormalizeRawSample(mic3[i]) + NormalizeRawSample(mic4[i])) /
        4.0f;
    PushRingValueLocked(mixed);
  }
}

void OnKinectAudioFrame(
    freenect_device *,
    int num_samples,
    int32_t *mic1,
    int32_t *mic2,
    int32_t *mic3,
    int32_t *mic4,
    int16_t *cancelled,
    void *) {
  if (!gMicCaptureRunning.load(std::memory_order_acquire) || num_samples <= 0) {
    return;
  }
  gMicCallbackCount.fetch_add(1, std::memory_order_relaxed);

  MicRoutingMode mode = MicRoutingMode::kProcessedMono;
  {
    std::lock_guard<std::mutex> lock(gStateMutex);
    mode = gMicRoutingMode;
  }

  if (mode == MicRoutingMode::kRawArray4 && mic1 != nullptr && mic2 != nullptr && mic3 != nullptr && mic4 != nullptr) {
    PushRawArraySamples(mic1, mic2, mic3, mic4, num_samples);
    return;
  }

  if (cancelled != nullptr) {
    PushProcessedMonoSamples(cancelled, num_samples);
    return;
  }

  PushFallbackMonoSamples(mic1, mic2, mic3, mic4, num_samples);
}

bool PopMicSamples(Float32 *out_buffer, std::size_t frames) {
  if (out_buffer == nullptr || frames == 0) {
    return false;
  }
  UInt32 channel_count = 1;
  {
    std::lock_guard<std::mutex> state_lock(gStateMutex);
    channel_count = gChannelCount;
  }
  std::lock_guard<std::mutex> lock(gMicMutex);
  if (gMicRing.empty()) {
    return false;
  }
  const std::size_t ring_size = gMicRing.size();
  const std::size_t sample_slots = frames * channel_count;
  bool had_any = false;
  for (std::size_t i = 0; i < sample_slots; ++i) {
    if (gMicAvailable > 0) {
      out_buffer[i] = gMicRing[gMicReadIndex];
      gMicReadIndex = (gMicReadIndex + 1) % ring_size;
      --gMicAvailable;
      had_any = true;
    } else {
      out_buffer[i] = 0.0f;
    }
  }
  return had_any;
}

void MicEventLoop() {
  while (gMicCaptureRunning.load(std::memory_order_acquire)) {
    timeval timeout{};
    timeout.tv_sec = 0;
    timeout.tv_usec = 5000;
    if (gMicContext == nullptr) {
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
      continue;
    }
    const int rc = freenect_process_events_timeout(gMicContext, &timeout);
    if (rc < 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
  }
}

bool StartKinectMicCapture() {
  if (gMicCaptureRunning.load(std::memory_order_acquire)) {
    return gMicCaptureReady.load(std::memory_order_acquire);
  }

  // The HAL runs in coreaudiod, so it has to bootstrap libfreenect and the
  // firmware-dependent v1 audio path without any help from the UI process.
  if (gLog != nullptr) {
    os_log_info(gLog, "StartKinectMicCapture: initializing...");
  }

  const std::string firmware_dir = FindFirmwareDirectory();
  if (!firmware_dir.empty()) {
    setenv("LIBFREENECT_FIRMWARE_PATH", firmware_dir.c_str(), 1);
    if (gLog != nullptr) {
      os_log_info(gLog, "StartKinectMicCapture: firmware dir=%{public}s", firmware_dir.c_str());
    }
  } else {
    if (gLog != nullptr) {
      os_log_error(gLog, "StartKinectMicCapture: firmware directory not found!");
    }
  }

  freenect_context *ctx = nullptr;
  if (freenect_init(&ctx, nullptr) < 0 || ctx == nullptr) {
    if (gLog != nullptr) {
      os_log_error(gLog, "HAL microphone capture could not initialize libfreenect.");
    }
    gMicCaptureReady.store(false, std::memory_order_release);
    return false;
  }

  if (gLog != nullptr) {
    os_log_info(gLog, "StartKinectMicCapture: libfreenect initialized");
  }

  freenect_set_log_level(ctx, FREENECT_LOG_WARNING);
  freenect_select_subdevices(ctx, FREENECT_DEVICE_AUDIO);
  int num_devs = freenect_num_devices(ctx);
  if (gLog != nullptr) {
    os_log_info(gLog, "StartKinectMicCapture: num_devices=%d", num_devs);
  }
  if (num_devs <= 0) {
    if (gLog != nullptr) {
      os_log_error(gLog, "HAL microphone capture found no Kinect audio devices.");
    }
    freenect_shutdown(ctx);
    gMicCaptureReady.store(false, std::memory_order_release);
    return false;
  }

  freenect_device *dev = nullptr;
  if (freenect_open_device(ctx, &dev, 0) < 0 || dev == nullptr) {
    if (gLog != nullptr) {
      os_log_error(gLog, "HAL microphone capture could not open Kinect audio device.");
    }
    freenect_shutdown(ctx);
    gMicCaptureReady.store(false, std::memory_order_release);
    return false;
  }

  freenect_close_device(dev);
  dev = nullptr;
  if (freenect_open_device(ctx, &dev, 0) < 0 || dev == nullptr) {
    if (gLog != nullptr) {
      os_log_error(gLog, "HAL microphone capture could not reopen Kinect audio device after firmware load.");
    }
    freenect_shutdown(ctx);
    gMicCaptureReady.store(false, std::memory_order_release);
    return false;
  }

  freenect_set_audio_in_callback(dev, &OnKinectAudioFrame);
  if (freenect_start_audio(dev) < 0) {
    if (gLog != nullptr) {
      os_log_error(gLog, "HAL microphone capture failed to start Kinect audio stream.");
    }
    freenect_close_device(dev);
    freenect_shutdown(ctx);
    gMicCaptureReady.store(false, std::memory_order_release);
    return false;
  }

  {
    std::lock_guard<std::mutex> state_lock(gStateMutex);
    RefreshMicFormatLocked(false);
  }
  UInt32 channel_count = 1;
  {
    std::lock_guard<std::mutex> state_lock(gStateMutex);
    channel_count = gChannelCount;
  }
  {
    std::lock_guard<std::mutex> lock(gMicMutex);
    ResetMicRingLocked(static_cast<std::size_t>(kNativeMicSampleRate) * channel_count * 4);
  }

  gMicContext = ctx;
  gMicDevice = dev;
  gMicCallbackCount.store(0, std::memory_order_release);
  gMicDeliveredFrameCount.store(0, std::memory_order_release);
  gMicSilentReadCount.store(0, std::memory_order_release);
  gMicCaptureRunning.store(true, std::memory_order_release);
  gMicCaptureReady.store(true, std::memory_order_release);
  if (gLog != nullptr) {
    os_log_info(gLog, "HAL microphone capture started. mode=%{public}s channels=%u firmware=%{public}s",
                gMicRoutingMode == MicRoutingMode::kRawArray4 ? "raw4" : "mono",
                static_cast<unsigned>(channel_count), firmware_dir.c_str());
  }
  gMicEventThread = std::thread(MicEventLoop);
  return true;
}

void StopKinectMicCapture() {
  gMicCaptureRunning.store(false, std::memory_order_release);
  if (gMicEventThread.joinable()) {
    gMicEventThread.join();
  }

  if (gMicDevice != nullptr) {
    freenect_stop_audio(gMicDevice);
    freenect_close_device(gMicDevice);
    gMicDevice = nullptr;
  }
  if (gMicContext != nullptr) {
    freenect_shutdown(gMicContext);
    gMicContext = nullptr;
  }

  {
    std::lock_guard<std::mutex> lock(gMicMutex);
    gMicAvailable = 0;
    gMicReadIndex = 0;
    gMicWriteIndex = 0;
  }
  if (gLog != nullptr) {
    os_log_info(gLog,
                "HAL microphone capture stopped. callbacks=%llu deliveredFrames=%llu silentReads=%llu",
                static_cast<unsigned long long>(gMicCallbackCount.load(std::memory_order_relaxed)),
                static_cast<unsigned long long>(gMicDeliveredFrameCount.load(std::memory_order_relaxed)),
                static_cast<unsigned long long>(gMicSilentReadCount.load(std::memory_order_relaxed)));
  }
  gMicCaptureReady.store(false, std::memory_order_release);
}
#endif

HRESULT STDMETHODCALLTYPE DriverQueryInterface(void *in_driver, REFIID, LPVOID *out_interface);
ULONG STDMETHODCALLTYPE DriverAddRef(void *in_driver);
ULONG STDMETHODCALLTYPE DriverRelease(void *in_driver);
OSStatus STDMETHODCALLTYPE DriverInitialize(AudioServerPlugInDriverRef in_driver, AudioServerPlugInHostRef in_host);
OSStatus STDMETHODCALLTYPE DriverCreateDevice(AudioServerPlugInDriverRef in_driver, CFDictionaryRef in_description,
                                              const AudioServerPlugInClientInfo *in_client_info,
                                              AudioObjectID *out_device_object_id);
OSStatus STDMETHODCALLTYPE DriverDestroyDevice(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id);
OSStatus STDMETHODCALLTYPE DriverAddDeviceClient(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id,
                                                 const AudioServerPlugInClientInfo *in_client_info);
OSStatus STDMETHODCALLTYPE DriverRemoveDeviceClient(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id,
                                                    const AudioServerPlugInClientInfo *in_client_info);
OSStatus STDMETHODCALLTYPE DriverPerformDeviceConfigurationChange(AudioServerPlugInDriverRef in_driver,
                                                                  AudioObjectID in_device_object_id,
                                                                  UInt64 in_change_action, void *in_change_info);
OSStatus STDMETHODCALLTYPE DriverAbortDeviceConfigurationChange(AudioServerPlugInDriverRef in_driver,
                                                                AudioObjectID in_device_object_id, UInt64 in_change_action,
                                                                void *in_change_info);
Boolean STDMETHODCALLTYPE DriverHasProperty(AudioServerPlugInDriverRef in_driver, AudioObjectID in_object_id,
                                            pid_t in_client_process_id,
                                            const AudioObjectPropertyAddress *in_address);
OSStatus STDMETHODCALLTYPE DriverIsPropertySettable(AudioServerPlugInDriverRef in_driver, AudioObjectID in_object_id,
                                                    pid_t in_client_process_id,
                                                    const AudioObjectPropertyAddress *in_address, Boolean *out_is_settable);
OSStatus STDMETHODCALLTYPE DriverGetPropertyDataSize(AudioServerPlugInDriverRef in_driver, AudioObjectID in_object_id,
                                                     pid_t in_client_process_id,
                                                     const AudioObjectPropertyAddress *in_address,
                                                     UInt32 in_qualifier_data_size, const void *in_qualifier_data,
                                                     UInt32 *out_data_size);
OSStatus STDMETHODCALLTYPE DriverGetPropertyData(AudioServerPlugInDriverRef in_driver, AudioObjectID in_object_id,
                                                 pid_t in_client_process_id,
                                                 const AudioObjectPropertyAddress *in_address,
                                                 UInt32 in_qualifier_data_size, const void *in_qualifier_data,
                                                 UInt32 in_data_size, UInt32 *out_data_size, void *out_data);
OSStatus STDMETHODCALLTYPE DriverSetPropertyData(AudioServerPlugInDriverRef in_driver, AudioObjectID in_object_id,
                                                 pid_t in_client_process_id,
                                                 const AudioObjectPropertyAddress *in_address,
                                                 UInt32 in_qualifier_data_size, const void *in_qualifier_data,
                                                 UInt32 in_data_size, const void *in_data);
OSStatus STDMETHODCALLTYPE DriverStartIO(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id,
                                         UInt32 in_client_id);
OSStatus STDMETHODCALLTYPE DriverStopIO(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id,
                                        UInt32 in_client_id);
OSStatus STDMETHODCALLTYPE DriverGetZeroTimeStamp(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id,
                                                  UInt32 in_client_id, Float64 *out_sample_time, UInt64 *out_host_time,
                                                  UInt64 *out_seed);
OSStatus STDMETHODCALLTYPE DriverWillDoIOOperation(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id,
                                                   UInt32 in_client_id, UInt32 in_operation_id, Boolean *out_will_do,
                                                   Boolean *out_will_do_in_place);
OSStatus STDMETHODCALLTYPE DriverBeginIOOperation(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id,
                                                  UInt32 in_client_id, UInt32 in_operation_id,
                                                  UInt32 in_io_buffer_frame_size,
                                                  const AudioServerPlugInIOCycleInfo *in_io_cycle_info);
OSStatus STDMETHODCALLTYPE DriverDoIOOperation(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id,
                                               AudioObjectID in_stream_object_id, UInt32 in_client_id,
                                               UInt32 in_operation_id, UInt32 in_io_buffer_frame_size,
                                               const AudioServerPlugInIOCycleInfo *in_io_cycle_info, void *io_main_buffer,
                                               void *io_secondary_buffer);
OSStatus STDMETHODCALLTYPE DriverEndIOOperation(AudioServerPlugInDriverRef in_driver, AudioObjectID in_device_object_id,
                                                UInt32 in_client_id, UInt32 in_operation_id,
                                                UInt32 in_io_buffer_frame_size,
                                                const AudioServerPlugInIOCycleInfo *in_io_cycle_info);

AudioServerPlugInDriverInterface gDriverInterface = {
    nullptr,
    DriverQueryInterface,
    DriverAddRef,
    DriverRelease,
    DriverInitialize,
    DriverCreateDevice,
    DriverDestroyDevice,
    DriverAddDeviceClient,
    DriverRemoveDeviceClient,
    DriverPerformDeviceConfigurationChange,
    DriverAbortDeviceConfigurationChange,
    DriverHasProperty,
    DriverIsPropertySettable,
    DriverGetPropertyDataSize,
    DriverGetPropertyData,
    DriverSetPropertyData,
    DriverStartIO,
    DriverStopIO,
    DriverGetZeroTimeStamp,
    DriverWillDoIOOperation,
    DriverBeginIOOperation,
    DriverDoIOOperation,
    DriverEndIOOperation};

AudioServerPlugInDriverInterface *gDriverInterfacePtr = &gDriverInterface;
AudioServerPlugInDriverRef gDriverRef = &gDriverInterfacePtr;

HRESULT STDMETHODCALLTYPE DriverQueryInterface(void *, REFIID, LPVOID *out_interface) {
  if (out_interface == nullptr) {
    return E_POINTER;
  }
  *out_interface = gDriverRef;
  DriverAddRef(nullptr);
  return S_OK;
}

ULONG STDMETHODCALLTYPE DriverAddRef(void *) {
  return ++gRefCount;
}

ULONG STDMETHODCALLTYPE DriverRelease(void *) {
  const ULONG value = --gRefCount;
  return value;
}

OSStatus STDMETHODCALLTYPE DriverInitialize(AudioServerPlugInDriverRef, AudioServerPlugInHostRef in_host) {
  std::lock_guard<std::mutex> lock(gStateMutex);
  gHost = in_host;
  if (gLog == nullptr) {
    gLog = os_log_create("com.mackinect.audiohal", "driver");
  }
  RefreshMicFormatLocked(false);
  gZeroHostTime = AudioGetCurrentHostTime();
  gZeroSampleTime = 0.0;
  gZeroTimeStampSeed = 1;
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverCreateDevice(AudioServerPlugInDriverRef, CFDictionaryRef,
                                              const AudioServerPlugInClientInfo *, AudioObjectID *) {
  return kAudioHardwareUnsupportedOperationError;
}

OSStatus STDMETHODCALLTYPE DriverDestroyDevice(AudioServerPlugInDriverRef, AudioObjectID) {
  return kAudioHardwareUnsupportedOperationError;
}

OSStatus STDMETHODCALLTYPE DriverAddDeviceClient(AudioServerPlugInDriverRef, AudioObjectID, const AudioServerPlugInClientInfo *) {
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverRemoveDeviceClient(AudioServerPlugInDriverRef, AudioObjectID,
                                                    const AudioServerPlugInClientInfo *) {
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverPerformDeviceConfigurationChange(AudioServerPlugInDriverRef, AudioObjectID, UInt64, void *) {
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverAbortDeviceConfigurationChange(AudioServerPlugInDriverRef, AudioObjectID, UInt64, void *) {
  return noErr;
}

Boolean STDMETHODCALLTYPE DriverHasProperty(AudioServerPlugInDriverRef, AudioObjectID in_object_id, pid_t,
                                            const AudioObjectPropertyAddress *in_address) {
  if (in_address == nullptr) {
    return false;
  }

  switch (in_object_id) {
    case kAudioObjectPlugInObject:
      switch (in_address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice:
        case kAudioPlugInPropertyResourceBundle:
          return true;
        default:
          return false;
      }
    case kObjectIDDevice:
      switch (in_address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyStreams:
        case kAudioDevicePropertyStreamConfiguration:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyBufferFrameSizeRange:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyClockAlgorithm:
        case kAudioDevicePropertyClockIsStable:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyPreferredChannelsForStereo:
        case kAudioDevicePropertyPreferredChannelLayout:
          return true;
        default:
          return false;
      }
    case kObjectIDStreamInput:
      switch (in_address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyPhysicalFormat:
        case kAudioStreamPropertyAvailablePhysicalFormats:
          return true;
        default:
          return false;
      }
    default:
      return false;
  }
}

OSStatus STDMETHODCALLTYPE DriverIsPropertySettable(AudioServerPlugInDriverRef, AudioObjectID in_object_id, pid_t,
                                                    const AudioObjectPropertyAddress *in_address, Boolean *out_is_settable) {
  if (in_address == nullptr || out_is_settable == nullptr) {
    return kAudioHardwareIllegalOperationError;
  }

  *out_is_settable = false;
  if (in_object_id == kObjectIDDevice && in_address->mSelector == kAudioDevicePropertyBufferFrameSize) {
    *out_is_settable = true;
  }
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverGetPropertyDataSize(AudioServerPlugInDriverRef, AudioObjectID in_object_id, pid_t,
                                                     const AudioObjectPropertyAddress *in_address, UInt32,
                                                     const void *, UInt32 *out_data_size) {
  if (in_address == nullptr || out_data_size == nullptr) {
    return kAudioHardwareIllegalOperationError;
  }

  switch (in_object_id) {
    case kAudioObjectPlugInObject:
      switch (in_address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
          *out_data_size = sizeof(AudioClassID);
          return noErr;
        case kAudioObjectPropertyManufacturer:
        case kAudioPlugInPropertyResourceBundle:
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
          *out_data_size = sizeof(AudioObjectID);
          return noErr;
        case kAudioPlugInPropertyTranslateUIDToDevice:
          *out_data_size = sizeof(AudioObjectID);
          return noErr;
        default:
          return UnknownProperty();
      }
    case kObjectIDDevice:
      switch (in_address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyClockAlgorithm:
        case kAudioDevicePropertyClockIsStable:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyBufferFrameSize:
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        case kAudioObjectPropertyControlList:
          *out_data_size = ControlListSize();
          return noErr;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams:
          *out_data_size = sizeof(AudioObjectID);
          return noErr;
        case kAudioDevicePropertyNominalSampleRate:
          *out_data_size = sizeof(Float64);
          return noErr;
        case kAudioDevicePropertyStreamConfiguration:
          *out_data_size = StreamConfigurationSize(in_address);
          return noErr;
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyBufferFrameSizeRange:
          *out_data_size = sizeof(AudioValueRange);
          return noErr;
        case kAudioDevicePropertyPreferredChannelsForStereo:
          *out_data_size = sizeof(UInt32) * 2;
          return noErr;
        case kAudioDevicePropertyPreferredChannelLayout:
          *out_data_size = PreferredChannelLayoutSize();
          return noErr;
        default:
          LogUnknownProperty("size", in_object_id, in_address);
          return UnknownProperty();
      }
    case kObjectIDStreamInput:
      switch (in_address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioObjectPropertyName:
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
          *out_data_size = sizeof(AudioStreamBasicDescription);
          return noErr;
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
          *out_data_size = sizeof(AudioStreamRangedDescription);
          return noErr;
        default:
          LogUnknownProperty("size", in_object_id, in_address);
          return UnknownProperty();
      }
    default:
      LogUnknownProperty("size", in_object_id, in_address);
      return UnknownProperty();
  }
}

OSStatus STDMETHODCALLTYPE DriverGetPropertyData(AudioServerPlugInDriverRef, AudioObjectID in_object_id, pid_t,
                                                 const AudioObjectPropertyAddress *in_address, UInt32 in_qualifier_data_size,
                                                 const void *in_qualifier_data, UInt32 in_data_size, UInt32 *out_data_size,
                                                 void *out_data) {
  if (in_address == nullptr || out_data_size == nullptr || out_data == nullptr) {
    return kAudioHardwareIllegalOperationError;
  }

  switch (in_object_id) {
    case kAudioObjectPlugInObject:
      switch (in_address->mSelector) {
        case kAudioObjectPropertyBaseClass:
          if (in_data_size < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioClassID *>(out_data) = kAudioObjectClassID;
          *out_data_size = sizeof(AudioClassID);
          return noErr;
        case kAudioObjectPropertyClass:
          if (in_data_size < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioClassID *>(out_data) = kAudioPlugInClassID;
          *out_data_size = sizeof(AudioClassID);
          return noErr;
        case kAudioObjectPropertyManufacturer:
          if (in_data_size < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<CFStringRef *>(out_data) = CopyCFString(kManufacturerName);
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
          if (in_data_size < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioObjectID *>(out_data) = kObjectIDDevice;
          *out_data_size = sizeof(AudioObjectID);
          return noErr;
        case kAudioPlugInPropertyTranslateUIDToDevice: {
          if (in_data_size < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
          AudioObjectID translated = kAudioObjectUnknown;
          if (in_qualifier_data_size == sizeof(CFStringRef) && in_qualifier_data != nullptr) {
            CFStringRef uid = *reinterpret_cast<CFStringRef const *>(in_qualifier_data);
            CFStringRef expected = CopyCFString(kDeviceUID);
            if (uid != nullptr && expected != nullptr && CFEqual(uid, expected)) {
              translated = kObjectIDDevice;
            }
            if (expected != nullptr) CFRelease(expected);
          }
          *reinterpret_cast<AudioObjectID *>(out_data) = translated;
          *out_data_size = sizeof(AudioObjectID);
          return noErr;
        }
        case kAudioPlugInPropertyResourceBundle:
          if (in_data_size < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<CFStringRef *>(out_data) = nullptr;
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        default:
          return UnknownProperty();
      }

    case kObjectIDDevice:
      switch (in_address->mSelector) {
        case kAudioObjectPropertyBaseClass:
          if (in_data_size < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioClassID *>(out_data) = kAudioObjectClassID;
          *out_data_size = sizeof(AudioClassID);
          return noErr;
        case kAudioObjectPropertyClass:
          if (in_data_size < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioClassID *>(out_data) = kAudioDeviceClassID;
          *out_data_size = sizeof(AudioClassID);
          return noErr;
        case kAudioObjectPropertyOwner:
          if (in_data_size < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioObjectID *>(out_data) = kAudioObjectPlugInObject;
          *out_data_size = sizeof(AudioObjectID);
          return noErr;
        case kAudioObjectPropertyName:
          if (in_data_size < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
          {
            std::lock_guard<std::mutex> lock(gStateMutex);
            *reinterpret_cast<CFStringRef *>(out_data) = CopyCFString(DeviceNameForMode(gMicRoutingMode));
          }
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        case kAudioObjectPropertyManufacturer:
          if (in_data_size < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<CFStringRef *>(out_data) = CopyCFString(kManufacturerName);
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        case kAudioObjectPropertyControlList:
          *out_data_size = 0;
          return noErr;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams:
          if (!IsInputScope(in_address)) {
            *out_data_size = 0;
            return noErr;
          }
          if (in_data_size < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioObjectID *>(out_data) = kObjectIDStreamInput;
          *out_data_size = sizeof(AudioObjectID);
          return noErr;
        case kAudioDevicePropertyDeviceUID:
          if (in_data_size < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<CFStringRef *>(out_data) = CopyCFString(kDeviceUID);
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        case kAudioDevicePropertyModelUID:
          if (in_data_size < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<CFStringRef *>(out_data) = CopyCFString(kModelUID);
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        case kAudioDevicePropertyTransportType:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = kAudioDeviceTransportTypeUSB;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyRelatedDevices:
          if (in_data_size < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioObjectID *>(out_data) = kObjectIDDevice;
          *out_data_size = sizeof(AudioObjectID);
          return noErr;
        case kAudioDevicePropertyClockDomain:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = kClockDomain;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyStreamConfiguration: {
          const UInt32 required_size = StreamConfigurationSize(in_address);
          if (in_data_size < required_size) return kAudioHardwareBadPropertySizeError;
          FillStreamConfiguration(in_address, out_data);
          *out_data_size = required_size;
          return noErr;
        }
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = IsInputScope(in_address) ? 1U : 0U;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = 0;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyNominalSampleRate: {
          if (in_data_size < sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
          std::lock_guard<std::mutex> lock(gStateMutex);
          *reinterpret_cast<Float64 *>(out_data) = gSampleRate;
          *out_data_size = sizeof(Float64);
          return noErr;
        }
        case kAudioDevicePropertyAvailableNominalSampleRates: {
          if (in_data_size < sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
          auto *range = reinterpret_cast<AudioValueRange *>(out_data);
          range->mMinimum = kNativeMicSampleRate;
          range->mMaximum = kNativeMicSampleRate;
          *out_data_size = sizeof(AudioValueRange);
          return noErr;
        }
        case kAudioDevicePropertyBufferFrameSize: {
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          std::lock_guard<std::mutex> lock(gStateMutex);
          *reinterpret_cast<UInt32 *>(out_data) = gBufferFrameSize;
          *out_data_size = sizeof(UInt32);
          return noErr;
        }
        case kAudioDevicePropertyBufferFrameSizeRange: {
          if (in_data_size < sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
          auto *range = reinterpret_cast<AudioValueRange *>(out_data);
          range->mMinimum = 64;
          range->mMaximum = 4096;
          *out_data_size = sizeof(AudioValueRange);
          return noErr;
        }
        case kAudioDevicePropertyDeviceIsAlive:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
#if KINECT_HAVE_LIBFREENECT
          {
            const bool running = gRunningIOClients.load(std::memory_order_acquire) > 0;
            const bool ready = gMicCaptureReady.load(std::memory_order_acquire);
            *reinterpret_cast<UInt32 *>(out_data) = (!running || ready) ? 1U : 0U;
          }
#else
          *reinterpret_cast<UInt32 *>(out_data) = 0;
#endif
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyDeviceIsRunning: {
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = gRunningIOClients.load(std::memory_order_acquire) > 0 ? 1U : 0U;
          *out_data_size = sizeof(UInt32);
          return noErr;
        }
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = 0;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyClockAlgorithm:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = kAudioDeviceClockAlgorithmSimpleIIR;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyClockIsStable:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = 1;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyZeroTimeStampPeriod:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          {
            std::lock_guard<std::mutex> lock(gStateMutex);
            *reinterpret_cast<UInt32 *>(out_data) = gBufferFrameSize;
          }
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyIsHidden:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = 0;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioDevicePropertyPreferredChannelsForStereo: {
          if (in_data_size < sizeof(UInt32) * 2) return kAudioHardwareBadPropertySizeError;
          UInt32 channel_count = 1;
          {
            std::lock_guard<std::mutex> lock(gStateMutex);
            channel_count = gChannelCount;
          }
          reinterpret_cast<UInt32 *>(out_data)[0] = 1;
          reinterpret_cast<UInt32 *>(out_data)[1] = channel_count >= 2 ? 2 : 1;
          *out_data_size = sizeof(UInt32) * 2;
          return noErr;
        }
        case kAudioDevicePropertyPreferredChannelLayout: {
          const UInt32 required_size = PreferredChannelLayoutSize();
          if (in_data_size < required_size) return kAudioHardwareBadPropertySizeError;
          FillPreferredChannelLayout(out_data);
          *out_data_size = required_size;
          return noErr;
        }
        default:
          LogUnknownProperty("get", in_object_id, in_address);
          return UnknownProperty();
      }

    case kObjectIDStreamInput:
      switch (in_address->mSelector) {
        case kAudioObjectPropertyBaseClass:
          if (in_data_size < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioClassID *>(out_data) = kAudioObjectClassID;
          *out_data_size = sizeof(AudioClassID);
          return noErr;
        case kAudioObjectPropertyClass:
          if (in_data_size < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioClassID *>(out_data) = kAudioStreamClassID;
          *out_data_size = sizeof(AudioClassID);
          return noErr;
        case kAudioObjectPropertyOwner:
          if (in_data_size < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<AudioObjectID *>(out_data) = kObjectIDDevice;
          *out_data_size = sizeof(AudioObjectID);
          return noErr;
        case kAudioObjectPropertyName:
          if (in_data_size < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
          {
            std::lock_guard<std::mutex> lock(gStateMutex);
            *reinterpret_cast<CFStringRef *>(out_data) = CopyCFString(DeviceNameForMode(gMicRoutingMode));
          }
          *out_data_size = sizeof(CFStringRef);
          return noErr;
        case kAudioStreamPropertyIsActive:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = 1;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioStreamPropertyDirection:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = 1;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioStreamPropertyTerminalType:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = kAudioStreamTerminalTypeMicrophone;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioStreamPropertyStartingChannel:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = 1;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioStreamPropertyLatency:
          if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
          *reinterpret_cast<UInt32 *>(out_data) = 0;
          *out_data_size = sizeof(UInt32);
          return noErr;
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: {
          if (in_data_size < sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
          std::lock_guard<std::mutex> lock(gStateMutex);
          *reinterpret_cast<AudioStreamBasicDescription *>(out_data) = MakeFormat(gSampleRate, gChannelCount);
          *out_data_size = sizeof(AudioStreamBasicDescription);
          return noErr;
        }
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: {
          if (in_data_size < sizeof(AudioStreamRangedDescription)) return kAudioHardwareBadPropertySizeError;
          auto *range = reinterpret_cast<AudioStreamRangedDescription *>(out_data);
          std::lock_guard<std::mutex> lock(gStateMutex);
          range->mFormat = MakeFormat(kNativeMicSampleRate, gChannelCount);
          range->mSampleRateRange.mMinimum = kNativeMicSampleRate;
          range->mSampleRateRange.mMaximum = kNativeMicSampleRate;
          *out_data_size = sizeof(AudioStreamRangedDescription);
          return noErr;
        }
        default:
          LogUnknownProperty("get", in_object_id, in_address);
          return UnknownProperty();
      }

    default:
      LogUnknownProperty("get", in_object_id, in_address);
      return UnknownProperty();
  }
}

OSStatus STDMETHODCALLTYPE DriverSetPropertyData(AudioServerPlugInDriverRef, AudioObjectID in_object_id, pid_t,
                                                 const AudioObjectPropertyAddress *in_address, UInt32, const void *,
                                                 UInt32 in_data_size, const void *in_data) {
  if (in_address == nullptr || in_data == nullptr) {
    return kAudioHardwareIllegalOperationError;
  }

  if (in_object_id == kObjectIDDevice && in_address->mSelector == kAudioDevicePropertyBufferFrameSize) {
    if (in_data_size < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
    std::lock_guard<std::mutex> lock(gStateMutex);
    const UInt32 requested = *reinterpret_cast<const UInt32 *>(in_data);
    gBufferFrameSize = std::max<UInt32>(64, std::min<UInt32>(requested, 4096));
    return noErr;
  }

  return kAudioHardwareUnsupportedOperationError;
}

OSStatus STDMETHODCALLTYPE DriverStartIO(AudioServerPlugInDriverRef, AudioObjectID, UInt32) {
#if KINECT_HAVE_LIBFREENECT
  {
    std::lock_guard<std::mutex> lock(gStateMutex);
    RefreshMicFormatLocked(true);
    ++gZeroTimeStampSeed;
  }
#endif
  const UInt32 previous = gRunningIOClients.fetch_add(1, std::memory_order_acq_rel);
#if KINECT_HAVE_LIBFREENECT
  bool capture_ready = gMicCaptureReady.load(std::memory_order_acquire);
  if (previous == 0) {
    capture_ready = StartKinectMicCapture();
  }
  if (!capture_ready) {
    gRunningIOClients.fetch_sub(1, std::memory_order_acq_rel);
    if (gLog != nullptr) {
      os_log_error(gLog, "HAL StartIO failed because Kinect microphone capture is not ready.");
    }
    return kAudioHardwareUnspecifiedError;
  }
  if (gLog != nullptr) {
    os_log_info(gLog, "HAL StartIO clients=%u ready=%{public}s", static_cast<unsigned>(previous + 1),
                capture_ready ? "true" : "false");
  }
#else
  (void)previous;
  return kAudioHardwareUnsupportedOperationError;
#endif
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverStopIO(AudioServerPlugInDriverRef, AudioObjectID, UInt32) {
  UInt32 current = gRunningIOClients.load(std::memory_order_acquire);
  while (current > 0 &&
         !gRunningIOClients.compare_exchange_weak(current, current - 1, std::memory_order_acq_rel, std::memory_order_acquire)) {
  }
#if KINECT_HAVE_LIBFREENECT
  if (current == 1) {
    StopKinectMicCapture();
  }
  if (gLog != nullptr) {
    os_log_info(gLog, "HAL StopIO remainingClients=%u", static_cast<unsigned>(current > 0 ? current - 1 : 0));
  }
#endif
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverGetZeroTimeStamp(AudioServerPlugInDriverRef, AudioObjectID, UInt32, Float64 *out_sample_time,
                                                  UInt64 *out_host_time, UInt64 *out_seed) {
  if (out_sample_time == nullptr || out_host_time == nullptr || out_seed == nullptr) {
    return kAudioHardwareIllegalOperationError;
  }

  std::lock_guard<std::mutex> lock(gStateMutex);
  const UInt64 now = AudioGetCurrentHostTime();
  if (gZeroHostTime == 0) {
    gZeroHostTime = now;
  }

  const Float64 elapsed = AudioConvertHostTimeToNanos(now - gZeroHostTime) / 1.0e9;
  gZeroSampleTime = elapsed * gSampleRate;

  *out_sample_time = gZeroSampleTime;
  *out_host_time = now;
  *out_seed = gZeroTimeStampSeed;
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverWillDoIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32 in_operation_id,
                                                   Boolean *out_will_do, Boolean *out_will_do_in_place) {
  if (out_will_do == nullptr || out_will_do_in_place == nullptr) {
    return kAudioHardwareIllegalOperationError;
  }
  const bool read_input = in_operation_id == kAudioServerPlugInIOOperationReadInput;
  *out_will_do = read_input ? 1 : 0;
  *out_will_do_in_place = 1;
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverBeginIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32, UInt32,
                                                  const AudioServerPlugInIOCycleInfo *) {
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverDoIOOperation(AudioServerPlugInDriverRef, AudioObjectID, AudioObjectID, UInt32,
                                               UInt32 in_operation_id, UInt32 in_io_buffer_frame_size,
                                               const AudioServerPlugInIOCycleInfo *, void *io_main_buffer, void *) {
  if (in_operation_id == kAudioServerPlugInIOOperationReadInput && io_main_buffer != nullptr) {
    auto *samples = reinterpret_cast<Float32 *>(io_main_buffer);
    UInt32 channel_count = 1;
    {
      std::lock_guard<std::mutex> lock(gStateMutex);
      channel_count = gChannelCount;
    }
    const std::size_t sample_count = static_cast<std::size_t>(in_io_buffer_frame_size) * channel_count;
#if KINECT_HAVE_LIBFREENECT
    const bool produced = gMicCaptureReady.load(std::memory_order_acquire) &&
                          PopMicSamples(samples, static_cast<std::size_t>(in_io_buffer_frame_size));
    if (!produced) {
      std::memset(samples, 0, sample_count * sizeof(Float32));
      gMicSilentReadCount.fetch_add(1, std::memory_order_relaxed);
    } else {
      gMicDeliveredFrameCount.fetch_add(in_io_buffer_frame_size, std::memory_order_relaxed);
    }
#else
    std::memset(samples, 0, sample_count * sizeof(Float32));
#endif
  }
  return noErr;
}

OSStatus STDMETHODCALLTYPE DriverEndIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32, UInt32,
                                                const AudioServerPlugInIOCycleInfo *) {
  return noErr;
}

}  // namespace

extern "C" void *KinectAudioHALPlugInFactory(CFAllocatorRef, CFUUIDRef requested_type_uuid) {
  if (requested_type_uuid == nullptr) {
    return nullptr;
  }
  CFUUIDRef expected = kAudioServerPlugInTypeUUID;
  if (!CFEqual(requested_type_uuid, expected)) {
    return nullptr;
  }
  DriverAddRef(nullptr);
  return gDriverRef;
}
