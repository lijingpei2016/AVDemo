//
//  JPMP4Muxer.m
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#import "JPMP4Muxer.h"
#import <AVFoundation/AVFoundation.h>

#define JPMP4MuxerAddOutputError 1000
#define JPMP4MuxerMaxQueueCount 10000


// 封装器的状态机。
typedef NS_ENUM(NSInteger, JPMP4MuxerStatus) {
    JPMP4MuxerStatusUnknown = 0,
    JPMP4MuxerStatusRunning = 1,
    JPMP4MuxerStatusFailed = 2,
    JPMP4MuxerStatusCompleted = 3,
    JPMP4MuxerStatusCancelled = 4,
};

@interface JPMP4Muxer () {
    CMSimpleQueueRef _audioQueue; // 音频数据队列。
    CMSimpleQueueRef _videoQueue; // 视频数据队列。
}

@property (nonatomic, strong, readwrite) JPMuxerConfig *config;
@property (nonatomic, strong) AVAssetWriter *muxWriter; // 封装器实例。
@property (nonatomic, strong) AVAssetWriterInput *writerVideoInput; // Muxer 的视频输入。
@property (nonatomic, strong) AVAssetWriterInput *writerAudioInput; // Muxer 的音频输入。
@property (nonatomic, strong) dispatch_queue_t muxerQueue;
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, assign) JPMP4MuxerStatus muxerStatus;

@end

@implementation JPMP4Muxer
#pragma mark - LifeCycle
- (instancetype)initWithConfig:(JPMuxerConfig *)config {
    self = [super init];
    if (self) {
        _config = config;
        _muxerQueue = dispatch_queue_create("com.KeyFrameKit.muxerQueue", DISPATCH_QUEUE_SERIAL); // 封装任务队列。
        _semaphore = dispatch_semaphore_create(1);
        CMSimpleQueueCreate(kCFAllocatorDefault, JPMP4MuxerMaxQueueCount, &_audioQueue);
        CMSimpleQueueCreate(kCFAllocatorDefault, JPMP4MuxerMaxQueueCount, &_videoQueue);
    }
    
    return self;
}

- (void)dealloc {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    [self _reset]; // 清理。
    dispatch_semaphore_signal(_semaphore);
}

#pragma mark - Public Method
- (void)startWriting {
    // 开始写入。
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.muxerQueue, ^{
        dispatch_semaphore_wait(weakSelf.semaphore, DISPATCH_TIME_FOREVER);
        [weakSelf _reset]; // 清理。
        weakSelf.muxerStatus = JPMP4MuxerStatusRunning; // 标记状态。
        dispatch_semaphore_signal(weakSelf.semaphore);
    });
}

- (void)cancelWriting {
    // 取消写入。
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.muxerQueue, ^{
        dispatch_semaphore_wait(weakSelf.semaphore, DISPATCH_TIME_FOREVER);
        if (weakSelf.muxWriter && weakSelf.muxWriter.status == AVAssetWriterStatusWriting) {
            [weakSelf.muxWriter cancelWriting];
        }
        weakSelf.muxerStatus = JPMP4MuxerStatusCancelled; // 标记状态。
        dispatch_semaphore_signal(weakSelf.semaphore);
    });
}

- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer || !CMSampleBufferGetDataBuffer(sampleBuffer) || self.muxerStatus != JPMP4MuxerStatusRunning) {
        return;
    }

    // 异步添加数据。

    __weak typeof(self) weakSelf = self;
    CFRetain(sampleBuffer);
    dispatch_async(self.muxerQueue, ^{
        dispatch_semaphore_wait(weakSelf.semaphore, DISPATCH_TIME_FOREVER);
        
        // 1、添加数据到队列。
        [weakSelf _enqueueSampleBuffer:sampleBuffer];
        
        // 2、第一次添加数据时，创建 Muxer 实例并触发写数据操作。
        if (!weakSelf.muxWriter) {
            // 检查数据是否正常。队列里面有数据则表示对应的数据携带的音视频格式信息是正常的，这个在初始化 Muxer 的输入源时需要用到。
            if (![weakSelf _checJPormatDescriptionLoadSuccess]) {
                CFRelease(sampleBuffer);
                dispatch_semaphore_signal(weakSelf.semaphore);
                return;
            }
            
            // 创建 Muxer 实例。
            NSError *error = nil;
            BOOL success = [weakSelf _setupMuxWriter:&error];
            if (!success) {
                weakSelf.muxerStatus = JPMP4MuxerStatusFailed;
                CFRelease(sampleBuffer);
                dispatch_semaphore_signal(weakSelf.semaphore);
                [weakSelf _callBackError:error];
                return;
            }
            
            // 开始封装写入。
            success = [weakSelf.muxWriter startWriting];
            if (success) {
                // 启动封装会话，传入数据起始时间。这个起始时间是音视频 pts 的最小值。
                [weakSelf.muxWriter startSessionAtSourceTime:[weakSelf _sessionSourceTime]];
            }
        }
        
        // 3、检查 Muxer 状态。
        if (!weakSelf.muxWriter || weakSelf.muxWriter.status != AVAssetWriterStatusWriting) {
            weakSelf.muxerStatus = JPMP4MuxerStatusFailed;
            CFRelease(sampleBuffer);
            dispatch_semaphore_signal(weakSelf.semaphore);
            [weakSelf _callBackError:weakSelf.muxWriter.error];
            return;
        }

        // 4、做音视频数据交织。
        [weakSelf _avInterLeavedSample];
        
        CFRelease(sampleBuffer);
        dispatch_semaphore_signal(weakSelf.semaphore);
    });
}

