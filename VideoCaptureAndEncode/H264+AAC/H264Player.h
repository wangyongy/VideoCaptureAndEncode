//
//  H264Player.h
//  VideoCaptureAndEncode
//
//  Created by 王勇 on 2018/11/22.
//  Copyright © 2018年 王勇. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface H264Player : NSObject

-(void)startDecodeWithView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
