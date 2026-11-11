#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>

@interface CarbPrepViewController : UIViewController <WKUIDelegate, WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation CarbPrepViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.06 blue:0.10 alpha:1.0];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.UIDelegate = self;
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.backgroundColor = self.view.backgroundColor;
    self.webView.scrollView.backgroundColor = self.view.backgroundColor;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:self.webView];

    NSString *wwwPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"];
    NSString *bundleHtmlPath = [wwwPath stringByAppendingPathComponent:@"bundle.html"];
    NSString *indexHtmlPath = [wwwPath stringByAppendingPathComponent:@"index.html"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:bundleHtmlPath]) {
        NSURL *fileURL = [NSURL fileURLWithPath:bundleHtmlPath];
        NSURL *readDir = [NSURL fileURLWithPath:wwwPath isDirectory:YES];
        [self.webView loadFileURL:fileURL allowingReadAccessToURL:readDir];
    } else if ([fm fileExistsAtPath:indexHtmlPath]) {
        NSURL *fileURL = [NSURL fileURLWithPath:indexHtmlPath];
        NSURL *readDir = [NSURL fileURLWithPath:wwwPath isDirectory:YES];
        [self.webView loadFileURL:fileURL allowingReadAccessToURL:readDir];
    }
}

- (void)webView:(WKWebView *)webView
requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
initiatedByFrame:(WKFrameInfo *)frame
           type:(WKMediaCaptureType)type
decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler API_AVAILABLE(ios(15.0)) {
    decisionHandler(WKPermissionDecisionGrant);
}

@end

@interface CarbPrepAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CarbPrepAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[CarbPrepViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([CarbPrepAppDelegate class]));
    }
}
