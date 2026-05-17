/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

#import <WebDriverAgentLib/FBDebugLogDelegateDecorator.h>
#import <WebDriverAgentLib/FBConfiguration.h>
#import <WebDriverAgentLib/FBFailureProofTestCase.h>
#import <WebDriverAgentLib/FBWebServer.h>
#import <WebDriverAgentLib/XCTestCase.h>

static NSString *const IvistaWDAServerDidStartNotification = @"com.ivista.wda.server.didStart";
static NSString *const IvistaWDAServerDidFailNotification = @"com.ivista.wda.server.didFail";

@interface IvistaWDAStatusViewController : UIViewController
@property (nonatomic, strong) UILabel *eyebrowLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *endpointLabel;
@property (nonatomic, strong) UIView *statusDot;
- (void)showStartingWithPort:(NSString *)port;
- (void)showConnectedWithURL:(NSString *)url;
- (void)showFailedWithMessage:(NSString *)message;
@end

@implementation IvistaWDAStatusViewController

- (void)viewDidLoad
{
  [super viewDidLoad];

  self.view.backgroundColor = [UIColor blackColor];

  UIView *content = [UIView new];
  content.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:content];

  UILabel *brandLabel = [UILabel new];
  brandLabel.translatesAutoresizingMaskIntoConstraints = NO;
  brandLabel.text = @"iVista";
  brandLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
  brandLabel.textColor = [UIColor whiteColor];
  [content addSubview:brandLabel];

  self.eyebrowLabel = [UILabel new];
  self.eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.eyebrowLabel.text = @"WebDriverAgent";
  self.eyebrowLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  self.eyebrowLabel.textColor = [UIColor colorWithWhite:1 alpha:0.52];
  [content addSubview:self.eyebrowLabel];

  self.statusDot = [UIView new];
  self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
  self.statusDot.layer.cornerRadius = 7;
  self.statusDot.backgroundColor = [UIColor systemOrangeColor];
  self.statusDot.layer.shadowOpacity = 0.45f;
  self.statusDot.layer.shadowRadius = 10;
  self.statusDot.layer.shadowOffset = CGSizeZero;
  [content addSubview:self.statusDot];

  self.titleLabel = [UILabel new];
  self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
  self.titleLabel.textColor = [UIColor whiteColor];
  self.titleLabel.numberOfLines = 0;
  [content addSubview:self.titleLabel];

  self.detailLabel = [UILabel new];
  self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.detailLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
  self.detailLabel.textColor = [UIColor colorWithWhite:1 alpha:0.58];
  self.detailLabel.numberOfLines = 0;
  [content addSubview:self.detailLabel];

  self.endpointLabel = [UILabel new];
  self.endpointLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.endpointLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
  self.endpointLabel.textColor = [UIColor colorWithWhite:1 alpha:0.86];
  self.endpointLabel.numberOfLines = 0;
  self.endpointLabel.lineBreakMode = NSLineBreakByCharWrapping;
  [content addSubview:self.endpointLabel];

  [NSLayoutConstraint activateConstraints:@[
    [content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:34],
    [content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-34],
    [content.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

    [brandLabel.topAnchor constraintEqualToAnchor:content.topAnchor],
    [brandLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],

    [self.eyebrowLabel.centerYAnchor constraintEqualToAnchor:brandLabel.centerYAnchor],
    [self.eyebrowLabel.leadingAnchor constraintEqualToAnchor:brandLabel.trailingAnchor constant:10],
    [self.eyebrowLabel.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor],

    [self.statusDot.topAnchor constraintEqualToAnchor:brandLabel.bottomAnchor constant:46],
    [self.statusDot.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [self.statusDot.widthAnchor constraintEqualToConstant:14],
    [self.statusDot.heightAnchor constraintEqualToConstant:14],

    [self.titleLabel.topAnchor constraintEqualToAnchor:self.statusDot.topAnchor constant:-11],
    [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:16],
    [self.titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

    [self.detailLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:18],
    [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [self.detailLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

    [self.endpointLabel.topAnchor constraintEqualToAnchor:self.detailLabel.bottomAnchor constant:34],
    [self.endpointLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [self.endpointLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [self.endpointLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
  ]];
}

- (void)showStartingWithPort:(NSString *)port
{
  self.statusDot.backgroundColor = [UIColor systemOrangeColor];
  self.statusDot.layer.shadowColor = [UIColor systemOrangeColor].CGColor;
  self.titleLabel.text = @"Starting";
  self.detailLabel.text = @"Keep this app open while iVista connects from your Mac.";
  self.endpointLabel.text = [NSString stringWithFormat:@"http://127.0.0.1:%@", port ?: @"8100"];
}

- (void)showConnectedWithURL:(NSString *)url
{
  self.statusDot.backgroundColor = [UIColor systemGreenColor];
  self.statusDot.layer.shadowColor = [UIColor systemGreenColor].CGColor;
  self.titleLabel.text = @"Connected";
  self.detailLabel.text = @"WebDriverAgent is running. You can now control this Simulator from iVista.";
  self.endpointLabel.text = url ?: @"http://127.0.0.1:8100";
}

- (void)showFailedWithMessage:(NSString *)message
{
  self.statusDot.backgroundColor = [UIColor systemRedColor];
  self.statusDot.layer.shadowColor = [UIColor systemRedColor].CGColor;
  self.titleLabel.text = @"Connection failed";
  self.detailLabel.text = message ?: @"WebDriverAgent could not start. The port may already be in use.";
  self.endpointLabel.text = @"Try: ivista wda stop, then ivista wda start --auto-port";
}

@end

@interface UITestingUITests : FBFailureProofTestCase <FBWebServerDelegate>
@end

@implementation UITestingUITests

static UIWindow *ivistaStatusWindow;
static IvistaWDAStatusViewController *ivistaStatusViewController;
static BOOL ivistaServerStarted;
static NSString *ivistaServerURL;

+ (void)setUp
{
  [FBDebugLogDelegateDecorator decorateXCTestLogger];
  [FBConfiguration disableRemoteQueryEvaluation];
  [FBConfiguration configureDefaultKeyboardPreferences];
  [FBConfiguration disableApplicationUIInterruptionsHandling];
  if (NSProcessInfo.processInfo.environment[@"ENABLE_AUTOMATIC_SCREEN_RECORDINGS"]) {
    [FBConfiguration enableScreenRecordings];
  } else {
    [FBConfiguration disableScreenRecordings];
  }
  if (NSProcessInfo.processInfo.environment[@"ENABLE_AUTOMATIC_SCREENSHOTS"]) {
    [FBConfiguration enableScreenshots];
  } else {
    [FBConfiguration disableScreenshots];
  }
  [super setUp];
}

+ (void)ivistaPerformOnMainThread:(dispatch_block_t)block
{
  if (NSThread.isMainThread) {
    block();
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), block);
}

+ (void)ivistaShowStatusWindow
{
  [self ivistaPerformOnMainThread:^{
    UIWindowScene *activeWindowScene = nil;
    if (@available(iOS 13.0, *)) {
      for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
          continue;
        }
        if (scene.activationState == UISceneActivationStateForegroundActive
            || scene.activationState == UISceneActivationStateForegroundInactive) {
          activeWindowScene = (UIWindowScene *)scene;
          break;
        }
        activeWindowScene = activeWindowScene ?: (UIWindowScene *)scene;
      }
    }

    if (nil == ivistaStatusWindow) {
      ivistaStatusViewController = [IvistaWDAStatusViewController new];
      if (@available(iOS 13.0, *)) {
        if (nil != activeWindowScene) {
          ivistaStatusWindow = [[UIWindow alloc] initWithWindowScene:activeWindowScene];
          ivistaStatusWindow.frame = activeWindowScene.coordinateSpace.bounds;
        }
      }
      ivistaStatusWindow = ivistaStatusWindow ?: [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
      ivistaStatusWindow.rootViewController = ivistaStatusViewController;
      ivistaStatusWindow.windowLevel = UIWindowLevelAlert + 1;
      [ivistaStatusWindow makeKeyAndVisible];

      [[NSNotificationCenter defaultCenter] addObserverForName:IvistaWDAServerDidStartNotification
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(NSNotification *notification) {
        NSString *url = notification.userInfo[@"url"];
        ivistaServerStarted = YES;
        ivistaServerURL = url;
        [ivistaStatusViewController showConnectedWithURL:url];
      }];

      [[NSNotificationCenter defaultCenter] addObserverForName:IvistaWDAServerDidFailNotification
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(NSNotification *notification) {
        NSString *message = notification.userInfo[@"error"];
        ivistaServerStarted = NO;
        ivistaServerURL = nil;
        [ivistaStatusViewController showFailedWithMessage:message];
      }];
    }

    NSString *port = NSProcessInfo.processInfo.environment[@"USE_PORT"] ?: @"8100";
    if (ivistaServerStarted) {
      [ivistaStatusViewController showConnectedWithURL:ivistaServerURL];
    } else {
      [ivistaStatusViewController showStartingWithPort:port];
    }
  }];
}

/**
 Never ending test used to start WebDriverAgent
 */
- (void)testRunner
{
  [self.class ivistaShowStatusWindow];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self.class ivistaShowStatusWindow];
  });

  FBWebServer *webServer = [[FBWebServer alloc] init];
  webServer.delegate = self;
  [webServer startServing];
}

#pragma mark - FBWebServerDelegate

- (void)webServerDidRequestShutdown:(FBWebServer *)webServer
{
  [webServer stopServing];
}

@end
