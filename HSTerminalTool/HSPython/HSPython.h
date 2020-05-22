//
//  HSPython.h
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/21.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

@interface HSPython : NSObject
-(NSError*)connectIP:(NSString*)ip port:(NSString*)port;
-(NSError*)disconnect;

/*!
 @brief Sends a command string and gets a response. Handles the transaction-id layer
 */
-(NSString*)send:(NSString*)input withError:(NSError**)err;

@property (readwrite) NSTimeInterval timeout;

@property (readwrite) BOOL isConnected;

@end

NS_ASSUME_NONNULL_END
