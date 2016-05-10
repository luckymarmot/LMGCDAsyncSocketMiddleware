//
//  LMGCDAsyncSocketMiddleware.h
//  Paw
//
// Copyright (c) 2016 Paw Inc.
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

#import "LMGCDAsyncSocketMiddleware.h"

#import "GCDAsyncSocket.h"

#import "LMGCDAsyncSocketToDataReadOperation.h"
#import "LMGCDAsyncSocketToLengthReadOperation.h"
#import "LMGCDAsyncSocketToEOFReadOperation.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netdb.h>

#define LMGCDAsyncSocketMiddlewareNoTimeout                 (-1)
#define LMGCDAsyncSocketMiddlewareEyeBallsUncachedDelay   0.300f
#define LMGCDAsyncSocketMiddlewareEyeBallsCachedDelay     2.000f


// Logging
#import "DDLog.h"

#define LogAsync   YES
#define LogContext GCDAsyncSocketLoggingContext

#define LogObjc(flg, frmt, ...) LOG_OBJC_MAYBE(LogAsync, logLevel, flg, LogContext, frmt, ##__VA_ARGS__)
#define LogC(flg, frmt, ...)    LOG_C_MAYBE(LogAsync, logLevel, flg, LogContext, frmt, ##__VA_ARGS__)

#define LogError(frmt, ...)     LogObjc(LOG_FLAG_ERROR,   (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define LogWarn(frmt, ...)      LogObjc(LOG_FLAG_WARN,    (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define LogInfo(frmt, ...)      LogObjc(LOG_FLAG_INFO,    (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define LogVerbose(frmt, ...)   LogObjc(LOG_FLAG_VERBOSE, (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)

#define LogCError(frmt, ...)    LogC(LOG_FLAG_ERROR,   (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define LogCWarn(frmt, ...)     LogC(LOG_FLAG_WARN,    (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define LogCInfo(frmt, ...)     LogC(LOG_FLAG_INFO,    (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define LogCVerbose(frmt, ...)  LogC(LOG_FLAG_VERBOSE, (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)

#define LogTrace()              LogObjc(LOG_FLAG_VERBOSE, @"%@: %@", THIS_FILE, THIS_METHOD)
#define LogCTrace()             LogC(LOG_FLAG_VERBOSE, @"%@: %s", THIS_FILE, __FUNCTION__)

static const int logLevel = DDLogLevelWarning;


const char* LMGCDAsyncSocketMiddlewareSocketQueue = "com.luckymarmot.Paw.LMGCDAsyncSocketMiddlewareSocketQueue";
static NSCache* _cachedAddresses;

typedef NS_ENUM (NSUInteger, LMGCDAsyncSocketStatus) {
    // not yet used
    LMGCDAsyncSocketStatusIdle,
    // not connecting, but waiting for eye balls timeout to fire
    LMGCDAsyncSocketStatusWaitingForEyeBallsTimeout,
    // connecting, not yet connected
    LMGCDAsyncSocketStatusConnecting,
    // connected
    LMGCDAsyncSocketStatusConnected,
    // disconnected after a successful connection
    LMGCDAsyncSocketStatusDisconnectedAfterConnect,
    // disconnected after a connection failure
    LMGCDAsyncSocketStatusDisconnectedConnectionFailed,
};

@interface LMGCDAsyncSocketMiddleware () <GCDAsyncSocketDelegate> {
    dispatch_queue_t _socketQueueIPv4;
    dispatch_queue_t _socketQueueIPv6;
    dispatch_queue_t _delegateQueue;
    NSMutableArray* _readOperations; // Accessed only from _delegateQueue (except init)
    NSMutableData* _readPrebuffer; // Accessed only from _delegateQueue (except init)
    void* _delegateQueueSpecificIvar;

    /** Happy Eyeballs algorithm
     *  Used to determine the preferred IP protocol to connect to.
     *  Will try with alternate IP protocol after 300ms (or 2sec if already cached).
     */
    NSString* _requestedHost;
    NSString* _requestedAddress;
    LMGCDAsyncSocketStatus _socketIPv4Status;
    LMGCDAsyncSocketStatus _socketIPv6Status;
    NSData* _alternateAddress;
    uint16_t _port;
}

@property (nonatomic, strong, readwrite) GCDAsyncSocket* socketIPv4;
@property (nonatomic, strong, readwrite) GCDAsyncSocket* socketIPv6;

