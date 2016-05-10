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

#import "LMGCDAsyncSocketReadOperation.h"

@interface LMGCDAsyncSocketReadOperation ()

@property (nonatomic, assign, readwrite) NSUInteger tag;
@property (nonatomic, strong, readwrite) NSMutableData* buffer;
@property (nonatomic, assign, readwrite) NSUInteger initialBufferLength;


@end

@implementation LMGCDAsyncSocketReadOperation

- (id)_initWithBuffer:(NSMutableData*)buffer tag:(NSUInteger)tag
{
    self = [self init];
    if (self) {
        self.buffer = buffer ?: [NSMutableData data];
        self.initialBufferLength = [buffer length];
        self.tag = tag;
    }
    return self;
}

- (BOOL)completeOperationWithPrebuffer:(NSMutableData*)prebuffer completionType:(LMGCDAsyncSocketReadOperationCompletionType)completionType
{
    NSAssert(NO, @"This is an abstract class");
    return NO;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"%@ (%p)", NSStringFromClass([self class]), self];
}

@end
