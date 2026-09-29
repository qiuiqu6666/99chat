// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Flutter/Flutter.h>
#import <ImageIO/ImageIO.h>
#import <math.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "FLTPHPickerSaveImageToPathOperation.h"

#import <os/log.h>

static dispatch_semaphore_t FLTPHPickerGIFDecodeSemaphore(void) {
  static dispatch_once_t onceToken;
  static dispatch_semaphore_t semaphore;
  dispatch_once(&onceToken, ^{ semaphore = dispatch_semaphore_create(1); });
  return semaphore;
}

API_AVAILABLE(ios(14))
@interface FLTPHPickerSaveImageToPathOperation ()

@property(strong, nonatomic) PHPickerResult *result;
@property(strong, nonatomic) NSNumber *maxHeight;
@property(strong, nonatomic) NSNumber *maxWidth;
@property(strong, nonatomic) NSNumber *desiredImageQuality;
@property(assign, nonatomic) BOOL requestFullMetadata;

@end

@implementation FLTPHPickerSaveImageToPathOperation {
  BOOL executing;
  BOOL finished;
  FLTGetSavedPath getSavedPath;
}

- (instancetype)initWithResult:(PHPickerResult *)result
                     maxHeight:(NSNumber *)maxHeight
                      maxWidth:(NSNumber *)maxWidth
           desiredImageQuality:(NSNumber *)desiredImageQuality
                  fullMetadata:(BOOL)fullMetadata
                savedPathBlock:(FLTGetSavedPath)savedPathBlock API_AVAILABLE(ios(14)) {
  if (self = [super init]) {
    if (result) {
      self.result = result;
      self.maxHeight = maxHeight;
      self.maxWidth = maxWidth;
      self.desiredImageQuality = desiredImageQuality;
      self.requestFullMetadata = fullMetadata;
      getSavedPath = savedPathBlock;
      executing = NO;
      finished = NO;
    } else {
      return nil;
    }
    return self;
  } else {
    return nil;
  }
}

- (BOOL)isConcurrent {
  return YES;
}

- (BOOL)isExecuting {
  return executing;
}

- (BOOL)isFinished {
  return finished;
}

