//
//  VideoController.m
//  camerawesome
//
//  Created by Dimitri Dessus on 17/12/2020.
//

#import "VideoController.h"

FourCharCode const videoFormat = kCVPixelFormatType_32BGRA;

@implementation VideoController

- (instancetype)init {
  self = [super init];
  _isRecording = NO;
  _isAudioEnabled = YES;
  _isPaused = NO;
  
  return self;
}

# pragma mark - User video interactions

/// Start recording video at given path
- (void)recordVideoAtPath:(NSString *)path captureDevice:(AVCaptureDevice *)device orientation:(NSInteger)orientation audioSetupCallback:(OnAudioSetup)audioSetupCallback videoWriterCallback:(OnVideoWriterSetup)videoWriterCallback options:(CupertinoVideoOptions *)options quality:(VideoRecordingQuality)quality completion:(nonnull void (^)(FlutterError * _Nullable))completion {
  _options = options;
  _recordingQuality = quality;

  // Get the codec type first
  AVVideoCodecType codecType = [self getBestCodecTypeAccordingOptions:options];
  
  // Configure color space with respect to the codec
  if (options && options != (id)[NSNull null] && options.colorSpace != CupertinoColorSpaceSRGB) {
    [self configureColorSpaceForRecording:device 
                               colorSpace:options.colorSpace
                                    codec:codecType];
  }
  
  // Create audio & video writer
  if (![self setupWriterForPath:path audioSetupCallback:audioSetupCallback options:options completion:completion]) {
    completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"impossible to write video at path" details:path]);
    return;
  }
  // Call parent to add delegates for video & audio (if needed)
  videoWriterCallback();
  
  _isRecording = YES;
  _videoTimeOffset = CMTimeMake(0, 1);
  _audioTimeOffset = CMTimeMake(0, 1);
  _videoIsDisconnected = NO;
  _audioIsDisconnected = NO;
  _orientation = orientation;
  _captureDevice = device;
  
  // Change video FPS if provided
  if (_options && _options.fps != nil && _options.fps > 0) {
    [self adjustCameraFPS:_options.fps];
  }
}

/// Stop recording video
- (void)stopRecordingVideo:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
  if (_options && _options.fps != nil && _options.fps > 0) {
    // Reset camera FPS
    [self adjustCameraFPS:@(30)];
  }
  
  if (_isRecording) {
    _isRecording = NO;
    if (_videoWriter.status != AVAssetWriterStatusUnknown) {
      [_videoWriter finishWritingWithCompletionHandler:^{
        if (self->_videoWriter.status == AVAssetWriterStatusCompleted) {
          completion(@(YES), nil);
        } else {
          completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"impossible to completely write video" details:@""]);
        }
      }];
    }
  } else {
    completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"video is not recording" details:@""]);
  }
}

- (void)pauseVideoRecording {
  _isPaused = YES;
}

- (void)resumeVideoRecording {
  _isPaused = NO;
}

# pragma mark - Audio & Video writers

