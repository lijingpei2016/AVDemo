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
    UIBarButtonItem *cameraBarButton = [[UIBarButtonItem alloc] initWithTitle:@"??????" style:UIBarButtonItemStylePlain target:self action:@selector(changeCamera)];
    UIBarButtonItem *shotBarButton = [[UIBarButtonItem alloc] initWithTitle:@"??????" style:UIBarButtonItemStylePlain target:self action:@selector(shot)];
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
            // ????????????????????????????????????????????????
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (granted) {
                    [weakSelf.videoCapture startRunning];
                } else {
                    // ???????????????
                }
            }];
            break;
        }
        case AVAuthorizationStatusAuthorized: {
            // ?????????????????????????????????
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
        // ?????????????????????????????????????????????????????????????????????
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            // ?????????????????????????????????????????????
            if (status == PHAuthorizationStatusAuthorized) {
                [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            }
        }];
    } else {
        NSLog(@"??????????????????");
    }
}

- (UIImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {    
    // ??? CMSampleBuffer ?????? CVImageBuffer????????? CVPixelBuffer??????
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    // ?????? CVPixelBuffer ???????????????
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // ?????? CVPixelBuffer ?????????????????????
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // ?????? CVPixelBuffer ????????????
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
 
    // ????????????????????? RGB ?????????????????????????????????????????? CMSampleBuffer ????????????????????????????????????
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
 
    // ?????? CVPixelBuffer ????????????????????? bitmap ???????????????
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    // ??? bitmap ??????????????????????????? CGImage ?????????
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // ?????? CVPixelBuffer???
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
 
    // ?????????????????????????????????
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
 
    // ??? CGImage ????????? UIImage???
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
 
    // ?????? CGImage???
    CGImageRelease(quartzImage);
 
    return image;
}

@end
