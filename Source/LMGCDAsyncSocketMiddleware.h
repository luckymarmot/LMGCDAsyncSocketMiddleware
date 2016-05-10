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

#import <Foundation/Foundation.h>

@class LMGCDAsyncSocketMiddleware;
@class GCDAsyncSocket;

@protocol LMGCDAsyncSocketMiddlewareDelegate <NSObject>

// Did Resolve DNS
- (void)socketMiddleware:(LMGCDAsyncSocketMiddleware*)sock didResolveHostnameWithIPv4Address:(NSString*)IPv4Address IPv6Address:(NSString*)IPv6Address;

// Did Connect
- (void)socketMiddleware:(LMGCDAsyncSocketMiddleware*)sock didConnectToHost:(NSString*)host port:(uint16_t)port address:(NSString*)address;

// Did Receive Trust
- (void)socketMiddlewareDidSecure:(LMGCDAsyncSocketMiddleware*)sock didReceiveTrust:(SecTrustRef)trust completionHandler:(void (^)(BOOL))completionHandler;

// Did Secure
- (void)socketMiddlewareDidSecure:(LMGCDAsyncSocketMiddleware*)sock;

// Did Write
- (void)socketMiddleware:(LMGCDAsyncSocketMiddleware*)sock didWriteDataWithTag:(long)tag;

// Did Read
- (void)socketMiddleware:(LMGCDAsyncSocketMiddleware*)sock didReadDataToBuffer:(NSData*)data rangeRead:(NSRange)rangeRead withTag:(long)tag;
- (void)socketMiddleware:(LMGCDAsyncSocketMiddleware*)sock didReadPartialDataOfLength:(NSUInteger)partialLength totalBytesRead:(NSUInteger)totalBytesRead tag:(long)tag;

// Did Disconnect
- (void)socketMiddlewareDidDisconnect:(LMGCDAsyncSocketMiddleware*)sock withError:(NSError*)error;

@end

@interface LMGCDAsyncSocketMiddleware : NSObject

// Init
- (id)initWithDelegate:(id<LMGCDAsyncSocketMiddlewareDelegate>)delegate delegateQueue:(dispatch_queue_t)delegateQueue;

// Connection
- (BOOL)connectToHost:(NSString*)host onPort:(uint16_t)port error:(NSError**)errPtr;
- (void)startTLS:(NSDictionary*)tlsSettings;

// Read
- (void)readDataToData:(NSData*)data buffer:(NSMutableData*)buffer tag:(NSUInteger)tag;
- (void)readDataToLength:(NSUInteger)length buffer:(NSMutableData*)buffer tag:(NSUInteger)tag;
- (void)readDataUntilCloseWithBuffer:(NSMutableData*)buffer tag:(NSUInteger)tag;

// Write
- (void)writeData:(NSData*)data tag:(NSUInteger)tag;

// Disconnection
- (void)clearDelegateAndDisconnect;

@property (nonatomic, weak) id<LMGCDAsyncSocketMiddlewareDelegate> delegate;
@property (nonatomic, strong, readonly) GCDAsyncSocket* socketIPv4;
@property (nonatomic, strong, readonly) GCDAsyncSocket* socketIPv6;

+ (NSData*)CRLFData;
+ (NSData*)CRLFCRLFData;

@end