@end

@implementation LMGCDAsyncSocketMiddleware

#pragma mark - Initialization

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _cachedAddresses = [[NSCache alloc] init];
    });
}

- (id)initWithDelegate:(id<LMGCDAsyncSocketMiddlewareDelegate>)delegate delegateQueue:(dispatch_queue_t)delegateQueue
{
    self = [super init];
    if (self) {
        _readOperations = [NSMutableArray array];
        _readPrebuffer = [NSMutableData data];

        // Socket queues
        _socketQueueIPv4 = dispatch_queue_create(LMGCDAsyncSocketMiddlewareSocketQueue, DISPATCH_QUEUE_SERIAL);
        _socketQueueIPv6 = dispatch_queue_create(LMGCDAsyncSocketMiddlewareSocketQueue, DISPATCH_QUEUE_SERIAL);

        // Delegate queue
        _delegateQueue = delegateQueue;
        _delegateQueueSpecificIvar = &_delegateQueueSpecificIvar; // Idea taken from GCDAsyncSocket
        dispatch_queue_set_specific(_delegateQueue, _delegateQueueSpecificIvar, _delegateQueueSpecificIvar, NULL);

        // Delegate
        _delegate = delegate;

        // Sockets
        _socketIPv4 = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_delegateQueue socketQueue:_socketQueueIPv4];
        _socketIPv4.IPv4Enabled = YES;
        _socketIPv4.IPv6Enabled = NO;
        _socketIPv6 = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_delegateQueue socketQueue:_socketQueueIPv6];
        _socketIPv6.IPv4Enabled = NO;
        _socketIPv6.IPv6Enabled = YES;

        // Status
        _socketIPv4Status = LMGCDAsyncSocketStatusIdle;
        _socketIPv6Status = LMGCDAsyncSocketStatusIdle;

        // Address & Port
        _alternateAddress = nil;
        _port = 0;
    }
    return self;
}

#pragma mark - Connection

+ (BOOL)_lookupHost:(NSString*)host port:(uint16_t)port IPv4Address:(NSData* __autoreleasing*)__IPv4Address IPv6Address:(NSData* __autoreleasing*)__IPv6Address error:(NSError* __autoreleasing*)__error
{
    /* Perform DNS Lookup
     * This is the only DNS Lookup performed as next connects are done directly
     * on the remote host's IP address.
     */
    NSData* IPv4Address = nil;
    NSData* IPv6Address = nil;
    NSArray* addresses = [GCDAsyncSocket lookupHost:host port:port error:__error];
    if (addresses == nil) {
        return NO;
    }

    // Determine IP protocol addresses
    for (NSData* address in addresses) {
        // IPv4
        if (IPv4Address == nil && [GCDAsyncSocket isIPv4Address:address]) {
            IPv4Address = address;
        }
        // IPv6
        else if (IPv6Address == nil && [GCDAsyncSocket isIPv6Address:address]) {
            IPv6Address = address;
        }
        // if found all, break
        if (IPv4Address != nil && IPv6Address != nil) {
            break;
        }
    }

    *__IPv4Address = IPv4Address;
    *__IPv6Address = IPv6Address;

    return YES;
}

- (BOOL)_connectToAddress:(NSData*)address port:(uint16_t)port error:(NSError**)__error
{
    GCDAsyncSocket* socket;
    if ([GCDAsyncSocket isIPv4Address:address]) {
        socket = _socketIPv4;
        _socketIPv4Status = LMGCDAsyncSocketStatusConnecting;
    }
    else {
        socket = _socketIPv6;
        _socketIPv6Status = LMGCDAsyncSocketStatusConnecting;
    }
    return [socket connectToHost:[GCDAsyncSocket hostFromAddress:address] onPort:port withTimeout:LMGCDAsyncSocketMiddlewareNoTimeout error:__error];
}

