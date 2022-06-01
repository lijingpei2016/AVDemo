//
//  JPVideoDecoder.m
//  AVDemo
//
//  Created by LJP on 2022/5/31.
//

#import "JPVideoDecoder.h"
#import <VideoToolBox/VideoToolBox.h>

#define JPDecoderRetrySessionMaxCount 5
#define JPDecoderDecodeFrameFailedMaxCount 20

@interface JPVideoDecoderInputPacket : NSObject
@property (nonatomic, assign) CMSampleBufferRef sampleBuffer;
@end

@implementation JPVideoDecoderInputPacket
@end

@interface JPVideoDecoder ()
@property (nonatomic, assign) VTDecompressionSessionRef decoderSession; // 视频解码器实例。
@property (nonatomic, strong) dispatch_queue_t decoderQueue;
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, assign) NSInteger retrySessionCount; // 解码器重试次数。
@property (nonatomic, assign) NSInteger decodeFrameFailedCount; // 解码失败次数。
@property (nonatomic, strong) NSMutableArray *gopList;
@property (nonatomic, assign) NSInteger inputCount;
@property (nonatomic, assign) NSInteger outputCount;
@end

@implementation JPVideoDecoder
#pragma mark - LifeCycle
- (instancetype)init {
    self = [super init];
    if (self) {
        _decoderQueue = dispatch_queue_create("com.KeyFrameKit.videoDecoder", DISPATCH_QUEUE_SERIAL);
        _semaphore = dispatch_semaphore_create(1);
        _gopList = [NSMutableArray new];
    }
    
    return self;
}

- (void)dealloc {
    // 清理解码器。
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    [self _releaseDecompressionSession];
    [self _clearCompressQueue];
    dispatch_semaphore_signal(_semaphore);
}

#pragma mark - Public Method
- (void)decodeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer || self.retrySessionCount >= JPDecoderRetrySessionMaxCount || self.decodeFrameFailedCount >= JPDecoderDecodeFrameFailedMaxCount) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    CFRetain(sampleBuffer);
    dispatch_async(_decoderQueue, ^{
        dispatch_semaphore_wait(weakSelf.semaphore, DISPATCH_TIME_FOREVER);
        
        // 1、如果还未创建解码器实例，或者解码器需要重建，则创建解码器。
        OSStatus setupStatus = noErr;
        if (!weakSelf.decoderSession) {
            // 支持重试，记录重试次数。
            setupStatus = [weakSelf _setupDecompressionSession:CMSampleBufferGetFormatDescription(sampleBuffer)];
            weakSelf.retrySessionCount = setupStatus == noErr ? 0 : (weakSelf.retrySessionCount + 1);
            if (setupStatus != noErr) {
                [weakSelf _releaseDecompressionSession];
            }
        }
        
        if (!weakSelf.decoderSession) {
            // 重试超过 JPDecoderRetrySessionMaxCount 次仍然失败则认为创建失败，报错。
            CFRelease(sampleBuffer);
            dispatch_semaphore_signal(weakSelf.semaphore);
            if (weakSelf.retrySessionCount >= JPDecoderRetrySessionMaxCount && weakSelf.errorCallBack) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.errorCallBack([NSError errorWithDomain:NSStringFromClass([JPVideoDecoder class]) code:setupStatus userInfo:nil]);
                });
            }
            return;
        }
        
        // 2、对 sampleBuffer 进行解码。
        VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
        VTDecodeInfoFlags flagOut = 0;
        // 解码当前 sampleBuffer。
        OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(weakSelf.decoderSession, sampleBuffer, flags, NULL, &flagOut);
        if (decodeStatus == kVTInvalidSessionErr) {
            // 解码当前帧失败，进行重建解码器重试。
            [weakSelf _releaseDecompressionSession];
            setupStatus = [weakSelf _setupDecompressionSession:CMSampleBufferGetFormatDescription(sampleBuffer)];
            // 记录重建解码器次数。
            weakSelf.retrySessionCount = setupStatus == noErr ? 0 : (weakSelf.retrySessionCount + 1);
            if (setupStatus == noErr) {
                // 重建解码器成功后，要从当前 GOP 开始的 I 帧解码。所以这里先解码缓存的当前 GOP 的前序帧。
                flags = kVTDecodeFrame_DoNotOutputFrame;
                for (JPVideoDecoderInputPacket *packet in weakSelf.gopList) {
                    VTDecompressionSessionDecodeFrame(weakSelf.decoderSession, packet.sampleBuffer, flags, NULL, &flagOut);
                }
                // 解码当前帧。
                flags = kVTDecodeFrame_EnableAsynchronousDecompression;
                decodeStatus = VTDecompressionSessionDecodeFrame(weakSelf.decoderSession, sampleBuffer, flags, NULL, &flagOut);
            } else {
                // 重建解码器失败。
                [weakSelf _releaseDecompressionSession];
            }
        } else if (decodeStatus != noErr) {
            // 解码当前帧失败。
            NSLog(@"JPVideoDecoder decode error:%d", decodeStatus);
        }
        
        // 统计解码入帧数。
        weakSelf.inputCount++;
        
        // 遇到新的 I 帧后，清空上一个 GOP 序列缓存，开始进行下一个 GOP 的缓存。
        if ([weakSelf _isKeyFrame:sampleBuffer]) {
            [weakSelf _clearCompressQueue];
        }
        JPVideoDecoderInputPacket *packet = [JPVideoDecoderInputPacket new];
        packet.sampleBuffer = sampleBuffer;
        [weakSelf.gopList addObject:packet];
        
        // 记录解码失败次数。
        weakSelf.decodeFrameFailedCount = decodeStatus == noErr ? 0 : (weakSelf.decodeFrameFailedCount + 1);
        
        dispatch_semaphore_signal(weakSelf.semaphore);
        
        // 解码失败次数超过 JPDecoderDecodeFrameFailedMaxCount 次，报错。
        if (weakSelf.decodeFrameFailedCount >= JPDecoderDecodeFrameFailedMaxCount && weakSelf.errorCallBack) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.errorCallBack([NSError errorWithDomain:NSStringFromClass([JPVideoDecoder class]) code:decodeStatus userInfo:nil]);
            });
        }
    });
}

