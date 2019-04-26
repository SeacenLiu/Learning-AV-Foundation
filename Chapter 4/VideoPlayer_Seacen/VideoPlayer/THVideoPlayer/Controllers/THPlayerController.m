//
//  MIT License
//
//  Copyright (c) 2014 Bob McCune http://bobmccune.com/
//  Copyright (c) 2014 TapHarmonic, LLC http://tapharmonic.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "THPlayerController.h"
#import "THThumbnail.h"
#import <AVFoundation/AVFoundation.h>
#import "THTransport.h"
#import "THPlayerView.h"
#import "AVAsset+THAdditions.h"
#import "UIAlertView+THAdditions.h"
#import "THNotifications.h"

// AVPlayerItem's status property
#define STATUS_KEYPATH @"status"

// Refresh interval for timed observations of AVPlayer
#define REFRESH_INTERVAL 0.5f

// Define this constant for the key-value observation context.
static const NSString *PlayerItemStatusContext;


@interface THPlayerController () <THTransportDelegate>

@property (strong, nonatomic) THPlayerView *playerView;

// Listing 4.4
@property (nonatomic, strong) AVAsset *asset;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, strong) AVPlayer *player;

@property (nonatomic, weak) id <THTransport> transport;

@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) id itemEndObserver;
@property (nonatomic, assign) float lastPlaybackRate;

@property (nonatomic, strong) AVAssetImageGenerator *imageGenerator;

@end

// FIXME: - 快速拖拽滑条崩溃！！！
@implementation THPlayerController

#pragma mark - Setup

- (id)initWithURL:(NSURL *)assetURL {
    self = [super init];
    if (self) {
        // Listing 4.6
        _asset = [AVAsset assetWithURL:assetURL];
        [self prepareToPlay];
        
    }
    return self;
}

- (void)prepareToPlay {
    // Listing 4.6
    NSArray *keys = @[@"tracks",
                      @"duration",
                      @"commonMetadata",
                      @"availableMediaCharacteristicsWithMediaSelectionOptions"];
    self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset automaticallyLoadedAssetKeys:keys];
    
    [self.playerItem addObserver:self
                      forKeyPath:STATUS_KEYPATH
                         options:0
                         context:&PlayerItemStatusContext];
    
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    
    self.playerView = [[THPlayerView alloc] initWithPlayer:self.player];
    self.transport = self.playerView.transport;
    self.transport.delegate = self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    // Listing 4.7
    if (context == &PlayerItemStatusContext) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.playerItem removeObserver:self forKeyPath:STATUS_KEYPATH];
            
            if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
                // Set up time observer.
                [self addPlayerItemTimeObserver];
                [self addItemEndObserverForPlayerItem];
                
                CMTime duration = self.playerItem.duration;
                
                // Synchronize the time display
                [self.transport setCurrentTime:CMTimeGetSeconds(kCMTimeZero) duration:CMTimeGetSeconds(duration)];
                
                // Set the video title.
                [self.transport setTitle:self.asset.title];
                
                [self.player play];
                
                // Listing 4.13
                // 生成缩略图
                [self generateThumbnails];
                
                // Lising 4.15
                [self loadMediaOptions];
                
            } else {
                [UIAlertView showAlertWithTitle:@"Error" message:@"Failed to load Video."];
            }
        });
    }
}

#pragma mark - Time Observers

- (void)addPlayerItemTimeObserver {
    // Listing 4.8
    // Create 0.5 seconed refresh interval - REFRESH_INTERVAL == 0.5
    CMTime interval = CMTimeMakeWithSeconds(REFRESH_INTERVAL, NSEC_PER_SEC);
    
    // Main dispatch queue
    dispatch_queue_t queue = dispatch_get_main_queue();
    
    // Create callblack block for time observer
    __weak THPlayerController *weakSelf = self;
    void (^callblack)(CMTime time) = ^(CMTime time) {
        NSTimeInterval currentTime = CMTimeGetSeconds(time);
        NSTimeInterval duration = CMTimeGetSeconds(weakSelf.playerItem.duration);
        [weakSelf.transport setCurrentTime:currentTime duration:duration];
    };
    
    // Add observer and store pointer for future use
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:interval
                                                                  queue:queue
                                                             usingBlock:callblack];
    
}

/// NSNotification
- (void)addItemEndObserverForPlayerItem {
    // Listing 4.9
    NSString *name = AVPlayerItemDidPlayToEndTimeNotification;
    NSOperationQueue *queue = [NSOperationQueue mainQueue];
    
    __weak THPlayerController *weakSelf = self;
    void (^callblack)(NSNotification *note) = ^(NSNotification *note) {
        [weakSelf.player seekToTime:kCMTimeZero
                  completionHandler:^(BOOL finished) {
                      [weakSelf.transport playbackComplete];
        }];
    };
    
    self.itemEndObserver = [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                                             object:self.playerItem
                                                                              queue:queue
                                                                         usingBlock:callblack];
}

