//
//  ViewController.m
//  ScalableSliderControlExploratorium
//
//  Created by Xcode Developer on 1/24/23.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (IBAction)pinchContentSize:(UIPinchGestureRecognizer *)sender {
    CGFloat s = [sender scale];
    if (sender.state == UIGestureRecognizerStateEnded) {
        printf("s == %f", s);
        [self.contentView setBounds:CGRectMake(self.contentView.bounds.origin.x, self.contentView.bounds.origin.y, self.contentView.bounds.size.width * s, self.contentView.bounds.size.height * s)];
        [self.contentView setFrame:CGRectMake(self.contentView.bounds.origin.x, self.contentView.bounds.origin.y, self.contentView.bounds.size.width * s, self.contentView.bounds.size.height * s)];
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return scrollView.subviews.firstObject.subviews.firstObject;
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
//    [scrollView setScrollEnabled:FALSE];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
//    [scrollView setScrollEnabled:TRUE];
}


@end
