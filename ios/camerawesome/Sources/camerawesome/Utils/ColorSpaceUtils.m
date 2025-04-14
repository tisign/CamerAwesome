//
//  ColorSpaceUtils.m
//  camerawesome
//  Created by Till Wietlisbach on 14.05.2025.
//

#import "ColorSpaceUtils.h"

@implementation ColorSpaceUtils

+ (AVCaptureColorSpace)captureColorSpaceFromCupertinoColorSpace:(CupertinoColorSpace)colorSpace {
  switch (colorSpace) {
    case CupertinoColorSpaceHlgBt2020:
      return AVCaptureColorSpaceHLG_BT2020;
    case CupertinoColorSpaceAppleLog:
      return AVCaptureColorSpaceAppleLog;
    case CupertinoColorSpaceSRGB:
    default:
      return AVCaptureColorSpaceSRGB;
  }
}

+ (BOOL)isColorSpaceAvailable:(AVCaptureColorSpace)colorSpace onDevice:(AVCaptureDevice *)device {
  for (AVCaptureDeviceFormat *format in device.formats) {
    for (NSNumber *supportedColorSpace in format.supportedColorSpaces) {
      if ([supportedColorSpace intValue] == colorSpace) {
        return YES;
      }
    }
  }
  return NO;
}

+ (AVCaptureDeviceFormat * _Nullable)findFormatWithResolution:(CGSize)resolution
                                                   frameRate:(float)fps
                                                  colorSpace:(AVCaptureColorSpace)colorSpace
                                               captureDevice:(AVCaptureDevice *)device {
  // Get all available formats for the device
  NSArray<AVCaptureDeviceFormat *> *formats = [device formats];
  
  // Filter formats that support the requested parameters
  NSMutableArray<AVCaptureDeviceFormat *> *compatibleFormats = [NSMutableArray array];
  
  for (AVCaptureDeviceFormat *format in formats) {
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    
    // Check if this format supports our resolution
    if (dimensions.width == resolution.width && dimensions.height == resolution.height) {
      // Check if this format supports our color space
      BOOL supportsColorSpace = NO;
      for (NSNumber *supportedColorSpace in format.supportedColorSpaces) {
        if ([supportedColorSpace intValue] == colorSpace) {
          supportsColorSpace = YES;
          break;
        }
      }
      
      if (supportsColorSpace) {
        // Check if this format supports our frame rate
        AVFrameRateRange *maxFrameRateRange = nil;
        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
          if (!maxFrameRateRange || range.maxFrameRate > maxFrameRateRange.maxFrameRate) {
            maxFrameRateRange = range;
          }
        }
        
        if (maxFrameRateRange && maxFrameRateRange.maxFrameRate >= fps) {
          [compatibleFormats addObject:format];
        }
      }
    }
  }
  
  // Sort formats by quality (assuming higher dimension = better quality)
  [compatibleFormats sortUsingComparator:^NSComparisonResult(AVCaptureDeviceFormat *format1, AVCaptureDeviceFormat *format2) {
    CMVideoDimensions dim1 = CMVideoFormatDescriptionGetDimensions(format1.formatDescription);
    CMVideoDimensions dim2 = CMVideoFormatDescriptionGetDimensions(format2.formatDescription);
    
    // Sort by total pixels (width * height)
    NSInteger pixels1 = dim1.width * dim1.height;
    NSInteger pixels2 = dim2.width * dim2.height;
    
    if (pixels1 < pixels2) {
      return NSOrderedDescending;
    } else if (pixels1 > pixels2) {
      return NSOrderedAscending;
    } else {
      return NSOrderedSame;
    }
  }];
  
  // Return the best compatible format or nil if none found
  return compatibleFormats.firstObject;
}

