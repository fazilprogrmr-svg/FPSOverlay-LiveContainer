#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <float.h>

@interface FPSOverlayController : NSObject
@property(nonatomic,strong)UILabel *label;
@property(nonatomic,strong)CADisplayLink *displayLink;
@property(nonatomic,weak)UIWindow *hostWindow;
@property(nonatomic,strong)NSTimer *refreshTimer;
@property(nonatomic)CFTimeInterval lastTimestamp;
@property(nonatomic)NSInteger frameCount;
@property(nonatomic,strong)NSMutableArray<NSNumber *> *samples;
@property(nonatomic)double minFPS,maxFPS,sumFPS;
@property(nonatomic)NSInteger sampleCount;
@end

@implementation FPSOverlayController
- (instancetype)init { if((self=[super init])){_samples=[NSMutableArray array];_minFPS=DBL_MAX;_maxFPS=0;[UIDevice currentDevice].batteryMonitoringEnabled=YES;} return self; }

- (UIWindow *)findGameWindow {
    if (@available(iOS 13.0,*)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (s.activationState!=UISceneActivationStateForegroundActive &&
                s.activationState!=UISceneActivationStateForegroundInactive) continue;
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws=(UIWindowScene *)s;
            for (UIWindow *w in ws.windows)
                if (!w.hidden && w.alpha>.01 && w.windowLevel==UIWindowLevelNormal && w.isKeyWindow) return w;
            for (UIWindow *w in ws.windows)
                if (!w.hidden && w.alpha>.01 && w.windowLevel==UIWindowLevelNormal) return w;
        }
    }
    return nil;
}

- (void)start {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [self refreshWindow];
        self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refreshWindow) userInfo:nil repeats:YES];
    });
}

- (void)refreshWindow {
    UIWindow *w=[self findGameWindow]; if(!w)return;
    if(self.hostWindow!=w || !self.label.superview) {
        [self.label removeFromSuperview]; self.hostWindow=w;
        UILabel *l=[UILabel new];
        l.textColor=UIColor.whiteColor; l.backgroundColor=UIColor.clearColor;
        l.font=[UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightBold];
        l.numberOfLines=0; l.userInteractionEnabled=NO;
        l.layer.shadowColor=UIColor.blackColor.CGColor; l.layer.shadowOffset=CGSizeMake(1,1);
        l.layer.shadowOpacity=.95; l.layer.shadowRadius=2; l.translatesAutoresizingMaskIntoConstraints=NO;
        [w addSubview:l];
        [NSLayoutConstraint activateConstraints:@[
            [l.leadingAnchor constraintEqualToAnchor:w.leadingAnchor constant:20],
            [l.topAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.topAnchor constant:8],
            [l.widthAnchor constraintEqualToConstant:245],
            [l.heightAnchor constraintEqualToConstant:185]]];
        self.label=l; [self updateLabel];
    }
    if(!self.displayLink){
        self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(frameTick:)];
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)frameTick:(CADisplayLink *)link {
    if(!self.lastTimestamp){self.lastTimestamp=link.timestamp;self.frameCount=0;return;}
    self.frameCount++; CFTimeInterval e=link.timestamp-self.lastTimestamp;
    if(e>=.5){
        double fps=self.frameCount/e;
        if(fps>0 && fps<240){[self.samples addObject:@(fps)];if(self.samples.count>600)[self.samples removeObjectAtIndex:0];self.sumFPS+=fps;self.sampleCount++;self.minFPS=MIN(self.minFPS,fps);self.maxFPS=MAX(self.maxFPS,fps);}
        self.frameCount=0;self.lastTimestamp=link.timestamp;[self updateLabel];
    }
}

- (double)percentileLow:(double)p {
    if(self.samples.count<2)return 0;
    NSArray *a=[self.samples sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger i=(NSUInteger)floor((a.count-1)*p); return a[i].doubleValue;
}

- (double)memoryMB {
    mach_task_basic_info_data_t info; mach_msg_type_number_t c=MACH_TASK_BASIC_INFO_COUNT;
    if(task_info(mach_task_self(),MACH_TASK_BASIC_INFO,(task_info_t)&info,&c)!=KERN_SUCCESS)return 0;
    return info.resident_size/(1024.0*1024.0);
}

- (void)updateLabel {
    if(!self.label)return;
    double fps=self.samples.lastObject.doubleValue, ms=fps>0?1000/fps:0;
    double avg=self.sampleCount?self.sumFPS/self.sampleCount:0;
    double low1=[self percentileLow:.01], low01=[self percentileLow:.001];
    double bat=UIDevice.currentDevice.batteryLevel>=0?UIDevice.currentDevice.batteryLevel*100:0;
    self.label.text=[NSString stringWithFormat:@"FPS %5.1f   %.2f ms\nAVG %5.1f  MIN %5.1f\nMAX %5.1f  1%% LOW %5.1f\n0.1%% LOW %4.1f\nRAM %5.0f MB  BAT %3.0f%%",fps,ms,avg,self.sampleCount?self.minFPS:0,self.maxFPS,low1,low01,[self memoryMB],bat];
}
@end

static FPSOverlayController *gFPSOverlayController;
__attribute__((constructor)) static void FPSOverlayInit(void){
    dispatch_async(dispatch_get_main_queue(),^{
        gFPSOverlayController=[FPSOverlayController new];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){[gFPSOverlayController refreshWindow];}];
        [gFPSOverlayController start];
    });
}