- (void)setFinished:(BOOL)isFinished {
  [self willChangeValueForKey:@"isFinished"];
  self->finished = isFinished;
  [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)isExecuting {
  [self willChangeValueForKey:@"isExecuting"];
  self->executing = isExecuting;
  [self didChangeValueForKey:@"isExecuting"];
}

- (void)completeOperationWithPath:(NSString *)savedPath error:(FlutterError *)error {
  getSavedPath(savedPath, error);
  [self setExecuting:NO];
  [self setFinished:YES];
}

- (void)start {
  if ([self isCancelled]) {
    [self setFinished:YES];
    return;
  }
  if (@available(iOS 14, *)) {
    [self setExecuting:YES];

    // This supports uniform types that conform to UTTypeImage.
    // This includes UTTypeHEIC, UTTypeHEIF, UTTypeLivePhoto, UTTypeICO, UTTypeICNS, UTTypePNG
    // UTTypeGIF, UTTypeJPEG, UTTypeWebP, UTTypeTIFF, UTTypeBMP, UTTypeSVG, UTTypeRAWImage
    if ([self.result.itemProvider hasItemConformingToTypeIdentifier:UTTypeImage.identifier]) {
      // Copy within this callback: the provider URL expires when it returns.
      [self.result.itemProvider
          loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier
                                completionHandler:^(NSURL *_Nullable url, NSError *_Nullable error) {
        @autoreleasepool {
          if (url != nil) {
            [self processImageURL:url];
          } else {
            [self completeOperationWithPath:nil error:[FlutterError
                errorWithCode:@"invalid_image" message:error.localizedDescription
                details:error.domain]];
          }
        }
      }];
    } else if ([self.result.itemProvider
                   // This supports uniform types that conform to UTTypeMovie.
                   // This includes kUTTypeVideo, kUTTypeMPEG4, public.3gpp, kUTTypeMPEG,
                   // public.3gpp2, public.avi, kUTTypeQuickTimeMovie.
                   hasItemConformingToTypeIdentifier:UTTypeMovie.identifier]) {
      [self processVideo];
    } else {
      FlutterError *flutterError = [FlutterError errorWithCode:@"invalid_source"
                                                       message:@"Invalid media source."
                                                       details:nil];
      [self completeOperationWithPath:nil error:flutterError];
    }
  } else {
    [self setFinished:YES];
  }
}

// Default selection preserves encoded bytes. Explicit sizing/quality uses
// ImageIO metadata and thumbnail creation before raster decode.
- (void)processImageURL:(NSURL *)url API_AVAILABLE(ios(14)) {
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url,
      (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO});
  if (source == NULL) {
    [self completeOperationWithPath:nil error:[FlutterError errorWithCode:@"invalid_image"
        message:@"Cannot read image metadata." details:nil]];
    return;
  }
  NSString *type = [(__bridge NSString *)CGImageSourceGetType(source) copy];
  BOOL gif = [type isEqualToString:UTTypeGIF.identifier];
  // Upstream exports HEIC/other still formats as JPEG. Preserve that upload
  // contract until downstream encoded-HEIC support is separately verified.
  BOOL canCopyEncoded = gif || [type isEqualToString:UTTypeJPEG.identifier] ||
      [type isEqualToString:UTTypePNG.identifier];
  BOOL transform = !canCopyEncoded || self.maxWidth != nil || self.maxHeight != nil ||
      (self.desiredImageQuality != nil && self.desiredImageQuality.doubleValue < 1.0);
  if (!transform || (gif && self.maxWidth == nil && self.maxHeight == nil)) {
    NSString *extension = [UTType typeWithIdentifier:type].preferredFilenameExtension;
    if (extension.length == 0) extension = url.pathExtension;
    NSString *name = [NSString stringWithFormat:@"image_picker_%@.%@", NSUUID.UUID.UUIDString,
                      extension.length > 0 ? extension : @"image"];
    NSURL *destination = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSError *error = nil;
    BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:url toURL:destination error:&error];
    CFRelease(source);
    [self completeOperationWithPath:copied ? destination.path : nil
        error:copied ? nil : [FlutterError errorWithCode:@"invalid_image"
            message:error.localizedDescription details:error.domain]];
    return;
  }
  if (gif) {
    // Preserve animation while allowing still-image exports to run in
    // parallel. GIF frame decoding remains single-flight because it is heavier.
    CFRelease(source);
    NSData *gifData =
        [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    if (gifData == nil) {
      [self completeOperationWithPath:nil
                                error:[FlutterError errorWithCode:@"invalid_image"
                                                          message:@"Cannot read animated image."
                                                          details:nil]];
      return;
    }
    dispatch_semaphore_wait(FLTPHPickerGIFDecodeSemaphore(), DISPATCH_TIME_FOREVER);
    @try {
      [self processImage:gifData];
    } @finally {
      dispatch_semaphore_signal(FLTPHPickerGIFDecodeSemaphore());
    }
    return;
  }
  NSMutableDictionary *properties = [CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) mutableCopy];
  double width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
  double height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
  NSInteger orientation = [properties[(__bridge NSString *)kCGImagePropertyOrientation] integerValue];
  if (orientation >= 5 && orientation <= 8) { double swap = width; width = height; height = swap; }
  if (width <= 0 || height <= 0) {
    CFRelease(source);
    [self completeOperationWithPath:nil error:[FlutterError errorWithCode:@"invalid_image"
        message:@"Invalid image dimensions." details:nil]];
    return;
  }
  double scale = 1.0;
  if (self.maxWidth != nil) scale = MIN(scale, self.maxWidth.doubleValue / width);
  if (self.maxHeight != nil) scale = MIN(scale, self.maxHeight.doubleValue / height);
  NSUInteger maxPixel = MAX(1, (NSUInteger)floor(MAX(width, height) * scale));
  CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
      (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
      (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
      (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixel),
      (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES});
  CFRelease(source);
  if (image == NULL) {
    [self completeOperationWithPath:nil error:[FlutterError errorWithCode:@"invalid_image"
        message:@"Cannot decode image." details:nil]];
    return;
  }
  BOOL png = [type isEqualToString:UTTypePNG.identifier];
  NSString *name = [NSString stringWithFormat:@"image_picker_%@.%@", NSUUID.UUID.UUIDString, png ? @"png" : @"jpg"];
  NSURL *destination = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
  CGImageDestinationRef encoder = CGImageDestinationCreateWithURL((__bridge CFURLRef)destination,
      (__bridge CFStringRef)(png ? UTTypePNG.identifier : UTTypeJPEG.identifier), 1, NULL);
  // The thumbnail already applies EXIF orientation. Never apply it twice.
  properties[(__bridge NSString *)kCGImagePropertyOrientation] = @1;
  properties[(__bridge NSString *)kCGImagePropertyPixelWidth] = @(CGImageGetWidth(image));
  properties[(__bridge NSString *)kCGImagePropertyPixelHeight] = @(CGImageGetHeight(image));
  NSMutableDictionary *tiff = [properties[(__bridge NSString *)kCGImagePropertyTIFFDictionary] mutableCopy];
  if (tiff != nil) { tiff[(__bridge NSString *)kCGImagePropertyTIFFOrientation] = @1;
    properties[(__bridge NSString *)kCGImagePropertyTIFFDictionary] = tiff; }
  NSMutableDictionary *exif = [properties[(__bridge NSString *)kCGImagePropertyExifDictionary] mutableCopy];
  if (exif != nil) {
    exif[(__bridge NSString *)kCGImagePropertyExifPixelXDimension] = @(CGImageGetWidth(image));
    exif[(__bridge NSString *)kCGImagePropertyExifPixelYDimension] = @(CGImageGetHeight(image));
    properties[(__bridge NSString *)kCGImagePropertyExifDictionary] = exif;
  }
  properties[(__bridge NSString *)kCGImageDestinationLossyCompressionQuality] = self.desiredImageQuality ?: @1;
  BOOL saved = NO;
  if (encoder != NULL) {
    CGImageDestinationAddImage(encoder, image, (__bridge CFDictionaryRef)properties);
    saved = CGImageDestinationFinalize(encoder);
    CFRelease(encoder);
  }
  CGImageRelease(image);
  if (!saved) [[NSFileManager defaultManager] removeItemAtURL:destination error:nil];
  [self completeOperationWithPath:saved ? destination.path : nil
      error:saved ? nil : [FlutterError errorWithCode:@"invalid_image"
          message:@"Cannot encode image." details:nil]];
}

