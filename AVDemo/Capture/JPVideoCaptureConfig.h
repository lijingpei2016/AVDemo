//
//  JPVideoCaptureConfig.h
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>


NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JPVideoCaptureMirrorType) {
    JPVideoCaptureMirrorNone = 0,
    JPVideoCaptureMirrorFront = 1 << 0,
    JPVideoCaptureMirrorBack = 1 << 1,
    JPVideoCaptureMirrorAll = (JPVideoCaptureMirrorFront | JPVideoCaptureMirrorBack),
};

@interface JPVideoCaptureConfig : NSObject

@property (nonatomic, copy) AVCaptureSessionPreset preset; // 视频采集参数，比如分辨率等，与画质相关。
@property (nonatomic, assign) AVCaptureDevicePosition position; // 前置/后置摄像头。
@property (nonatomic, assign) AVCaptureVideoOrientation orientation; // 视频画面方向。
@property (nonatomic, assign) NSInteger fps; // 视频帧率。
@property (nonatomic, assign) OSType pixelFormatType; // 颜色空间格式。
@property (nonatomic, assign) JPVideoCaptureMirrorType mirrorType; // 镜像类型。

@end

NS_ASSUME_NONNULL_END