- (void)_connectToAlternateAddress
{
    BOOL shouldConnect;
    if ([GCDAsyncSocket isIPv4Address:_alternateAddress]) {
        shouldConnect = (_socketIPv4Status == LMGCDAsyncSocketStatusWaitingForEyeBallsTimeout &&
                         (_socketIPv6Status == LMGCDAsyncSocketStatusConnecting ||
                          _socketIPv6Status == LMGCDAsyncSocketStatusDisconnectedConnectionFailed));
    }
    else {
        shouldConnect = (_socketIPv6Status == LMGCDAsyncSocketStatusWaitingForEyeBallsTimeout &&
                         (_socketIPv4Status == LMGCDAsyncSocketStatusConnecting ||
                          _socketIPv4Status == LMGCDAsyncSocketStatusDisconnectedConnectionFailed));
    }

    // if we still got no response yet, retry with 2nd address
    if (shouldConnect) {
        LogInfo(@"No response on preferred address ~> trying '%@'...", [GCDAsyncSocket hostFromAddress:_alternateAddress]);

        /* connect to the alternate socket, if connected or
         * disconnected (cancelled) before, this will be nil and
         * safely be ignored */
        if (![self _connectToAddress:_alternateAddress port:_port error:NULL]) {
            // TODO: fail and disconnect...
        }
    }
}

- (void)_connectToAlternateAddressAfterDelay:(NSTimeInterval)eyeBallsDelay
{
    if ([GCDAsyncSocket isIPv4Address:_alternateAddress]) {
        _socketIPv4Status = LMGCDAsyncSocketStatusWaitingForEyeBallsTimeout;
    }
    else {
        _socketIPv6Status = LMGCDAsyncSocketStatusWaitingForEyeBallsTimeout;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(eyeBallsDelay * NSEC_PER_SEC)), _delegateQueue, ^{
        [self _connectToAlternateAddress];
    });
}

- (BOOL)connectToHost:(NSString*)host onPort:(uint16_t)port error:(NSError* __autoreleasing*)__error
{
    LogInfo(@"Connect to Host: %@ port: %d", host, port);

    // Perform DNS Lookup
    NSData* IPv4Address = nil;
    NSData* IPv6Address = nil;
    if (![LMGCDAsyncSocketMiddleware _lookupHost:host port:port IPv4Address:&IPv4Address IPv6Address:&IPv6Address error:__error]) {
        return NO;
    }

    // Call delegate after DNS lookup
    [self.delegate socketMiddleware:self didResolveHostnameWithIPv4Address:[GCDAsyncSocket hostFromAddress:IPv4Address] IPv6Address:[GCDAsyncSocket hostFromAddress:IPv6Address]];

    // Keep original request address (cache key)
    _requestedAddress = [NSString stringWithFormat:@"%@:%d", host, port];
    _requestedHost = [host copy];
    _port = port;

    // Determine preferred IP protocol address
    NSData* preferredAddress = nil;
    NSTimeInterval eyeBallsDelay = LMGCDAsyncSocketMiddlewareEyeBallsUncachedDelay;
    if (IPv4Address != nil && IPv6Address != nil) {
        // only check cache if there are multiple IP protocol options
        preferredAddress = [_cachedAddresses objectForKey:_requestedAddress];
        if (preferredAddress != nil) {
            if ([GCDAsyncSocket hostFromAddress:preferredAddress] != nil) {
                eyeBallsDelay = LMGCDAsyncSocketMiddlewareEyeBallsCachedDelay;
                LogInfo(@"Multiple addresses available (preferred from cache: %@)", [GCDAsyncSocket hostFromAddress:preferredAddress]);
            }
            else {
                LogInfo(@"Preferred address is cached, but it's invalid - discarding it.");
                preferredAddress = nil;
            }
        }
    }
    if (preferredAddress == nil) {
        preferredAddress = IPv4Address != nil ? IPv4Address : IPv6Address;
        LogInfo(@"%@ address(es) available (preferred: %@)", ((IPv4Address != nil && IPv6Address != nil) ? @"Multiple" : @"One"), [GCDAsyncSocket hostFromAddress:preferredAddress]);
    }

    // Connect to 2nd address, after delay
    if (IPv4Address != nil && IPv6Address != nil) {
        _alternateAddress = [GCDAsyncSocket isIPv4Address:preferredAddress] ? IPv6Address : IPv4Address;
        [self _connectToAlternateAddressAfterDelay:eyeBallsDelay];
    }

    // Connect to 1st address
    return [self _connectToAddress:preferredAddress port:port error:__error];
}

- (void)startTLS:(NSDictionary*)tlsSettings
{
    LogTrace();

    [(_socketIPv4 ?: _socketIPv6) startTLS:tlsSettings];
}

#pragma mark - Read

