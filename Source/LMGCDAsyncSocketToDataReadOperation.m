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

#import "LMGCDAsyncSocketToDataReadOperation.h"

@interface LMGCDAsyncSocketToDataReadOperation ()

@property (nonatomic, strong, readwrite) NSData* toData;

@end

@implementation LMGCDAsyncSocketToDataReadOperation

- (id)initWithData:(NSData*)data buffer:(NSMutableData*)buffer tag:(NSUInteger)tag
{
    self = [self _initWithBuffer:buffer tag:tag];
    if (self) {
        self.toData = data;
    }
    return self;
}

- (BOOL)completeOperationWithPrebuffer:(NSMutableData*)prebuffer completionType:(LMGCDAsyncSocketReadOperationCompletionType)completionType
{
    NSRange range = [prebuffer rangeOfData:self.toData options:kNilOptions range:NSMakeRange(0, [prebuffer length])];
    NSRange dataRange = NSMakeRange(0, range.location + range.length);

    // If toData not found, we can't complete for now
    if (range.location != NSNotFound) {
        // Append the necessary data to our buffer
        [self.buffer appendBytes:[prebuffer bytes] length:dataRange.length];

        // Remove this data from prebuffer
        [prebuffer replaceBytesInRange:dataRange withBytes:NULL length:0];

        return YES;
    }
    else {
        return NO;
    }
}

@end
