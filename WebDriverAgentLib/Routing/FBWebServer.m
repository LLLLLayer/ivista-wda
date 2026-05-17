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
  "body{margin:0;min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',sans-serif;background:#050608;color:#f8fafc;}"
  "body:before{content:'';position:fixed;inset:0;background:radial-gradient(circle at 20% 0%,rgba(20,184,166,.18),transparent 30%),radial-gradient(circle at 80% 20%,rgba(59,130,246,.15),transparent 34%);pointer-events:none;}"
  "main{position:relative;max-width:900px;margin:0 auto;padding:56px 24px;}"
  ".top{display:flex;align-items:center;justify-content:space-between;gap:18px;margin-bottom:34px;}"
  ".brand{font-size:15px;font-weight:700;letter-spacing:.02em;color:#d1d5db;}"
  ".pill{display:inline-flex;align-items:center;gap:9px;padding:8px 12px;border:1px solid #1f2937;border-radius:999px;background:#0b0f16;color:#a7f3d0;font-size:13px;font-weight:700;}"
  ".dot{width:9px;height:9px;border-radius:999px;background:#22c55e;box-shadow:0 0 18px #22c55e;}"
  ".hero{border:1px solid #1f2937;background:rgba(10,15,24,.88);border-radius:22px;padding:30px;box-shadow:0 24px 80px rgba(0,0,0,.36);}"
  ".eyebrow{margin:0 0 10px;color:#5eead4;font-size:13px;font-weight:800;text-transform:uppercase;letter-spacing:.08em;}"
  "h1{font-size:38px;line-height:1.08;margin:0 0 14px;letter-spacing:0;}"
  "p{font-size:16px;line-height:1.65;color:#cbd5e1;margin:0;}"
  ".grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin-top:22px;}"
  ".item{display:block;border:1px solid #1f2937;border-radius:14px;padding:16px;background:#070b12;color:#e5e7eb;text-decoration:none;}"
  ".item:hover{border-color:#38bdf8;background:#0b1220;}"
  ".label{display:block;font-size:12px;color:#94a3b8;margin-bottom:6px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;}"
  ".value{font-size:16px;font-weight:800;}"
  ".api{cursor:default;}"
  ".api:hover{border-color:#1f2937;background:#070b12;}"
  ".cmd{margin-top:18px;background:#020617;border:1px solid #1e293b;border-radius:14px;padding:14px 16px;color:#e2e8f0;font-family:'SF Mono',Menlo,monospace;font-size:13px;overflow:auto;}"
  ".note{margin-top:18px;font-size:13px;color:#94a3b8;}"
  "@media(max-width:640px){main{padding:32px 16px}.top{align-items:flex-start;flex-direction:column}.hero{padding:22px}h1{font-size:30px}.grid{grid-template-columns:1fr}}"
  "</style>"
  "</head>"
  "<body>"
  "<main>"
  "<div class=\"top\"><div class=\"brand\">iVista WebDriverAgent</div><div class=\"pill\"><span class=\"dot\"></span>Connected on port $PORT</div></div>"
  "<section class=\"hero\">"
  "<p class=\"eyebrow\">Ready</p>"
  "<h1>iVista WDA is running</h1>"
  "<p>This WebDriverAgent instance is connected and ready for iVista. Keep this process running while the CLI controls the Simulator or iPhone.</p>"
  "<div class=\"grid\">"
  "<div class=\"item api\"><span class=\"label\">Connection</span><span class=\"value\">Healthy</span></div>"
  "<div class=\"item api\"><span class=\"label\">JSON API</span><span class=\"value\">/status</span></div>"
  "<div class=\"item api\"><span class=\"label\">JSON API</span><span class=\"value\">/wda/healthcheck</span></div>"
  "</div>"
  "<div class=\"cmd\">ivista wda status --port $PORT<br>ivista screen texts --port $PORT</div>"
  "<p class=\"note\">This is the only human-facing page. JSON endpoints stay raw for WebDriverAgent clients and iVista CLI compatibility.</p>"
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
