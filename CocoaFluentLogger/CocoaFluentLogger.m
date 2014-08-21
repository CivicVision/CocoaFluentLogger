#import "CocoaFluentLogger.h"

#import <MessagePack/MessagePackPacker.h>

@interface CocoaFluentLogger() <NSStreamDelegate>
@property (nonatomic) NSString* tagPrefix;
@property (nonatomic) NSString* host;
@property (nonatomic) NSUInteger port;
@property (nonatomic) NSOutputStream* outputStream;
@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableArray *messageQueue;
@end

static NSUInteger kFluentdDefaultPort = 24224;

@implementation CocoaFluentLogger

+ (id)loggerWithHost:(NSString *)host
{
  return [CocoaFluentLogger loggerWithHost:host port:kFluentdDefaultPort];
}

+ (id)loggerWithHost:(NSString *)host port:(NSUInteger)port
{
  return [CocoaFluentLogger loggerWithHost:host port:port tagPrefix:@""];
}

+ (id)loggerWithHost:(NSString *)host port:(NSUInteger)port tagPrefix:(NSString *)prefix
{
  return [[CocoaFluentLogger alloc] initWithHost:host port:port tagPrefix:prefix];
}

- (id)initWithHost:(NSString *)host
{
  return [self initWithHost:host port:kFluentdDefaultPort];
}

- (id)initWithHost:(NSString *)host port:(NSUInteger)port
{
  return [self initWithHost:host port:port tagPrefix:@""];
}

- (id)initWithHost:(NSString *)host port:(NSUInteger)port tagPrefix:(NSString *)prefix
{
  self = [self init];
  if(self){
    self.tagPrefix = prefix;
    self.host = host;
    self.port = port;
    
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.host, self.port, NULL, &writeStream);
    self.outputStream = CFBridgingRelease(writeStream);
    self.outputStream.delegate = self;
    
    _queue = dispatch_queue_create("so.lai.CocoaFluentLogger", NULL);
  }
  
  return self;
}

- (void)dealloc
{
  if (_queue != NULL) {
		dispatch_release(_queue);
		_queue = NULL;
	}
  
  [self.outputStream close];
}

- (void)connect {
    if([self.outputStream streamStatus] == NSStreamStatusOpen){
        [self sendMessagesInQueue];
        return;
    }
    if ([self.outputStream streamStatus] == NSStreamStatusError) {
        [self.outputStream close];
        [self reconnect];
    }
    [self.outputStream open];
}

- (void)reconnect {
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.host, self.port, NULL, &writeStream);
    self.outputStream = CFBridgingRelease(writeStream);
}

- (void)disConnect {
    [self.outputStream close];
}

- (void)post:(NSString *)tag object:(NSDictionary *)object {
    NSNumber* timeStamp = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]];
    NSData* msg = [MessagePackPacker pack:@[[self.tagPrefix stringByAppendingFormat:@".%@", tag], timeStamp, object]];
    [self sendMessage:msg];
}

- (void)sendMessage: (NSData*)message {
    [self connect];
    dispatch_sync(_queue, ^{
        if(self.outputStream.streamStatus == NSStreamStatusOpen){
            [self.outputStream write:message.bytes maxLength:message.length];
        }else {
            [self appendMessageToQueue: message];
        }
    });
}

- (void)appendMessageToQueue: (NSData*)message {
    [self.messageQueue addObject:message];
}

- (void)sendMessagesInQueue {
    NSArray *queue = [self.messageQueue copy];
    for (NSData *message in queue) {
        [self.messageQueue removeObject:message];
        [self sendMessage:message];
    }
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
    NSLog(@"error %lu",streamEvent);
    [self reconnect];
}

@end
