//
//  JPVideoMuxerViewController.m
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#import "JPVideoMuxerViewController.h"
#import "JPVideoCapture.h"
#import "JPVideoEncoder.h"
#import "JPMP4Muxer.h"

@interface JPVideoMuxerViewController ()
@property (nonatomic, strong) JPVideoCaptureConfig *videoCaptureConfig;
@property (nonatomic, strong) JPVideoCapture *videoCapture;
@property (nonatomic, strong) JPVideoEncoderConfig *videoEncoderConfig;
@property (nonatomic, strong) JPVideoEncoder *videoEncoder;
@property (nonatomic, strong) JPMuxerConfig *muxerConfig;
@property (nonatomic, strong) JPMP4Muxer *muxer;
@property (nonatomic, assign) BOOL isWriting;
@end

@implementation JPVideoMuxerViewController
#pragma mark - Property
- (JPVideoCaptureConfig *)videoCaptureConfig {
    if (!_videoCaptureConfig) {
        _videoCaptureConfig = [[JPVideoCaptureConfig alloc] init];
    }
    return _videoCaptureConfig;
}

- (JPVideoCapture *)videoCapture {
    if (!_videoCapture) {
        _videoCapture = [[JPVideoCapture alloc] initWithConfig:self.videoCaptureConfig];
        __weak typeof(self) weakSelf = self;
        _videoCapture.sessionInitSuccessCallBack = ^() {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 预览渲染。
                [weakSelf.view.layer insertSublayer:weakSelf.videoCapture.previewLayer atIndex:0];
                weakSelf.videoCapture.previewLayer.backgroundColor = [UIColor blackColor].CGColor;
                weakSelf.videoCapture.previewLayer.frame = weakSelf.view.bounds;
            });
        };
        _videoCapture.sampleBufferOutputCallBack = ^(CMSampleBufferRef sampleBuffer) {
            if (sampleBuffer && weakSelf.isWriting) {
                // 编码。
                [weakSelf.videoEncoder encodePixelBuffer:CMSampleBufferGetImageBuffer(sampleBuffer) ptsTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
            }
        };
        _videoCapture.sessionErrorCallBack = ^(NSError *error) {
            NSLog(@"JPVideoCapture Error:%zi %@", error.code, error.localizedDescription);
        };
    }
    
    return _videoCapture;
}

- (JPVideoEncoderConfig *)videoEncoderConfig {
    if (!_videoEncoderConfig) {
        _videoEncoderConfig = [[JPVideoEncoderConfig alloc] init];
    }
    
    return _videoEncoderConfig;
}

- (JPVideoEncoder *)videoEncoder {
    if (!_videoEncoder) {
        _videoEncoder = [[JPVideoEncoder alloc] initWithConfig:self.videoEncoderConfig];
        __weak typeof(self) weakSelf = self;
        _videoEncoder.sampleBufferOutputCallBack = ^(CMSampleBufferRef sampleBuffer) {
            // 视频编码数据回调。
            if (weakSelf.isWriting) {
                // 当标记封装写入中时，将编码的 H.264/H.265 数据送给封装器。
                [weakSelf.muxer appendSampleBuffer:sampleBuffer];
            }
        };
    }
    
    return _videoEncoder;
}

- (JPMuxerConfig *)muxerConfig {
    if (!_muxerConfig) {
        _muxerConfig = [[JPMuxerConfig alloc] init];
        NSString *videoPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"test.mp4"];
        NSLog(@"MP4 file path: %@", videoPath);
        [[NSFileManager defaultManager] removeItemAtPath:videoPath error:nil];
        _muxerConfig.outputURL = [NSURL fileURLWithPath:videoPath];
        _muxerConfig.muxerType = JPMediaVideo;
    }
    
    return _muxerConfig;
}

- (JPMP4Muxer *)muxer {
    if (!_muxer) {
        _muxer = [[JPMP4Muxer alloc] initWithConfig:self.muxerConfig];
    }
    
    return _muxer;
}

#pragma mark - Lifecycle
- (void)viewDidLoad {
    [super viewDidLoad];

    // 启动后即开始请求视频采集权限并开始采集。
    [self requestAccessForVideo];
    [self setupUI];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.videoCapture.previewLayer.frame = self.view.bounds;
}

- (void)dealloc {
    
}

#pragma mark - Action
- (void)start {
    if (!self.isWriting) {
        // 启动封装，
        [self.muxer startWriting];
        // 标记开始封装写入。
        self.isWriting = YES;
    }
}

- (void)stop {
    if (self.isWriting) {
        __weak typeof(self) weakSelf = self;
        [self.videoEncoder flushWithCompleteHandler:^{
            weakSelf.isWriting = NO;
            [weakSelf.muxer stopWriting:^(BOOL success, NSError * _Nonnull error) {
                NSLog(@"muxer stop %@", success ? @"success" : @"failed");
            }];
        }];
    }
}

- (void)changeCamera {
    [self.videoCapture changeDevicePosition:self.videoCapture.config.position == AVCaptureDevicePositionBack ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack];
}

- (void)singleTap:(UIGestureRecognizer *)sender {
    
}

-(void)handleDoubleTap:(UIGestureRecognizer *)sender {
    [self.videoCapture changeDevicePosition:self.videoCapture.config.position == AVCaptureDevicePositionBack ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack];
}

#pragma mark - Private Method
- (void)requestAccessForVideo {
    __weak typeof(self) weakSelf = self;
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    switch (status) {
        case AVAuthorizationStatusNotDetermined:{
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
        case AVAuthorizationStatusAuthorized:{
            // 已经开启授权，可继续。
            [weakSelf.videoCapture startRunning];
            break;
        }
        default:
            break;
    }
}

- (void)setupUI {
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;
    self.title = @"Video Muxer";
    self.view.backgroundColor = [UIColor whiteColor];
    
    // 添加手势。
    UITapGestureRecognizer *singleTapGesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(singleTap:)];
    singleTapGesture.numberOfTapsRequired = 1;
    singleTapGesture.numberOfTouchesRequired = 1;
    [self.view addGestureRecognizer:singleTapGesture];
    
    UITapGestureRecognizer *doubleTapGesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTapGesture.numberOfTapsRequired = 2;
    doubleTapGesture.numberOfTouchesRequired = 1;
    [self.view addGestureRecognizer:doubleTapGesture];
    
    [singleTapGesture requireGestureRecognizerToFail:doubleTapGesture];

    
    // Navigation item.
    UIBarButtonItem *startBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Start" style:UIBarButtonItemStylePlain target:self action:@selector(start)];
    UIBarButtonItem *stopBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Stop" style:UIBarButtonItemStylePlain target:self action:@selector(stop)];
    UIBarButtonItem *cameraBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Camera" style:UIBarButtonItemStylePlain target:self action:@selector(changeCamera)];
    self.navigationItem.rightBarButtonItems = @[stopBarButton, startBarButton, cameraBarButton];
}

@end