/// Setup video channel & write file on path
- (BOOL)setupWriterForPath:(NSString *)path audioSetupCallback:(OnAudioSetup)audioSetupCallback options:(CupertinoVideoOptions *)options completion:(nonnull void (^)(FlutterError * _Nullable))completion {
  NSError *error = nil;
  NSURL *outputURL;
  if (path != nil) {
    outputURL = [NSURL fileURLWithPath:path];
  } else {
    return NO;
  }
  if (_isAudioEnabled && !_isAudioSetup) {
    audioSetupCallback();
  }
  printf(@"[CameraAwesome] Color space before writer setup: %ld", (long)_captureDevice.activeColorSpace);
  // Read from options if available
  AVVideoCodecType codecType = [self getBestCodecTypeAccordingOptions:options];
  AVFileType fileType = [self getBestFileTypeAccordingOptions:options];
  CGSize videoSize = [self getBestVideoSizeAccordingQuality: _recordingQuality];
    
  NSDictionary *videoSettings = @{
    AVVideoCodecKey   : codecType,
    AVVideoWidthKey   : @(videoSize.height),
    AVVideoHeightKey  : @(videoSize.width),
  };
  
  _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
  [_videoWriterInput setTransform:[self getVideoOrientation]];
  
  _videoAdaptor = [AVAssetWriterInputPixelBufferAdaptor
                   assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput
                   sourcePixelBufferAttributes:@{
    (NSString *)kCVPixelBufferPixelFormatTypeKey: @(videoFormat)
  }];
  
  NSParameterAssert(_videoWriterInput);
  _videoWriterInput.expectsMediaDataInRealTime = YES;
  
  _videoWriter = [[AVAssetWriter alloc] initWithURL:outputURL
                                           fileType:fileType
                                              error:&error];
  NSParameterAssert(_videoWriter);
  if (error) {
    completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"impossible to create video writer, check your options" details:error.description]);
    return NO;
  }
  
  [_videoWriter addInput:_videoWriterInput];
  
  if (_isAudioEnabled) {
    AudioChannelLayout acl;
    bzero(&acl, sizeof(acl));
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    NSDictionary *audioOutputSettings = nil;
    
    audioOutputSettings = [NSDictionary
                           dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey,
                           [NSNumber numberWithFloat:44100.0], AVSampleRateKey,
                           [NSNumber numberWithInt:1], AVNumberOfChannelsKey,
                           [NSData dataWithBytes:&acl length:sizeof(acl)],
                           AVChannelLayoutKey, nil];
    _audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                           outputSettings:audioOutputSettings];
    _audioWriterInput.expectsMediaDataInRealTime = YES;
    
    [_videoWriter addInput:_audioWriterInput];
  }

  printf(@"[CameraAwesome] Color space after writer setup: %ld", (long)_captureDevice.activeColorSpace);
  
  return YES;
}

- (CGAffineTransform)getVideoOrientation {
  CGAffineTransform transform;
  
  switch ([[UIDevice currentDevice] orientation]) {
    case UIDeviceOrientationLandscapeLeft:
      transform = CGAffineTransformMakeRotation(-M_PI_2);
      break;
    case UIDeviceOrientationLandscapeRight:
      transform = CGAffineTransformMakeRotation(M_PI_2);
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      transform = CGAffineTransformMakeRotation(M_PI);
      break;
    default:
      transform = CGAffineTransformIdentity;
      break;
  }
  
  return transform;
}

/// Append audio data
- (void)newAudioSample:(CMSampleBufferRef)sampleBuffer {
  if (_videoWriter.status != AVAssetWriterStatusWriting) {
    if (_videoWriter.status == AVAssetWriterStatusFailed) {
      //      *error = [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"writing video failed" details:_videoWriter.error];
    }
    return;
  }
  if (_audioWriterInput.readyForMoreMediaData) {
    if (![_audioWriterInput appendSampleBuffer:sampleBuffer]) {
      //      *error = [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"adding audio channel failed" details:_videoWriter.error];
    }
  }
}

/// Adjust time to sync audio & video
- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sample by:(CMTime)offset CF_RETURNS_RETAINED {
  CMItemCount count;
  CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
  CMSampleTimingInfo *pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
  CMSampleBufferGetSampleTimingInfoArray(sample, count, pInfo, &count);
  for (CMItemCount i = 0; i < count; i++) {
    pInfo[i].decodeTimeStamp = CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
    pInfo[i].presentationTimeStamp = CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
  }
  CMSampleBufferRef sout;
  CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, pInfo, &sout);
  free(pInfo);
  return sout;
}

/// Adjust video preview & recording to specified FPS
- (void)adjustCameraFPS:(NSNumber *)fps {
  NSArray *frameRateRanges = _captureDevice.activeFormat.videoSupportedFrameRateRanges;
  
  if (frameRateRanges.count > 0) {
    AVFrameRateRange *frameRateRange = frameRateRanges.firstObject;
    NSError *error = nil;
    
    if ([_captureDevice lockForConfiguration:&error]) {
      CMTime frameDuration = CMTimeMake(1, [fps intValue]);
      if (CMTIME_COMPARE_INLINE(frameDuration, <=, frameRateRange.maxFrameDuration) && CMTIME_COMPARE_INLINE(frameDuration, >=, frameRateRange.minFrameDuration)) {
        _captureDevice.activeVideoMinFrameDuration = frameDuration;
      }
      [_captureDevice unlockForConfiguration];
    }
  }
}

