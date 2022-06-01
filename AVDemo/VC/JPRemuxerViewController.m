//
//  JPRemuxerViewController.m
//  AVDemo
//
//  Created by LJP on 2022/5/31.
//

#import "JPRemuxerViewController.h"
#import "JPMP4Demuxer.h"
#import "JPMP4Muxer.h"

@interface JPRemuxerViewController ()

@property (nonatomic, strong) JPDemuxerConfig *demuxerConfig;
@property (nonatomic, strong) JPMP4Demuxer *demuxer;
@property (nonatomic, strong) JPMuxerConfig *muxerConfig;
@property (nonatomic, strong) JPMP4Muxer *muxer;

@end

@implementation JPRemuxerViewController

#pragma mark - Property
- (JPDemuxerConfig *)demuxerConfig {
    if (!_demuxerConfig) {
        _demuxerConfig = [[JPDemuxerConfig alloc] init];
        _demuxerConfig.demuxerType = JPMediaAV;
        NSString *videoPath = [[NSBundle mainBundle] pathForResource:@"input" ofType:@"mp4"];
        _demuxerConfig.asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:videoPath]];
    }
    
    return _demuxerConfig;
}

- (JPMP4Demuxer *)demuxer {
    if (!_demuxer) {
        _demuxer = [[JPMP4Demuxer alloc] initWithConfig:self.demuxerConfig];
        _demuxer.errorCallBack = ^(NSError *error) {
            NSLog(@"JPMP4Demuxer error:%zi %@", error.code, error.localizedDescription);
        };
    }
    
    return _demuxer;
}

- (JPMuxerConfig *)muxerConfig {
    if (!_muxerConfig) {
        _muxerConfig = [[JPMuxerConfig alloc] init];
        NSString *videoPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"output.mp4"];
        NSLog(@"MP4 file path: %@", videoPath);
        [[NSFileManager defaultManager] removeItemAtPath:videoPath error:nil];
        _muxerConfig.outputURL = [NSURL fileURLWithPath:videoPath];
        _muxerConfig.muxerType = JPMediaAV;
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

    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"AV Remuxer";
    UIBarButtonItem *startBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Start" style:UIBarButtonItemStylePlain target:self action:@selector(start)];
    self.navigationItem.rightBarButtonItems = @[startBarButton];
}

#pragma mark - Action
- (void)start {
    __weak typeof(self) weakSelf = self;
    NSLog(@"JPMP4Demuxer start");
    [self.demuxer startReading:^(BOOL success, NSError * _Nonnull error) {
        if (success) {
            // Demuxer 启动成功后，就可以从它里面获取解封装后的数据了。
            [weakSelf fetchAndRemuxData];
        }else{
            NSLog(@"JPDemuxer error: %zi %@", error.code, error.localizedDescription);
        }
    }];
}

#pragma mark - Utility
- (void)fetchAndRemuxData {
    // 异步地从 Demuxer 获取解封装后的 H.264/H.265 编码数据，再重新封装。
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self.muxer startWriting];
        while (self.demuxer.hasVideoSampleBuffer || self.demuxer.hasAudioSampleBuffer) {
            CMSampleBufferRef videoBuffer = [self.demuxer copyNextVideoSampleBuffer];
            if (videoBuffer) {
                [self.muxer appendSampleBuffer:videoBuffer];
                CFRelease(videoBuffer);
            }
            
            CMSampleBufferRef audioBuffer = [self.demuxer copyNextAudioSampleBuffer];
            if (audioBuffer) {
                [self.muxer appendSampleBuffer:audioBuffer];
                CFRelease(audioBuffer);
            }
        }
        if (self.demuxer.demuxerStatus == JPMP4DemuxerStatusCompleted) {
            NSLog(@"JPMP4Demuxer complete");
            [self.muxer stopWriting:^(BOOL success, NSError * _Nonnull error) {
                NSLog(@"JPMP4Muxer complete:%d", success);
            }];
        }
    });
}

@end
