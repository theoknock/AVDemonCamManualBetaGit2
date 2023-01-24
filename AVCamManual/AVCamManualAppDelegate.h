/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Application delegate.
*/

@import Foundation;
@import UIKit;
@import AVFoundation;

@protocol MovieAppEventDelegate <NSObject>

@property (nonatomic) AVCaptureMovieFileOutput * movieFileOutput;
- (IBAction)toggleMovieRecording:(id)sender;


@end

@interface AVCamManualAppDelegate : UIResponder <UIApplicationDelegate>

+ (AVCamManualAppDelegate *)sharedAppDelegate;




@property (nonatomic) UIWindow *window;
@property (weak) IBOutlet id<MovieAppEventDelegate> movieAppEventDelegate;

//@property (nonatomic) dispatch_queue_t sessionQueue;

@end