- (void)flush {
    // 清空解码缓冲区。
    __weak typeof(self) weakSelf = self;
    dispatch_async(_decoderQueue, ^{
        dispatch_semaphore_wait(weakSelf.semaphore, DISPATCH_TIME_FOREVER);
        [weakSelf _flush];
        dispatch_semaphore_signal(weakSelf.semaphore);
    });
}

- (void)flushWithCompleteHandler:(void (^)(void))completeHandler {
    // 清空解码缓冲区并回调完成。
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.decoderQueue, ^{
        dispatch_semaphore_wait(weakSelf.semaphore, DISPATCH_TIME_FOREVER);
        [weakSelf _flush];
        dispatch_semaphore_signal(weakSelf.semaphore);
        if (completeHandler) {
            completeHandler();
        }
    });
}

#pragma mark - Private Method
- (OSStatus)_setupDecompressionSession:(CMFormatDescriptionRef)videoDescription {
    if (_decoderSession) {
        return noErr;
    }
        
    // 1、设置颜色格式。
    NSDictionary *attrs = @{(NSString *) kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
    
    //  2、设置解码回调。
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionOutputCallback;
    callBackRecord.decompressionOutputRefCon = (__bridge void *) self;
    
    // 3、创建解码器实例。
    OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                   videoDescription,
                                                   NULL,
                                                   (__bridge void *) attrs,
                                                   &callBackRecord,
                                                   &_decoderSession);
    
    return status;
}

- (void)_releaseDecompressionSession {
    // 清理解码器。
    if (_decoderSession) {
        VTDecompressionSessionWaitForAsynchronousFrames(_decoderSession);
        VTDecompressionSessionInvalidate(_decoderSession);
        _decoderSession = NULL;
    }
}

- (void)_flush {
    // 清理解码器缓冲。
    if (_decoderSession) {
        VTDecompressionSessionFinishDelayedFrames(_decoderSession);
        VTDecompressionSessionWaitForAsynchronousFrames(_decoderSession);
    }
}

- (void)_clearCompressQueue {
    // 清空当前 GOP 缓冲区。
    for (JPVideoDecoderInputPacket *packet in self.gopList) {
        if (packet.sampleBuffer) {
            CFRelease(packet.sampleBuffer);
        }
    }
    [self.gopList removeAllObjects];
}

- (BOOL)_isKeyFrame:(CMSampleBufferRef)sampleBuffer {
    CFArrayRef array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    if (!array) {
        return NO;
    }
    
    CFDictionaryRef dic = (CFDictionaryRef)CFArrayGetValueAtIndex(array, 0);
    if (!dic) {
        return NO;
    }
    
    // 是否关键帧。
    BOOL keyframe = !CFDictionaryContainsKey(dic, kCMSampleAttachmentKey_NotSync);
    
    return keyframe;
}

#pragma mark - DecoderOutputCallback
static void decompressionOutputCallback( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ) {
    if (status != noErr) {
        return;
    }
    
    if (infoFlags & kVTDecodeInfo_FrameDropped) {
        NSLog(@"JPVideoDecoder drop frame");
        return;
    }
    
    // 向外层回调解码数据。
    JPVideoDecoder *videoDecoder = (__bridge JPVideoDecoder *) decompressionOutputRefCon;
    if (videoDecoder && imageBuffer && videoDecoder.pixelBufferOutputCallBack) {
        videoDecoder.pixelBufferOutputCallBack(imageBuffer, presentationTimeStamp);
        videoDecoder.outputCount++; // 统计解码出帧数。
    }
}

@end

