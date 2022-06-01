//
//  JPMediaBase.h
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#ifndef JPMediaBase_h
#define JPMediaBase_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, JPMediaType) {
    JPMediaNone = 0,
    JPMediaAudio = 1 << 0, // 仅音频。
    JPMediaVideo = 1 << 1, // 仅视频。
    JPMediaAV = JPMediaAudio | JPMediaVideo,  // 音视频都有。
};

#endif /* JPMediaBase_h */