# pragma mark - Camera Delegates
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection captureVideoOutput:(AVCaptureVideoDataOutput *)captureVideoOutput {
  
  if (self.isPaused) {
    return;
  }
  
  if (_videoWriter.status == AVAssetWriterStatusFailed) {
    //    _result([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"impossible to write video " details:_videoWriter.error]);
    return;
  }
  
  CFRetain(sampleBuffer);
  CMTime currentSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
  
  if (_videoWriter.status != AVAssetWriterStatusWriting) {
    [_videoWriter startWriting];
    [_videoWriter startSessionAtSourceTime:currentSampleTime];
  }
  
  if (output == captureVideoOutput) {
    if (_videoIsDisconnected) {
      _videoIsDisconnected = NO;
      
      if (_videoTimeOffset.value == 0) {
        _videoTimeOffset = CMTimeSubtract(currentSampleTime, _lastVideoSampleTime);
      } else {
        CMTime offset = CMTimeSubtract(currentSampleTime, _lastVideoSampleTime);
        _videoTimeOffset = CMTimeAdd(_videoTimeOffset, offset);
      }
      
      return;
    }
    
    _lastVideoSampleTime = currentSampleTime;
    
    CVPixelBufferRef nextBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CMTime nextSampleTime = CMTimeSubtract(_lastVideoSampleTime, _videoTimeOffset);
    [_videoAdaptor appendPixelBuffer:nextBuffer withPresentationTime:nextSampleTime];
  } else {
    CMTime dur = CMSampleBufferGetDuration(sampleBuffer);
    
    if (dur.value > 0) {
      currentSampleTime = CMTimeAdd(currentSampleTime, dur);
    }
    if (_audioIsDisconnected) {
      _audioIsDisconnected = NO;
      
      if (_audioTimeOffset.value == 0) {
        _audioTimeOffset = CMTimeSubtract(currentSampleTime, _lastAudioSampleTime);
      } else {
        CMTime offset = CMTimeSubtract(currentSampleTime, _lastAudioSampleTime);
        _audioTimeOffset = CMTimeAdd(_audioTimeOffset, offset);
      }
      
      return;
    }
    
    _lastAudioSampleTime = currentSampleTime;
    
    if (_audioTimeOffset.value != 0) {
      CFRelease(sampleBuffer);
      sampleBuffer = [self adjustTime:sampleBuffer by:_audioTimeOffset];
    }
    
    [self newAudioSample:sampleBuffer];
  }
  
  CFRelease(sampleBuffer);
}

# pragma mark - Settings converters

- (AVFileType)getBestFileTypeAccordingOptions:(CupertinoVideoOptions *)options {
  AVFileType fileType = AVFileTypeQuickTimeMovie;
  
  if (options && options != (id)[NSNull null]) {
    CupertinoFileType type = options.fileType;
    switch (type) {
      case CupertinoFileTypeQuickTimeMovie:
        fileType = AVFileTypeQuickTimeMovie;
        break;
      case CupertinoFileTypeMpeg4:
        fileType = AVFileTypeMPEG4;
        break;
      case CupertinoFileTypeAppleM4V:
        fileType = AVFileTypeAppleM4V;
        break;
      case CupertinoFileTypeType3GPP:
        fileType = AVFileType3GPP;
        break;
      case CupertinoFileTypeType3GPP2:
        fileType = AVFileType3GPP2;
        break;
      default:
        break;
    }
  }
  
  return fileType;
}

- (AVVideoCodecType)getBestCodecTypeAccordingOptions:(CupertinoVideoOptions *)options {
  AVVideoCodecType codecType = AVVideoCodecTypeH264;
  if (options && options != (id)[NSNull null]) {
    CupertinoCodecType codec = options.codec;
    switch (codec) {
      case CupertinoCodecTypeH264:
        codecType = AVVideoCodecTypeH264;
        break;
      case CupertinoCodecTypeHevc:
        codecType = AVVideoCodecTypeHEVC;
        break;
      case CupertinoCodecTypeHevcWithAlpha:
        codecType = AVVideoCodecTypeHEVCWithAlpha;
        break;
      case CupertinoCodecTypeJpeg:
        codecType = AVVideoCodecTypeJPEG;
        break;
      case CupertinoCodecTypeAppleProRes4444:
        codecType = AVVideoCodecTypeAppleProRes4444;
        break;
      case CupertinoCodecTypeAppleProRes422:
        codecType = AVVideoCodecTypeAppleProRes422;
        break;
      case CupertinoCodecTypeAppleProRes422HQ:
        codecType = AVVideoCodecTypeAppleProRes422HQ;
        break;
      case CupertinoCodecTypeAppleProRes422LT:
        codecType = AVVideoCodecTypeAppleProRes422LT;
        break;
      case CupertinoCodecTypeAppleProRes422Proxy:
        codecType = AVVideoCodecTypeAppleProRes422Proxy;
        break;
      default:
        break;
    }
  }
  return codecType;
}