// Must be called on _delegateQueue
- (void)_processRead:(NSInteger)newDataLength completionType:(LMGCDAsyncSocketReadOperationCompletionType)completionType
{
    // Until we have both data in prebuffer and read operations pending
    while ([_readPrebuffer length] > 0 && [_readOperations count] > 0) {
        LMGCDAsyncSocketReadOperation* readOperation = [_readOperations firstObject];
        BOOL completed = [readOperation completeOperationWithPrebuffer:_readPrebuffer completionType:completionType];
        NSRange rangeReadInBuffer = NSMakeRange(readOperation.initialBufferLength, [readOperation.buffer length] - readOperation.initialBufferLength);

        // If completed, call delegate remove read operation
        if (completed) {
            LogVerbose(@"Completed Read Operation: %@", readOperation);

            // Remove Read Operation (Must be before we call the delegate)
            [_readOperations removeObjectAtIndex:0];

            // Call Delegate
            [self.delegate socketMiddleware:self didReadDataToBuffer:readOperation.buffer rangeRead:rangeReadInBuffer withTag:readOperation.tag];
        }
        // If not completed, read more
        else {
            LogVerbose(@"Read Operation Not Yet Completed: %@", NSStringFromClass([readOperation class]));

            // Call Delegate if New Data
            if (newDataLength >= 0) {
                [self.delegate socketMiddleware:self didReadPartialDataOfLength:newDataLength totalBytesRead:[_readPrebuffer length] tag:readOperation.tag];
            }

            break;
        }
    }

    // If read operations are still available, we need to read more
    if (_readOperations.count > 0) {
        [(_socketIPv4 ?: _socketIPv6) readDataWithTimeout:LMGCDAsyncSocketMiddlewareNoTimeout tag:0];
    }
}

// Can be called from any queue
- (void)_runOnDelegateQueue:(dispatch_block_t)block
{
    // Run on _delegateQueue no matter what
    if (dispatch_get_specific(_delegateQueueSpecificIvar) != NULL) {
        LogVerbose(@"Run Block directly on Delegate Queue");
        block();
    }
    else {
        LogVerbose(@"Run Block synchronously on Delegate Queue");
        dispatch_sync(_delegateQueue, block);
    }
}

- (void)readDataToData:(NSData*)data buffer:(NSMutableData*)buffer tag:(NSUInteger)tag
{
    LogVerbose(@"Queue Read-To-Data (buffer length: %@)", buffer ? @([buffer length]) : @"no buffer");

    LMGCDAsyncSocketReadOperation* readOperation = [[LMGCDAsyncSocketToDataReadOperation alloc] initWithData:data buffer:buffer tag:tag];

    [self _runOnDelegateQueue:^{
        [_readOperations addObject:readOperation];
        [self _processRead:(-1) completionType:LMGCDAsyncSocketReadOperationCompletionTypeAddReadOperation];
    }];
}

- (void)readDataToLength:(NSUInteger)length buffer:(NSMutableData*)buffer tag:(NSUInteger)tag
{
    LogVerbose(@"Queue Read-To-Length: %ld (buffer length: %@)", length, buffer ? @([buffer length]) : @"no buffer");

    LMGCDAsyncSocketReadOperation* readOperation = [[LMGCDAsyncSocketToLengthReadOperation alloc] initWithLength:length buffer:buffer tag:tag];

    [self _runOnDelegateQueue:^{
        [_readOperations addObject:readOperation];
        [self _processRead:(-1) completionType:LMGCDAsyncSocketReadOperationCompletionTypeAddReadOperation];
    }];
}

- (void)readDataUntilCloseWithBuffer:(NSMutableData*)buffer tag:(NSUInteger)tag
{
    LogVerbose(@"Queue Read-To-EOF (buffer length: %@)", buffer ? @([buffer length]) : @"no buffer");

    LMGCDAsyncSocketReadOperation* readOperation = [[LMGCDAsyncSocketToEOFReadOperation alloc] initWithBuffer:buffer tag:tag];

    [self _runOnDelegateQueue:^{
        [_readOperations addObject:readOperation];
        [self _processRead:(-1) completionType:LMGCDAsyncSocketReadOperationCompletionTypeAddReadOperation];
    }];
}

#pragma mark - Write

