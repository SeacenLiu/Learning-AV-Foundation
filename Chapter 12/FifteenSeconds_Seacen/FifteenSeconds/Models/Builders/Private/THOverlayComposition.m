//
//  MIT License
//
//  Copyright (c) 2013 Bob McCune http://bobmccune.com/
//  Copyright (c) 2013 TapHarmonic, LLC http://tapharmonic.com/
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
//

#import "THOverlayComposition.h"
#import "AVPlayerItem+THAdditions.h"
#import "THConstants.h"

@implementation THOverlayComposition

- (id)initWithComposition:(AVComposition *)composition
		 videoComposition:(AVVideoComposition *)videoComposition
				 audioMix:(AVAudioMix *)audioMix
               titleLayer:(CALayer *)titleLayer {
	self = [super init];
	if (self) {
        _composition = composition;
        _videoComposition = videoComposition;
        _audioMix = audioMix;
        _titleLayer = titleLayer;
	}
	return self;
}

- (AVPlayerItem *)makePlayable {
    // Listing 12.8
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:[self.composition copy]];
    
    playerItem.videoComposition = self.videoComposition;
    playerItem.audioMix = self.audioMix;
    
    if (self.titleLayer) {
        AVSynchronizedLayer *syncLayer = [AVSynchronizedLayer synchronizedLayerWithPlayerItem:playerItem];
        [syncLayer addSublayer:self.titleLayer];
        
        playerItem.syncLayer = syncLayer;
    }
    
    return playerItem;
}

- (AVAssetExportSession *)makeExportable {
    // Listing 12.9
    if (self.titleLayer) {
        CALayer *animationLayer = [CALayer layer];
        animationLayer.frame = TH720pVideoRect;
        
        CALayer *videoLayer = [CALayer layer];
        videoLayer.frame = TH720pVideoRect;
        
        [animationLayer addSublayer:videoLayer];
        [animationLayer addSublayer:self.titleLayer];
        
        animationLayer.geometryFlipped = YES;
        
        AVVideoCompositionCoreAnimationTool *animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer inLayer:animationLayer];
        
        AVMutableVideoComposition *mvc = (AVMutableVideoComposition*)self.videoComposition;
        mvc.animationTool = animationTool;
    }
    
    NSString *presetName = AVAssetExportPresetHighestQuality;
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:[self.composition copy] presetName:presetName];
    session.audioMix = self.audioMix;
    session.videoComposition = self.videoComposition;
    
    return session;
}

@end
