//
//  ColorSpaceUtils.h
//  camerawesome
//  Created by Till Wietlisbach on 14/04/2025.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "Pigeon.h"

NS_ASSUME_NONNULL_BEGIN

@interface ColorSpaceUtils : NSObject

/**
 * Converts a CupertinoColorSpace enum to an AVCaptureColorSpace enum
 */
+ (AVCaptureColorSpace)captureColorSpaceFromCupertinoColorSpace:(CupertinoColorSpace)colorSpace;

/**
 * Finds the best format that supports the requested color space, resolution, and frame rate
 * Returns nil if no compatible format is found
 */
+ (AVCaptureDeviceFormat * _Nullable)findFormatWithResolution:(CGSize)resolution
                                                    frameRate:(float)fps
                                                   colorSpace:(AVCaptureColorSpace)colorSpace
                                                captureDevice:(AVCaptureDevice *)device;

/**
 * Configures the device for the requested color space, with appropriate fallbacks
 * Returns the selected color space (which might be different from the requested one if fallback occurred)
 */
+ (AVCaptureColorSpace)configureDevice:(AVCaptureDevice *)device
                          withColorSpace:(CupertinoColorSpace)preferredColorSpace
                              resolution:(CGSize)resolution
                                     fps:(float)fps
                          captureSession:(AVCaptureSession *)session;

/**
 * Checks if a color space is supported by any format on the device
 */
+ (BOOL)isColorSpaceAvailable:(AVCaptureColorSpace)colorSpace onDevice:(AVCaptureDevice *)device;

/**
 * Logs detailed information about available device formats and color spaces
 * Useful for debugging color space issues
 */
+ (void)logAvailableFormatsForDevice:(AVCaptureDevice *)device;

@end

NS_ASSUME_NONNULL_END