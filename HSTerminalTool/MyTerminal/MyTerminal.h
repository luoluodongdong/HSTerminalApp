//
//  MyTerminal.h
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/22.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MyTerminal : NSObject

-(BOOL)startTerminal;
-(void)writeCommand:(NSData *)cmd;
-(void)stopTerminal;

@end

NS_ASSUME_NONNULL_END