- (CGSize)getBestVideoSizeAccordingQuality:(VideoRecordingQuality)quality {
  CGSize size;
  switch (quality) {
    case VideoRecordingQualityUhd:
    case VideoRecordingQualityHighest:
      if (@available(iOS 9.0, *)) {
        if ([_captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset3840x2160]) {
          size = CGSizeMake(3840, 2160);
        } else {
          size = CGSizeMake(1920, 1080);
        }
      } else {
        return CGSizeMake(1920, 1080);
      }
      break;
    case VideoRecordingQualityFhd:
      size = CGSizeMake(1920, 1080);
      break;
    case VideoRecordingQualityHd:
      size = CGSizeMake(1280, 720);
      break;
    case VideoRecordingQualitySd:
    case VideoRecordingQualityLowest:
      size = CGSizeMake(960, 540);
      break;
  }
    
  // ensure video output size does not exceed capture session size
  if (size.width > _previewSize.width) {
    size = _previewSize;
  }
  
  return size;
}

// Convert CupertinoColorSpace to AVCaptureColorSpace
- (AVCaptureColorSpace)convertToAVCaptureColorSpace:(CupertinoColorSpace)colorSpace {
  switch (colorSpace) {
    case CupertinoColorSpaceP3_D65:
      return AVCaptureColorSpace_P3_D65;
    case CupertinoColorSpaceHlg_BT2020:
      return AVCaptureColorSpace_HLG_BT2020;
    case CupertinoColorSpaceAppleLog:
      if (@available(iOS 16.0, *)) {
        return AVCaptureColorSpace_AppleLog;
      } else {
        return AVCaptureColorSpace_sRGB;
      }
    case CupertinoColorSpaceSRGB:
    default:
      return AVCaptureColorSpace_sRGB;
  }
}

// Check if a device format supports a specific color space
- (BOOL)deviceFormat:(AVCaptureDeviceFormat *)format supportsColorSpace:(AVCaptureColorSpace)colorSpace {
  if (@available(iOS 10.0, *)) {
    NSArray<NSNumber *> *supportedColorSpaces = [format supportedColorSpaces];
    for (NSNumber *supportedSpace in supportedColorSpaces) {
      if ([supportedSpace intValue] == colorSpace) {
        return YES;
      }
    }
  }
  return NO;
}

// Configure color space for recording
// In VideoController.m
- (void)configureColorSpaceForRecording:(AVCaptureDevice *)device 
                             colorSpace:(CupertinoColorSpace)colorSpace
                                  codec:(AVVideoCodecType)codecType {
  if (colorSpace == nil) {
    printf(@"[CameraAwesome] No color space specified, using default");
    return;
  }
  
  AVCaptureColorSpace avColorSpace = [self convertToAVCaptureColorSpace:colorSpace];
  printf(@"[CameraAwesome] Attempting to set color space: %ld for codec: %@", (long)avColorSpace, codecType);
  
  // Check current color space before changing
  printf(@"[CameraAwesome] Current color space before change: %ld", (long)device.activeColorSpace);
  
  // Check if the device format supports the color space
  if (![self deviceFormat:device.activeFormat supportsColorSpace:avColorSpace]) {
    printf(@"[CameraAwesome] Device format does not support requested color space %ld", (long)avColorSpace);
    avColorSpace = [self findCompatibleColorSpace:device.activeFormat 
                                originalColorSpace:avColorSpace
                                            codec:codecType];
    printf(@"[CameraAwesome] Using compatible color space instead: %ld", (long)avColorSpace);
  } else {
    printf(@"[CameraAwesome] Device format supports requested color space");
    // Check codec compatibility with color space
    if (![self isColorSpaceCompatibleWithCodec:avColorSpace codec:codecType]) {
      printf(@"[CameraAwesome] Color space not compatible with codec");
      avColorSpace = [self findCompatibleColorSpaceForCodec:device.activeFormat codec:codecType];
      printf(@"[CameraAwesome] Using codec-compatible color space: %ld", (long)avColorSpace);
    }
  }
  
  // Set the color space
  NSError *error = nil;
  if ([device lockForConfiguration:&error]) {
    printf(@"[CameraAwesome] Device locked for configuration");
    device.activeColorSpace = avColorSpace;
    [device unlockForConfiguration];
    printf(@"[CameraAwesome] Color space set and device unlocked");
    // Verify the change was applied
    printf(@"[CameraAwesome] Color space after setting: %ld", (long)device.activeColorSpace);
  } else {
    printf(@"[CameraAwesome] Failed to lock device for configuration: %@", error);
  }
}

