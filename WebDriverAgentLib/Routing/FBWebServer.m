/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBWebServer.h"

#import "RoutingConnection.h"
#import "RoutingHTTPServer.h"

#import "FBCommandHandler.h"
#import "FBErrorBuilder.h"
#import "FBExceptionHandler.h"
#import "FBMjpegServer.h"
#import "FBRouteRequest.h"
#import "FBRuntimeUtils.h"
#import "FBSession.h"
#import "FBTCPSocket.h"
#import "FBUnknownCommands.h"
#import "FBConfiguration.h"
#import "FBLogger.h"

#import "XCUIDevice+FBHelpers.h"

static NSString *const FBServerURLBeginMarker = @"ServerURLHere->";
static NSString *const FBServerURLEndMarker = @"<-ServerURLHere";
static NSString *const IvistaWDAServerDidStartNotification = @"com.ivista.wda.server.didStart";
static NSString *const IvistaWDAServerDidFailNotification = @"com.ivista.wda.server.didFail";

static NSString *IvistaHTMLPage(NSString *port)
{
  NSString *page = @"<!DOCTYPE html>"
  "<html lang=\"en\">"
  "<head>"
  "<meta charset=\"utf-8\">"
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
  "<title>iVista WDA</title>"
  "<style>"
  ":root{color-scheme:dark;}"
  "*{box-sizing:border-box;}"
  "body{margin:0;min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',sans-serif;background:#050505;color:#f5f5f5;}"
  "main{max-width:960px;margin:0 auto;padding:40px 22px 28px;}"
  ".top{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:24px;}"
  ".brand{font-size:18px;font-weight:800;color:#f5f5f5;}"
  ".sub{font-size:13px;color:#a3a3a3;margin-top:3px;}"
  ".status{display:inline-flex;align-items:center;gap:10px;padding:9px 12px;border:1px solid #2a2a2a;border-radius:999px;background:#111;color:#bbf7d0;font-size:13px;font-weight:800;white-space:nowrap;}"
  ".dot{width:9px;height:9px;border-radius:999px;background:#22c55e;box-shadow:0 0 16px rgba(34,197,94,.9);}"
  ".panel{border:1px solid #262626;background:#0d0d0d;border-radius:8px;padding:26px;box-shadow:0 18px 60px rgba(0,0,0,.35);}"
  ".headline{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:24px;align-items:start;border-bottom:1px solid #242424;padding-bottom:22px;}"
  ".eyebrow{margin:0 0 8px;color:#86efac;font-size:12px;font-weight:900;text-transform:uppercase;letter-spacing:.08em;}"
  "h1{font-size:34px;line-height:1.12;margin:0 0 10px;letter-spacing:0;}"
  "p{font-size:15px;line-height:1.62;color:#c7c7c7;margin:0;}"
  ".port{min-width:132px;text-align:right;}"
  ".port .label{color:#a3a3a3;font-size:12px;font-weight:800;text-transform:uppercase;letter-spacing:.07em;}"
  ".port .number{font-size:34px;font-weight:900;margin-top:4px;color:#fff;}"
  ".grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin-top:22px;}"
  ".item{border:1px solid #262626;border-radius:8px;padding:15px;background:#111;color:#e5e5e5;text-decoration:none;min-height:92px;}"
  ".item:hover{border-color:#3b82f6;background:#121826;}"
  ".label{display:block;font-size:12px;color:#a3a3a3;margin-bottom:8px;font-weight:800;text-transform:uppercase;letter-spacing:.07em;}"
  ".value{display:block;font-size:17px;font-weight:850;overflow-wrap:anywhere;}"
  ".cmds{margin-top:18px;display:grid;grid-template-columns:1fr 1fr;gap:12px;}"
  ".cmd{background:#020617;border:1px solid #1f2937;border-radius:8px;padding:13px 14px;color:#e2e8f0;font-family:'SF Mono',Menlo,monospace;font-size:13px;overflow:auto;white-space:nowrap;}"
  ".note{margin-top:18px;font-size:13px;color:#8b8b8b;}"
  "@media(max-width:720px){main{padding:28px 14px}.top,.headline{display:block}.status{margin-top:14px}.panel{padding:20px}.port{text-align:left;margin-top:18px}.grid,.cmds{grid-template-columns:1fr}h1{font-size:28px}}"
  "</style>"
  "</head>"
  "<body>"
  "<main>"
  "<div class=\"top\"><div><div class=\"brand\">iVista WebDriverAgent</div><div class=\"sub\">Local control bridge for Simulator and iPhone automation</div></div><div class=\"status\"><span class=\"dot\"></span>Connected</div></div>"
  "<section class=\"panel\">"
  "<div class=\"headline\"><div>"
  "<p class=\"eyebrow\">Ready</p>"
  "<h1>WDA is running</h1>"
  "<p>This device is ready for iVista commands. Keep the WDA process alive while the Mac captures screenshots, reads accessibility text, and performs gestures.</p>"
  "</div><div class=\"port\"><div class=\"label\">Port</div><div class=\"number\">$PORT</div></div></div>"
  "<div class=\"grid\">"
  "<div class=\"item\"><span class=\"label\">Connection</span><span class=\"value\">Healthy</span></div>"
  "<a class=\"item\" href=\"/status\"><span class=\"label\">Machine API</span><span class=\"value\">/status</span></a>"
  "<a class=\"item\" href=\"/wda/healthcheck\"><span class=\"label\">Health API</span><span class=\"value\">/wda/healthcheck</span></a>"
  "</div>"
  "<div class=\"cmds\"><div class=\"cmd\">ivista wda status --port $PORT</div><div class=\"cmd\">ivista screen texts --port $PORT</div></div>"
  "<p class=\"note\">The dashboard is for humans. WebDriverAgent JSON endpoints stay raw for iVista, Appium, and other automation clients.</p>"
  "</section>"
  "</main>"
  "</body>"
  "</html>";
  return [page stringByReplacingOccurrencesOfString:@"$PORT" withString:port];
}

