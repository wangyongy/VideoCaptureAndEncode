//
//  H264Encoder.h
//  VideoCaptureAndEncode
//
//  Created by 王勇 on 2018/11/21.
//  Copyright © 2018年 王勇. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
NS_ASSUME_NONNULL_BEGIN

@interface H264Encoder : NSObject

- (void)initVideoToolBox;

- (void)EndVideoToolBox;

- (void)encodeSampleBuffer:(CMSampleBufferRef )sampleBuffer;

- (NSFileHandle *)audioFileHandle;

@end

NS_ASSUME_NONNULL_END