- (AVVideoCodecType)ensureCodecCompatibilityWithColorSpace:(AVVideoCodecType)codec colorSpace:(CupertinoColorSpace)colorSpace {
  if (colorSpace == CupertinoColorSpaceAppleLog) {
    // appleLog requires ProRes
    if (!([codec isEqualToString:AVVideoCodecTypeAppleProRes4444] ||
          [codec isEqualToString:AVVideoCodecTypeAppleProRes422] ||
          [codec isEqualToString:AVVideoCodecTypeAppleProRes422HQ] ||
          [codec isEqualToString:AVVideoCodecTypeAppleProRes422LT] ||
          [codec isEqualToString:AVVideoCodecTypeAppleProRes422Proxy])) {
      return AVVideoCodecTypeAppleProRes422HQ;
    }
  } else if (colorSpace == CupertinoColorSpaceHlg_BT2020) {
    // HLG works best with HEVC
    if (![codec isEqualToString:AVVideoCodecTypeHEVC]) {
      return AVVideoCodecTypeHEVC;
    }
  }
  
  return codec;
}

// Check if a color space is compatible with a codec
- (BOOL)isColorSpaceCompatibleWithCodec:(AVCaptureColorSpace)colorSpace codec:(AVVideoCodecType)codec {
  // appleLog is only compatible with ProRes codecs
  if (colorSpace == AVCaptureColorSpace_AppleLog) {
    return [codec isEqualToString:AVVideoCodecTypeAppleProRes4444] ||
           [codec isEqualToString:AVVideoCodecTypeAppleProRes422] ||
           [codec isEqualToString:AVVideoCodecTypeAppleProRes422HQ] ||
           [codec isEqualToString:AVVideoCodecTypeAppleProRes422LT] ||
           [codec isEqualToString:AVVideoCodecTypeAppleProRes422Proxy];
  }
  
  // HLG_BT2020 works best with HEVC but can work with others
  // We'll allow any codec with HLG
  
  return YES;  // Other combinations are compatible
}

