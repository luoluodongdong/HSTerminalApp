//
//  HSsimplePTY.h
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/22.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol HSsimplePTYDelegate <NSObject>

- (void)receiveStandardInData:(NSString *)str;
- (void)receiveStandardOutData:(NSString *)str;
- (void)receiveStandardErrorData:(NSString *)str;
 
@end

@interface HSsimplePTY : NSObject

@property (weak) id<HSsimplePTYDelegate> delegate;
-(BOOL)setWinWidth:(int )width height:(int )height;
-(BOOL)startTerminal;
-(void)writeCommand:(NSString *)cmd;
-(void)stopTerminal;

@end

NS_ASSUME_NONNULL_END
