//
//  H264Player.m
//  VideoCaptureAndEncode
//
//  Created by 王勇 on 2018/11/22.
//  Copyright © 2018年 王勇. All rights reserved.
//

#import "H264Player.h"
#import "LYOpenGLView.h"
#import <VideoToolbox/VideoToolbox.h>
#define WS(weakSelf)            __weak __typeof(&*self)weakSelf = self; // 弱引用

#define ST(strongSelf)          __strong __typeof(&*self)strongSelf = weakSelf; //使用这个要先声明weakSelf

@interface H264Player ()

@property (nonatomic , strong) LYOpenGLView *openGLView;

@property (nonatomic , strong) CADisplayLink *dispalyLink;

@end

const uint8_t lyStartCode[4] = {0, 0, 0, 1};

@implementation H264Player
{
    dispatch_queue_t _encodeQueue;
    
    dispatch_queue_t _decodeQueue;
    
    VTDecompressionSessionRef _decodeSession;
    
    CMFormatDescriptionRef  _formatDescription;
    
    uint8_t *_mSPS;
    
    long _mSPSSize;
    
    uint8_t *_mPPS;
    
    long _mPPSSize;
    
    // 输入
    NSInputStream *_inputStream;
    
    uint8_t*       _packetBuffer;
    
    long         _packetSize;
    
    uint8_t*       _inputBuffer;
    
    long         _inputSize;
    
    long         _inputMaxSize;
}

- (void)startDecodeWithView:(UIView *)view
{
    self.openGLView = (LYOpenGLView *)view;
    
    [self.openGLView setupGL];
    
    [self startDecode];
}
- (instancetype)init
{
    self = [super init];
    
    if (self) {
        
        _decodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

        self.dispalyLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        
        self.dispalyLink.preferredFramesPerSecond = 30; // 默认是30FPS的帧率录制
        
        [self.dispalyLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        [self.dispalyLink setPaused:YES];
    }
    return self;
}
#pragma mark - video decode
- (void)onInputStart {
    
    _inputStream = [[NSInputStream alloc] initWithFileAtPath:[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"abc.h264"]];
    
    [_inputStream open];
    
    _inputSize = 0;
    
    _inputMaxSize = 1024*1024*1024;
    
    _inputBuffer = malloc(_inputMaxSize);
}

- (void)onInputEnd {
    
    [_inputStream close];
    
    _inputStream = nil;
    
    if (_inputBuffer) {
        
        free(_inputBuffer);
        
        _inputBuffer = NULL;
    }
    
    [self.dispalyLink setPaused:YES];
}

- (void)readPacket {
    
    if (_packetSize && _packetBuffer) {
        
        _packetSize = 0;
        
        free(_packetBuffer);
        
        _packetBuffer = NULL;
    }
    if (_inputSize < _inputMaxSize && _inputStream.hasBytesAvailable) {
        
        _inputSize += [_inputStream read:_inputBuffer + _inputSize maxLength:_inputMaxSize - _inputSize];
    }
    
    if (memcmp(_inputBuffer, lyStartCode, 4) == 0) {
        
        if (_inputSize > 4) { // 除了开始码还有内容
            
            uint8_t *pStart = _inputBuffer + 4;
            
            uint8_t *pEnd = _inputBuffer + _inputSize;
            
            while (pStart != pEnd) { //这里使用一种简略的方式来获取这一帧的长度：通过查找下一个0x00000001来确定。
                
                if(memcmp(pStart - 3, lyStartCode, 4) == 0) {
                    
                    _packetSize = pStart - _inputBuffer - 3;
                    
                    if (_packetBuffer) {
                        
                        free(_packetBuffer);
                        
                        _packetBuffer = NULL;
                    }
                    
                    _packetBuffer = malloc(_packetSize);
                    
                    memcpy(_packetBuffer, _inputBuffer, _packetSize); //复制packet内容到新的缓冲区
                    
                    memmove(_inputBuffer, _inputBuffer + _packetSize, _inputSize - _packetSize); //把缓冲区前移
                    
                    _inputSize -= _packetSize;
                    
                    break;
                    
                }else {
                    
                    ++pStart;
                }
            }
        }
    }
}

void didDecompress(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
}

-(void)startDecode {
    
    [self onInputStart];
    
    [self.dispalyLink setPaused:NO];
}

-(void)updateFrame {
    
    WS(weakSelf)
    
    dispatch_sync(_decodeQueue, ^{
        
        [weakSelf syncUpdateFrame];
    });
}

- (void)syncUpdateFrame
{
    if (_inputStream){
        
        [self readPacket];
        
        if(_packetBuffer == NULL || _packetSize == 0) {
            
            [self onInputEnd];
            
            return ;
        }
        
        uint32_t nalSize = (uint32_t)(_packetSize - 4);
        
        uint32_t *pNalSize = (uint32_t *)_packetBuffer;
        
        *pNalSize = CFSwapInt32HostToBig(nalSize);
        
        // 在buffer的前面填入代表长度的int
        
        CVPixelBufferRef pixelBuffer = NULL;
        
        int nalType = _packetBuffer[4] & 0x1F;
        
        switch (nalType) {
            case 0x05:
                
                NSLog(@"Nal type is IDR frame");
                
                [self initVideoDecodeToolBox];
                
                pixelBuffer = [self decode];
                
                break;
            case 0x07:
                
                NSLog(@"Nal type is SPS");
                
                _mSPSSize = _packetSize - 4;
                
                _mSPS = malloc(_mSPSSize);
                
                memcpy(_mSPS, _packetBuffer + 4, _mSPSSize);
                
                break;
                
            case 0x08:
                
                NSLog(@"Nal type is PPS");
                
                _mPPSSize = _packetSize - 4;
                
                _mPPS = malloc(_mPPSSize);
                
                memcpy(_mPPS, _packetBuffer + 4, _mPPSSize);
                
                break;
            default:
                
                NSLog(@"Nal type is B/P frame");
                
                pixelBuffer = [self decode];
                
                break;
        }
        
        if(pixelBuffer) {
            
            WS(weakSelf)
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [weakSelf.openGLView displayPixelBuffer:pixelBuffer];
                
                CVPixelBufferRelease(pixelBuffer);
            });
        }
        
        NSLog(@"Read Nalu size %ld", _packetSize);
    }
}