// Find a compatible color space for device format while respecting codec
- (AVCaptureColorSpace)findCompatibleColorSpace:(AVCaptureDeviceFormat *)format 
                           originalColorSpace:(AVCaptureColorSpace)originalColorSpace
                                       codec:(AVVideoCodecType)codec {
  NSArray<NSNumber *> *supportedColorSpaces = [format supportedColorSpaces];
  BOOL isProResCodec = [codec isEqualToString:AVVideoCodecTypeAppleProRes4444] ||
                       [codec isEqualToString:AVVideoCodecTypeAppleProRes422] ||
                       [codec isEqualToString:AVVideoCodecTypeAppleProRes422HQ] ||
                       [codec isEqualToString:AVVideoCodecTypeAppleProRes422LT] ||
                       [codec isEqualToString:AVVideoCodecTypeAppleProRes422Proxy];
  
  // Original was appleLog
  if (originalColorSpace == AVCaptureColorSpace_AppleLog) {
    // If it's a ProRes codec, we need to check alternatives for appleLog
    if (isProResCodec) {
      // Check for HLG_BT2020 support
      for (NSNumber *space in supportedColorSpaces) {
        if ([space intValue] == AVCaptureColorSpace_HLG_BT2020) {
          return AVCaptureColorSpace_HLG_BT2020;
        }
      }
      
      // Check for P3_D65 support
      for (NSNumber *space in supportedColorSpaces) {
        if ([space intValue] == AVCaptureColorSpace_P3_D65) {
          return AVCaptureColorSpace_P3_D65;
        }
      }
    } else {
      // For non-ProRes codecs, appleLog isn't supported anyway
      // Check other color spaces
      for (NSNumber *space in supportedColorSpaces) {
        if ([space intValue] == AVCaptureColorSpace_HLG_BT2020) {
          return AVCaptureColorSpace_HLG_BT2020;
        }
      }
      
      for (NSNumber *space in supportedColorSpaces) {
        if ([space intValue] == AVCaptureColorSpace_P3_D65) {
          return AVCaptureColorSpace_P3_D65;
        }
      }
    }
  } 
  // Original was HLG_BT2020
  else if (originalColorSpace == AVCaptureColorSpace_HLG_BT2020) {
    // Check for P3_D65 support
    for (NSNumber *space in supportedColorSpaces) {
      if ([space intValue] == AVCaptureColorSpace_P3_D65) {
        return AVCaptureColorSpace_P3_D65;
      }
    }
  }
  
  // Default fallback to sRGB
  return AVCaptureColorSpace_sRGB;
}

// Find the best compatible color space for a codec
- (AVCaptureColorSpace)findCompatibleColorSpaceForCodec:(AVCaptureDeviceFormat *)format codec:(AVVideoCodecType)codec {
  NSArray<NSNumber *> *supportedColorSpaces = [format supportedColorSpaces];
  BOOL isProResCodec = [codec isEqualToString:AVVideoCodecTypeAppleProRes4444] ||
                      [codec isEqualToString:AVVideoCodecTypeAppleProRes422] ||
                      [codec isEqualToString:AVVideoCodecTypeAppleProRes422HQ] ||
                      [codec isEqualToString:AVVideoCodecTypeAppleProRes422LT] ||
                      [codec isEqualToString:AVVideoCodecTypeAppleProRes422Proxy];
  
  if (isProResCodec) {
    // ProRes can work with appleLog if supported
    if (@available(iOS 16.0, *)) {
      for (NSNumber *space in supportedColorSpaces) {
        if ([space intValue] == AVCaptureColorSpace_AppleLog) {
          return AVCaptureColorSpace_AppleLog;
        }
      }
    }
    
    // Check for HLG_BT2020
    for (NSNumber *space in supportedColorSpaces) {
      if ([space intValue] == AVCaptureColorSpace_HLG_BT2020) {
        return AVCaptureColorSpace_HLG_BT2020;
      }
    }
    
    // Check for P3_D65
    for (NSNumber *space in supportedColorSpaces) {
      if ([space intValue] == AVCaptureColorSpace_P3_D65) {
        return AVCaptureColorSpace_P3_D65;
      }
    }
  } else {
    // For non-ProRes codecs
    // Check for HLG_BT2020 - works especially well with HEVC
    for (NSNumber *space in supportedColorSpaces) {
      if ([space intValue] == AVCaptureColorSpace_HLG_BT2020) {
        return AVCaptureColorSpace_HLG_BT2020;
      }
    }
    
    // Check for P3_D65
    for (NSNumber *space in supportedColorSpaces) {
      if ([space intValue] == AVCaptureColorSpace_P3_D65) {
        return AVCaptureColorSpace_P3_D65;
      }
    }
  }
  
  // Default fallback
  return AVCaptureColorSpace_sRGB;
}

# pragma mark - Setter
- (void)setIsAudioEnabled:(bool)isAudioEnabled {
  _isAudioEnabled = isAudioEnabled;
}
- (void)setIsAudioSetup:(bool)isAudioSetup {
  _isAudioSetup = isAudioSetup;
}

- (void)setPreviewSize:(CGSize)previewSize {
  _previewSize = previewSize;
}

- (void)setVideoIsDisconnected:(bool)videoIsDisconnected {
  _videoIsDisconnected = videoIsDisconnected;
}

- (void)setAudioIsDisconnected:(bool)audioIsDisconnected {
  _audioIsDisconnected = audioIsDisconnected;
}

@end
