//
//  HSTerminalPTY.h
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/21.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol HSTerminalStreamListener <NSObject>

- (void)receiveStandardInData:(NSString *)str;
- (void)receiveStandardOutData:(NSString *)str;
- (void)receiveStandardErrorData:(NSString *)str;
 
@end

@interface HSTerminalPTY : NSObject
-(BOOL)launchMyPTY:(NSError **)err;
-(BOOL)connectPTYClosedHandler:(void (^)(NSError *))closed_handler error:(NSError **)err;
-(void)disconnectPTY;
-(BOOL)sendMessage:(NSString *)message;

@property (weak) id<HSTerminalStreamListener> ptyListener; /* listeners to receive raw stdout and stderr data */
//Path to where the telnet binary is
@property (strong) NSString *launchPath;

@end

NS_ASSUME_NONNULL_END