/// Processes the image.
- (void)processImage:(NSData *)pickerImageData API_AVAILABLE(ios(14)) {
  // GIF frames are independently downsampled with ImageIO before raster decode.
  NSString *savedPath =
      [FLTImagePickerPhotoAssetUtil saveImageWithOriginalImageData:pickerImageData
                                                             image:nil
                                                          maxWidth:self.maxWidth
                                                         maxHeight:self.maxHeight
                                                      imageQuality:self.desiredImageQuality
                                        downsampleOriginalImageData:NO];
  [self completeOperationWithPath:savedPath
                             error:savedPath == nil
                                       ? [FlutterError errorWithCode:@"invalid_image"
                                                             message:@"Could not export the animated image."
                                                             details:nil]
                                       : nil];
}

/// Processes the video.
- (void)processVideo API_AVAILABLE(ios(14)) {
  NSString *typeIdentifier = self.result.itemProvider.registeredTypeIdentifiers.firstObject;
  [self.result.itemProvider
      loadFileRepresentationForTypeIdentifier:typeIdentifier
                            completionHandler:^(NSURL *_Nullable videoURL,
                                                NSError *_Nullable error) {
                              if (error != nil) {
                                FlutterError *flutterError =
                                    [FlutterError errorWithCode:@"invalid_image"
                                                        message:error.localizedDescription
                                                        details:error.domain];
                                [self completeOperationWithPath:nil error:flutterError];
                                return;
                              }

                              NSURL *destination =
                                  [FLTImagePickerPhotoAssetUtil saveVideoFromURL:videoURL];
                              if (destination == nil) {
                                [self
                                    completeOperationWithPath:nil
                                                        error:[FlutterError
                                                                  errorWithCode:
                                                                      @"flutter_image_picker_copy_"
                                                                      @"video_error"
                                                                        message:@"Could not cache "
                                                                                @"the video file."
                                                                        details:nil]];
                                return;
                              }

                              [self completeOperationWithPath:[destination path] error:nil];
                            }];
}

@end
