#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@class RaceboltViewController;
@interface RaceboltMessageProxy : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) RaceboltViewController *owner;
@end

@interface RaceboltViewController : UIViewController <WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSArray<NSRegularExpression *> *blockedPatterns;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIBarButtonItem *backButton;
@property (nonatomic, strong) UIBarButtonItem *forwardButton;
@property (nonatomic, strong) UIBarButtonItem *pagesButton;
@property (nonatomic, assign) BOOL safetyReady;
- (void)showCheckoutBlocked;
@end

@implementation RaceboltMessageProxy
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.owner showCheckoutBlocked];
}
@end

@implementation RaceboltViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleDarkContent; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.status = [[UILabel alloc] init];
    self.status.text = @"PREPARING LIVE SITE SAFETY RULES";
    self.status.font = [UIFont boldSystemFontOfSize:11];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.textColor = [UIColor colorWithRed:0.65 green:0.05 blue:0.08 alpha:1];
    self.status.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    RaceboltMessageProxy *proxy = [[RaceboltMessageProxy alloc] init];
    proxy.owner = self;
    [configuration.userContentController addScriptMessageHandler:proxy name:@"raceboltBlocked"];
    NSURL *guardURL = [[NSBundle mainBundle] URLForResource:@"LiveGuard" withExtension:@"js"];
    NSError *guardError = nil;
    NSString *guard = guardURL ? [NSString stringWithContentsOfURL:guardURL encoding:NSUTF8StringEncoding error:&guardError] : nil;
    if (guard.length) {
        WKUserScript *script = [[WKUserScript alloc] initWithSource:guard injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
        [configuration.userContentController addUserScript:script];
    }
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
    self.webView.opaque = NO;
    self.webView.backgroundColor = UIColor.whiteColor;
    self.webView.scrollView.backgroundColor = UIColor.whiteColor;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

    UIToolbar *toolbar = [[UIToolbar alloc] init];
    toolbar.tintColor = self.status.textColor;
    self.backButton = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];
    self.forwardButton = [[UIBarButtonItem alloc] initWithTitle:@"Next" style:UIBarButtonItemStylePlain target:self action:@selector(goForward)];
    UIBarButtonItem *home = [[UIBarButtonItem alloc] initWithTitle:@"Home" style:UIBarButtonItemStylePlain target:self action:@selector(goHome)];
    self.pagesButton = [[UIBarButtonItem alloc] initWithTitle:@"Pages" style:UIBarButtonItemStylePlain target:self action:@selector(showPages)];
    UIBarButtonItem *reload = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadPage)];
    UIBarButtonItem *(^space)(void) = ^{ return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]; };
    toolbar.items = @[self.backButton, space(), self.forwardButton, space(), home, space(), self.pagesButton, space(), reload];
    self.backButton.enabled = NO;
    self.forwardButton.enabled = NO;
    for (UIView *view in @[self.status, self.webView, toolbar]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:view];
    }
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.status.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.status.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.status.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.status.heightAnchor constraintEqualToConstant:28],
        [toolbar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:44],
        [self.webView.topAnchor constraintEqualToAnchor:self.status.bottomAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:toolbar.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor]
    ]];
    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.backgroundColor = UIColor.whiteColor;
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.errorLabel.centerXAnchor constraintEqualToAnchor:self.webView.centerXAnchor],
        [self.errorLabel.centerYAnchor constraintEqualToAnchor:self.webView.centerYAnchor],
        [self.errorLabel.widthAnchor constraintEqualToAnchor:self.webView.widthAnchor constant:-32]
    ]];

    NSURL *rulesURL = [[NSBundle mainBundle] URLForResource:@"LiveSafetyRules" withExtension:@"json"];
    NSError *rulesError = nil;
    NSString *rules = rulesURL ? [NSString stringWithContentsOfURL:rulesURL encoding:NSUTF8StringEncoding error:&rulesError] : nil;
    if (!guard.length) { [self safetyFailedWithReason:guardError.localizedDescription ?: @"LiveGuard.js is missing or empty in the installed app."]; return; }
    if (!rules.length) { [self safetyFailedWithReason:rulesError.localizedDescription ?: @"LiveSafetyRules.json is missing or empty in the installed app."]; return; }
    id parsed = [NSJSONSerialization JSONObjectWithData:[rules dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&rulesError];
    if (![parsed isKindOfClass:NSArray.class] || ![(NSArray *)parsed count]) {
        [self safetyFailedWithReason:rulesError.localizedDescription ?: @"Safety JSON must contain a nonempty array."];
        return;
    }
    NSArray *entries = parsed;
    NSMutableArray *patterns = [[NSMutableArray alloc] init];
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"trigger"] isKindOfClass:NSDictionary.class]) {
            [self safetyFailedWithReason:@"Invalid safety rule structure."]; return;
        }
        NSString *filter = entry[@"trigger"][@"url-filter"];
        if (![filter isKindOfClass:NSString.class] || !filter.length || [filter containsString:@"|"]) {
            [self safetyFailedWithReason:@"Invalid safety filter or unsupported WebKit alternation."]; return;
        }
        NSError *regexError = nil;
        NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:filter options:NSRegularExpressionCaseInsensitive error:&regexError];
        if (!pattern) { [self safetyFailedWithReason:regexError.localizedDescription ?: @"Safety regex parsing failed."]; return; }
        [patterns addObject:pattern];
    }
    self.blockedPatterns = patterns;
    __weak typeof(self) weakSelf = self;
    [[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:@"RaceboltLiveSafety-v3" encodedContentRuleList:rules completionHandler:^(WKContentRuleList *list, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            RaceboltViewController *owner = weakSelf;
            if (!owner) return;
            if (error || !list) {
                NSString *reason = error ? [NSString stringWithFormat:@"%@ (%ld): %@", error.domain, (long)error.code, error.localizedDescription] : @"WebKit returned no compiled safety list.";
                [owner safetyFailedWithReason:reason]; return;
            }
            [owner.webView.configuration.userContentController addContentRuleList:list];
            owner.safetyReady = YES;
            owner.status.text = @"LIVE SITE · CHECKOUT BLOCKED";
            [owner goHome];
        });
    }];
}