- (void)stopWriting:(void (^)(BOOL success, NSError *error))completeHandler {
    // 停止写入。
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.muxerQueue, ^{
        dispatch_semaphore_wait(weakSelf.semaphore, DISPATCH_TIME_FOREVER);
        [weakSelf _stopWriting:^(BOOL success, NSError *error) {
            weakSelf.muxerStatus = success ? JPMP4MuxerStatusCompleted : JPMP4MuxerStatusFailed;
            dispatch_semaphore_signal(weakSelf.semaphore);
            if (completeHandler) {
                completeHandler(success, error);
            }
        }];
    });
}

#pragma mark - Private Method
- (BOOL)_setupMuxWriter:(NSError **)error {
    if (!self.config.outputURL) {
        *error = [NSError errorWithDomain:NSStringFromClass([JPMP4Muxer class]) code:40003 userInfo:nil];
        return NO;
    }
    
    // 1、清理写入路径的文件。
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.config.outputURL.path]) {
        [[NSFileManager defaultManager] removeItemAtPath:self.config.outputURL.path error:nil];
    }
    
    
    // 2、创建封装器实例。
    if (_muxWriter) {
        return YES;
    }
    // 使用 AVAssetWriter 作为封装器，类型使用 AVFileTypeMPEG4。M4A 格式是遵循 MPEG4 规范的一种音频格式。
    _muxWriter = [[AVAssetWriter alloc] initWithURL:self.config.outputURL fileType:AVFileTypeMPEG4 error:error];
    if (*error) {
        return NO;
    }
    _muxWriter.movieTimeScale = 1000000000;
    _muxWriter.shouldOptimizeForNetworkUse = YES; // 这个选项会将 MP4 的 moov box 前置。
    
    // 3、当封装内容包含视频时，创建 Muxer 的视频输入。
    if ((self.config.muxerType & JPMediaVideo) && !_writerVideoInput) {
        // 从队列中的视频数据里获取视频格式信息，用于初始化视频输入源。
        CMVideoFormatDescriptionRef videoDecscription = CMSampleBufferGetFormatDescription((CMSampleBufferRef)CMSimpleQueueGetHead(_videoQueue));
        _writerVideoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:videoDecscription];
        _writerVideoInput.expectsMediaDataInRealTime = YES; // 输入是否为实时数据源，比如相机采集。
        _writerVideoInput.transform = self.config.preferredTransform; // 画面是否做变换。
        if ([self.muxWriter canAddInput:self.writerVideoInput]) {
            [self.muxWriter addInput:self.writerVideoInput];
        } else {
            *error = self.muxWriter.error ? self.muxWriter.error : [NSError errorWithDomain:NSStringFromClass([JPMP4Muxer class]) code:JPMP4MuxerAddOutputError userInfo:nil];
            return NO;
        }
    }
    
    // 4、当封装内容包含音频时，创建 Muxer 的音频输入。
    if ((self.config.muxerType & JPMediaAudio) && !_writerAudioInput) {
        // 从队列中的音频数据里获取音频格式信息，用于初始化音频输入源。
        CMAudioFormatDescriptionRef audioDecscription = CMSampleBufferGetFormatDescription((CMSampleBufferRef)CMSimpleQueueGetHead(_audioQueue));
        _writerAudioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:nil sourceFormatHint:audioDecscription];
        _writerAudioInput.expectsMediaDataInRealTime = YES; // 输入是否为实时数据源，比如麦克风采集。
        if ([self.muxWriter canAddInput:self.writerAudioInput]) {
            [self.muxWriter addInput:self.writerAudioInput];
        } else {
            *error = self.muxWriter.error ? self.muxWriter.error : [NSError errorWithDomain:NSStringFromClass([JPMP4Muxer class]) code:JPMP4MuxerAddOutputError userInfo:nil];
            return NO;
        }
    }

    return YES;
}