@interface FBHTTPConnection : RoutingConnection
@end

@implementation FBHTTPConnection

- (void)handleResourceNotFound
{
  [FBLogger logFmt:@"Received request for %@ which we do not handle", self.requestURI];
  [super handleResourceNotFound];
}

@end


@interface FBWebServer ()
@property (nonatomic, strong) FBExceptionHandler *exceptionHandler;
@property (nonatomic, strong) RoutingHTTPServer *server;
@property (atomic, assign) BOOL keepAlive;
@property (nonatomic, nullable) FBTCPSocket *screenshotsBroadcaster;
@property (nonatomic, nullable, strong) FBMjpegServer *mjpegServer;
@end

@implementation FBWebServer

- (void)dealloc
{
  [self stopScreenshotsBroadcaster];
}

+ (NSArray<Class<FBCommandHandler>> *)collectCommandHandlerClasses
{
  NSArray *handlersClasses = FBClassesThatConformsToProtocol(@protocol(FBCommandHandler));
  NSMutableArray *handlers = [NSMutableArray array];
  for (Class aClass in handlersClasses) {
    if ([aClass respondsToSelector:@selector(shouldRegisterAutomatically)]) {
      if (![aClass shouldRegisterAutomatically]) {
        continue;
      }
    }
    [handlers addObject:aClass];
  }
  return handlers.copy;
}

- (void)startServing
{
  [FBLogger logFmt:@"Built at %s %s", __DATE__, __TIME__];
  self.exceptionHandler = [FBExceptionHandler new];
  if (![self startHTTPServer]) {
    [self runUntilStopped];
    return;
  }
  [self initScreenshotsBroadcaster];

  [self runUntilStopped];
}

