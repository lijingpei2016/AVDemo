//
//  JPDemuxerConfig.h
//  AVDemo
//
//  Created by LJP on 2022/5/31.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "JPMediaBase.h"

NS_ASSUME_NONNULL_BEGIN

@interface JPDemuxerConfig : NSObject

@property (nonatomic, strong) AVAsset *asset; // 待解封装的资源。
@property (nonatomic, assign) JPMediaType demuxerType; // 解封装类型。

@end

NS_ASSUME_NONNULL_END