- (void)writeData:(NSData*)data tag:(NSUInteger)tag
{
    LogVerbose(@"Write data length: %ld tag: %ld", [data length], tag);

    [(_socketIPv4 ?: _socketIPv6) writeData:data withTimeout:LMGCDAsyncSocketMiddlewareNoTimeout tag:tag];
}

#pragma mark - Disconnection

- (void)clearDelegateAndDisconnect
{
    LogTrace();

    _delegate = nil;
    _delegateQueue = NULL;
    _socketQueueIPv4 = NULL;
    _socketQueueIPv6 = NULL;

    [_socketIPv4 setDelegate:nil delegateQueue:NULL];
    [_socketIPv4 disconnect];
    _socketIPv4 = nil;
    [_socketIPv6 setDelegate:nil delegateQueue:NULL];
    [_socketIPv6 disconnect];
    _socketIPv6 = nil;
}

#pragma mark - Helpers

+ (NSData*)CRLFData
{
    return [GCDAsyncSocket CRLFData];
}

+ (NSData*)CRLFCRLFData
{
    return [NSData dataWithBytes:"\r\n\r\n" length:4];
}

- (NSData*)_addressDataFromHost:(NSString*)host port:(uint16_t)port
{
    if (host == nil) {
        return nil;
    }

    // hostname
    const char* hostChars = [host UTF8String];

    // struct sockaddr_in (IPv4)
    struct sockaddr_in dst;
    BOOL isIPv4 = inet_pton(AF_INET, hostChars, &dst.sin_addr) == 1;
    if (isIPv4) {
        dst.sin_family = AF_INET;
        dst.sin_len = sizeof(dst);
        dst.sin_port = htons(port);
        return [NSData dataWithBytes:&dst length:sizeof(dst)];
    }
    // struct sockaddr_in6 (IPv6)
    else {
        struct sockaddr_in6 dst6;
        memset((char*)&dst6, 0, sizeof(dst6));
        BOOL isIPv6 = inet_pton(AF_INET6, hostChars, &dst6.sin6_addr) == 1;
        if (isIPv6) {
            dst6.sin6_family = AF_INET6;
            dst6.sin6_len = sizeof(dst6);
            dst6.sin6_port = htons(port);

            return [NSData dataWithBytes:&dst6 length:sizeof(dst6)];
        }
    }

    return nil;
}

+ (void)disconnectSocket:(GCDAsyncSocket*)socket onQueue:(dispatch_queue_t)queue
{
    dispatch_async(queue, ^{
        [socket setDelegate:nil delegateQueue:NULL];
        [socket disconnect];
        LogVerbose(@"Disconnected unused socket");
    });
}

#pragma mark - GCDAsyncSocketDelegate

// All Delegate Methods are called on _delegateQueue

- (void)socket:(GCDAsyncSocket*)sock didConnectToHost:(NSString*)host port:(uint16_t)port
{
    LogVerbose(@"socket:didConnectToHost:%@ port:%d", host, port);

    BOOL didConnect = NO;

    if (sock == _socketIPv4 &&
        _socketIPv4Status == LMGCDAsyncSocketStatusConnecting &&
        _socketIPv6Status != LMGCDAsyncSocketStatusConnected &&
        _socketIPv6Status != LMGCDAsyncSocketStatusDisconnectedAfterConnect) {
        LogInfo(@"Connected to %@ with IPv4 socket", host);
        _socketIPv4Status = LMGCDAsyncSocketStatusConnected;
        didConnect = YES;

        if (_socketIPv6Status != LMGCDAsyncSocketStatusIdle) {
            // disconnect IPv6 asynchronously
            _socketIPv6Status = LMGCDAsyncSocketStatusDisconnectedConnectionFailed;
            [LMGCDAsyncSocketMiddleware disconnectSocket:_socketIPv6 onQueue:_socketQueueIPv6];
            _socketQueueIPv6 = NULL;
            _socketIPv6 = nil;
        }
    }
    else if (sock == _socketIPv6 &&
             _socketIPv6Status == LMGCDAsyncSocketStatusConnecting &&
             _socketIPv4Status != LMGCDAsyncSocketStatusConnected &&
             _socketIPv4Status != LMGCDAsyncSocketStatusDisconnectedAfterConnect) {
        LogInfo(@"Connected to %@ with IPv6 socket", host);
        _socketIPv6Status = LMGCDAsyncSocketStatusConnected;
        didConnect = YES;

        if (_socketIPv4Status != LMGCDAsyncSocketStatusIdle) {
            // disconnect IPv4 asynchronously
            _socketIPv4Status = LMGCDAsyncSocketStatusDisconnectedConnectionFailed;
            [LMGCDAsyncSocketMiddleware disconnectSocket:_socketIPv4 onQueue:_socketQueueIPv4];
            _socketQueueIPv4 = NULL;
            _socketIPv4 = nil;
        }
    }

    // Procceed if not connected yet
    if (didConnect) {
        // Cache the address that responded as preferred
        [_cachedAddresses setObject:[self _addressDataFromHost:host port:port] forKey:_requestedAddress];

        // Call delegate
        [self.delegate socketMiddleware:self didConnectToHost:_requestedHost port:port address:host];
    }
}

