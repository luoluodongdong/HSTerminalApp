//
//  NSTask.h
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/21.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTask (PTY)
- (NSFileHandle *)masterSideOfPTYOrError:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
