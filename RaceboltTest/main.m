#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface RaceboltViewController : UIViewController <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSURL *localRoot;
@end

@implementation RaceboltViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleDarkContent; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.backgroundColor = UIColor.whiteColor;
    self.webView.scrollView.backgroundColor = UIColor.whiteColor;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:self.webView];
    self.localRoot = [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"www" isDirectory:YES];
    NSURL *page = [self.localRoot URLByAppendingPathComponent:@"index.html"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:page.path]) {
        [self.webView loadFileURL:page allowingReadAccessToURL:self.localRoot];
    } else {
        UILabel *error = [[UILabel alloc] initWithFrame:self.view.bounds];
        error.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        error.numberOfLines = 0;
        error.textAlignment = NSTextAlignmentCenter;
        error.text = @"Racebolt test assets are missing.\nPlease rebuild the complete source folder.";
        [self.view addSubview:error];
    }
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    NSString *allowedRoot = [self.localRoot.URLByStandardizingPath.path stringByAppendingString:@"/"];
    BOOL isLocal = url.isFileURL && [url.URLByStandardizingPath.path hasPrefix:allowedRoot];
    BOOL isEmptyPage = [url.absoluteString isEqualToString:@"about:blank"];
    // Test-only: never navigate to the real shop, checkout or any external URL.
    decisionHandler((isLocal || isEmptyPage) ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

@end

@interface RaceboltAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation RaceboltAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[RaceboltViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(RaceboltAppDelegate.class));
    }
}