- (void)socket:(GCDAsyncSocket*)sock didReceiveTrust:(SecTrustRef)trust completionHandler:(void (^)(BOOL))completionHandler
{
    [self.delegate socketMiddlewareDidSecure:self didReceiveTrust:trust completionHandler:completionHandler];
}

- (void)socketDidSecure:(GCDAsyncSocket*)sock
{
    [self.delegate socketMiddlewareDidSecure:self];
}

- (void)socket:(GCDAsyncSocket*)sock didReadData:(NSData*)data withTag:(long)tag
{
    LogVerbose(@"Received Data from Socket (length: %ld)", [data length]);

    [_readPrebuffer appendData:data];
    [self _processRead:[data length] completionType:LMGCDAsyncSocketReadOperationCompletionTypeRead];
}

- (void)socket:(GCDAsyncSocket*)sock didWriteDataWithTag:(long)tag
{
    [self.delegate socketMiddleware:self didWriteDataWithTag:tag];
}

- (void)socketDidDisconnect:(GCDAsyncSocket*)sock withError:(NSError*)err
{
    BOOL isConnectionClosed = NO;

    if (sock == _socketIPv4) {
        if (_socketIPv4Status == LMGCDAsyncSocketStatusConnected) {
            LogVerbose(@"[IPv4] Remote server closed the connection: %@", err.localizedDescription);
            _socketIPv4Status = LMGCDAsyncSocketStatusDisconnectedAfterConnect;
        }
        else if (_socketIPv4Status != LMGCDAsyncSocketStatusIdle) {
            LogVerbose(@"[IPv4] Couldn't connect to the server: %@", err.localizedDescription);
            _socketIPv4Status = LMGCDAsyncSocketStatusDisconnectedConnectionFailed;
        }

        // if IPv6 is hopeless (either idle or already failed)
        isConnectionClosed = (_socketIPv6Status == LMGCDAsyncSocketStatusIdle ||
                              _socketIPv6Status == LMGCDAsyncSocketStatusDisconnectedConnectionFailed);
    }
    else {
        if (_socketIPv6Status == LMGCDAsyncSocketStatusConnected) {
            LogVerbose(@"[IPv6] Remote server closed the connection: %@", err.localizedDescription);
            _socketIPv6Status = LMGCDAsyncSocketStatusDisconnectedAfterConnect;
        }
        else if (_socketIPv6Status != LMGCDAsyncSocketStatusIdle) {
            LogVerbose(@"[IPv6] Couldn't connect to the server: %@", err.localizedDescription);
            _socketIPv6Status = LMGCDAsyncSocketStatusDisconnectedConnectionFailed;
        }

        // if IPv4 is hopeless (either idle or already failed)
        isConnectionClosed = (_socketIPv4Status == LMGCDAsyncSocketStatusIdle ||
                              _socketIPv4Status == LMGCDAsyncSocketStatusDisconnectedConnectionFailed);
    }

    if (isConnectionClosed) {
        [self _processRead:(-1) completionType:LMGCDAsyncSocketReadOperationCompletionTypeEOF];
        [self.delegate socketMiddlewareDidDisconnect:self withError:err];
    }
    else {
        if (sock == _socketIPv4 && _socketIPv6Status == LMGCDAsyncSocketStatusWaitingForEyeBallsTimeout) {
            [self _connectToAlternateAddress];
        }
        else if (sock == _socketIPv6 && _socketIPv4Status == LMGCDAsyncSocketStatusWaitingForEyeBallsTimeout) {
            [self _connectToAlternateAddress];
        }
    }
}

@end
