//
//  JPVideoCaptureConfig.m
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#import "JPVideoCaptureConfig.h"

@implementation JPVideoCaptureConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _preset = AVCaptureSessionPreset1920x1080;
        _position = AVCaptureDevicePositionFront;
        _orientation = AVCaptureVideoOrientationPortrait;
        _fps = 30;
        _mirrorType = JPVideoCaptureMirrorFront;
        _pixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    }
    
    return self;
}
@end
