//
//  JPMuxerConfig.m
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#import "JPMuxerConfig.h"

@implementation JPMuxerConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _muxerType = JPMediaAV;
        _preferredTransform = CGAffineTransformIdentity;
    }
    return self;
}

@end