- (void)_enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CFRetain(sampleBuffer);
    // 音频、视频的格式信息正确才能入队。因为后面创建 Muxer 实例的输入源时也需要从队列中的音视频数据中获取相关格式信息。
    if (CMFormatDescriptionGetMediaType(CMSampleBufferGetFormatDescription(sampleBuffer)) == kCMMediaType_Audio) {
        CMSimpleQueueEnqueue(_audioQueue, sampleBuffer); // 音频数据入队列。
    } else if (CMFormatDescriptionGetMediaType(CMSampleBufferGetFormatDescription(sampleBuffer)) == kCMMediaType_Video) {
        CMSimpleQueueEnqueue(_videoQueue, sampleBuffer); // 视频数据入队列。
    }
}

- (void)_flushMuxer {
    // 将队列数据消费掉。
    [self _appendAudioSample];
    [self _appendVideoSample];
}

- (void)_appendAudioSample {
    // 音频写入封装。
    while (self.writerAudioInput && self.writerAudioInput.readyForMoreMediaData && CMSimpleQueueGetCount(_audioQueue) > 0) {
        CMSampleBufferRef audioSample = (CMSampleBufferRef)CMSimpleQueueDequeue(_audioQueue);
        [self.writerAudioInput appendSampleBuffer:audioSample];
        CFRelease(audioSample);
    }
}

- (void)_appendVideoSample {
    // 视频写入封装。
    while (self.writerVideoInput && self.writerVideoInput.readyForMoreMediaData && CMSimpleQueueGetCount(_videoQueue) > 0) {
        CMSampleBufferRef videoSample = (CMSampleBufferRef)CMSimpleQueueDequeue(_videoQueue);
        [self.writerVideoInput appendSampleBuffer:videoSample];
        CFRelease(videoSample);
    }
}

- (void)_avInterLeavedSample {
    // 当同时封装音频和视频时，需要做好交织，这样可以提升音视频播放时的体验。
    if ((self.config.muxerType & JPMediaAudio) && (self.config.muxerType & JPMediaVideo)) { // 同时封装音频和视频。
        while (CMSimpleQueueGetCount(_audioQueue) > 0 && CMSimpleQueueGetCount(_videoQueue) > 0) {
            if (self.writerAudioInput.readyForMoreMediaData && self.writerVideoInput.readyForMoreMediaData) {
                // 音频、视频队列数据各出队 1 个。
                CMSampleBufferRef audioHeader = (CMSampleBufferRef)CMSimpleQueueGetHead(_audioQueue);
                CMTime audioDtsTime = CMSampleBufferGetPresentationTimeStamp(audioHeader);
                CMSampleBufferRef videoHeader = (CMSampleBufferRef)CMSimpleQueueGetHead(_videoQueue);
                CMTime videoDtsTime = CMSampleBufferGetDecodeTimeStamp(videoHeader).value > 0 ? CMSampleBufferGetDecodeTimeStamp(videoHeader) : CMSampleBufferGetPresentationTimeStamp(videoHeader);
                // 比较 dts 较小者写入封装。
                if (CMTimeGetSeconds(audioDtsTime) >= CMTimeGetSeconds(videoDtsTime)) {
                    CMSampleBufferRef videoSample = (CMSampleBufferRef)CMSimpleQueueDequeue(_videoQueue);
                    [self.writerVideoInput appendSampleBuffer:videoSample];
                    CFRelease(videoSample);
                } else {
                    CMSampleBufferRef audioSample = (CMSampleBufferRef)CMSimpleQueueDequeue(_audioQueue);
                    [self.writerAudioInput appendSampleBuffer:audioSample];
                    CFRelease(audioSample);
                }
            } else {
                break;
            }
        }
    } else if (self.config.muxerType & JPMediaAudio) { // 只封装音频。
        [self _appendAudioSample];
    } else if (self.config.muxerType & JPMediaVideo) { // 只封装视频。
        [self _appendVideoSample];
    }
}

