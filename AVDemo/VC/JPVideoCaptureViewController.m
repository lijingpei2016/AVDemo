//
//  JPVideoCaptureViewController.m
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#import "JPVideoCaptureViewController.h"
#import "JPVideoCapture.h"
#import <Photos/Photos.h>

@interface JPVideoCaptureViewController ()
@property (nonatomic, strong) JPVideoCaptureConfig *videoCaptureConfig;
@property (nonatomic, strong) JPVideoCapture *videoCapture;
@property (nonatomic, assign) int shotCount;
@end

@implementation JPVideoCaptureViewController

#pragma mark - Property
- (JPVideoCaptureConfig *)videoCaptureConfig {
    if (!_videoCaptureConfig) {
        _videoCaptureConfig = [[JPVideoCaptureConfig alloc] init];

        _videoCaptureConfig.pixelFormatType = kCVPixelFormatType_32BGRA;
    }
    
    return _videoCaptureConfig;
}

- (JPVideoCapture *)videoCapture {
    if (!_videoCapture) {
        _videoCapture = [[JPVideoCapture alloc] initWithConfig:self.videoCaptureConfig];
        __weak typeof(self) weakSelf = self;
        _videoCapture.sessionInitSuccessCallBack = ^() {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.view.layer addSublayer:weakSelf.videoCapture.previewLayer];
                weakSelf.videoCapture.previewLayer.frame = weakSelf.view.bounds;
            });
        };
        _videoCapture.sampleBufferOutputCallBack = ^(CMSampleBufferRef sample) {
            if (weakSelf.shotCount > 0) {
                weakSelf.shotCount--;
                [weakSelf saveSampleBuffer:sample];
            }
        };
        _videoCapture.sessionErrorCallBack = ^(NSError* error) {
            NSLog(@"JPVideoCapture Error:%zi %@", error.code, error.localizedDescription);
        };
    }
    
    return _videoCapture;
}

#pragma mark - Lifecycle
- (void)viewDidLoad {
    [super viewDidLoad];
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;
    self.title = @"Video Capture";
    self.view.backgroundColor = [UIColor whiteColor];

    self.shotCount = 0;
    [self requestAccessForVideo];
    
    // Navigation item.
    UIBarButtonItem *cameraBarButton = [[UIBarButtonItem alloc] initWithTitle:@"切换" style:UIBarButtonItemStylePlain target:self action:@selector(changeCamera)];
    UIBarButtonItem *shotBarButton = [[UIBarButtonItem alloc] initWithTitle:@"截图" style:UIBarButtonItemStylePlain target:self action:@selector(shot)];
    self.navigationItem.rightBarButtonItems = @[cameraBarButton, shotBarButton];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.videoCapture.previewLayer.frame = self.view.bounds;
}

- (void)dealloc {
    
}

#pragma mark - Action
- (void)changeCamera {
    [self.videoCapture changeDevicePosition:self.videoCapture.config.position == AVCaptureDevicePositionBack ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack];
}

- (void)shot {
    self.shotCount = 1;
}

#pragma mark - Utility
- (void)requestAccessForVideo {
    __weak typeof(self) weakSelf = self;
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    switch (status) {
        case AVAuthorizationStatusNotDetermined: {
            // 许可对话没有出现，发起授权许可。
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (granted) {
                    [weakSelf.videoCapture startRunning];
                } else {
                    // 用户拒绝。
                }
            }];
            break;
        }
        case AVAuthorizationStatusAuthorized: {
            // 已经开启授权，可继续。
            [weakSelf.videoCapture startRunning];
            break;
        }
        default:
            break;
    }
}

- (void)saveSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    __block UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
    
    PHAuthorizationStatus authorizationStatus = [PHPhotoLibrary authorizationStatus];
    if (authorizationStatus == PHAuthorizationStatusAuthorized) {
        PHPhotoLibrary *library = [PHPhotoLibrary sharedPhotoLibrary];
        [library performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            
        }];
    } else if (authorizationStatus == PHAuthorizationStatusNotDetermined) {
        // 如果没请求过相册权限，弹出指示框，让用户选择。
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            // 如果用户选择授权，则保存图片。
            if (status == PHAuthorizationStatusAuthorized) {
                [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            }
        }];
    } else {
        NSLog(@"无相册权限。");
    }
}

- (UIImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {    
    // 从 CMSampleBuffer 获取 CVImageBuffer（也是 CVPixelBuffer）。
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    // 锁定 CVPixelBuffer 的基地址。
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // 获取 CVPixelBuffer 每行的字节数。
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // 获取 CVPixelBuffer 的宽高。
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
 
    // 创建设备相关的 RGB 颜色空间。这里的颜色空间要与 CMSampleBuffer 图像数据的颜色空间一致。
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
 
    // 基于 CVPixelBuffer 的数据创建绘制 bitmap 的上下文。
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    // 从 bitmap 绘制的上下文中获取 CGImage 图像。
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // 解锁 CVPixelBuffer。
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
 
    // 是否上下文和颜色空间。
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
 
    // 从 CGImage 转换到 UIImage。
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
 
    // 释放 CGImage。
    CGImageRelease(quartzImage);
 
    return image;
}

@end
