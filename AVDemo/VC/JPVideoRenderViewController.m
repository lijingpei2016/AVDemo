//
//  JPVideoRenderViewController.m
//  AVDemo
//
//  Created by LJP on 2022/6/1.
//

#import "JPVideoRenderViewController.h"
#import "JPVideoCapture.h"
#import "JPMetalView.h"

@interface JPVideoRenderViewController ()
@property (nonatomic, strong) JPVideoCaptureConfig *videoCaptureConfig;
@property (nonatomic, strong) JPVideoCapture *videoCapture;
@property (nonatomic, strong) JPMetalView *metalView;
@end

@implementation JPVideoRenderViewController
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
        _videoCapture.sampleBufferOutputCallBack = ^(CMSampleBufferRef sampleBuffer) {
             // 视频采集数据回调。将采集回来的数据给渲染模块渲染。
            [weakSelf.metalView renderPixelBuffer:CMSampleBufferGetImageBuffer(sampleBuffer)];
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

    [self requestAccessForVideo];
    [self setupUI];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.metalView.frame = self.view.bounds;
}

#pragma mark - Action
- (void)changeCamera {
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
    self.title = @"Video Render";
    self.view.backgroundColor = [UIColor whiteColor];
    
    // Navigation item.
    UIBarButtonItem *cameraBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Camera" style:UIBarButtonItemStylePlain target:self action:@selector(changeCamera)];
    self.navigationItem.rightBarButtonItems = @[cameraBarButton];
    
    // 渲染 view。
    _metalView = [[JPMetalView alloc] initWithFrame:self.view.bounds];
    _metalView.fillMode = JPMetalViewContentModeFill;
    [self.view addSubview:self.metalView];
}

@end


