//
//
//  
//  LearnVideoToolBox
//
//  Created by loyinglin on 16/9/1.
//  Copyright © 2016年 loyinglin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AACEncoder : NSObject



- (void) encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;


@end
