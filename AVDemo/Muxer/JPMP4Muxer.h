//
//  JPMP4Muxer.h
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import "JPMuxerConfig.h"


NS_ASSUME_NONNULL_BEGIN

@interface JPMP4Muxer : NSObject

- (instancetype)initWithConfig:(JPMuxerConfig *)config;

@property (nonatomic, strong, readonly) JPMuxerConfig *config;
@property (nonatomic, copy) void (^errorCallBack)(NSError *error); // 封装错误回调。

- (void)startWriting; // 开始写入封装数据。
- (void)cancelWriting; // 取消写入封装数据。
- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer; // 添加封装数据。
- (void)stopWriting:(void (^)(BOOL success, NSError *error))completeHandler; // 停止写入封装数据。

@end

NS_ASSUME_NONNULL_END
