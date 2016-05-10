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

#import "LMGCDAsyncSocketToLengthReadOperation.h"

@interface LMGCDAsyncSocketToLengthReadOperation ()

@property (nonatomic, assign, readwrite) NSUInteger toLength;

@end

@implementation LMGCDAsyncSocketToLengthReadOperation

- (id)initWithLength:(NSUInteger)length buffer:(NSMutableData*)buffer tag:(NSUInteger)tag
{
    self = [self _initWithBuffer:(buffer ?: [NSMutableData dataWithCapacity:length]) tag:tag];
    if (self) {
        self.toLength = length;
    }
    return self;
}

- (BOOL)completeOperationWithPrebuffer:(NSMutableData*)prebuffer completionType:(LMGCDAsyncSocketReadOperationCompletionType)completionType
{
    // If enough data in prebuffer
    if ([prebuffer length] >= self.toLength) {
        // Append the necessary data to our buffer
        [self.buffer appendBytes:[prebuffer bytes] length:self.toLength];

        // Remove this data from prebuffer
        [prebuffer replaceBytesInRange:NSMakeRange(0, self.toLength) withBytes:NULL length:0];

        return YES;
    }
    // If not enough data, we can't complete for now
    else {
        return NO;
    }
}

@end