- (void)safetyFailedWithReason:(NSString *)reason {
    self.safetyReady = NO;
    self.status.text = @"SITE NOT LOADED — SAFETY SETUP FAILED";
    self.errorLabel.font = [UIFont systemFontOfSize:15];
    self.errorLabel.text = [NSString stringWithFormat:@"Racebolt Test build 3\nCheckout safeguards could not load.\n\n%@\n\nPlease send a screenshot of this message.", reason];
    self.errorLabel.hidden = NO;
}

- (BOOL)isBlockedURL:(NSURL *)url {
    NSString *text = url.absoluteString ?: @"";
    for (NSInteger i = 0; i < 3; i++) {
        for (NSRegularExpression *pattern in self.blockedPatterns) {
            if ([pattern firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
        }
        NSString *next = text.stringByRemovingPercentEncoding;
        if (!next || [next isEqualToString:text]) break;
        text = next;
    }
    return NO;
}

- (BOOL)isSiteURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString;
    return [url.scheme.lowercaseString isEqualToString:@"https"] && ([host isEqualToString:@"raceboltuk.com"] || [host isEqualToString:@"www.raceboltuk.com"]);
}

- (void)loadSitePath:(NSString *)path {
    if (!self.safetyReady) return;
    self.errorLabel.hidden = YES;
    NSURL *url = [NSURL URLWithString:[@"https://raceboltuk.com" stringByAppendingString:path]];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}
- (void)goHome { [self loadSitePath:@"/"]; }
- (void)goBack { if (self.safetyReady && self.webView.canGoBack) [self.webView goBack]; }
- (void)goForward { if (self.safetyReady && self.webView.canGoForward) [self.webView goForward]; }
- (void)reloadPage {
    if (!self.safetyReady) return;
    self.errorLabel.hidden = YES;
    if (self.webView.URL) [self.webView reload]; else [self goHome];
}
- (void)showPages {
    if (!self.safetyReady || self.presentedViewController) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Racebolt live pages" message:@"Accounts and basket use the real website. Checkout is disabled." preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *pages = @[@[@"Home / Select your motorcycle", @"/"], @[@"How to measure a bolt", @"/how-to-measure-your-motorcycle-bolts/"], @[@"Blog", @"/blog/"], @[@"Technical", @"/technical/"], @[@"Basket", @"/basket/"], @[@"My account", @"/my-account/"]];
    __weak typeof(self) weakSelf = self;
    for (NSArray *page in pages) {
        [menu addAction:[UIAlertAction actionWithTitle:page[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [weakSelf loadSitePath:page[1]]; }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.barButtonItem = self.pagesButton;
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)showCheckoutBlocked {
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Checkout disabled" message:@"This app is for browsing and basket testing. Ordering, express payment and payment-method setup are blocked." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (!self.safetyReady || [self isBlockedURL:url]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        if (self.safetyReady && (navigationAction.targetFrame.isMainFrame || !navigationAction.targetFrame)) [self showCheckoutBlocked];
        return;
    }
    BOOL mainFrame = !navigationAction.targetFrame || navigationAction.targetFrame.isMainFrame;
    // Keep links inside this test app. Never open Safari as a checkout bypass.
    BOOL allowed = mainFrame ? [self isSiteURL:url] : ([url.scheme.lowercaseString isEqualToString:@"https"] || [url.absoluteString isEqualToString:@"about:blank"]);
    if (!allowed) { decisionHandler(WKNavigationActionPolicyCancel); return; }
    if (!navigationAction.targetFrame) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [webView loadRequest:navigationAction.request];
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)response decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    NSURL *url = response.response.URL;
    BOOL allowed = self.safetyReady && ![self isBlockedURL:url] && (!response.isForMainFrame || [self isSiteURL:url]) && response.canShowMIMEType;
    decisionHandler(allowed ? WKNavigationResponsePolicyAllow : WKNavigationResponsePolicyCancel);
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    self.errorLabel.hidden = YES;
    self.status.text = @"LOADING LIVE SITE · CHECKOUT BLOCKED";
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.status.text = @"LIVE SITE · CHECKOUT BLOCKED";
    self.backButton.enabled = webView.canGoBack;
    self.forwardButton.enabled = webView.canGoForward;
}
- (void)showLoadError:(NSError *)error {
    if (error.code == NSURLErrorCancelled) return;
    self.status.text = @"LIVE SITE UNAVAILABLE · CHECKOUT BLOCKED";
    self.errorLabel.text = @"The live page could not load.\nCheck your connection, then tap Refresh or Home.";
    self.errorLabel.hidden = YES; // Preserve any already-loaded page; show only if the initial load failed.
    if (!self.webView.backForwardList.currentItem) self.errorLabel.hidden = NO;
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showLoadError:error]; }
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showLoadError:error]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView { [self reloadPage]; }
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    if (self.presentedViewController) { completionHandler(); return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Racebolt" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completionHandler(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    if (self.presentedViewController) { completionHandler(NO); return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Racebolt" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { completionHandler(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completionHandler(YES); }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString *))completionHandler {
    if (self.presentedViewController) { completionHandler(nil); return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Racebolt" message:prompt preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = defaultText; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { completionHandler(nil); }]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completionHandler(weakAlert.textFields.firstObject.text); }]];
    [self presentViewController:alert animated:YES completion:nil];
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