- (void)dealloc {
    if (self.itemEndObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.itemEndObserver
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:self.player.currentItem];
        self.itemEndObserver = nil;
    }
}

#pragma mark - THTransportDelegate Methods

- (void)play {
    // Listing 4.10
    [self.player play];
}

- (void)pause {
    // Listing 4.10
    self.lastPlaybackRate = self.player.rate;
    [self.player pause];
}

- (void)stop {
    // Listing 4.10
    [self.player setRate:0.0f];
    [self.transport playbackComplete];
}

// 跳转时间点
- (void)jumpedToTime:(NSTimeInterval)time {
    // Listing 4.10
    [self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)];
}

/// 开始拖拽
- (void)scrubbingDidStart {
    // Listing 4.11
    self.lastPlaybackRate = self.player.rate;
    [self.player pause];
    // 防止时间轴更新错乱
    [self.player removeTimeObserver:self.timeObserver];
}

/// 拖拽过程
- (void)scrubbedToTime:(NSTimeInterval)time {
    // Listing 4.11
    [self.playerItem cancelPendingSeeks];
    [self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)];
}

/// 拖拽结束
- (void)scrubbingDidEnd {
    // Listing 4.11
    // 重新设置播放
    [self addPlayerItemTimeObserver];
    if (self.lastPlaybackRate > 0.0f) {
        [self.player play];
    }
}


#pragma mark - Thumbnail Generation

- (void)generateThumbnails {
    // Listing 4.14
    self.imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:self.asset];
    
    // Generate the @2x/@3x equivalent
    CGFloat scale = [UIScreen mainScreen].scale;
    self.imageGenerator.maximumSize = CGSizeMake(100.0f * scale, 0.0f);
    
    CMTime duration = self.asset.duration;
    
    NSMutableArray *times = [NSMutableArray array];
    CMTimeValue increment = duration.value / 20;
    CMTimeValue currentValue = 0.0;
    while (currentValue <= duration.value) {
        CMTime time = CMTimeMake(currentValue, duration.timescale);
        [times addObject:[NSValue valueWithCMTime:time]];
        currentValue += increment;
    }
    
    __block NSUInteger imageCount = times.count;
    __block NSMutableArray *images = [NSMutableArray array];
    
    AVAssetImageGeneratorCompletionHandler handler;
    
    handler = ^(CMTime requestedTime,
                CGImageRef imageRef,
                CMTime actualTime,
                AVAssetImageGeneratorResult result,
                NSError *error) {
        
        if (result == AVAssetImageGeneratorSucceeded) {
            UIImage *image = [UIImage imageWithCGImage:imageRef];
            id thumbnail = [THThumbnail thumbnailWithImage:image time:actualTime];
            [images addObject:thumbnail];
        } else {
            NSLog(@"Failed to create thumnail image.");
        }
        
        // If the decremented image count is at 0, we are all done.
        if (--imageCount == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *name = THThumbnailsGeneratedNotification;
                [[NSNotificationCenter defaultCenter] postNotificationName:name object:images];
            });
        }
    };
    
    [self.imageGenerator generateCGImagesAsynchronouslyForTimes:times completionHandler:handler];
}


- (void)loadMediaOptions {
    // Listing 4.16
    NSString *mc = AVMediaCharacteristicLegible;
    AVMediaSelectionGroup *group = [self.asset mediaSelectionGroupForMediaCharacteristic:mc];
    if (group) {
        NSMutableArray *subtitles = [NSMutableArray array];
        for (AVMediaSelectionOption *option in group.options) {
            [subtitles addObject:option.displayName];
        }
        [self.transport setSubtitles:subtitles];
    } else {
        [self.transport setSubtitles:nil];
    }
}

- (void)subtitleSelected:(NSString *)subtitle {
    // Listing 4.17
    NSString *mc = AVMediaCharacteristicLegible;
    AVMediaSelectionGroup *group = [self.asset mediaSelectionGroupForMediaCharacteristic:mc];
    BOOL selected = NO;
    for (AVMediaSelectionOption *option in group.options) {
        if ([option.displayName isEqualToString:subtitle]) {
            [self.playerItem selectMediaOption:option inMediaSelectionGroup:group];
            selected = YES;
        }
    }
    if (!selected) {
        [self.playerItem selectMediaOption:nil inMediaSelectionGroup:group];
    }
}


#pragma mark - Housekeeping

- (UIView *)view {
    return self.playerView;
}

@end