-(CVPixelBufferRef)decode {
    
    CVPixelBufferRef outputPixelBuffer = NULL;
    
    if (_decodeSession) {
        
        CMBlockBufferRef blockBuffer = NULL;
        
        OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,(void*)_packetBuffer, _packetSize,kCFAllocatorNull,NULL, 0, _packetSize, 0, &blockBuffer);
        
        if(status == kCMBlockBufferNoErr) {
            
            CMSampleBufferRef sampleBuffer = NULL;
            
            const size_t sampleSizeArray[] = {_packetSize};
            
            status = CMSampleBufferCreateReady(kCFAllocatorDefault,blockBuffer,_formatDescription,1, 0, NULL, 1, sampleSizeArray,&sampleBuffer);
            
            if (status == kCMBlockBufferNoErr && sampleBuffer) {
                
                VTDecodeFrameFlags flags = 0;
                
                VTDecodeInfoFlags flagOut = 0;
                
                // 默认是同步操作。
                // 调用didDecompress，返回后再回调
                OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_decodeSession,sampleBuffer,flags, &outputPixelBuffer,&flagOut);
                
                if(decodeStatus == kVTInvalidSessionErr) {
                    
                    NSLog(@"IOS8VT: Invalid session, reset decoder session");
                    
                } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                    
                    NSLog(@"IOS8VT: decode failed status=%d(Bad data)", decodeStatus);
                    
                } else if(decodeStatus != noErr) {
                    
                    NSLog(@"IOS8VT: decode failed status=%d", decodeStatus);
                }
                
                CFRelease(sampleBuffer);
            }
            
            CFRelease(blockBuffer);
        }
    }
    
    return outputPixelBuffer;
}

- (void)initVideoDecodeToolBox {
    
    if (!_decodeSession) {
        
        const uint8_t* parameterSetPointers[2] = {_mSPS, _mPPS};
        const size_t parameterSetSizes[2] = {_mSPSSize, _mPPSSize};
        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,2, //param count
                                                                              parameterSetPointers,
                                                                              parameterSetSizes,
                                                                              4, //nal start code size
                                                                              &_formatDescription);
        if(status == noErr) {
            
            CFDictionaryRef attrs = NULL;
            
            const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
            
            uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
            
            const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
            
            attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
            
            VTDecompressionOutputCallbackRecord callBackRecord;
            
            callBackRecord.decompressionOutputCallback = didDecompress;
            
            callBackRecord.decompressionOutputRefCon = NULL;
            
            status = VTDecompressionSessionCreate(kCFAllocatorDefault, _formatDescription,NULL, attrs,&callBackRecord,&_decodeSession);
            
            CFRelease(attrs);
            
        } else {
            
            NSLog(@"IOS8VT: reset decoder session failed status=%d", status);
        }
    }
}

- (void)EndVideoDecodeToolBox
{
    if(_decodeSession) {
        
        VTDecompressionSessionInvalidate(_decodeSession);
        
        CFRelease(_decodeSession);
        
        _decodeSession = NULL;
    }
    
    if(_formatDescription) {
        
        CFRelease(_formatDescription);
        
        _formatDescription = NULL;
    }
    
    free(_mSPS);
    
    free(_mPPS);
    
    _mSPSSize = _mPPSSize = 0;
}

@end
