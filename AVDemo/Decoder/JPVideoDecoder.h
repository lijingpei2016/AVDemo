//
//  JPVideoDecoder.h
//  AVDemo
//
//  Created by LJP on 2022/5/31.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

@interface JPVideoDecoder : NSObject

@property (nonatomic, copy) void (^pixelBufferOutputCallBack)(CVPixelBufferRef pixelBuffer, CMTime ptsTime); // 视频解码数据回调。
@property (nonatomic, copy) void (^errorCallBack)(NSError *error); // 视频解码错误回调。
- (void)decodeSampleBuffer:(CMSampleBufferRef)sampleBuffer; // 解码。
- (void)flush; // 清空解码缓冲区。
- (void)flushWithCompleteHandler:(void (^)(void))completeHandler; // 清空解码缓冲区并回调完成。

@end

NS_ASSUME_NONNULL_END