- (BOOL)_checJPormatDescriptionLoadSuccess {
    // 检查数据是否正常。
    if (!_muxWriter) {
        if ((self.config.muxerType & JPMediaAudio) && (self.config.muxerType & JPMediaVideo)) {
            return CMSimpleQueueGetCount(_videoQueue) > 0 && CMSimpleQueueGetCount(_audioQueue) > 0;
        } else if (self.config.muxerType & JPMediaAudio) {
            return CMSimpleQueueGetCount(_audioQueue) > 0;
        } else if (self.config.muxerType & JPMediaVideo) {
            return CMSimpleQueueGetCount(_videoQueue) > 0;
        }
    }
    
    return NO;
}

- (CMTime)_sessionSourceTime {
    // 数据起始时间：音视频 pts 的最小值。
    CMSampleBufferRef audioFirstBuffer = (CMSampleBufferRef)CMSimpleQueueGetHead(_audioQueue);
    CMSampleBufferRef videoFirstBuffer = (CMSampleBufferRef)CMSimpleQueueGetHead(_videoQueue);
    if (audioFirstBuffer && videoFirstBuffer) {
        Float64 audioPtsTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(audioFirstBuffer));
        Float64 videoPtsTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(videoFirstBuffer));
        return audioPtsTime >= videoPtsTime ? CMSampleBufferGetPresentationTimeStamp(videoFirstBuffer) : CMSampleBufferGetPresentationTimeStamp(audioFirstBuffer);
    } else if (audioFirstBuffer) {
        return CMSampleBufferGetPresentationTimeStamp(audioFirstBuffer);
    } else if (videoFirstBuffer) {
        return CMSampleBufferGetPresentationTimeStamp(videoFirstBuffer);
    }
    
    return kCMTimeInvalid;
}

- (void)_stopWriting:(void (^)(BOOL success, NSError *error))completeHandler {
    // 1、状态不对，回调错误。
    if (!self.muxWriter || self.muxWriter.status == AVAssetWriterStatusCompleted || self.muxWriter.status == AVAssetWriterStatusCancelled || self.muxWriter.status == AVAssetWriterStatusUnknown) {
        if (completeHandler) {
            completeHandler(NO, self.muxWriter.error ? self.muxWriter.error : [NSError errorWithDomain:NSStringFromClass(self.class) code:self.muxWriter.status userInfo:nil]);
        }
        return;
    }
    
    // 2、消费掉队列中剩余的数据。
    // 先做剩余数据的音视频交织。
    [self _avInterLeavedSample];
    // 消费剩余数据。
    [self _flushMuxer];
    
    // 3、标记视频输入和音频输入为结束状态。
    [self _markVideoAsFinished];
    [self _markAudioAsFinished];
    
    // 4、结束写入。
    __weak typeof(self) weakSelf = self;
    [self.muxWriter finishWritingWithCompletionHandler:^{
        BOOL complete = weakSelf.muxWriter.status == AVAssetWriterStatusCompleted;
        if (completeHandler) {
            completeHandler(complete, complete ? nil : weakSelf.muxWriter.error);
        }
    }];
}

- (void)_markVideoAsFinished {
    // 标记视频输入源为结束状态。
    if (self.muxWriter.status == AVAssetWriterStatusWriting && self.writerVideoInput) {
        [self.writerVideoInput markAsFinished];
    }
}

- (void)_markAudioAsFinished {
    // 标记音频输入源为结束状态。
    if (self.muxWriter.status == AVAssetWriterStatusWriting && self.writerAudioInput) {
        [self.writerAudioInput markAsFinished];
    }
}

- (void)_reset {
    // 取消写入操作。
    if (_muxWriter && _muxWriter.status == AVAssetWriterStatusWriting) {
        [_muxWriter cancelWriting];
    }
    
    // 清理实例。
    _muxWriter = nil;
    _writerVideoInput = nil;
    _writerVideoInput = nil;
    
    // 清理音频和视频数据队列。
    while (CMSimpleQueueGetCount(_audioQueue) > 0) {
        CMSampleBufferRef sampleBuffer = (CMSampleBufferRef) CMSimpleQueueDequeue(_audioQueue);
        CFRelease(sampleBuffer);
    }
    while (CMSimpleQueueGetCount(_videoQueue) > 0) {
        CMSampleBufferRef sampleBuffer = (CMSampleBufferRef) CMSimpleQueueDequeue(_videoQueue);
        CFRelease(sampleBuffer);
    }
}

- (void)_callBackError:(NSError *)error {
    if (error && self.errorCallBack) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.errorCallBack(error);
        });
    }
}

@end

