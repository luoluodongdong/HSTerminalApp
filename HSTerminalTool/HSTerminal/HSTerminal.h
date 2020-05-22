//
//  HSTerminal.h
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/21.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol HSTerminalStreamListener <NSObject>

- (void)receiveStandardInData:(NSString *)str;
- (void)receiveStandardOutData:(NSString *)str;
- (void)receiveStandardErrorData:(NSString *)str;
 
@end

@interface HSTerminal : NSObject

+ (instancetype)ezTelnetWithURL:(NSURL *)url;
+ (instancetype)ezTelnetWithHost:(NSString *)host port:(unsigned)port;
- (bool)openConnectionWithTimeout:(NSTimeInterval)timeout connectionClosedHandler:(void (^)(NSError *))handler error:(NSError *__autoreleasing *)err;

- (bool)write:(NSString *)str waitForRegexMatch:(NSString *)regex_str timeout:(NSTimeInterval)timeo response:(NSString *__autoreleasing *)response;
- (void)close;

@property (strong) NSString *lineSeparator;                 /* by default is '\n' */
@property (weak) id<HSTerminalStreamListener> telnetListener; /* listeners to receive raw stdout and stderr data */

//Path to where the telnet binary is
@property (strong) NSString *launchPath;

@end

