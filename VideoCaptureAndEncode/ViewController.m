//
//  ViewController.m
//  VideoCaptureAndEncode
//
//  Created by 王勇 on 2018/11/20.
//  Copyright © 2018年 王勇. All rights reserved.
//

#import "ViewController.h"
#import "VideoRecordViewController.h"
#import "VideoCaptureEncodeViewController.h"
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"H264+AAC采集编码" style:UIBarButtonItemStyleDone target:self action:@selector(captureButtonAction:)];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"本地录制" style:UIBarButtonItemStyleDone target:self action:@selector(videoRecordButtonAction:)];
    
    self.navigationController.interactivePopGestureRecognizer.delegate = (id <UIGestureRecognizerDelegate>)self;
    
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    // Do any additional setup after loading the view, typically from a nib.
}
- (void)captureButtonAction:(id)sender
{
    [self.navigationController pushViewController:[VideoCaptureEncodeViewController new] animated:YES];
}
- (void)videoRecordButtonAction:(id)sender
{
    [self.navigationController pushViewController:[VideoRecordViewController new] animated:YES];
}
@end