- (void)runUntilStopped
{
  self.keepAlive = YES;
  NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
  while (self.keepAlive &&
         [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
}

- (BOOL)startHTTPServer
{
  self.server = [[RoutingHTTPServer alloc] init];
  [self.server setRouteQueue:dispatch_get_main_queue()];
  [self.server setDefaultHeader:@"Server" value:@"WebDriverAgent/1.0"];
  [self.server setDefaultHeader:@"Access-Control-Allow-Origin" value:@"*"];
  [self.server setDefaultHeader:@"Access-Control-Allow-Headers" value:@"Content-Type, X-Requested-With"];
  [self.server setConnectionClass:[FBHTTPConnection self]];

  [self registerRouteHandlers:[self.class collectCommandHandlerClasses]];
  [self registerServerKeyRouteHandlers];

  NSRange serverPortRange = FBConfiguration.bindingPortRange;
  NSString *bindingIP = FBConfiguration.bindingIPAddress;
  if (bindingIP != nil) {
    [self.server setInterface:bindingIP];
    [FBLogger logFmt:@"Using custom binding IP address: %@", bindingIP];
  }

  NSError *error;
  BOOL serverStarted = NO;

  for (NSUInteger index = 0; index < serverPortRange.length; index++) {
    NSInteger port = serverPortRange.location + index;
    [self.server setPort:(UInt16)port];

    serverStarted = [self attemptToStartServer:self.server onPort:port withError:&error];
    if (serverStarted) {
      break;
    }

    [FBLogger logFmt:@"Failed to start web server on port %ld with error %@", (long)port, [error description]];
  }

  if (!serverStarted) {
    [FBLogger logFmt:@"Last attempt to start web server failed with error %@", [error description]];
    NSDictionary *userInfo = @{
      @"error": error.localizedDescription ?: error.description ?: @"WebDriverAgent could not start",
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:IvistaWDAServerDidFailNotification object:self userInfo:userInfo];
    return NO;
  }

  NSString *serverHost = bindingIP ?: ([XCUIDevice sharedDevice].fb_wifiIPAddress ?: @"127.0.0.1");
  NSString *serverURL = [NSString stringWithFormat:@"http://%@:%d", serverHost, [self.server port]];
  [FBLogger logFmt:@"%@%@%@", FBServerURLBeginMarker, serverURL, FBServerURLEndMarker];
  [[NSNotificationCenter defaultCenter] postNotificationName:IvistaWDAServerDidStartNotification
                                                      object:self
                                                    userInfo:@{@"url": serverURL}];
  return YES;
}

- (void)initScreenshotsBroadcaster
{
  [self readMjpegSettingsFromEnv];
  self.mjpegServer = [[FBMjpegServer alloc] init];
  self.screenshotsBroadcaster = [[FBTCPSocket alloc]
                                 initWithPort:(uint16_t)FBConfiguration.mjpegServerPort];
  self.screenshotsBroadcaster.delegate = self.mjpegServer;
  NSError *error;
  if (![self.screenshotsBroadcaster startWithError:&error]) {
    [FBLogger logFmt:@"Cannot init screenshots broadcaster service on port %@. Original error: %@", @(FBConfiguration.mjpegServerPort), error.description];
    [self.mjpegServer stopStreaming];
    self.mjpegServer = nil;
    self.screenshotsBroadcaster = nil;
  }
}

- (void)stopScreenshotsBroadcaster
{
  if (nil == self.screenshotsBroadcaster) {
    self.mjpegServer = nil;
    return;
  }

  id<FBTCPSocketDelegate> delegate = self.screenshotsBroadcaster.delegate;
  if ([(NSObject *)delegate respondsToSelector:@selector(stopStreaming)]) {
    [(FBMjpegServer *)delegate stopStreaming];
  }
  self.screenshotsBroadcaster.delegate = nil;
  [self.screenshotsBroadcaster stop];
  self.screenshotsBroadcaster = nil;
  self.mjpegServer = nil;
}

- (void)readMjpegSettingsFromEnv
{
  NSDictionary *env = NSProcessInfo.processInfo.environment;
  NSString *scalingFactor = [env objectForKey:@"MJPEG_SCALING_FACTOR"];
  if (scalingFactor != nil && [scalingFactor length] > 0) {
    [FBConfiguration setMjpegScalingFactor:[scalingFactor floatValue]];
  }
  NSString *screenshotQuality = [env objectForKey:@"MJPEG_SERVER_SCREENSHOT_QUALITY"];
  if (screenshotQuality != nil && [screenshotQuality length] > 0) {
    [FBConfiguration setMjpegServerScreenshotQuality:[screenshotQuality integerValue]];
  }
}

- (void)stopServing
{
  [FBSession.activeSession kill];
  [self stopScreenshotsBroadcaster];
  if (self.server.isRunning) {
    [self.server stop:NO];
  }
  self.server = nil;
  self.exceptionHandler = nil;
  self.keepAlive = NO;
}

- (BOOL)attemptToStartServer:(RoutingHTTPServer *)server onPort:(NSInteger)port withError:(NSError **)error
{
  server.port = (UInt16)port;
  NSError *innerError = nil;
  BOOL started = [server start:&innerError];
  if (!started) {
    if (!error) {
      return NO;
    }

    NSString *description = @"Unknown Error when Starting server";
    if ([innerError.domain isEqualToString:NSPOSIXErrorDomain] && innerError.code == EADDRINUSE) {
      description = [NSString stringWithFormat:@"Unable to start web server on port %ld", (long)port];
    }
    return
    [[[[FBErrorBuilder builder]
       withDescription:description]
      withInnerError:innerError]
     buildError:error];
  }
  return YES;
}

- (void)registerRouteHandlers:(NSArray *)commandHandlerClasses
{
  __weak typeof(self) weakSelf = self;
  for (Class<FBCommandHandler> commandHandler in commandHandlerClasses) {
    NSArray *routes = [commandHandler routes];
    for (FBRoute *route in routes) {
      [self.server handleMethod:route.verb withPath:route.path block:^(RouteRequest *request, RouteResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (nil == strongSelf) {
          return;
        }
        NSDictionary *arguments = [NSJSONSerialization JSONObjectWithData:request.body options:NSJSONReadingMutableContainers error:NULL];
        FBRouteRequest *routeParams = [FBRouteRequest
          routeRequestWithURL:request.url
          parameters:request.params
          arguments:arguments ?: @{}
        ];

        [FBLogger verboseLog:routeParams.description];

        @try {
          [route mountRequest:routeParams intoResponse:response];
        }
        @catch (NSException *exception) {
          [strongSelf handleException:exception forResponse:response];
        }
      }];
    }
  }
}

- (void)handleException:(NSException *)exception forResponse:(RouteResponse *)response
{
  [self.exceptionHandler handleException:exception forResponse:response];
}

- (void)registerServerKeyRouteHandlers
{
  [self.server get:@"/" withBlock:^(RouteRequest *request, RouteResponse *response) {
    NSString *port = NSProcessInfo.processInfo.environment[@"USE_PORT"] ?: @"8100";
    [response setHeader:@"Content-Type" value:@"text/html;charset=UTF-8"];
    [response respondWithString:IvistaHTMLPage(port)];
  }];

  [self.server get:@"/health" withBlock:^(RouteRequest *request, RouteResponse *response) {
    NSString *port = NSProcessInfo.processInfo.environment[@"USE_PORT"] ?: @"8100";
    [response setHeader:@"Content-Type" value:@"text/html;charset=UTF-8"];
    [response respondWithString:IvistaHTMLPage(port)];
  }];

  NSString *calibrationPage = @"<html>"
  "<title>{\"x\":null,\"y\":null}</title>"
  "<header>"
  "<script>document.addEventListener(\"click\",function(e){document.title=JSON.stringify({x:e.clientX,y:e.clientY})})</script>"
  "</header>"
  "</html>";
  [self.server get:@"/calibrate" withBlock:^(RouteRequest *request, RouteResponse *response) {
    [response respondWithString:calibrationPage];
  }];

  __weak typeof(self) weakSelf = self;
  [self.server get:@"/wda/shutdown" withBlock:^(RouteRequest *request, RouteResponse *response) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (nil == strongSelf) {
      return;
    }
    [response respondWithString:@"Shutting down"];
    [strongSelf.delegate webServerDidRequestShutdown:strongSelf];
  }];

  [self registerRouteHandlers:@[FBUnknownCommands.class]];
}

@end
