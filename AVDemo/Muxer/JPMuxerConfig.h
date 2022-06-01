//
//  JPMuxerConfig.h
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "JPMediaBase.h"

NS_ASSUME_NONNULL_BEGIN

@interface JPMuxerConfig : NSObject

@property (nonatomic, strong) NSURL *outputURL; // 封装文件输出地址。
@property (nonatomic, assign) JPMediaType muxerType; // 封装文件类型。
@property (nonatomic, assign) CGAffineTransform preferredTransform; // 图像的变换信息。比如：视频图像旋转。

@end

NS_ASSUME_NONNULL_END