+ (AVCaptureColorSpace)configureDevice:(AVCaptureDevice *)device
                        withColorSpace:(CupertinoColorSpace)preferredColorSpace
                            resolution:(CGSize)resolution
                                   fps:(float)fps
                        captureSession:(AVCaptureSession *)session {
  // First try with the preferred color space
  AVCaptureColorSpace targetColorSpace = [self captureColorSpaceFromCupertinoColorSpace:preferredColorSpace];
  
  // Check if this color space is available on the device
  if (![self isColorSpaceAvailable:targetColorSpace onDevice:device]) {
    NSLog(@"Color space %ld not available on device %@, falling back", (long)targetColorSpace, device.localizedName);
    if (preferredColorSpace == CupertinoColorSpaceAppleLog) {
      targetColorSpace = AVCaptureColorSpaceHLG_BT2020;
      if (![self isColorSpaceAvailable:targetColorSpace onDevice:device]) {
        targetColorSpace = AVCaptureColorSpaceSRGB;
      }
    } else if (preferredColorSpace == CupertinoColorSpaceHlgBt2020) {
      targetColorSpace = AVCaptureColorSpaceSRGB;
    }
  }
  
  // Find a compatible format
  AVCaptureDeviceFormat *selectedFormat = [self findFormatWithResolution:resolution
                                                               frameRate:fps
                                                              colorSpace:targetColorSpace
                                                           captureDevice:device];
  
  // If no format found, try fallback color spaces
  if (!selectedFormat && targetColorSpace == AVCaptureColorSpaceAppleLog) {
    NSLog(@"No format found for AppleLog, trying HDR");
    targetColorSpace = AVCaptureColorSpaceHLG_BT2020;
    selectedFormat = [self findFormatWithResolution:resolution
                                          frameRate:fps
                                         colorSpace:targetColorSpace
                                      captureDevice:device];
  }
  
  if (!selectedFormat && targetColorSpace != AVCaptureColorSpaceSRGB) {
    NSLog(@"No format found for HDR, falling back to sRGB");
    targetColorSpace = AVCaptureColorSpaceSRGB;
    selectedFormat = [self findFormatWithResolution:resolution
                                          frameRate:fps
                                         colorSpace:targetColorSpace
                                      captureDevice:device];
  }
  
  // If we found a compatible format, apply it
  if (selectedFormat) {
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
      // Disable automatic color space configuration
      if (session) {
        [session setAutomaticallyConfiguresCaptureDeviceForWideColor:NO];
      }
      
      // Set the active format and color space
      device.activeFormat = selectedFormat;
      device.activeColorSpace = targetColorSpace;
      
      // Set the frame rate if specified
      if (fps > 0) {
        CMTime frameDuration = CMTimeMake(1, (int32_t)fps);
        [device setActiveVideoMinFrameDuration:frameDuration];
        [device setActiveVideoMaxFrameDuration:frameDuration];
      }
      
      [device unlockForConfiguration];
      
      NSLog(@"Device %@ configured with format: %dx%d, color space: %ld", 
            device.localizedName,
            CMVideoFormatDescriptionGetDimensions(selectedFormat.formatDescription).width,
            CMVideoFormatDescriptionGetDimensions(selectedFormat.formatDescription).height,
            (long)targetColorSpace);
    } else {
      NSLog(@"Failed to lock device for color space configuration: %@", error);
    }
  } else {
    NSLog(@"Could not find compatible format for resolution %fx%f, fps %f, colorSpace %ld",
          resolution.width, resolution.height, fps, (long)targetColorSpace);
  }
  
  return targetColorSpace;
}

+ (void)logAvailableFormatsForDevice:(AVCaptureDevice *)device {
  NSLog(@"========= DEVICE FORMAT INFORMATION =========");
  NSLog(@"Device: %@", device.localizedName);
  NSLog(@"Currently active format dimensions: %dx%d", 
        CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription).width,
        CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription).height);
  NSLog(@"Current color space: %ld", (long)device.activeColorSpace);
  
  NSLog(@"Total formats available: %lu", (unsigned long)device.formats.count);
  
  int i = 0;
  for (AVCaptureDeviceFormat *format in device.formats) {
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    
    // Get FPS range
    NSString *fpsRange = @"unknown";
    if (format.videoSupportedFrameRateRanges.count > 0) {
      AVFrameRateRange *range = format.videoSupportedFrameRateRanges[0];
      fpsRange = [NSString stringWithFormat:@"%.1f-%.1f", range.minFrameRate, range.maxFrameRate];
    }
    
    // Get supported color spaces
    NSMutableArray *colorSpaces = [NSMutableArray array];
    for (NSNumber *colorSpace in format.supportedColorSpaces) {
      switch ([colorSpace intValue]) {
        case AVCaptureColorSpaceSRGB:
          [colorSpaces addObject:@"sRGB"];
          break;
        case AVCaptureColorSpaceP3_D65:
          [colorSpaces addObject:@"P3_D65"];
          break;
        case AVCaptureColorSpaceHLG_BT2020:
          [colorSpaces addObject:@"HLG_BT2020"];
          break;
        case AVCaptureColorSpaceAppleLog:
          [colorSpaces addObject:@"AppleLog"];
          break;
      }
    }
    
    NSString *colorSpacesStr = [colorSpaces componentsJoinedByString:@" "];
    NSString *pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? @"420v" : 
                           (CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ? @"420f" : 
                            (CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr8VideoRange_8A ? @"x420" : 
                             (CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_422YpCbCr8_yuvs ? @"x422" : @"other")));
                           
    NSString *activeStr = (format == device.activeFormat) ? @"  ^^^ ACTIVE FORMAT ^^^" : @"";
    
    NSLog(@"Format[%d]: %dx%d, Pixel Format: %@, 8-bit, FPS: %@, Color Spaces: %@%@", 
          i, dimensions.width, dimensions.height, pixelFormat, fpsRange, colorSpacesStr, activeStr);
    i++;
  }
  
  NSLog(@"===========================================");
}

@end